import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class WhatsappApiScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;

  const WhatsappApiScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
  });

  @override
  State<WhatsappApiScreen> createState() => _WhatsappApiScreenState();
}

class _WhatsappApiScreenState extends State<WhatsappApiScreen>
    with SingleTickerProviderStateMixin {
  final IntegrationService _service = IntegrationService();
  final RegionService _regionService = RegionService();
  late final TabController _tabs;
  List<AppWhatsappDevice> _devices = const [];
  List<AppWhatsappLog> _logs = const [];
  List<AppRegionOption> _regions = const [];
  AppWhatsappConfig? _config;
  bool _loading = true;
  bool _working = false;
  String? _error;
  Timer? _poll;

  bool get _principalAdministrator =>
      AuthService().currentSession?.administrator == true &&
      AuthService().currentSession?.userId == 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant WhatsappApiScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load(silent: true);
    _configurePolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 1) _loadLogs(silent: true);
  }

  void _configurePolling() {
    _poll?.cancel();
    if (widget.active && _devices.any((device) => device.dispatching)) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _loadDeviceProgress();
        if (_tabs.index == 1) await _loadLogs(silent: true);
      });
    }
  }

  Future<void> _loadDeviceProgress() async {
    try {
      final List<AppWhatsappDevice> devices = await _service
          .fetchWhatsappDeviceProgress();
      if (!mounted) return;
      final bool wasDispatching = _devices.any((device) => device.dispatching);
      final Map<int, AppWhatsappDevice> progressById = {
        for (final AppWhatsappDevice device in devices) device.id: device,
      };
      final List<AppWhatsappDevice> visibleDevices = _devices
          .map((device) => progressById[device.id] ?? device)
          .toList(growable: false);
      final bool isDispatching = visibleDevices.any(
        (device) => device.dispatching,
      );
      setState(() => _devices = visibleDevices);
      _configurePolling();
      if (wasDispatching && !isDispatching) {
        await _loadLogs(silent: true);
      }
    } on IntegrationServiceException {
      // O próximo ciclo tenta novamente sem interromper a tela.
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final values = await Future.wait<Object>([
        _service.fetchWhatsappConfig(),
        _service.fetchWhatsappDevices(),
        _service.fetchWhatsappLogs(),
        _regionService.fetchOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = values[0] as AppWhatsappConfig;
        _devices = values[1] as List<AppWhatsappDevice>;
        _logs = values[2] as List<AppWhatsappLog>;
        _regions = values[3] as List<AppRegionOption>;
        _loading = false;
        _error = null;
      });
      _configurePolling();
    } on IntegrationServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _loadDevices({bool silent = false}) async {
    try {
      final devices = await _service.fetchWhatsappDevices();
      if (!mounted) return;
      setState(() => _devices = devices);
      _configurePolling();
    } on IntegrationServiceException catch (error) {
      if (!silent && mounted) await _alert(error.message);
    }
  }

  Future<void> _loadLogs({bool silent = false}) async {
    try {
      final logs = await _service.fetchWhatsappLogs();
      if (mounted) setState(() => _logs = logs);
    } on IntegrationServiceException catch (error) {
      if (!silent && mounted) await _alert(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.sidebar_whatsapp_api,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _WhatsappError(message: _error!, onRetry: _load)
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 8,
                    compact ? 8 : 14,
                    compact ? 10 : 8,
                    compact ? 5 : 8,
                  ),
                  child: _summary(compact: compact),
                ),
                Material(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: TabBar(
                    controller: _tabs,
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
                    tabs: const [
                      Tab(height: 39, text: 'Dispositivos'),
                      Tab(height: 39, text: 'Logs'),
                      Tab(height: 39, text: 'Configuração'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [_devicesTab(), _logsTab(), _configurationTab()],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summary({required bool compact}) {
    final bool active = _config?.active == true;
    final int connected = _devices.where((device) => device.connected).length;
    return Row(
      children: [
        Container(
          width: compact ? 36 : 44,
          height: compact ? 36 : 44,
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compact ? 10 : 13),
          ),
          padding: EdgeInsets.all(compact ? 5 : 7),
          child: Image.asset('assets/images/whats.webp', fit: BoxFit.contain),
        ),
        SizedBox(width: compact ? 8 : 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhatsApp WebDigital',
                style: TextStyle(
                  fontSize: compact ? 13.5 : 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                active
                    ? '$connected dispositivo(s) conectado(s)'
                    : 'Integração desativada',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: compact ? 10.5 : 12.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 3 : 6,
          ),
          decoration: BoxDecoration(
            color: (active ? context.colors.primary : Colors.orange).withValues(
              alpha: 0.13,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            active ? 'Ativa' : 'Inativa',
            style: TextStyle(
              color: active ? context.colors.primary : Colors.orange.shade800,
              fontSize: compact ? 9.5 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _devicesTab() {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final double bottomClearance = compact ? 124 : 24;
    if (_devices.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadDevices,
        child: ListView(
          padding: EdgeInsets.only(bottom: bottomClearance),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            Icon(
              Icons.phone_android_rounded,
              size: 48,
              color: context.colors.primary,
            ),
            const SizedBox(height: 10),
            const Center(child: Text('Nenhum dispositivo sincronizado.')),
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                onPressed: _loadDevices,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sincronizar'),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool grid = constraints.maxWidth >= 900;
          if (grid) {
            return GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottomClearance),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: _devices.any((device) => device.dispatching)
                    ? 275
                    : 235,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _devices.length,
              itemBuilder: (_, index) => _deviceCard(_devices[index]),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(10, 4, 10, bottomClearance),
            itemCount: _devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, index) => _deviceCard(_devices[index]),
          );
        },
      ),
    );
  }

  Widget _deviceCard(AppWhatsappDevice device) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final bool disconnected = device.status == 'DESCONECTADO';
    final Color statusColor = device.connected
        ? context.colors.primary
        : disconnected
        ? Colors.red
        : Colors.orange;
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 34 : 40,
                height: compact ? 34 : 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(compact ? 9 : 12),
                ),
                padding: EdgeInsets.all(compact ? 4 : 5),
                child: Image.asset(
                  'assets/images/whats.webp',
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 12.5 : 15,
                      ),
                    ),
                    Text(
                      [
                        if (device.phone != null) device.phone!,
                        if (device.provider != null)
                          device.provider!.toUpperCase(),
                      ].join(' • '),
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: compact ? 9.5 : 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              _badge(
                device.dispatching ? 'Disparando' : device.status,
                device.dispatching ? Colors.orange : statusColor,
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 11),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: context.colors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  device.regionNames.isEmpty
                      ? 'Nenhuma região vinculada'
                      : device.regionNames.join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: compact ? 10.5 : 12,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _smallAction('Status', () => _refresh(device)),
              _smallAction('Regiões', () => _chooseRegions(device)),
              _smallAction(
                'Teste',
                device.connected && !device.dispatching
                    ? () => _test(device)
                    : null,
              ),
              if (device.dispatching)
                _smallAction('Parar', () => _stop(device), destructive: true)
              else
                _smallAction(
                  'Disparar',
                  device.connected ? () => _dispatch(device) : null,
                  primary: true,
                ),
            ],
          ),
          if (device.dispatching) ...[
            SizedBox(height: compact ? 9 : 13),
            _dispatchProgress(device, compact: compact),
          ],
        ],
      ),
    );
  }

  Widget _dispatchProgress(AppWhatsappDevice device, {required bool compact}) {
    final int percent = (device.dispatchProgress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Processando ${device.dispatchProcessed} de ${device.dispatchTotal}',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: compact ? 9.5 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                color: context.colors.primary,
                fontSize: compact ? 10 : 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: compact ? 6 : 7,
            value: device.dispatchProgress,
            backgroundColor: context.colors.primary.withValues(alpha: .13),
            valueColor: AlwaysStoppedAnimation<Color>(context.colors.primary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${device.dispatchSucceeded} enviados • ${device.dispatchErrors} erros • ${device.dispatchIgnored} ignorados',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: compact ? 9 : 10.5,
          ),
        ),
      ],
    );
  }

  Widget _logsTab() {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    final double bottomClearance = compact ? 124 : 24;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_logs.length} registro(s) recentes',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _loadLogs,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Limpar logs',
                onPressed: _logs.isEmpty ? null : _clearLogs,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: _logs.isEmpty
              ? const Center(child: Text('Nenhum log de WhatsApp.'))
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, bottomClearance),
                  itemCount: _logs.length,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
                  itemBuilder: (_, index) => _logRow(_logs[index]),
                ),
        ),
      ],
    );
  }

  Widget _logRow(AppWhatsappLog log) {
    final String status = log.status.trim().toUpperCase();
    final bool success = status == 'SUCESSO';
    final bool warning = status == 'AVISO';
    final Color color = success
        ? context.colors.primary
        : (status == 'ERRO'
              ? Colors.redAccent
              : (warning ? Colors.blueGrey : Colors.orange));
    final String region = log.regionName?.trim().isNotEmpty == true
        ? log.regionName!.trim()
        : (log.deviceName?.trim().isNotEmpty == true
              ? log.deviceName!.trim()
              : 'SISTEMA');
    return Material(
      color: context.colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: context.colors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              region.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  success
                      ? Icons.check_circle_outline_rounded
                      : warning
                      ? Icons.info_outline_rounded
                      : Icons.error_outline_rounded,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _logDescription(log),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _legacyLogStatus(log.status),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _logDetails(log),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _dateTime(log.createdAt),
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: context.colors.divider),
        ],
      ),
    );
  }

  String _logDescription(AppWhatsappLog log) {
    final String client = log.clientName?.trim().isNotEmpty == true
        ? log.clientName!.trim()
        : 'cliente';
    switch (log.status.trim().toUpperCase()) {
      case 'SUCESSO':
        return 'Mensagem enviada para $client';
      case 'ERRO':
        final String error = log.error?.trim() ?? '';
        if (error.isEmpty) return 'Falha no disparo para $client';
        if (error.contains('JDBC exception') ||
            error.contains('SQL [') ||
            error.contains('syntax error')) {
          return 'Falha ao buscar clientes para o disparo.';
        }
        return error.length > 150 ? '${error.substring(0, 147)}...' : error;
      case 'AVISO':
        return log.error?.trim().isNotEmpty == true
            ? log.error!.trim()
            : 'Nenhum cliente encontrado para este disparo.';
      default:
        return 'Disparo para $client';
    }
  }

  String _legacyLogStatus(String value) {
    switch (value.trim().toUpperCase()) {
      case 'SUCESSO':
        return 'OK';
      case 'ERRO':
        return 'ERRO';
      default:
        final String status = value.trim().toUpperCase();
        return status.isEmpty ? 'PENDENTE' : status;
    }
  }

  String _legacyLogType(String value) {
    switch (value.trim().toUpperCase()) {
      case 'VENCE_HOJE':
        return 'Vence hoje';
      case 'DESAPARECIDAS':
        return 'Desaparecidas';
      case 'TESTE':
        return 'Teste';
      case 'PIX':
        return 'PIX enviado';
      case 'PIX_RECEBIDO':
        return 'PIX recebido';
      case 'AQUISICAO':
        return 'Aquisição';
      case 'EMPRESTIMO_ATUALIZADO':
        return 'Mensagem atualizada';
      default:
        return 'Atrasadas';
    }
  }

  String _logDetails(AppWhatsappLog log) {
    final List<String> parts = [_legacyLogType(log.type)];
    final String phone = _formatLogPhone(log.phone);
    parts.add(phone.isEmpty ? 'sem telefone' : phone);
    if (log.loanId != null) parts.add('Contrato ${log.loanId}');
    return parts.join(' • ');
  }

  String _formatLogPhone(String? value) {
    String digits = brazilianPhoneDigits(value ?? '');
    if ((digits.length == 12 || digits.length == 13) &&
        digits.startsWith('55')) {
      digits = digits.substring(2);
    }
    return formatBrazilianPhone(digits);
  }

  Widget _configurationTab() {
    if (_config == null) return const SizedBox.shrink();
    if (!_principalAdministrator) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Somente o usuário ADMINISTRADOR pode alterar o token e as mensagens.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ),
      );
    }
    return _WhatsappConfigurationForm(
      key: ValueKey('${_config!.active}-${_config!.tokenConfigured}'),
      config: _config!,
      saving: _working,
      onSave: _saveConfiguration,
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );

  Widget _smallAction(
    String label,
    VoidCallback? onTap, {
    bool destructive = false,
    bool primary = false,
  }) {
    final VoidCallback? action = _working ? null : onTap;
    final Widget child = Text(
      label.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    );
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    if (primary) {
      return FilledButton(
        onPressed: action,
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: context.colors.primary.withValues(
            alpha: .28,
          ),
          disabledForegroundColor: Colors.white.withValues(alpha: .78),
          minimumSize: const Size(78, 36),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          visualDensity: VisualDensity.compact,
          elevation: 0,
          shape: shape,
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: action,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive
            ? Colors.redAccent
            : context.colors.textPrimary,
        disabledForegroundColor: context.colors.disabled,
        minimumSize: const Size(78, 36),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: shape,
        side: BorderSide(
          color: destructive
              ? Colors.redAccent.withValues(alpha: .55)
              : context.colors.divider,
        ),
      ),
      child: child,
    );
  }

  Future<void> _refresh(AppWhatsappDevice device) async {
    await _run(
      () => _service.refreshWhatsappDevice(device.id),
      'Status atualizado.',
    );
  }

  Future<void> _chooseRegions(AppWhatsappDevice device) async {
    final Set<int> selected = device.regionIds.toSet();
    final Set<int> regionsUsedByOtherDevices = _devices
        .where((item) => item.id != device.id)
        .expand((item) => item.regionIds)
        .toSet();
    final List<AppRegionOption> availableRegions = _regions
        .where(
          (region) =>
              selected.contains(region.id) ||
              !regionsUsedByOtherDevices.contains(region.id),
        )
        .toList(growable: false);
    final Set<int>? result = await showRegionSelectionDialog(
      context: context,
      options: availableRegions,
      selected: selected,
      subtitle: 'Marque as regiões vinculadas a este dispositivo.',
      emptySelectionLabel: 'Nenhuma região marcada',
    );
    if (result == null) return;
    final List<int> regionIds = result.toList()..sort();
    await _run(
      () => _service.updateWhatsappDeviceRegions(device.id, regionIds),
      'Regiões atualizadas.',
    );
  }

  Future<void> _test(AppWhatsappDevice device) async {
    final String? phone = await _textDialog(
      'Enviar mensagem de teste',
      'Telefone com DDD',
    );
    if (phone == null || phone.trim().isEmpty) return;
    await _run(
      () => _service.testWhatsappDevice(device.id, phone.trim()),
      'Mensagem de teste enviada.',
    );
    await _loadLogs(silent: true);
  }

  Future<void> _dispatch(AppWhatsappDevice device) async {
    final String? type = await showCupertinoModalPopup<String>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text('Disparar com ${device.name}'),
        message: const Text(
          'As mensagens são enviadas com intervalo seguro e ficam registradas nos logs.',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'ATRASADAS'),
            child: const Text('Parcelas atrasadas'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'VENCE_HOJE'),
            child: const Text('Parcelas que vencem hoje'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'DESAPARECIDAS'),
            child: const Text('Clientes desaparecidos'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, 'AQUISICAO'),
            child: const Text('Aquisição de clientes quitados'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (type == null) return;
    if (!mounted) return;
    final String dispatchLabel = switch (type) {
      'VENCE_HOJE' => 'parcelas que vencem hoje',
      'DESAPARECIDAS' => 'clientes desaparecidos',
      'AQUISICAO' => 'clientes quitados sem contrato aberto',
      _ => 'parcelas atrasadas',
    };
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Iniciar disparo?'),
            content: Text(
              'O dispositivo ${device.name} enviará mensagens para $dispatchLabel nas regiões vinculadas.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Iniciar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _working = true);
    try {
      final String message = await _service.startWhatsappDispatch(
        device.id,
        type,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadDeviceProgress();
    } on IntegrationServiceException catch (error) {
      if (mounted) await _alert(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop(AppWhatsappDevice device) async {
    if (!await _confirm(
      'Interromper disparo?',
      'As mensagens que ainda não foram processadas não serão enviadas.',
    )) {
      return;
    }
    await _run(
      () => _service.stopWhatsappDispatch(device.id),
      'Disparo interrompido.',
    );
  }

  Future<void> _clearLogs() async {
    if (!await _confirm(
      'Limpar todos os logs?',
      'Esta ação remove o histórico recente de disparos do novo backend.',
    )) {
      return;
    }
    setState(() => _working = true);
    try {
      await _service.clearWhatsappLogs();
      if (mounted) setState(() => _logs = const []);
    } on IntegrationServiceException catch (error) {
      if (mounted) await _alert(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveConfiguration(Map<String, dynamic> data) async {
    setState(() => _working = true);
    try {
      final config = await _service.saveWhatsappConfig(data);
      if (!mounted) return;
      setState(() => _config = config);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração do WhatsApp salva.')),
      );
      await _loadDevices(silent: true);
    } on IntegrationServiceException catch (error) {
      if (mounted) await _alert(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _run(Future<Object> Function() operation, String success) async {
    setState(() => _working = true);
    try {
      await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _loadDevices(silent: true);
    } on IntegrationServiceException catch (error) {
      if (mounted) await _alert(error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _textDialog(String title, String label) {
    return showAppCupertinoTextInputDialog(
      context: context,
      title: title,
      placeholder: label,
      confirmLabel: 'Enviar',
      keyboardType: TextInputType.phone,
    );
  }

  Future<bool> _confirm(String title, String message) async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

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

  String _dateTime(DateTime? value) => value == null
      ? '—'
      : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
}

class _WhatsappConfigurationForm extends StatefulWidget {
  final AppWhatsappConfig config;
  final bool saving;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _WhatsappConfigurationForm({
    super.key,
    required this.config,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_WhatsappConfigurationForm> createState() =>
      _WhatsappConfigurationFormState();
}

class _WhatsappConfigurationFormState
    extends State<_WhatsappConfigurationForm> {
  late bool _active;
  final TextEditingController _token = TextEditingController();
  late final TextEditingController _overdue;
  late final TextEditingController _dueToday;
  late final TextEditingController _missing;
  late final TextEditingController _acquisition;
  late final TextEditingController _pix;
  late final TextEditingController _pixReceived;

  @override
  void initState() {
    super.initState();
    _active = widget.config.active;
    _overdue = TextEditingController(text: widget.config.overdueMessage);
    _dueToday = TextEditingController(text: widget.config.dueTodayMessage);
    _missing = TextEditingController(text: widget.config.missingMessage);
    _acquisition = TextEditingController(
      text: widget.config.acquisitionMessage,
    );
    _pix = TextEditingController(text: widget.config.pixMessage);
    _pixReceived = TextEditingController(
      text: widget.config.pixReceivedMessage,
    );
  }

  @override
  void dispose() {
    _token.dispose();
    _overdue.dispose();
    _dueToday.dispose();
    _missing.dispose();
    _acquisition.dispose();
    _pix.dispose();
    _pixReceived.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, compact ? 124 : 28),
      children: [
        Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.colors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ativar API WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Envios são processados exclusivamente pelo backend Money.',
                  ),
                  value: _active,
                  onChanged: widget.saving
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Token WebDigital',
                    hintText: widget.config.tokenConfigured
                        ? 'Configurado — deixe vazio para manter'
                        : 'Cole o token da API',
                  ),
                ),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Endpoint seguro',
                  ),
                  child: Text(widget.config.baseUrl),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _messageField('Parcelas atrasadas', _overdue),
        _messageField('Vencendo hoje', _dueToday),
        _messageField('Clientes desaparecidos', _missing),
        _messageField('Aquisição de clientes', _acquisition),
        _messageField('Envio de PIX', _pix),
        _messageField('Confirmação de PIX recebido', _pixReceived),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: widget.saving
              ? null
              : () => widget.onSave({
                  'active': _active,
                  'apiToken': _token.text.trim(),
                  'overdueMessage': _overdue.text.trim(),
                  'dueTodayMessage': _dueToday.text.trim(),
                  'missingMessage': _missing.text.trim(),
                  'acquisitionMessage': _acquisition.text.trim(),
                  'pixMessage': _pix.text.trim(),
                  'pixReceivedMessage': _pixReceived.text.trim(),
                }),
          icon: widget.saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Salvar configuração'),
        ),
      ],
    );
  }

  Widget _messageField(String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
          ),
        ),
      );
}

class _WhatsappError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _WhatsappError({required this.message, required this.onRetry});

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
