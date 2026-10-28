import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class ProfileScreen extends StatefulWidget {
  final bool showAppBar;
  final bool compact;
  final Future<void> Function()? onLogout;
  final AppUserDetail? initialProfile;

  const ProfileScreen({
    super.key,
    this.showAppBar = true,
    this.compact = false,
    this.onLogout,
    this.initialProfile,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();

  AppUserDetail? _profile;
  bool _loading = true;
  bool _changingPassword = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final AppUserDetail? initialProfile = widget.initialProfile;
    if (initialProfile == null) {
      _load();
    } else {
      _profile = initialProfile;
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: 'Meu perfil',
              leading: const AppSidebarMenuButton(),
              showDefaultActions: false,
              actions: [
                if (widget.onLogout != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 10),
                    child: IconButton(
                      onPressed: _confirmLogout,
                      tooltip: 'Sair',
                      icon: Icon(
                        Icons.logout_rounded,
                        color: context.colors.secondary,
                        size: 23,
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }

    if (_errorMessage != null || _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: context.colors.textSecondary,
                size: 44,
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ?? 'Não foi possível carregar o perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.textSecondary),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final AppUserDetail profile = _profile!;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          UserProfileHeader(
            name: profile.name,
            username: profile.username,
            enabled: profile.enabled,
            administrator: profile.administrator,
            lastAccess: profile.lastAccess,
            onChangePassword: _changingPassword ? null : _changePassword,
            topAction: !widget.showAppBar && widget.onLogout != null
                ? TextButton.icon(
                    onPressed: _confirmLogout,
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.secondary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sair'),
                  )
                : null,
          ),
          Material(
            color: context.colors.surface,
            child: TabBar(
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              indicatorColor: context.colors.primary,
              dividerColor: context.colors.divider,
              tabs: const [
                Tab(text: 'Informações'),
                Tab(text: 'Regiões'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInformationTab(profile),
                _buildRegionsTab(profile.regions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationTab(AppUserDetail profile) {
    final DateFormat dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final String fullName = [
      profile.firstName,
      profile.lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ');

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(10, 9, 10, widget.compact ? 16 : 100),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _ProfileSectionCard(
                title: 'Informações do usuário',
                icon: Icons.badge_outlined,
                children: [
                  _ProfileInformationRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Nome completo',
                    value: fullName.isEmpty ? profile.name : fullName,
                  ),
                  _ProfileInformationRow(
                    icon: Icons.alternate_email_rounded,
                    label: 'Usuário',
                    value: profile.username,
                  ),
                  _ProfileInformationRow(
                    icon: Icons.email_outlined,
                    label: 'E-mail',
                    value: profile.email.isEmpty
                        ? 'Não informado'
                        : profile.email,
                  ),
                  _ProfileInformationRow(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Perfil de acesso',
                    value: profile.administrator ? 'Administrador' : 'Usuário',
                  ),
                  _ProfileInformationRow(
                    icon: Icons.edit_note_rounded,
                    label: 'Permissão nas rotinas',
                    value: profile.canEdit
                        ? 'Pode realizar edições'
                        : 'Somente visualização',
                  ),
                  _ProfileInformationRow(
                    icon: Icons.schedule_rounded,
                    label: 'Último acesso',
                    value: profile.lastAccess == null
                        ? 'Não registrado'
                        : dateFormat.format(profile.lastAccess!),
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionsTab(List<AppUserRegion> regions) {
    final List<AppUserRegion> assignedRegions = regions
        .where((region) => region.assigned)
        .toList(growable: false);

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(10, 9, 10, widget.compact ? 16 : 100),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _ProfileSectionCard(
                title: 'Regiões de acesso',
                icon: Icons.location_on_outlined,
                subtitle: assignedRegions.isEmpty
                    ? 'Nenhuma região vinculada ao seu usuário.'
                    : '${assignedRegions.length} ${assignedRegions.length == 1 ? 'região vinculada' : 'regiões vinculadas'}.',
                children: assignedRegions.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Solicite ao administrador o acesso às regiões necessárias.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ]
                    : [
                        for (
                          int index = 0;
                          index < assignedRegions.length;
                          index++
                        )
                          _ProfileInformationRow(
                            icon: Icons.location_on_rounded,
                            label: 'Região',
                            value: assignedRegions[index].name.isEmpty
                                ? 'Região #${assignedRegions[index].id}'
                                : assignedRegions[index].name,
                            showDivider: index != assignedRegions.length - 1,
                          ),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final AppUserDetail profile = await _userService.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on UserServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _changePassword() async {
    final String? password = await _requestNewPassword();
    if (password == null || !mounted) return;

    setState(() => _changingPassword = true);
    try {
      await _authService.changeRequiredPassword(password);
      if (!mounted) return;
      setState(() => _changingPassword = false);
      await _showMessage(
        title: 'Senha alterada',
        message: 'Sua nova senha foi salva com sucesso.',
      );
    } on AuthenticationException catch (error) {
      if (!mounted) return;
      setState(() => _changingPassword = false);
      await _showMessage(
        title: 'Não foi possível alterar a senha',
        message: error.message,
      );
    }
  }

  Future<String?> _requestNewPassword() async {
    return showAppCupertinoDialog<String>(
      context: context,
      builder: (_) => const _ProfilePasswordDialog(),
    );
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

  Future<void> _confirmLogout() async {
    final Future<void> Function()? onLogout = widget.onLogout;
    if (onLogout == null) return;
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Sair do Money?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Sua sessão será encerrada e será necessário informar a senha novamente.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onLogout();
  }
}

class _ProfilePasswordDialog extends StatefulWidget {
  const _ProfilePasswordDialog();

  @override
  State<_ProfilePasswordDialog> createState() => _ProfilePasswordDialogState();
}

class _ProfilePasswordDialogState extends State<_ProfilePasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: const Text('Alterar senha'),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          _field(
            controller: _password,
            placeholder: 'Nova senha numérica',
            obscure: _obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          const SizedBox(height: 8),
          _field(
            controller: _confirmation,
            placeholder: 'Confirmar nova senha',
            obscure: _obscureConfirmation,
            onToggle: () =>
                setState(() => _obscureConfirmation = !_obscureConfirmation),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: context.colors.error, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: _submit,
        child: const Text('Alterar'),
      ),
    ],
  );

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    required bool obscure,
    required VoidCallback onToggle,
  }) => CupertinoTextField(
    controller: controller,
    placeholder: placeholder,
    keyboardType: TextInputType.number,
    obscureText: obscure,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 4, 11),
    suffix: CupertinoButton(
      minimumSize: const Size.square(34),
      padding: EdgeInsets.zero,
      onPressed: onToggle,
      child: Icon(
        obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
        size: 18,
      ),
    ),
  );

  void _submit() {
    final String password = _password.text;
    final String confirmation = _confirmation.text;
    final String? validationMessage = switch (password) {
      String value when value.length < 4 =>
        'A senha deve ter pelo menos 4 números.',
      String value when value.length > 64 =>
        'A senha deve ter no máximo 64 números.',
      String value when value != confirmation =>
        'As senhas informadas são diferentes.',
      _ => null,
    };
    if (validationMessage != null) {
      setState(() => _error = validationMessage);
      return;
    }
    Navigator.pop(context, password);
  }
}

class _ProfileSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  const _ProfileSectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _ProfileInformationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  const _ProfileInformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.5),
          child: Row(
            children: [
              Icon(icon, color: context.colors.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: context.colors.divider),
      ],
    );
  }
}
