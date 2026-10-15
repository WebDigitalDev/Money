import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class UsersScreenController {
  bool Function()? _closeDetail;
  VoidCallback? _openCreate;

  bool closeDetail() => _closeDetail?.call() ?? false;

  void openCreate() => _openCreate?.call();
}

class UsersScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final UsersScreenController? controller;
  final ValueChanged<bool>? onDetailVisibilityChanged;

  const UsersScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
    this.onDetailVisibilityChanged,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const int _pageSize = 50;
  static const Duration _liveRefreshInterval = Duration(seconds: 10);

  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalTableController = ScrollController();

  final List<AppUserSummary> _users = [];
  Timer? _searchDebounce;
  Timer? _liveRefreshTimer;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshingSilently = false;
  bool _hasNext = false;
  int _nextPage = 0;
  int _desktopPage = 0;
  int _totalUsers = 0;
  int _requestVersion = 0;
  String? _errorMessage;
  int? _embeddedUserId;
  bool _creatingUser = false;
  bool _desktopDialogOpen = false;
  final UserDetailScreenController _detailController =
      UserDetailScreenController();

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _scrollController.addListener(_handleScroll);
    NetworkStatusService().statusListenable.addListener(
      _handleNetworkStatusChanged,
    );
    _liveRefreshTimer = Timer.periodic(
      _liveRefreshInterval,
      (_) => _refreshLoadedPages(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _loadUsers(reset: true);
    });
  }

  @override
  void didUpdateWidget(covariant UsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (!oldWidget.active && widget.active) {
      if (_users.isEmpty && _loading) {
        _loadUsers(reset: true);
      } else {
        unawaited(_refreshLoadedPages());
      }
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    if (_embeddedUserId != null || _creatingUser) {
      final ValueChanged<bool>? callback = widget.onDetailVisibilityChanged;
      if (callback != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback(false));
      }
    }
    _searchDebounce?.cancel();
    _liveRefreshTimer?.cancel();
    NetworkStatusService().statusListenable.removeListener(
      _handleNetworkStatusChanged,
    );
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _horizontalTableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showingDetail = _embeddedUserId != null || _creatingUser;
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final String appBarTitle = showingDetail
        ? (_creatingUser ? 'Novo usuário' : 'Perfil do usuário')
        : context.tr!.sidebar_users;

    return Scaffold(
      // Esta tela fica dentro do Scaffold principal no mobile. Se os dois
      // Scaffolds reagirem ao teclado, o espaço do teclado é descontado duas
      // vezes e uma faixa vazia acaba cobrindo a lista.
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: appBarTitle,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: showingDetail
          ? UserDetailScreen(
              userId: _embeddedUserId,
              showAppBar: false,
              embedded: true,
              showEmbeddedHeader: !_creatingUser,
              onBack: _closeEmbeddedDetail,
              onSaved: _refreshAfterEdit,
              controller: _detailController,
            )
          : _buildUsersBody(compact),
    );
  }

  void _attachController(UsersScreenController? controller) {
    controller?._closeDetail = _closeDetailFromController;
    controller?._openCreate = _openCreateFromController;
  }

  void _detachController(UsersScreenController? controller) {
    controller?._closeDetail = null;
    controller?._openCreate = null;
  }

  void _openCreateFromController() {
    if (_embeddedUserId != null || _creatingUser) return;
    _openUser();
  }

  Widget _buildUsersBody(bool compact) {
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.showAppBar ? 12 : 8,
              compact ? 10 : 14,
              widget.showAppBar ? 12 : 8,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  _UsersHeader(
                    totalUsers: _totalUsers,
                    onCreateUser: () => _openUser(),
                  ),
                  const SizedBox(height: 16),
                ],
                _SearchField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildContent(compact: compact)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({required bool compact}) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }

    if (_errorMessage != null && _users.isEmpty) {
      return _UsersMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar os usuários',
        message: _errorMessage!,
        actionLabel: 'Tentar novamente',
        onAction: () => _loadUsers(reset: true),
      );
    }

    if (_users.isEmpty) {
      return _UsersMessage(
        icon: Icons.person_search_rounded,
        title: 'Nenhum usuário encontrado',
        message: _searchController.text.trim().isEmpty
            ? 'Cadastre o primeiro usuário para começar.'
            : 'Tente pesquisar por outro nome ou usuário.',
      );
    }

    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      return _buildDesktopTable();
    }

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _loadUsers(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + (compact ? 76 : 0),
        ),
        itemCount: _users.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: context.colors.primary,
                  ),
                ),
              ),
            );
          }
          final AppUserSummary user = _users[index];
          return _UserCard(user: user, onTap: () => _openUser(user.id));
        },
      ),
    );
  }

  Widget _buildDesktopTable() {
    final DateFormat dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final List<DataColumn> columns = const [
      DataColumn(label: SizedBox(width: 205, child: Text('USUÁRIO'))),
      DataColumn(label: SizedBox(width: 125, child: Text('LOGIN'))),
      DataColumn(label: SizedBox(width: 190, child: Text('E-MAIL'))),
      DataColumn(label: SizedBox(width: 100, child: Text('PERFIL'))),
      DataColumn(label: SizedBox(width: 85, child: Text('STATUS'))),
      DataColumn(label: SizedBox(width: 125, child: Text('ÚLTIMO ACESSO'))),
      DataColumn(label: SizedBox(width: 24)),
    ];
    return DesktopPaginatedDataTable(
      columns: columns,
      rows: [
        for (final AppUserSummary user in _users)
          DataRow(
            onSelectChanged: (_) => _openUser(user.id),
            cells: [
              DataCell(
                SizedBox(
                  width: 205,
                  child: Row(
                    children: [
                      _TableInitials(text: _initials(user.name, user.username)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          user.name.isEmpty ? user.username : user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 125,
                  child: Text(
                    user.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 190,
                  child: Text(
                    user.email ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 100,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(
                      label: user.administrator
                          ? 'Administrador'
                          : user.collector
                          ? 'Cobrador'
                          : 'Usuário',
                      color: user.administrator || user.collector
                          ? context.colors.primary
                          : context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 85,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(
                      label: user.enabled ? 'Ativo' : 'Desativado',
                      color: user.enabled
                          ? context.colors.primary
                          : context.colors.error,
                    ),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 125,
                  child: Text(
                    user.lastAccess == null
                        ? '—'
                        : dateFormat.format(user.lastAccess!),
                    maxLines: 1,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 24,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
      ],
      totalItems: _totalUsers,
      currentPage: _desktopPage,
      rowsPerPage: _pageSize,
      onPageChanged: _loadDesktopPage,
      verticalController: _scrollController,
      horizontalController: _horizontalTableController,
    );
  }

  void _onSearchChanged(String value) {
    // Evita que uma resposta antiga substitua a pesquisa que ainda está sendo
    // digitada e não reconstrói a lista inteira a cada tecla.
    _requestVersion++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadUsers(reset: true),
    );
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _searchDebounce?.cancel();
    _loadUsers(reset: true);
  }

  void _handleScroll() {
    if (kIsWeb && mounted && MediaQuery.sizeOf(context).width >= 1024) {
      return;
    }
    if (!_scrollController.hasClients || !_hasNext || _loadingMore) return;
    if (_scrollController.position.extentAfter < 280) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers({bool reset = false, int? targetPage}) async {
    final bool replace = reset || targetPage != null;
    final int requestedPage = targetPage ?? (reset ? 0 : _nextPage);
    if (replace) {
      _requestVersion++;
      final AppUserPage? cached = _userService.cachedUsers(
        query: _searchController.text,
        page: requestedPage,
        size: _pageSize,
      );
      setState(() {
        _loading = cached == null;
        _loadingMore = false;
        _errorMessage = null;
        _nextPage = 0;
        _hasNext = false;
        _desktopPage = requestedPage;
        _users.clear();
        if (cached != null) _applyPage(cached, reset: true);
      });
    } else {
      if (_loading || _loadingMore || !_hasNext) return;
      setState(() => _loadingMore = true);
    }

    final int version = _requestVersion;
    try {
      final AppUserPage result = await _userService.fetchUsers(
        query: _searchController.text,
        page: requestedPage,
        size: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _applyPage(result, reset: replace);
        if (replace) _desktopPage = result.page;
        _loading = false;
        _loadingMore = false;
        _errorMessage = null;
      });
    } on UserServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorMessage = _users.isEmpty ? error.message : null;
      });
    }
  }

  void _loadDesktopPage(int page) {
    if (page == _desktopPage || _loading) return;
    _loadUsers(targetPage: page);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _applyPage(AppUserPage result, {required bool reset}) {
    if (reset) _users.clear();
    _users.addAll(result.items);
    _totalUsers = result.totalItems;
    _nextPage = result.page + 1;
    _hasNext = result.hasNext;
  }

  void _handleNetworkStatusChanged() {
    if (NetworkStatusService().isOnline) _refreshLoadedPages();
  }

  Future<void> _refreshLoadedPages() async {
    if (!mounted ||
        !widget.active ||
        !NetworkStatusService().isOnline ||
        _loading ||
        _loadingMore ||
        _refreshingSilently ||
        _embeddedUserId != null ||
        _creatingUser) {
      return;
    }

    _refreshingSilently = true;
    final int version = _requestVersion;
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    final int loadedPageCount = _nextPage.clamp(1, 20);
    try {
      if (desktop) {
        final AppUserPage page = await _userService.fetchUsers(
          query: _searchController.text,
          page: _desktopPage,
          size: _pageSize,
        );
        if (!mounted || version != _requestVersion) return;
        setState(() {
          _users
            ..clear()
            ..addAll(page.items);
          _totalUsers = page.totalItems;
          _nextPage = page.page + 1;
          _hasNext = page.hasNext;
          _desktopPage = page.page;
          _errorMessage = null;
        });
        return;
      }
      final List<AppUserPage> pages = await Future.wait([
        for (int page = 0; page < loadedPageCount; page++)
          _userService.fetchUsers(
            query: _searchController.text,
            page: page,
            size: _pageSize,
          ),
      ]);
      if (!mounted || version != _requestVersion || pages.isEmpty) return;

      final Map<int, AppUserSummary> currentUsers = {};
      for (final AppUserPage page in pages) {
        for (final AppUserSummary user in page.items) {
          currentUsers[user.id] = user;
        }
      }
      final AppUserPage lastPage = pages.last;
      setState(() {
        _users
          ..clear()
          ..addAll(currentUsers.values);
        _totalUsers = pages.first.totalItems;
        _nextPage = lastPage.page + 1;
        _hasNext = lastPage.hasNext;
        _errorMessage = null;
      });
    } on UserServiceException {
      // O conteúdo atual permanece visível; o monitor global trata a conexão.
    } finally {
      _refreshingSilently = false;
    }
  }

  void _openUser([int? userId]) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      if (!_desktopDialogOpen) unawaited(_openDesktopUserDialog(userId));
      return;
    }
    setState(() {
      _embeddedUserId = userId;
      _creatingUser = userId == null;
    });
    widget.onDetailVisibilityChanged?.call(true);
  }

  Future<void> _openDesktopUserDialog(int? userId) async {
    _desktopDialogOpen = true;
    final UserDetailScreenController detailController =
        UserDetailScreenController();
    try {
      await showAppSideDrawer<void>(
        context: context,
        fromStart: true,
        maxWidth: 500,
        builder: (drawerContext) => Column(
          children: [
            AppPanelHeader(
              title: userId == null ? 'Novo usuário' : 'Perfil do usuário',
              subtitle: userId == null
                  ? 'Preencha os dados para criar o acesso.'
                  : 'Consulte e altere os dados do usuário.',
              icon: Icons.manage_accounts_outlined,
              onClose: detailController.requestClose,
            ),
            Expanded(
              child: UserDetailScreen(
                userId: userId,
                showAppBar: false,
                embedded: true,
                showEmbeddedHeader: userId != null,
                onBack: () => Navigator.pop(drawerContext),
                onSaved: _refreshAfterEdit,
                controller: detailController,
              ),
            ),
          ],
        ),
      );
    } finally {
      _desktopDialogOpen = false;
      if (mounted) unawaited(_loadUsers(targetPage: _desktopPage));
    }
  }

  void _closeEmbeddedDetail() {
    if (_embeddedUserId == null && !_creatingUser) return;
    setState(() {
      _embeddedUserId = null;
      _creatingUser = false;
    });
    widget.onDetailVisibilityChanged?.call(false);
  }

  bool _closeDetailFromController() {
    if (_embeddedUserId == null && !_creatingUser) return false;
    if (!_detailController.requestClose()) _closeEmbeddedDetail();
    return true;
  }

  void _refreshAfterEdit() {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      _loadUsers(targetPage: _desktopPage);
    } else {
      _loadUsers(reset: true);
    }
  }
}

class _UsersHeader extends StatelessWidget {
  final int totalUsers;
  final VoidCallback onCreateUser;

  const _UsersHeader({required this.totalUsers, required this.onCreateUser});

  @override
  Widget build(BuildContext context) {
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gestão de usuários',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          totalUsers == 1
              ? '1 usuário encontrado'
              : '$totalUsers usuários encontrados',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 11.5),
        ),
      ],
    );
    final Widget createButton = FilledButton(
      onPressed: onCreateUser,
      style: FilledButton.styleFrom(
        backgroundColor: context.colors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text(
        'NOVO USUÁRIO',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 12), createButton],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            createButton,
          ],
        );
      },
    );
  }
}

class _SearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late bool _showClearButton;

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final bool showClearButton = widget.controller.text.isNotEmpty;
    if (showClearButton == _showClearButton) return;
    setState(() => _showClearButton = showClearButton);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Pesquisar por nome, usuário ou e-mail',
        hintStyle: TextStyle(
          color: context.colors.textPlaceholder,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: context.colors.primary,
          size: 20,
        ),
        suffixIcon: !_showClearButton
            ? null
            : IconButton(
                tooltip: 'Limpar pesquisa',
                onPressed: widget.onClear,
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: context.colors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.colors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUserSummary user;
  final VoidCallback onTap;

  const _UserCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final String initials = _initials(user.name, user.username);

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.divider),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name.isEmpty ? user.username : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (user.administrator) ...[
                          const SizedBox(width: 5),
                          _StatusBadge(
                            label: 'Administrador',
                            color: context.colors.primary,
                          ),
                        ],
                        if (user.collector && !user.administrator) ...[
                          const SizedBox(width: 5),
                          _StatusBadge(
                            label: 'Cobrador',
                            color: context.colors.primary,
                          ),
                        ],
                        if (!user.enabled) ...[
                          const SizedBox(width: 5),
                          _StatusBadge(
                            label: 'Desativado',
                            color: context.colors.error,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        _UserMetadata(
                          icon: Icons.alternate_email_rounded,
                          text: user.username,
                        ),
                        if (user.lastAccess != null)
                          _UserMetadata(
                            icon: Icons.schedule_rounded,
                            text:
                                'Último acesso: ${dateFormat.format(user.lastAccess!)}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableInitials extends StatelessWidget {
  final String text;

  const _TableInitials({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UserMetadata extends StatelessWidget {
  final IconData icon;
  final String text;

  const _UserMetadata({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: context.colors.textSecondary),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _UsersMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _UsersMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: context.colors.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _initials(String name, String username) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return username.isEmpty ? '?' : username[0].toUpperCase();
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
