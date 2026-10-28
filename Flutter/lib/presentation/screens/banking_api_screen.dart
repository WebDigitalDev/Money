import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money/money.dart';

class BankingApiScreenController {
  VoidCallback? _openCreate;

  void openCreate() => _openCreate?.call();
}

class BankingApiScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final BankingApiScreenController? controller;

  const BankingApiScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
  });

  @override
  State<BankingApiScreen> createState() => _BankingApiScreenState();
}

class _BankingApiScreenState extends State<BankingApiScreen> {
  final IntegrationService _service = IntegrationService();
  final RegionService _regionService = RegionService();
  List<AppBankAccount> _accounts = const [];
  List<AppRegionOption> _regions = const [];
  bool _loading = true;
  String? _error;

  bool get _principalAdministrator =>
      AuthService().currentSession?.administrator == true &&
      AuthService().currentSession?.userId == 1;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    _load();
  }

  @override
  void didUpdateWidget(covariant BankingApiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (widget.active && !oldWidget.active) _load(silent: true);
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController(BankingApiScreenController? controller) {
    controller?._openCreate = _principalAdministrator ? _create : null;
  }

  void _detachController(BankingApiScreenController? controller) {
    controller?._openCreate = null;
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait<Object>([
        _service.fetchBankAccounts(),
        _regionService.fetchOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = results[0] as List<AppBankAccount>;
        _regions = results[1] as List<AppRegionOption>;
        _loading = false;
        _error = null;
      });
    } on IntegrationServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on RegionServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.sidebar_banking_api,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        color: context.colors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!compact)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                sliver: SliverToBoxAdapter(child: _header()),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(message: _error!, onRetry: _load),
              )
            else if (_accounts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyBanking(
                  onCreate: !compact && _principalAdministrator
                      ? _create
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 16,
                  compact ? 10 : 4,
                  compact ? 10 : 16,
                  28,
                ),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final bool grid = constraints.crossAxisExtent >= 900;
                    return grid
                        ? SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: 190,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (_, index) => _accountCard(
                                _accounts[index],
                                compact: false,
                              ),
                              childCount: _accounts.length,
                            ),
                          )
                        : SliverList.separated(
                            itemCount: _accounts.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: compact ? 6 : 10),
                            itemBuilder: (_, index) => _accountCard(
                              _accounts[index],
                              compact: compact,
                            ),
                          );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contas bancárias',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Vincule as regiões às contas Sicredi usadas na geração de PIX.',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        if (_principalAdministrator)
          FilledButton(
            onPressed: _create,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'NOVA CONTA',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _accountCard(AppBankAccount account, {required bool compact}) {
    final Color statusColor = account.active
        ? context.colors.primary
        : context.colors.textSecondary;
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 13 : 16),
        side: BorderSide(color: context.colors.divider),
      ),
      child: InkWell(
        onTap: () => _edit(account),
        borderRadius: BorderRadius.circular(compact ? 13 : 16),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: compact ? 64 : 76,
                    height: compact ? 30 : 36,
                    child: Image.asset(
                      'assets/images/sicredi.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 13.5 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          account.bank,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: compact ? 10.5 : 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 7 : 9,
                      vertical: compact ? 3 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      account.active ? 'Ativa' : 'Inativa',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: compact ? 9.5 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 14),
              _line(
                Icons.location_on_outlined,
                account.regionNames.isEmpty
                    ? 'Nenhuma região vinculada'
                    : account.regionNames.join(', '),
              ),
              SizedBox(height: compact ? 5 : 8),
              _line(
                account.credentialsReady
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber_rounded,
                account.credentialsReady
                    ? 'Credenciais e certificados configurados'
                    : 'Configuração bancária incompleta',
              ),
              SizedBox(height: compact ? 7 : 14),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  'Gerenciar  ›',
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 10.5 : 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 16, color: context.colors.primary),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12.5),
        ),
      ),
    ],
  );

  Future<void> _create() async {
    final String? name = await _textDialog(
      'Nova conta bancária',
      'Nome da conta',
    );
    if (name == null || name.trim().isEmpty) return;
    await _execute(
      () => _service.createBankAccount(name: name.trim(), regionIds: const []),
      'Conta criada com sucesso.',
    );
  }

  Future<void> _edit(AppBankAccount account) async {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    final List<AppRegionOption> availableRegions = _availableRegionsFor(
      account,
    );
    final bool? changed = desktop
        ? await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _BankAccountDialog(
              account: account,
              regions: availableRegions,
              principalAdministrator: _principalAdministrator,
              service: _service,
            ),
          )
        : await showAppBottomSheet<bool>(
            context: context,
            title: 'Configurar conta Sicredi',
            subtitle: 'Regiões, credenciais PIX e certificados.',
            icon: Icons.account_balance_rounded,
            heightFactor: .84,
            builder: (_) => _BankAccountDialog(
              account: account,
              regions: availableRegions,
              principalAdministrator: _principalAdministrator,
              service: _service,
              embedded: true,
            ),
          );
    if (changed == true) await _load(silent: true);
  }

  List<AppRegionOption> _availableRegionsFor(AppBankAccount account) {
    final Set<int> linkedToOtherAccounts = _accounts
        .where((other) => other.id != account.id)
        .expand((other) => other.regionIds)
        .toSet();

    return _regions
        .where((region) => !linkedToOtherAccounts.contains(region.id))
        .toList(growable: false);
  }

  Future<void> _execute(
    Future<AppBankAccount> Function() operation,
    String success,
  ) async {
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _load(silent: true);
    } on IntegrationServiceException catch (error) {
      if (mounted) await _alert(error.message);
    }
  }

  Future<String?> _textDialog(String title, String hint) {
    return showAppCupertinoTextInputDialog(
      context: context,
      title: title,
      placeholder: hint,
    );
  }

  Future<void> _alert(String message) => showAppCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Não foi possível concluir'),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class _BankAccountDialog extends StatefulWidget {
  final AppBankAccount account;
  final List<AppRegionOption> regions;
  final bool principalAdministrator;
  final IntegrationService service;
  final bool embedded;

  const _BankAccountDialog({
    required this.account,
    required this.regions,
    required this.principalAdministrator,
    required this.service,
    this.embedded = false,
  });

  @override
  State<_BankAccountDialog> createState() => _BankAccountDialogState();
}

class _BankAccountDialogState extends State<_BankAccountDialog> {
  late final TextEditingController _name;
  final TextEditingController _clientId = TextEditingController();
  final TextEditingController _clientSecret = TextEditingController();
  late final TextEditingController _pixKey;
  late Set<int> _regions;
  late bool _active;
  bool _saving = false;
  XFile? _certificate;
  XFile? _privateKey;
  XFile? _chain;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account.name);
    _pixKey = TextEditingController(text: widget.account.pixKey);
    _regions = widget.account.regionIds.toSet();
    _active = widget.account.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _pixKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = widget.embedded;
    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
      child: Column(
        children: [
          if (!widget.embedded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_rounded,
                    color: context.colors.primary,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Configurar conta Sicredi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.divider),
          ],
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 12 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.principalAdministrator) ...[
                    TextField(
                      controller: _name,
                      style: TextStyle(fontSize: compact ? 12 : 14),
                      decoration: _inputDecoration(
                        'Nome da conta',
                        compact: compact,
                      ),
                    ),
                    SizedBox(height: compact ? 9 : 14),
                  ],
                  _sectionTitle('Regiões vinculadas', compact: compact),
                  SizedBox(height: compact ? 5 : 7),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: compact ? 140 : 180),
                    child: Material(
                      color: context.colors.background,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: context.colors.divider),
                      ),
                      child: widget.regions.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('Nenhuma região disponível.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: widget.regions.length,
                              itemBuilder: (_, index) {
                                final region = widget.regions[index];
                                return SizedBox(
                                  height: compact ? 34 : null,
                                  child: CheckboxListTile(
                                    dense: true,
                                    visualDensity: compact
                                        ? const VisualDensity(
                                            horizontal: -4,
                                            vertical: -4,
                                          )
                                        : null,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: compact ? 8 : 12,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    value: _regions.contains(region.id),
                                    title: Text(
                                      region.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 10.5 : 13,
                                      ),
                                    ),
                                    onChanged: (value) => setState(
                                      () => value == true
                                          ? _regions.add(region.id)
                                          : _regions.remove(region.id),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  if (widget.principalAdministrator) ...[
                    SizedBox(height: compact ? 10 : 18),
                    Row(
                      children: [
                        Expanded(
                          child: _sectionTitle(
                            'Credenciais PIX',
                            compact: compact,
                          ),
                        ),
                        SizedBox(
                          width: compact ? 42 : 52,
                          height: compact ? 28 : 40,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Switch(
                              value: _active,
                              onChanged: (value) =>
                                  setState(() => _active = value),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    TextField(
                      controller: _clientId,
                      style: TextStyle(fontSize: compact ? 12 : 14),
                      decoration: _inputDecoration(
                        'Client ID',
                        compact: compact,
                        hintText: widget.account.clientIdConfigured
                            ? 'Configurado — deixe vazio para manter'
                            : null,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 10),
                    TextField(
                      controller: _clientSecret,
                      obscureText: true,
                      style: TextStyle(fontSize: compact ? 12 : 14),
                      decoration: _inputDecoration(
                        'Client Secret',
                        compact: compact,
                        hintText: widget.account.clientSecretConfigured
                            ? 'Configurado — deixe vazio para manter'
                            : null,
                      ),
                    ),
                    SizedBox(height: compact ? 5 : 10),
                    TextField(
                      controller: _pixKey,
                      style: TextStyle(fontSize: compact ? 12 : 14),
                      decoration: _inputDecoration(
                        'Chave PIX',
                        compact: compact,
                      ),
                    ),
                    SizedBox(height: compact ? 10 : 18),
                    _sectionTitle('Certificados mTLS', compact: compact),
                    SizedBox(height: compact ? 5 : 8),
                    _fileTile(
                      'Certificado .CER',
                      _certificate?.name ?? widget.account.certificateName,
                      () => _pick('certificate'),
                    ),
                    _fileTile(
                      'Chave privada .KEY',
                      _privateKey?.name ?? widget.account.privateKeyName,
                      () => _pick('key'),
                    ),
                    _fileTile(
                      'Cadeia de certificados (opcional)',
                      _chain?.name ?? widget.account.certificateChainName,
                      () => _pick('chain'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 14,
              compact ? 7 : 14,
              compact ? 10 : 14,
              compact ? 7 : 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: compact
                      ? TextButton.styleFrom(
                          minimumSize: const Size(72, 34),
                          textStyle: const TextStyle(fontSize: 11),
                        )
                      : null,
                  child: const Text('CANCELAR'),
                ),
                SizedBox(width: compact ? 5 : 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: compact
                      ? FilledButton.styleFrom(
                          minimumSize: const Size(82, 34),
                          textStyle: const TextStyle(fontSize: 11),
                        )
                      : null,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('SALVAR'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) {
      return Material(color: context.colors.surface, child: content);
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: content,
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    required bool compact,
    String? hintText,
  }) => InputDecoration(
    labelText: label,
    hintText: hintText,
    isDense: compact,
    labelStyle: compact ? const TextStyle(fontSize: 11) : null,
    hintStyle: compact ? const TextStyle(fontSize: 10.5) : null,
    contentPadding: compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
        : null,
  );

  Widget _sectionTitle(String value, {bool compact = false}) => Text(
    value,
    style: TextStyle(
      fontSize: compact ? 11.5 : 13,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _fileTile(String label, String? fileName, VoidCallback onTap) =>
      Padding(
        padding: EdgeInsets.only(bottom: widget.embedded ? 5 : 8),
        child: Material(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(11),
          child: ListTile(
            dense: true,
            visualDensity: widget.embedded
                ? const VisualDensity(horizontal: -3, vertical: -3)
                : null,
            contentPadding: EdgeInsets.symmetric(
              horizontal: widget.embedded ? 9 : 16,
            ),
            leading: Icon(
              Icons.key_rounded,
              color: context.colors.primary,
              size: widget.embedded ? 17 : 20,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontSize: widget.embedded ? 10.5 : 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              fileName ?? 'Nenhum arquivo selecionado',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: widget.embedded ? 9.5 : null),
            ),
            trailing: Icon(
              Icons.upload_file_rounded,
              size: widget.embedded ? 18 : 24,
            ),
            onTap: onTap,
          ),
        ),
      );

  Future<void> _pick(String type) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Certificados',
          extensions: type == 'key'
              ? const ['key', 'pem']
              : const ['cer', 'crt', 'pem'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    setState(() {
      if (type == 'certificate') _certificate = file;
      if (type == 'key') _privateKey = file;
      if (type == 'chain') _chain = file;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      AppBankAccount result = await widget.service.updateBankAccount(
        widget.account.id,
        name: widget.principalAdministrator ? _name.text.trim() : null,
        regionIds: _regions.toList(),
      );
      if (widget.principalAdministrator &&
          (_certificate != null || _privateKey != null || _chain != null)) {
        result = await widget.service.uploadSicrediFiles(
          result.id,
          certificate: _certificate,
          privateKey: _privateKey,
          certificateChain: _chain,
        );
      }
      if (widget.principalAdministrator) {
        await widget.service.saveSicredi(
          result.id,
          active: _active,
          clientId: _clientId.text.trim(),
          clientSecret: _clientSecret.text.trim(),
          pixKey: _pixKey.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on IntegrationServiceException catch (error) {
      if (!mounted) return;
      await showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Não foi possível salvar'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error.message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 46,
            color: context.colors.primary,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyBanking extends StatelessWidget {
  final VoidCallback? onCreate;

  const _EmptyBanking({this.onCreate});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_outlined,
            size: 50,
            color: context.colors.primary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Nenhuma conta bancária cadastrada.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (onCreate != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar conta'),
            ),
          ],
        ],
      ),
    ),
  );
}
