import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';

class ClientsScreenController {
  bool Function()? _closeDetail;
  VoidCallback? _openCreate;
  ValueChanged<int>? _openDetail;
  Future<bool> Function()? _ensureTutorialClient;
  Future<bool> Function()? _openTutorialClient;

  bool closeDetail() => _closeDetail?.call() ?? false;

  void openCreate() => _openCreate?.call();

  void openDetail(int clientId) => _openDetail?.call(clientId);

  Future<bool> ensureTutorialClient() async =>
      await _ensureTutorialClient?.call() ?? false;

  Future<bool> openTutorialClient() async =>
      await _openTutorialClient?.call() ?? false;
}

class ClientsScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final ClientsScreenController? controller;
  final TutorialGuideController? tutorialController;
  final bool tutorialMode;
  final ValueChanged<bool>? onDetailVisibilityChanged;
  final VoidCallback? onLoanCreated;

  const ClientsScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
    this.tutorialController,
    this.tutorialMode = false,
    this.onDetailVisibilityChanged,
    this.onLoanCreated,
  });

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 50;
  static const Duration _refreshInterval = Duration(seconds: 10);

  final ClientService _clientService = ClientService();
  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalTableController = ScrollController();
  final ClientDetailScreenController _detailController =
      ClientDetailScreenController();
  final List<AppClientSummary> _clients = [];
  late final TabController _tabController;
  Timer? _searchDebounce;
  Timer? _refreshTimer;
  List<AppRegionOption> _regions = const [];
  Set<int> _selectedRegionIds = {};
  AppClientStatus? _status;
  AppClientStatusCounts _counts = const AppClientStatusCounts.empty();
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _hasNext = false;
  int _nextPage = 0;
  int _desktopPage = 0;
  int _requestVersion = 0;
  int _totalItems = 0;
  String? _errorMessage;
  int? _embeddedClientId;
  bool _creatingClient = false;
  bool _desktopDialogOpen = false;
  BuildContext? _desktopDrawerContext;
  bool _tutorialFilterApplied = false;
  bool _restoringFilters = false;
  double _tabDragDistance = 0;

  bool get _showingDetail => _embeddedClientId != null || _creatingClient;
  bool get _canEdit {
    final AuthSession? session = AuthService().currentSession;
    return session?.administrator == true || session?.canEdit == true;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_handleTabChanged);
    _attachController(widget.controller);
    _scrollController.addListener(_handleScroll);
    NetworkStatusService().statusListenable.addListener(_handleNetworkChanged);
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshSilently());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(covariant ClientsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (oldWidget.tutorialMode != widget.tutorialMode) {
      unawaited(_handleTutorialModeChanged());
      return;
    }
    if (!oldWidget.active && widget.active) {
      if (_clients.isEmpty && _loading) {
        unawaited(_loadRegions());
        _load(reset: true);
      } else {
        unawaited(_refreshSilently());
      }
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    _searchDebounce?.cancel();
    _refreshTimer?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _horizontalTableController.dispose();
    _searchController.dispose();
    NetworkStatusService().statusListenable.removeListener(
      _handleNetworkChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final String title = _showingDetail
        ? (_creatingClient ? 'Novo cliente' : 'Detalhes do cliente')
        : context.tr!.sidebar_clients;
    return Scaffold(
      // Mantém a estrutura da página estável durante a pesquisa: no mobile o
      // teclado deve sobrepor a parte inferior, sem comprimir o conteúdo.
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(title: title, leading: const AppSidebarMenuButton())
          : null,
      body: _showingDetail
          ? ClientDetailScreen(
              clientId: _embeddedClientId,
              showAppBar: false,
              embedded: true,
              onBack: _closeDetail,
              onSaved: _refreshAfterChange,
              onCreated: _handleClientCreated,
              onLoanCreated: _handleLoanCreated,
              controller: _detailController,
              tutorialController: widget.tutorialController,
            )
          : _buildList(compact),
    );
  }

  Widget _buildList(bool compact) {
    final bool desktopTable =
        kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.showAppBar ? 10 : 8,
              compact ? 8 : 14,
              widget.showAppBar ? 10 : 8,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  _ClientsHeader(
                    total: _totalItems,
                    canEdit: _canEdit,
                    onExport: widget.showAppBar ? null : _confirmExport,
                    onCreate: _openCreate,
                    newClientKey:
                        widget.tutorialController?.desktopNewClientButtonKey,
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (widget.showAppBar) ...[
                      AppMobileExcelExportButton(
                        onPressed: _confirmExport,
                        dimension: 45,
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: _ClientSearchField(
                        key: widget.tutorialController?.clientSearchKey,
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onClear: _clearSearch,
                      ),
                    ),
                    if (!widget.tutorialMode) ...[
                      const SizedBox(width: 7),
                      _ClientFilterButton(
                        count: _selectedRegionIds.length,
                        onTap: _openRegionFilter,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Material(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: context.colors.primary,
                    labelColor: context.colors.primary,
                    unselectedLabelColor: context.colors.textSecondary,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: [
                      Tab(
                        height: 39,
                        text:
                            'Todos (${_counts.active + _counts.withoutLoans + _counts.missing})',
                      ),
                      Tab(height: 39, text: 'Ativos (${_counts.active})'),
                      Tab(
                        height: 39,
                        text: 'Sem empréstimos (${_counts.withoutLoans})',
                      ),
                      Tab(
                        height: 39,
                        text: 'Desaparecidos (${_counts.missing})',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: desktopTable
                      ? _buildContent(compact)
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (_) => _tabDragDistance = 0,
                          onHorizontalDragUpdate: (details) =>
                              _tabDragDistance += details.delta.dx,
                          onHorizontalDragEnd: _handleTabSwipe,
                          onHorizontalDragCancel: () => _tabDragDistance = 0,
                          child: _buildContent(compact),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool compact) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null && _clients.isEmpty) {
      return _ClientsMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar os clientes',
        message: _errorMessage!,
        onRetry: () => _load(reset: true, force: true),
      );
    }
    if (_clients.isEmpty) {
      return _ClientsMessage(
        icon: Icons.person_search_outlined,
        title: 'Nenhum cliente encontrado',
        message: 'Ajuste a pesquisa, a aba ou as regiões selecionadas.',
      );
    }
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      return _buildDesktopTable();
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _load(reset: true, force: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: compact ? 76 : 8),
        itemCount: _clients.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == _clients.length) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: SizedBox.square(
                  dimension: 23,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: context.colors.primary,
                  ),
                ),
              ),
            );
          }
          return _ClientCard(
            key: _isTutorialClient(_clients[index])
                ? widget.tutorialController?.tutorialClientKey
                : null,
            client: _clients[index],
            onTap: () => _openDetail(_clients[index].id),
          );
        },
      ),
    );
  }

  Widget _buildDesktopTable() {
    final List<DataColumn> columns = const [
      DataColumn(label: SizedBox(width: 225, child: Text('CLIENTE'))),
      DataColumn(label: SizedBox(width: 135, child: Text('CPF/CNPJ'))),
      DataColumn(label: SizedBox(width: 245, child: Text('REGIÃO'))),
      DataColumn(label: SizedBox(width: 125, child: Text('TELEFONE'))),
      DataColumn(label: SizedBox(width: 90, child: Text('SITUAÇÃO'))),
      DataColumn(label: SizedBox(width: 24)),
    ];
    return DesktopPaginatedDataTable(
      columns: columns,
      rows: [
        for (final AppClientSummary client in _clients)
          DataRow(
            onSelectChanged: (_) => _openDetail(client.id),
            cells: [
              DataCell(
                SizedBox(
                  key: _isTutorialClient(client)
                      ? widget.tutorialController?.tutorialClientKey
                      : null,
                  width: 225,
                  child: Row(
                    children: [
                      _ClientTableInitial(name: client.name),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          client.name,
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
                  width: 135,
                  child: Text(
                    client.document ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 245,
                  child: Text(
                    client.regionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 125,
                  child: Text(
                    client.primaryPhone == null
                        ? '—'
                        : formatBrazilianPhone(client.primaryPhone),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 90,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ClientTableStatus(status: client.status),
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
      totalItems: _totalItems,
      currentPage: _desktopPage,
      rowsPerPage: _pageSize,
      onPageChanged: _loadDesktopPage,
      verticalController: _scrollController,
      horizontalController: _horizontalTableController,
      columnSpacing: 24,
    );
  }

  void _attachController(ClientsScreenController? controller) {
    controller?._closeDetail = _closeDetailFromController;
    controller?._openCreate = _openCreate;
    controller?._openDetail = _openDetail;
    controller?._ensureTutorialClient = _ensureTutorialClient;
    controller?._openTutorialClient = _openTutorialClient;
  }

  void _detachController(ClientsScreenController? controller) {
    controller?._closeDetail = null;
    controller?._openCreate = null;
    controller?._openDetail = null;
    controller?._ensureTutorialClient = null;
    controller?._openTutorialClient = null;
  }

  Future<void> _initialize() async {
    if (widget.tutorialMode) {
      await _prepareTutorialFilter();
    } else {
      await _restoreSavedFilters();
      if (!mounted) return;
      unawaited(_loadRegions());
    }
    if (!mounted || !widget.active) return;
    await _load(reset: true, force: widget.tutorialMode);
  }

  Future<void> _handleTutorialModeChanged() async {
    if (widget.tutorialMode) {
      _requestVersion++;
      setState(() {
        _clients.clear();
        _regions = const [];
        _selectedRegionIds = {-1};
        _status = null;
        _counts = const AppClientStatusCounts.empty();
        _loading = true;
        _loadingMore = false;
        _hasNext = false;
        _nextPage = 0;
        _desktopPage = 0;
        _totalItems = 0;
        _errorMessage = null;
        _tutorialFilterApplied = false;
      });
      await _prepareTutorialFilter(force: true);
    } else if (mounted) {
      await _restoreSavedFilters();
      if (!mounted) return;
      unawaited(_loadRegions(force: true));
    }
    if (mounted && widget.active) {
      await _load(reset: true, force: true);
    }
  }

  Future<void> _prepareTutorialFilter({bool force = false}) async {
    if (_tutorialFilterApplied && !force) return;
    try {
      // A tela pode ser aberta diretamente durante a animação do tutorial,
      // antes que o painel tenha concluído a concessão temporária da região.
      // Por isso cada página protegida prepara o próprio acesso antes de
      // buscar as opções e os dados.
      await AuthService().beginTutorial();
      final List<AppRegionOption> regions = await _regionService.fetchOptions(
        force: true,
        tutorialMode: true,
      );
      AppRegionOption? tutorialRegion;
      for (final AppRegionOption region in regions) {
        if (TutorialGuideController.isTutorialRegionName(region.name)) {
          tutorialRegion = region;
          break;
        }
      }
      if (!mounted) return;
      _setStatusTab(null);
      setState(() {
        _regions = tutorialRegion == null
            ? const <AppRegionOption>[]
            : <AppRegionOption>[tutorialRegion];
        _status = null;
        _selectedRegionIds = {tutorialRegion?.id ?? -1};
        _tutorialFilterApplied = tutorialRegion != null;
        _errorMessage = tutorialRegion == null
            ? 'A região TUTORIAL não foi encontrada.'
            : null;
      });
    } on AuthenticationException catch (error) {
      if (!mounted) return;
      _setStatusTab(null);
      setState(() {
        _status = null;
        _selectedRegionIds = {-1};
        _tutorialFilterApplied = false;
        _errorMessage = error.message;
      });
    } on RegionServiceException catch (error) {
      if (!mounted) return;
      _setStatusTab(null);
      setState(() {
        _status = null;
        _selectedRegionIds = {-1};
        _tutorialFilterApplied = false;
        _errorMessage = error.message;
      });
    }
  }

  bool _isTutorialClient(AppClientSummary client) =>
      client.name.trim().toUpperCase() ==
      TutorialGuideController.tutorialClientName;

  Future<bool> _openTutorialClient() async {
    if (!await _ensureTutorialClient()) return false;
    final AppClientSummary tutorialClient = _clients.firstWhere(
      _isTutorialClient,
    );
    if (!mounted) return false;
    _openDetail(tutorialClient.id);
    return true;
  }

  Future<bool> _ensureTutorialClient() async {
    if (!_tutorialFilterApplied || _selectedRegionIds.contains(-1)) {
      await _prepareTutorialFilter(force: true);
    }
    if (!mounted) return false;
    if (!_clients.any(_isTutorialClient)) {
      await _load(reset: true, force: true);
    }
    if (!mounted || !_clients.any(_isTutorialClient)) return false;
    await _prefetchTutorialClient();
    return mounted;
  }

  Future<void> _prefetchTutorialClient() async {
    AppClientSummary? tutorialClient;
    for (final AppClientSummary client in _clients) {
      if (_isTutorialClient(client)) {
        tutorialClient = client;
        break;
      }
    }
    if (tutorialClient == null) return;
    try {
      await _clientService.prefetchClient(tutorialClient.id);
    } on ClientServiceException {
      // A abertura normal fará uma nova tentativa se a antecipação falhar.
    }
  }

  void _handleTabChanged() {
    if (_restoringFilters || _tabController.indexIsChanging) return;
    final AppClientStatus? next = switch (_tabController.index) {
      1 => AppClientStatus.active,
      2 => AppClientStatus.withoutLoans,
      3 => AppClientStatus.missing,
      _ => null,
    };
    if (_status == next) return;
    _status = next;
    unawaited(_saveFilters());
    _load(reset: true);
  }

  void _handleTabSwipe(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    final double distance = _tabDragDistance;
    _tabDragDistance = 0;
    if ((velocity.abs() < 250 && distance.abs() < 48) ||
        _tabController.indexIsChanging) {
      return;
    }

    final bool moveForward = velocity.abs() >= 250
        ? velocity < 0
        : distance < 0;
    final int nextIndex =
        (moveForward ? _tabController.index + 1 : _tabController.index - 1)
            .clamp(0, _tabController.length - 1);
    if (nextIndex != _tabController.index) {
      _tabController.animateTo(nextIndex);
    }
  }

  void _onSearchChanged(String value) {
    // Evita que uma resposta antiga substitua a pesquisa que ainda está sendo
    // digitada e não reconstrói a lista inteira a cada tecla.
    _requestVersion++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => _load(reset: true),
    );
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _searchDebounce?.cancel();
    _load(reset: true);
  }

  Future<void> _confirmExport() async {
    await showAppExcelExportFlow(
      context: context,
      title: 'Exportar clientes',
      confirmationMessage:
          'Deseja exportar os clientes em Excel considerando a aba, a pesquisa e os filtros atuais?',
      generate: (onProgress) async {
        try {
          onProgress(.02, 'Buscando os clientes filtrados...');
          final List<AppClientSummary> clients = await _clientService
              .fetchClientsForExport(
                status: _status,
                query: _searchController.text,
                regionIds: _selectedRegionIds,
                tutorialMode: widget.tutorialMode,
                onProgress: (value) => onProgress(
                  .02 + (value * .48),
                  'Recebendo dados dos clientes...',
                ),
              );
          if (clients.isEmpty) {
            throw const AppExcelExportException(
              'Nenhum cliente foi encontrado para exportar.',
            );
          }
          final AppClientExcelFile file = await ClientExcelExportService()
              .create(
                clients,
                onProgress: (value, status) =>
                    onProgress(.50 + (value * .50), status),
              );
          return AppGeneratedExcelFile(
            bytes: file.bytes,
            fileName: file.fileName,
            successMessage: '${clients.length} cliente(s) exportado(s).',
          );
        } on ClientServiceException catch (error) {
          throw AppExcelExportException(error.message);
        }
      },
    );
  }

  void _handleScroll() {
    if (kIsWeb && mounted && MediaQuery.sizeOf(context).width >= 1024) {
      return;
    }
    if (!_scrollController.hasClients || !_hasNext || _loadingMore) return;
    if (_scrollController.position.extentAfter < 280) _load();
  }

  Future<void> _load({
    bool reset = false,
    bool force = false,
    int? targetPage,
  }) async {
    final bool replace = reset || targetPage != null;
    final int version = replace ? ++_requestVersion : _requestVersion;
    final int page = targetPage ?? (reset ? 0 : _nextPage);
    if (!replace && (_loading || _loadingMore || !_hasNext)) return;
    final AppClientPage? cached = replace
        ? _clientService.cachedClients(
            status: _status,
            query: _searchController.text,
            regionIds: _selectedRegionIds,
            page: page,
            size: _pageSize,
            tutorialMode: widget.tutorialMode,
          )
        : null;
    if (mounted) {
      setState(() {
        if (replace) {
          _loading = cached == null;
          _loadingMore = false;
          _errorMessage = null;
          _clients.clear();
          _nextPage = 0;
          _hasNext = false;
          _desktopPage = page;
          if (cached != null) _applyPage(cached, reset: true);
        } else {
          _loadingMore = true;
        }
      });
      if (cached != null && widget.tutorialMode) {
        unawaited(_prefetchTutorialClient());
      }
    }
    try {
      final AppClientPage result = await _clientService.fetchClients(
        status: _status,
        query: _searchController.text,
        regionIds: _selectedRegionIds,
        page: page,
        size: _pageSize,
        force: force,
        tutorialMode: widget.tutorialMode,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _applyPage(result, reset: replace);
        if (replace) _desktopPage = result.page;
        _loading = false;
        _loadingMore = false;
        _errorMessage = null;
      });
      if (widget.tutorialMode) unawaited(_prefetchTutorialClient());
    } on ClientServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_clients.isEmpty) _errorMessage = error.message;
      });
    }
  }

  void _loadDesktopPage(int page) {
    if (page == _desktopPage || _loading) return;
    _load(targetPage: page);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _applyPage(AppClientPage page, {required bool reset}) {
    if (reset) _clients.clear();
    final Set<int> known = _clients.map((item) => item.id).toSet();
    _clients.addAll(page.items.where((item) => known.add(item.id)));
    _counts = page.counts;
    _totalItems = page.totalItems;
    _nextPage = page.page + 1;
    _hasNext = page.hasNext;
  }

  Future<void> _loadRegions({bool force = false}) async {
    try {
      final List<AppRegionOption> result = await _regionService.fetchOptions(
        force: force,
        tutorialMode: widget.tutorialMode,
      );
      if (mounted) {
        setState(() {
          _regions = widget.tutorialMode
              ? result
                    .where(
                      (region) => TutorialGuideController.isTutorialRegionName(
                        region.name,
                      ),
                    )
                    .toList(growable: false)
              : result;
        });
      }
    } on RegionServiceException {
      // O filtro continua utilizável assim que a conexão retornar.
    }
  }

  Future<void> _restoreSavedFilters() async {
    final int? userId = AuthService().currentSession?.userId;
    final Map<String, dynamic>? data = userId == null
        ? null
        : await _preferencesService.getUserFilters(
            scope: 'clients',
            userId: userId,
          );
    if (!mounted) return;
    final Set<int> regionIds = ((data?['regionIds'] as List?) ?? const [])
        .map((Object? item) => int.tryParse('$item'))
        .whereType<int>()
        .toSet();
    final String savedStatus = '${data?['status'] ?? ''}';
    AppClientStatus? status;
    for (final AppClientStatus value in AppClientStatus.values) {
      if (value.name == savedStatus) {
        status = value;
        break;
      }
    }
    _setStatusTab(status);
    setState(() {
      _status = status;
      _selectedRegionIds = Set<int>.unmodifiable(regionIds);
      _tutorialFilterApplied = false;
    });
  }

  void _setStatusTab(AppClientStatus? status) {
    final int index = switch (status) {
      AppClientStatus.active => 1,
      AppClientStatus.withoutLoans => 2,
      AppClientStatus.missing => 3,
      null => 0,
    };
    if (_tabController.index == index) return;
    _restoringFilters = true;
    _tabController.index = index;
    _restoringFilters = false;
  }

  Future<void> _saveFilters() async {
    if (widget.tutorialMode) return;
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'clients',
      userId: userId,
      filters: <String, Object?>{
        'regionIds': _selectedRegionIds.toList(growable: false)..sort(),
        'status': _status?.name,
      },
    );
  }

  Future<void> _openRegionFilter() async {
    if (widget.tutorialMode) return;
    await _loadRegions(force: true);
    if (!mounted) return;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool compact = screenWidth < 600;
    final Set<int>? result = await showAppSideDrawer<Set<int>>(
      context: context,
      maxWidth: compact ? screenWidth * appMobileFilterDrawerWidthFactor : 410,
      barrierDismissible: compact,
      builder: (_) =>
          _RegionFilterDrawer(regions: _regions, selected: _selectedRegionIds),
    );
    if (result == null || !mounted) return;
    final Set<int> selectedRegionIds = result;
    setState(() => _selectedRegionIds = selectedRegionIds);
    await _saveFilters();
    if (!mounted) return;
    _load(reset: true, force: true);
  }

  void _handleNetworkChanged() {
    if (NetworkStatusService().isOnline) _refreshSilently();
  }

  Future<void> _refreshSilently() async {
    if (!mounted ||
        !widget.active ||
        _showingDetail ||
        _loading ||
        _loadingMore ||
        _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
      await _load(reset: !desktop, targetPage: desktop ? _desktopPage : null);
    } finally {
      _refreshing = false;
    }
  }

  void _openCreate() {
    if (!_canEdit || _showingDetail) return;
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      if (!_desktopDialogOpen) unawaited(_openDesktopClientDialog());
      return;
    }
    setState(() => _creatingClient = true);
    widget.onDetailVisibilityChanged?.call(true);
  }

  void _openDetail(int id) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      if (!_desktopDialogOpen) unawaited(_openDesktopClientDialog(id));
      return;
    }
    setState(() => _embeddedClientId = id);
    widget.onDetailVisibilityChanged?.call(true);
  }

  Future<void> _openDesktopClientDialog([int? clientId]) async {
    _desktopDialogOpen = true;
    bool loanCreated = false;
    int? activeClientId = clientId;
    final ClientDetailScreenController detailController =
        ClientDetailScreenController();
    try {
      await showAppSideDrawer<void>(
        context: context,
        fromStart: true,
        maxWidth: 500,
        builder: (drawerContext) {
          _desktopDrawerContext = drawerContext;
          return StatefulBuilder(
            builder: (context, setDrawerState) => Column(
              children: [
                AppPanelHeader(
                  title: activeClientId == null
                      ? 'Novo cliente'
                      : 'Detalhes do cliente',
                  subtitle: activeClientId == null
                      ? 'Preencha os dados para cadastrar.'
                      : 'Consulte e altere os dados do cliente.',
                  icon: Icons.person_outline_rounded,
                  onClose: detailController.requestClose,
                ),
                Expanded(
                  child: ClientDetailScreen(
                    clientId: activeClientId,
                    showAppBar: false,
                    embedded: true,
                    showEmbeddedHeader: activeClientId != null,
                    onBack: () => Navigator.pop(drawerContext),
                    onSaved: _refreshAfterChange,
                    onCreated: (client) =>
                        setDrawerState(() => activeClientId = client.id),
                    onLoanCreated: () {
                      loanCreated = true;
                      Navigator.pop(drawerContext);
                    },
                    controller: detailController,
                    tutorialController: widget.tutorialController,
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _desktopDialogOpen = false;
      _desktopDrawerContext = null;
      if (mounted) {
        unawaited(_load(targetPage: _desktopPage));
        if (loanCreated) widget.onLoanCreated?.call();
      }
    }
  }

  void _handleLoanCreated() {
    _closeDetail();
    widget.onLoanCreated?.call();
  }

  void _handleClientCreated(AppClientDetail client) {
    if (!mounted) return;
    setState(() {
      _embeddedClientId = client.id;
      _creatingClient = false;
    });
  }

  void _closeDetail() {
    if (!_showingDetail) return;
    setState(() {
      _embeddedClientId = null;
      _creatingClient = false;
    });
    widget.onDetailVisibilityChanged?.call(false);
  }

  bool _closeDetailFromController() {
    final BuildContext? drawerContext = _desktopDrawerContext;
    if (_desktopDialogOpen && drawerContext != null) {
      final NavigatorState navigator = Navigator.of(drawerContext);
      if (navigator.canPop()) navigator.pop();
      return true;
    }
    if (!_showingDetail) return false;
    if (!_detailController.requestClose()) _closeDetail();
    return true;
  }

  void _refreshAfterChange() {
    _clientService.clearCache();
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      _load(targetPage: _desktopPage, force: true);
    } else {
      _load(reset: true, force: true);
    }
  }
}

class _ClientsHeader extends StatelessWidget {
  final int total;
  final bool canEdit;
  final VoidCallback? onExport;
  final VoidCallback onCreate;
  final Key? newClientKey;

  const _ClientsHeader({
    required this.total,
    required this.canEdit,
    required this.onExport,
    required this.onCreate,
    this.newClientKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestão de clientes',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$total clientes nesta aba',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        if (onExport != null) ...[
          AppDesktopExcelExportButton(onPressed: onExport!),
          const SizedBox(width: 8),
        ],
        if (canEdit)
          FilledButton(
            key: newClientKey,
            onPressed: onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'NOVO CLIENTE',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _ClientSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _ClientSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_ClientSearchField> createState() => _ClientSearchFieldState();
}

class _ClientSearchFieldState extends State<_ClientSearchField> {
  late bool _showClearButton;

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _ClientSearchField oldWidget) {
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
    return SizedBox(
      height: 45,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Pesquisar por nome, CPF/CNPJ ou telefone',
          hintStyle: TextStyle(
            color: context.colors.textPlaceholder,
            fontSize: 13.5,
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
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
          filled: true,
          fillColor: context.colors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _ClientFilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ClientFilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: IconButton.filledTonal(
        tooltip: 'Filtrar por regiões',
        onPressed: onTap,
        style: IconButton.styleFrom(
          fixedSize: const Size(45, 45),
          backgroundColor: context.colors.surface,
          foregroundColor: context.colors.primary,
          side: BorderSide(color: context.colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.tune_rounded, size: 21),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  final AppClientSummary client;
  final VoidCallback onTap;

  const _ClientCard({super.key, required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String initial = client.name.trim().isEmpty
        ? 'C'
        : client.name.trim().substring(0, 1).toUpperCase();
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.divider),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
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
                            client.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 9,
                      runSpacing: 2,
                      children: [
                        if (client.document != null)
                          _ClientMetadata(
                            icon: Icons.badge_outlined,
                            text: client.document!,
                          ),
                        _ClientMetadata(
                          icon: Icons.location_on_outlined,
                          text: client.regionName,
                        ),
                        if (client.primaryPhone != null)
                          _ClientMetadata(
                            icon: Icons.phone_outlined,
                            text: formatBrazilianPhone(client.primaryPhone),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientTableInitial extends StatelessWidget {
  final String name;

  const _ClientTableInitial({required this.name});

  @override
  Widget build(BuildContext context) {
    final String initial = name.trim().isEmpty
        ? 'C'
        : name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ClientTableStatus extends StatelessWidget {
  final AppClientStatus status;

  const _ClientTableStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final String label = switch (status) {
      AppClientStatus.active => 'Ativo',
      AppClientStatus.withoutLoans => 'Sem empréstimos',
      AppClientStatus.missing => 'Desaparecido',
    };
    final Color color = switch (status) {
      AppClientStatus.active => context.colors.primary,
      AppClientStatus.withoutLoans => Colors.orange.shade700,
      AppClientStatus.missing => context.colors.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ClientMetadata extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ClientMetadata({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: context.colors.textSecondary),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _RegionFilterDrawer extends StatefulWidget {
  final List<AppRegionOption> regions;
  final Set<int> selected;

  const _RegionFilterDrawer({required this.regions, required this.selected});

  @override
  State<_RegionFilterDrawer> createState() => _RegionFilterDrawerState();
}

class _RegionFilterDrawerState extends State<_RegionFilterDrawer> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    final Set<int> availableRegionIds = _allRegionIds;
    final Set<int> selectedRegionIds = widget.selected
        .where(availableRegionIds.contains)
        .toSet();
    _selected = selectedRegionIds;
  }

  Set<int> get _allRegionIds =>
      widget.regions.map((region) => region.id).toSet();

  bool get _allRegionsSelected =>
      widget.regions.isEmpty ||
      (_selected.length == widget.regions.length &&
          widget.regions.every((region) => _selected.contains(region.id)));

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 18,
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPanelHeader(
                title: 'Filtros de clientes',
                subtitle: 'Selecione as regiões da listagem.',
                icon: Icons.tune_rounded,
                compact: MediaQuery.sizeOf(context).width < 600,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
                  child: AppFilterSectionCard(
                    title: 'Regiões',
                    icon: Icons.location_on_outlined,
                    trailing: _ClientRegionFilterToggle(
                      allSelected: _allRegionsSelected,
                      onPressed: _toggleAllRegions,
                    ),
                    expandChild: true,
                    child: Material(
                      color: context.colors.background.withValues(alpha: .62),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: context.colors.divider.withValues(alpha: .8),
                        ),
                      ),
                      child: widget.regions.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhuma região encontrada',
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: widget.regions.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                indent: 38,
                                color: context.colors.divider.withValues(
                                  alpha: .55,
                                ),
                              ),
                              itemBuilder: (context, index) {
                                final AppRegionOption region =
                                    widget.regions[index];
                                return CheckboxListTile(
                                  dense: true,
                                  visualDensity: const VisualDensity(
                                    horizontal: -4,
                                    vertical: -4,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  activeColor: context.colors.primary,
                                  checkboxShape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  title: Text(
                                    region.name.isEmpty
                                        ? 'Região #${region.id}'
                                        : region.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 10.8,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  value: _selected.contains(region.id),
                                  onChanged: (selected) => _toggleRegion(
                                    region.id,
                                    selected == true,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
              AppFilterActionBar(
                onClear: _clearRegions,
                onApply: _apply,
                equalWidths: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearRegions() => setState(_selected.clear);

  void _toggleAllRegions() {
    setState(() {
      if (_allRegionsSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_allRegionIds);
      }
    });
  }

  void _toggleRegion(int regionId, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(regionId);
      } else {
        _selected.remove(regionId);
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _allRegionsSelected ? <int>{} : Set<int>.unmodifiable(_selected),
    );
  }
}

class _ClientRegionFilterToggle extends StatelessWidget {
  final bool allSelected;
  final VoidCallback onPressed;

  const _ClientRegionFilterToggle({
    required this.allSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        allSelected ? 'Desmarcar todas' : 'Selecionar todas',
        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ClientsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _ClientsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.colors.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
