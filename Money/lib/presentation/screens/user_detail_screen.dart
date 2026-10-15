import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class UserDetailScreenController {
  Future<void> Function()? _requestClose;

  bool requestClose() {
    final Future<void> Function()? callback = _requestClose;
    if (callback == null) return false;
    unawaited(callback());
    return true;
  }
}

class UserDetailScreen extends StatefulWidget {
  final int? userId;
  final AppUserDetail? initialUser;
  final bool showAppBar;
  final bool embedded;
  final bool showEmbeddedHeader;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final UserDetailScreenController? controller;

  const UserDetailScreen({
    super.key,
    this.userId,
    this.initialUser,
    this.showAppBar = true,
    this.embedded = false,
    this.showEmbeddedHeader = true,
    this.onBack,
    this.onSaved,
    this.controller,
  });

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final UserService _userService = UserService();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _initialPasswordController =
      TextEditingController();

  AppUserDetail? _user;
  List<AppUserRegion> _regions = const [];
  final Set<int> _selectedRegionIds = {};
  bool _loading = true;
  bool _saving = false;
  bool _closing = false;
  bool _enabled = true;
  bool _forcePasswordChange = false;
  bool _administrator = false;
  bool _canEdit = false;
  bool _collector = false;
  bool _showTutorial = true;
  bool _obscureInitialPassword = true;
  int? _savedUserId;
  String? _errorMessage;

  bool get _isNew => widget.userId == null && _savedUserId == null;

  @override
  void initState() {
    super.initState();
    widget.controller?._requestClose = _requestClose;
    for (final TextEditingController controller in [
      _firstNameController,
      _lastNameController,
      _usernameController,
      _emailController,
      _initialPasswordController,
    ]) {
      controller.addListener(_refreshFormState);
    }
    final AppUserDetail? initialUser = widget.initialUser;
    if (initialUser == null) {
      if (widget.userId == null) {
        // O formulário novo não depende das regiões para ser exibido.
        _loading = false;
        _loadNewUserRegions();
      } else {
        _load();
      }
    } else {
      _applyUser(initialUser);
      _loading = false;
    }
  }

  void _refreshFormState() {
    if (mounted && !_loading) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UserDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?._requestClose = null;
    widget.controller?._requestClose = _requestClose;
  }

  @override
  void dispose() {
    widget.controller?._requestClose = null;
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _initialPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = _isNew ? 'Novo usuário' : 'Perfil do usuário';
    final Widget body = _buildBody();
    final Widget? saveBar = _loading || _errorMessage != null
        ? null
        : _SaveBar(
            saving: _saving,
            isNew: _isNew,
            hasChanges: _hasChanges(),
            onSave: _saving ? null : _save,
            onCancel: _saving ? null : _requestClose,
          );

    if (widget.embedded) {
      return ColoredBox(
        color: context.colors.background,
        child: Column(
          children: [
            Expanded(child: body),
            ?saveBar,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: title,
              leading: widget.onBack != null
                  ? const AppSidebarMenuButton()
                  : IconButton(
                      tooltip: 'Voltar',
                      onPressed: _requestClose,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
            )
          : null,
      body: body,
      bottomNavigationBar: saveBar,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: context.colors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textPrimary),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          if (!widget.embedded || widget.showEmbeddedHeader)
            UserProfileHeader(
              name: _displayName,
              username: _usernameController.text,
              enabled: _enabled,
              administrator: _administrator,
              lastAccess: _user?.lastAccess,
              onChangePassword: _isNew ? null : _changePassword,
            ),
          Material(
            color: context.colors.surface,
            child: TabBar(
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              indicatorColor: context.colors.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(height: 43, text: 'Identificação'),
                Tab(height: 43, text: 'Regiões'),
                Tab(height: 43, text: 'Ajustes'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildIdentificationTab(),
                _buildRegionsTab(),
                _buildAdjustmentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentificationTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _SectionCard(
              title: 'Dados pessoais',
              subtitle: 'Informações utilizadas para identificar o usuário.',
              icon: Icons.badge_outlined,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bool twoColumns = constraints.maxWidth >= 680;
                  final List<Widget> fields = [
                    _AppTextField(
                      controller: _firstNameController,
                      label: 'Primeiro nome',
                      icon: Icons.person_outline_rounded,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    _AppTextField(
                      controller: _lastNameController,
                      label: 'Sobrenome',
                      icon: Icons.person_outline_rounded,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                    ),
                    _AppTextField(
                      controller: _usernameController,
                      label: 'Usuário',
                      icon: Icons.alternate_email_rounded,
                      inputFormatters: const [_UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                    ),
                    _AppTextField(
                      controller: _emailController,
                      label: 'E-mail',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ];
                  return _FieldGrid(fields: fields, twoColumns: twoColumns);
                },
              ),
            ),
          ),
        ),
        if (_isNew) ...[
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: _SectionCard(
                title: 'Acesso inicial',
                subtitle:
                    'Defina a senha numérica utilizada no primeiro acesso.',
                icon: Icons.lock_outline_rounded,
                child: _AppTextField(
                  controller: _initialPasswordController,
                  label: 'Senha inicial',
                  icon: Icons.password_rounded,
                  keyboardType: TextInputType.number,
                  obscureText: _obscureInitialPassword,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureInitialPassword = !_obscureInitialPassword,
                    ),
                    icon: Icon(
                      _obscureInitialPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRegionsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _SectionCard(
              title: 'Regiões vinculadas',
              subtitle:
                  '${_selectedRegionIds.length} de ${_regions.length} regiões selecionadas.',
              icon: Icons.location_on_outlined,
              trailing: TextButton(
                onPressed: _toggleAllRegions,
                child: Text(
                  _selectedRegionIds.length == _regions.length
                      ? 'Desmarcar todas'
                      : 'Selecionar todas',
                ),
              ),
              child: _regions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'Nenhuma região disponível.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    )
                  : Column(
                      children: [
                        for (
                          int index = 0;
                          index < _regions.length;
                          index++
                        ) ...[
                          Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              dense: true,
                              value: _selectedRegionIds.contains(
                                _regions[index].id,
                              ),
                              onChanged: (selected) => _toggleRegion(
                                _regions[index].id,
                                selected == true,
                              ),
                              activeColor: context.colors.primary,
                              visualDensity: const VisualDensity(
                                horizontal: -4,
                                vertical: -4,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                _regions[index].name,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          if (index != _regions.length - 1)
                            Divider(height: 1, color: context.colors.divider),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: _SectionCard(
              title: 'Ajustes do usuário',
              subtitle: 'Controle o acesso e as permissões desta conta.',
              icon: Icons.admin_panel_settings_outlined,
              child: Column(
                children: [
                  _SettingSwitch(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Usuário ativo',
                    subtitle: _enabled
                        ? 'O usuário pode acessar o aplicativo.'
                        : 'O acesso está desativado.',
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  Divider(height: 1, color: context.colors.divider),
                  _SettingSwitch(
                    icon: Icons.shield_outlined,
                    title: 'Administrador',
                    subtitle: 'Pode gerenciar usuários e acessar recursos administrativos.',
                    value: _administrator,
                    onChanged: (value) =>
                        setState(() => _administrator = value),
                  ),
                  Divider(height: 1, color: context.colors.divider),
                  _SettingSwitch(
                    icon: Icons.edit_note_rounded,
                    title: 'Permitir edições nas rotinas',
                    subtitle: _canEdit
                        ? 'Pode criar, alterar e executar operações permitidas.'
                        : 'Acesso somente para consulta; alterações ficam indisponíveis.',
                    value: _canEdit,
                    onChanged: (value) => setState(() => _canEdit = value),
                  ),
                  Divider(height: 1, color: context.colors.divider),
                  _SettingSwitch(
                    icon: Icons.route_outlined,
                    title: 'Cobrador',
                    subtitle: _collector
                        ? 'Pode acessar rotas e registrar cobranças nas regiões vinculadas.'
                        : 'O acesso às rotas de cobrança está desativado.',
                    value: _collector,
                    onChanged: (value) => setState(() => _collector = value),
                  ),
                  Divider(height: 1, color: context.colors.divider),
                  _SettingSwitch(
                    icon: Icons.key_rounded,
                    title: 'Solicitar troca de senha',
                    subtitle:
                        'Exige uma nova senha numérica no próximo acesso.',
                    value: _forcePasswordChange,
                    onChanged: (value) =>
                        setState(() => _forcePasswordChange = value),
                  ),
                  if (!_isNew) ...[
                    Divider(height: 1, color: context.colors.divider),
                    _SettingSwitch(
                      icon: Icons.school_outlined,
                      title: 'Exibir tutorial novamente',
                      subtitle: _showTutorial
                          ? 'O tutorial será exibido no próximo acesso deste usuário.'
                          : 'Este usuário já concluiu o tutorial inicial.',
                      value: _showTutorial,
                      onChanged: (value) =>
                          setState(() => _showTutorial = value),
                    ),
                  ],
                  if (_user?.locked == true ||
                      _user?.expired == true ||
                      _user?.credentialsExpired == true) ...[
                    Divider(height: 1, color: context.colors.divider),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_user?.locked == true)
                            const _AccountAlert(label: 'Conta bloqueada'),
                          if (_user?.expired == true)
                            const _AccountAlert(label: 'Conta expirada'),
                          if (_user?.credentialsExpired == true)
                            const _AccountAlert(label: 'Credenciais expiradas'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _displayName {
    final String fullName = [
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
    ].where((value) => value.isNotEmpty).join(' ');
    if (fullName.isNotEmpty) return fullName;
    final String username = _usernameController.text.trim();
    return username.isEmpty ? 'Novo usuário' : username;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      if (widget.userId == null) {
        final List<AppUserRegion> regions = await _userService
            .fetchRegionOptions();
        if (!mounted) return;
        setState(() {
          _regions = regions;
          _selectedRegionIds.clear();
          _enabled = true;
          _canEdit = false;
          _loading = false;
        });
      } else {
        final AppUserDetail user = await _userService.fetchUser(widget.userId!);
        if (!mounted) return;
        _applyUser(user);
        setState(() => _loading = false);
      }
    } on UserServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _loadNewUserRegions() async {
    try {
      final List<AppUserRegion> regions = await _userService
          .fetchRegionOptions();
      if (!mounted || !_isNew) return;
      setState(() => _regions = regions);
    } on UserServiceException {
      // O formulário permanece disponível; a aba de regiões pode ser
      // atualizada ao tentar novamente pela abertura seguinte.
    }
  }

  void _applyUser(AppUserDetail user) {
    _user = user;
    _savedUserId = user.id;
    _firstNameController.text = user.firstName;
    _lastNameController.text = user.lastName;
    _usernameController.text = user.username;
    _emailController.text = user.email;
    _enabled = user.enabled;
    _forcePasswordChange = user.forcePasswordChange;
    _administrator = user.administrator;
    _canEdit = user.canEdit;
    _collector = user.collector;
    _showTutorial = !user.tutorialCompleted;
    _regions = user.regions;
    _selectedRegionIds
      ..clear()
      ..addAll(
        user.regions.where((region) => region.assigned).map((r) => r.id),
      );
  }

  Future<bool> _save({bool showSuccess = true}) async {
    final bool creatingUser = _isNew;
    final String firstName = _firstNameController.text.trim();
    final String username = _usernameController.text.trim().toUpperCase();
    if (firstName.isEmpty || username.isEmpty) {
      await _showMessage(
        title: 'Dados incompletos',
        message: firstName.isEmpty
            ? 'Informe o primeiro nome do usuário.'
            : 'Informe o nome de usuário.',
      );
      return false;
    }
    if (_isNew && _initialPasswordController.text.isEmpty) {
      await _showMessage(
        title: 'Senha obrigatória',
        message: 'Informe a senha inicial do usuário.',
      );
      return false;
    }

    setState(() => _saving = true);
    try {
      final Map<String, dynamic> data = {
        'firstName': firstName,
        'lastName': _lastNameController.text.trim(),
        'username': username,
        'email': _emailController.text.trim(),
        'enabled': _enabled,
        'forcePasswordChange': _forcePasswordChange,
        'administrator': _administrator,
        'canEdit': _canEdit,
        'collector': _collector,
        'regionIds': _selectedRegionIds.toList()..sort(),
      };

      final AppUserDetail saved;
      if (creatingUser) {
        data['password'] = _initialPasswordController.text;
        saved = await _userService.createUser(data);
      } else {
        data.addAll({
          'locked': _user?.locked ?? false,
          'expired': _user?.expired ?? false,
          'credentialsExpired': _user?.credentialsExpired ?? false,
          'showTutorial': _showTutorial,
        });
        saved = await _userService.updateUser(_savedUserId!, data);
      }
      if (!mounted) return false;
      _applyUser(saved);
      setState(() => _saving = false);
      widget.onSaved?.call();
      if (showSuccess) {
        await _showMessage(
          title: creatingUser ? 'Usuário cadastrado' : 'Usuário salvo',
          message: creatingUser
              ? 'Usuário cadastrado com sucesso.'
              : 'As informações foram atualizadas com sucesso.',
        );
      }
      if (creatingUser && mounted) _goBack();
      return true;
    } on UserServiceException catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      await _showMessage(
        title: 'Não foi possível salvar',
        message: error.message,
      );
      return false;
    }
  }

  Future<void> _changePassword() async {
    final String? password = await showAppCupertinoTextInputDialog(
      context: context,
      title: 'Alterar senha',
      placeholder: 'Nova senha numérica',
      confirmLabel: 'Alterar',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      obscureText: true,
    );
    if (password == null || password.isEmpty || _savedUserId == null) return;

    setState(() => _saving = true);
    try {
      await _userService.changePassword(_savedUserId!, password);
      if (!mounted) return;
      setState(() => _saving = false);
      await _showMessage(
        title: 'Senha alterada',
        message: 'A nova senha foi salva com sucesso.',
      );
    } on UserServiceException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await _showMessage(
        title: 'Não foi possível alterar a senha',
        message: error.message,
      );
    }
  }

  Future<void> _showMessage({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showAppCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('OK', style: TextStyle(color: context.colors.primary)),
          ),
        ],
      ),
    );
  }

  void _toggleRegion(int id, bool selected) {
    setState(() {
      if (selected) {
        _selectedRegionIds.add(id);
      } else {
        _selectedRegionIds.remove(id);
      }
    });
  }

  void _toggleAllRegions() {
    setState(() {
      if (_selectedRegionIds.length == _regions.length) {
        _selectedRegionIds.clear();
      } else {
        _selectedRegionIds
          ..clear()
          ..addAll(_regions.map((region) => region.id));
      }
    });
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!.call();
    } else {
      Navigator.of(context).pop();
    }
  }

  bool _hasChanges() {
    final AppUserDetail? user = _user;
    if (user == null) return false;
    final Set<int> originalRegionIds = user.regions
        .where((region) => region.assigned)
        .map((region) => region.id)
        .toSet();
    return _firstNameController.text.trim() != user.firstName ||
        _lastNameController.text.trim() != user.lastName ||
        _usernameController.text.trim().toUpperCase() != user.username ||
        _emailController.text.trim() != user.email ||
        _enabled != user.enabled ||
        _forcePasswordChange != user.forcePasswordChange ||
        _administrator != user.administrator ||
        _canEdit != user.canEdit ||
        _collector != user.collector ||
        _showTutorial != !user.tutorialCompleted ||
        originalRegionIds.length != _selectedRegionIds.length ||
        !originalRegionIds.containsAll(_selectedRegionIds);
  }

  Future<void> _requestClose() async {
    if (_saving || _closing) return;
    _closing = true;
    if (!_isNew && _hasChanges()) {
      final bool discard = await _confirmDiscardChanges();
      if (!mounted) return;
      if (!discard) {
        _closing = false;
        return;
      }
    }
    if (mounted) _goBack();
  }

  Future<bool> _confirmDiscardChanges() async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Descartar alterações?'),
          content: const Text(
            'As alterações realizadas no usuário serão perdidas.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continuar editando'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;
}

class UserProfileHeader extends StatelessWidget {
  final String name;
  final String username;
  final bool enabled;
  final bool administrator;
  final DateTime? lastAccess;
  final VoidCallback? onChangePassword;
  final Widget? topAction;

  const UserProfileHeader({
    super.key,
    required this.name,
    required this.username,
    required this.enabled,
    required this.administrator,
    required this.lastAccess,
    required this.onChangePassword,
    this.topAction,
  });

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      width: double.infinity,
      color: context.colors.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool compact = constraints.maxWidth < 620;
              final Widget identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4B7D60), Color(0xFF76B475)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _profileInitials(name, username),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          username.isEmpty
                              ? 'Configure o novo acesso'
                              : '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            _ProfileChip(
                              label: enabled ? 'Ativo' : 'Desativado',
                              color: enabled
                                  ? context.colors.primary
                                  : context.colors.error,
                            ),
                            if (administrator)
                              _ProfileChip(
                                label: 'Administrador',
                                color: context.colors.primary,
                              ),
                            if (lastAccess != null)
                              _ProfileChip(
                                label: 'Acesso: ${format.format(lastAccess!)}',
                                color: context.colors.textSecondary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (topAction != null) ...[
                    const SizedBox(width: 8),
                    topAction!,
                  ],
                ],
              );
              final Widget? passwordButton = onChangePassword == null
                  ? null
                  : OutlinedButton.icon(
                      onPressed: onChangePassword,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                      icon: const Icon(Icons.password_rounded, size: 16),
                      label: const Text('Alterar senha'),
                    );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    if (passwordButton != null) ...[
                      const SizedBox(height: 8),
                      passwordButton,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  if (passwordButton != null) ...[
                    const SizedBox(width: 14),
                    passwordButton,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final String label;
  final Color color;

  const _ProfileChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: context.colors.primary, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _FieldGrid extends StatelessWidget {
  final List<Widget> fields;
  final bool twoColumns;

  const _FieldGrid({required this.fields, required this.twoColumns});

  @override
  Widget build(BuildContext context) {
    if (!twoColumns) {
      return Column(
        children: [
          for (int index = 0; index < fields.length; index++) ...[
            fields[index],
            if (index != fields.length - 1) const SizedBox(height: 9),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (int index = 0; index < fields.length; index += 2) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: fields[index]),
              const SizedBox(width: 9),
              Expanded(
                child: index + 1 < fields.length
                    ? fields[index + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (index + 2 < fields.length) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  const _AppTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.obscureText = false,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: context.colors.primary, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 42,
        ),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: context.colors.background,
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
          borderSide: BorderSide(color: context.colors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: context.colors.primary, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            subtitle,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
          ),
        ),
        trailing: Transform.scale(
          scale: 0.75,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: context.colors.primary,
            activeTrackColor: context.colors.primary.withValues(alpha: 0.45),
          ),
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }
}

class _AccountAlert extends StatelessWidget {
  final String label;

  const _AccountAlert({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.error,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool saving;
  final bool isNew;
  final bool hasChanges;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  const _SaveBar({
    required this.saving,
    required this.isNew,
    required this.hasChanges,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final showPrimary = isNew || hasChanges;
    final secondaryButton = OutlinedButton(
      onPressed: onCancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.textSecondary,
        side: BorderSide(color: context.colors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(isNew ? 'CANCELAR' : 'VOLTAR'),
    );
    final primaryButton = DecoratedBox(
      decoration: BoxDecoration(
        gradient: CustomFloatingActionButton.gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FilledButton(
        onPressed: onSave,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(isNew ? 'CADASTRAR USUÁRIO' : 'SALVAR ALTERAÇÕES'),
      ),
    );

    return Material(
      color: context.colors.surface,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: mobile
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showPrimary) ...[
                          SizedBox(height: 42, child: primaryButton),
                          const SizedBox(height: 6),
                        ],
                        SizedBox(height: 42, child: secondaryButton),
                      ],
                    )
                  : SizedBox(
                      height: 42,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: secondaryButton),
                          if (showPrimary) ...[
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: primaryButton),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

String _profileInitials(String name, String username) {
  final List<String> parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return username.isEmpty ? '?' : username[0].toUpperCase();
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
