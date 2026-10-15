import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class ReportScreenController {
  bool Function()? _closeHistory;
  VoidCallback? _exportHistory;

  bool closeHistory() => _closeHistory?.call() ?? false;

  void exportCurrent() => _exportHistory?.call();
}

class ReportScreen extends StatefulWidget {
  final bool showAppBar;
  final ReportScreenController? controller;
  final ValueChanged<bool>? onHistoryVisibilityChanged;

  const ReportScreen({
    super.key,
    this.showAppBar = true,
    this.controller,
    this.onHistoryVisibilityChanged,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const int _pageSize = 250;

  final ReportService _reportService = ReportService();
  final RegionService _regionService = RegionService();
  final LoanService _loanService = LoanService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final ScrollController _historyController = ScrollController();
  final List<AppAuditHistoryItem> _history = [];

  late AppAuditHistoryFilters _filters;
  late final Future<void> _filtersReady;
  late DateTime _draftStartDate;
  late DateTime _draftEndDate;
  Set<int> _draftRegionIds = {};
  Set<String> _draftUsernames = {};
  List<AppRegionOption> _regionOptions = const [];
  List<String> _userOptions = const [];
  bool _historyOpen = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasNext = false;
  int _nextPage = 0;
  int _requestVersion = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filters = AppAuditHistoryFilters.lastThirtyDays(DateTime.now());
    _draftStartDate = _filters.startDate;
    _draftEndDate = _filters.endDate;
    _filtersReady = _restoreSavedFilters();
    _historyController.addListener(_handleHistoryScroll);
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant ReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    _historyController
      ..removeListener(_handleHistoryScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: _historyOpen
                  ? 'Histórico de alterações'
                  : context.tr!.sidebar_reports,
              leading: _historyOpen
                  ? IconButton(
                      tooltip: 'Voltar para relatórios',
                      onPressed: _closeHistory,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: context.colors.textPrimary,
                      ),
                    )
                  : const AppSidebarMenuButton(),
            )
          : null,
      body: SafeArea(
        top: false,
        child: _historyOpen ? _buildHistory() : _buildLanding(),
      ),
    );
  }

  Widget _buildLanding() {
    final bool compact = MediaQuery.sizeOf(context).width < 700;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 8,
            compact ? 16 : 14,
            compact ? 14 : 8,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                Text(
                  'Relatórios',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Consulte atividades da operação e gere arquivos completos em Excel.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (compact) ...[
                _ReportOptionCard(
                  title: 'Histórico de alterações',
                  description:
                      'Acompanhe operações por região, usuário e período, em ordem cronológica.',
                  footer: 'Últimos 30 dias por padrão',
                  icon: Icons.history_rounded,
                  onTap: _openHistory,
                ),
                const SizedBox(height: 12),
                _ReportOptionCard(
                  title: 'Exportar relatório geral',
                  description:
                      'Gere um Excel completo com regiões, empréstimos e contratos com penhora.',
                  footer: 'Arquivo com 3 planilhas',
                  imageAsset: AppImages.excel,
                  onTap: _exportGeneralReport,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ReportOptionCard(
                        title: 'Histórico de alterações',
                        description:
                            'Acompanhe operações por região, usuário e período, em ordem cronológica.',
                        footer: 'Últimos 30 dias por padrão',
                        icon: Icons.history_rounded,
                        onTap: _openHistory,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ReportOptionCard(
                        title: 'Exportar relatório geral',
                        description:
                            'Gere um Excel completo com regiões, empréstimos e contratos com penhora.',
                        footer: 'Arquivo com 3 planilhas',
                        imageAsset: AppImages.excel,
                        onTap: _exportGeneralReport,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    final bool compact = MediaQuery.sizeOf(context).width < 700;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 0 : 8,
            compact ? 9 : 14,
            compact ? 0 : 8,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.showAppBar) ...[
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Voltar para relatórios',
                      onPressed: _closeHistory,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Histórico de alterações',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Operações mais recentes primeiro',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppDesktopExcelExportButton(onPressed: _exportHistory),
                  ],
                ),
                const SizedBox(height: 11),
              ],
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 0),
                child: _HistoryFilterPanel(
                  startDate: _draftStartDate,
                  endDate: _draftEndDate,
                  regionLabel: _regionLabel,
                  userLabel: _userLabel,
                  onStartDate: () => _selectDate(start: true),
                  onEndDate: () => _selectDate(start: false),
                  onRegions: _selectRegions,
                  onUser: _selectUser,
                  onClearUser: _draftUsernames.isEmpty
                      ? null
                      : () => setState(_draftUsernames.clear),
                  onApply: _applyFilters,
                  applying: _loading,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 0),
                child: _HistoryTableHeader(
                  middleLabel: _filters.usernames.isEmpty
                      ? 'Usuário'
                      : 'Operação',
                ),
              ),
              const SizedBox(height: 3),
              Expanded(child: _buildHistoryList(compact)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList(bool compact) {
    if (_loading && _history.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_error != null && _history.isEmpty) {
      return _ReportMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar o histórico',
        message: _error!,
        onRetry: () => _loadHistory(reset: true),
      );
    }
    if (_history.isEmpty) {
      return const _ReportMessage(
        icon: Icons.history_toggle_off_rounded,
        title: 'Nenhuma alteração encontrada',
        message: 'Ajuste o período, o usuário ou as regiões selecionadas.',
      );
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _loadHistory(reset: true),
      child: ListView.builder(
        controller: _historyController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 0,
          0,
          compact ? 10 : 0,
          compact ? 78 : 12,
        ),
        itemCount: _history.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _history.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: context.colors.primary,
                  ),
                ),
              ),
            );
          }
          return _HistoryLine(
            item: _history[index],
            showOperation: _filters.usernames.isNotEmpty,
          );
        },
      ),
    );
  }

  String get _regionLabel {
    if (_draftRegionIds.isEmpty) return 'Todas as regiões';
    if (_draftRegionIds.length > 1) {
      return '${_draftRegionIds.length} regiões selecionadas';
    }
    final int id = _draftRegionIds.first;
    for (final AppRegionOption option in _regionOptions) {
      if (option.id == id) return option.name;
    }
    return 'Região #$id';
  }

  String get _userLabel {
    if (_draftUsernames.isEmpty) return 'Todos os usuários';
    if (_draftUsernames.length == 1) return _draftUsernames.first;
    return '${_draftUsernames.length} usuários selecionados';
  }

  void _attachController(ReportScreenController? controller) {
    controller?._closeHistory = _closeHistory;
    controller?._exportHistory = _historyOpen ? _exportHistory : null;
  }

  void _detachController(ReportScreenController? controller) {
    controller?._closeHistory = null;
    controller?._exportHistory = null;
  }

  void _syncController() {
    widget.controller?._exportHistory = _historyOpen ? _exportHistory : null;
  }

  void _openHistory() {
    if (_historyOpen) return;
    setState(() => _historyOpen = true);
    _syncController();
    widget.onHistoryVisibilityChanged?.call(true);
    unawaited(_initializeHistory());
  }

  Future<void> _initializeHistory() async {
    await _filtersReady;
    if (!mounted || !_historyOpen) return;
    unawaited(_loadFilterOptions());
    await _loadHistory(reset: true);
  }

  Future<void> _restoreSavedFilters() async {
    final AppAuditHistoryFilters fallback =
        AppAuditHistoryFilters.lastThirtyDays(DateTime.now());
    final int? userId = AuthService().currentSession?.userId;
    final Map<String, dynamic>? data = userId == null
        ? null
        : await _preferencesService.getUserFilters(
            scope: 'reports.audit',
            userId: userId,
          );
    DateTime startDate =
        DateTime.tryParse('${data?['startDate'] ?? ''}') ?? fallback.startDate;
    DateTime endDate =
        DateTime.tryParse('${data?['endDate'] ?? ''}') ?? fallback.endDate;
    if (startDate.isAfter(endDate)) {
      startDate = fallback.startDate;
      endDate = fallback.endDate;
    }
    final Set<String> usernames = ((data?['usernames'] as List?) ?? const [])
        .map((Object? item) => '$item'.trim())
        .where((String item) => item.isNotEmpty)
        .toSet();
    final Set<int> regionIds = ((data?['regionIds'] as List?) ?? const [])
        .map((Object? item) => int.tryParse('$item'))
        .whereType<int>()
        .toSet();
    if (!mounted) return;
    setState(() {
      _filters = AppAuditHistoryFilters(
        startDate: startDate,
        endDate: endDate,
        usernames: Set<String>.unmodifiable(usernames),
        regionIds: Set<int>.unmodifiable(regionIds),
      );
      _draftStartDate = startDate;
      _draftEndDate = endDate;
      _draftUsernames = Set<String>.of(usernames);
      _draftRegionIds = Set<int>.of(regionIds);
    });
  }

  Future<void> _saveFilters() async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'reports.audit',
      userId: userId,
      filters: <String, Object?>{
        'startDate': _filters.startDate.toIso8601String(),
        'endDate': _filters.endDate.toIso8601String(),
        'usernames': _filters.usernames.toList(growable: false)..sort(),
        'regionIds': _filters.regionIds.toList(growable: false)..sort(),
      },
    );
  }

  bool _closeHistory() {
    if (!_historyOpen) return false;
    setState(() => _historyOpen = false);
    _syncController();
    widget.onHistoryVisibilityChanged?.call(false);
    return true;
  }

  Future<void> _loadFilterOptions() async {
    try {
      final List<Object> result = await Future.wait<Object>([
        _regionService.fetchOptions(),
        _reportService.fetchHistoryUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _regionOptions = result[0] as List<AppRegionOption>;
        _userOptions = result[1] as List<String>;
      });
    } on Object {
      // A listagem continua disponível; as opções podem ser tentadas novamente
      // quando o usuário abrir um dos seletores.
    }
  }

  Future<void> _loadHistory({required bool reset}) async {
    if (!reset && (_loading || _loadingMore)) return;
    final int request = ++_requestVersion;
    final int page = reset ? 0 : _nextPage;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final AppAuditHistoryPage result = await _reportService.fetchHistory(
        filters: _filters,
        page: page,
        size: _pageSize,
      );
      if (!mounted || request != _requestVersion) return;
      setState(() {
        if (reset) _history.clear();
        final Set<int> ids = _history.map((item) => item.id).toSet();
        _history.addAll(result.items.where((item) => ids.add(item.id)));
        _hasNext = result.hasNext;
        _nextPage = page + 1;
        _error = null;
      });
    } on ReportServiceException catch (error) {
      if (!mounted || request != _requestVersion) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted && request == _requestVersion) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _handleHistoryScroll() {
    if (_historyController.position.extentAfter < 520 &&
        _hasNext &&
        !_loadingMore &&
        !_loading) {
      unawaited(_loadHistory(reset: false));
    }
  }

  Future<void> _selectDate({required bool start}) async {
    final DateTime initial = start ? _draftStartDate : _draftEndDate;
    final DateTime? selected = await showAppDatePickerDialog(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: start ? 'Data inicial' : 'Data final',
      subtitle: 'Selecione o período do histórico.',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _draftStartDate = selected;
      } else {
        _draftEndDate = selected;
      }
    });
  }

  Future<void> _selectRegions() async {
    if (_regionOptions.isEmpty) await _loadFilterOptions();
    if (!mounted) return;
    final Set<int>? selected = await showRegionSelectionDialog(
      context: context,
      options: _regionOptions,
      selected: _draftRegionIds,
      title: 'Regiões do histórico',
      subtitle: 'Marque as regiões que deseja consultar.',
    );
    if (selected == null || !mounted) return;
    setState(() => _draftRegionIds = selected);
  }

  Future<void> _selectUser() async {
    if (_userOptions.isEmpty) await _loadFilterOptions();
    if (!mounted) return;
    final Set<String>? selected = await showHistoryUserSelectionDialog(
      context: context,
      users: _userOptions,
      selected: _draftUsernames,
    );
    if (!mounted || selected == null) return;
    setState(() => _draftUsernames = selected);
  }

  void _applyFilters() {
    if (_draftStartDate.isAfter(_draftEndDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data inicial deve ser anterior à data final.'),
        ),
      );
      return;
    }
    setState(() {
      _filters = AppAuditHistoryFilters(
        startDate: _draftStartDate,
        endDate: _draftEndDate,
        usernames: Set<String>.unmodifiable(_draftUsernames),
        regionIds: Set<int>.unmodifiable(_draftRegionIds),
      );
    });
    unawaited(_saveFilters());
    unawaited(_loadHistory(reset: true));
  }

  Future<void> _exportHistory() async {
    await showAppExcelExportFlow(
      context: context,
      title: 'Exportar histórico',
      confirmationMessage:
          'Deseja exportar todo o histórico considerando os filtros atuais?',
      generate: (onProgress) async {
        try {
          onProgress(.02, 'Buscando o histórico filtrado...');
          final List<AppAuditHistoryItem> history = await _reportService
              .fetchHistoryForExport(
                filters: _filters,
                onProgress: (value) => onProgress(
                  .02 + (value * .48),
                  'Recebendo dados do histórico...',
                ),
              );
          if (history.isEmpty) {
            throw const AppExcelExportException(
              'Nenhuma alteração foi encontrada para exportar.',
            );
          }
          final AppReportExcelFile file = await AuditHistoryExcelExportService()
              .create(
                history,
                onProgress: (value, status) =>
                    onProgress(.50 + (value * .50), status),
              );
          return AppGeneratedExcelFile(
            bytes: file.bytes,
            fileName: file.fileName,
            successMessage: '${history.length} alteração(ões) exportada(s).',
          );
        } on ReportServiceException catch (error) {
          throw AppExcelExportException(error.message);
        }
      },
    );
  }

  Future<void> _exportGeneralReport() async {
    await showAppExcelExportFlow(
      context: context,
      title: 'Exportar relatório geral',
      confirmationMessage:
          'Deseja gerar o relatório geral com regiões, empréstimos e penhoras?',
      generate: (onProgress) async {
        try {
          onProgress(.02, 'Carregando regiões...');
          final List<AppRegionSummary> regions = await _regionService
              .fetchRegionsForExport(
                query: '',
                filters: const AppRegionFilters(startDate: null, endDate: null),
                onProgress: (value) =>
                    onProgress(.02 + (value * .16), 'Carregando regiões...'),
              );
          onProgress(.18, 'Carregando empréstimos...');
          final List<AppLoanSummary> loans = await _loanService
              .fetchLoansForExport(
                query: '',
                filters: const AppLoanFilters(),
                onProgress: (value) => onProgress(
                  .18 + (value * .34),
                  'Carregando empréstimos...',
                ),
              );
          final AppReportExcelFile file =
              await GeneralReportExcelExportService().create(
                regions: regions,
                loans: loans,
                onProgress: (value, status) =>
                    onProgress(.52 + (value * .48), status),
              );
          return AppGeneratedExcelFile(
            bytes: file.bytes,
            fileName: file.fileName,
            successMessage:
                'Relatório geral gerado com ${regions.length} região(ões) e ${loans.length} empréstimo(s).',
          );
        } on RegionServiceException catch (error) {
          throw AppExcelExportException(error.message);
        } on LoanServiceException catch (error) {
          throw AppExcelExportException(error.message);
        }
      },
    );
  }
}

class _ReportOptionCard extends StatelessWidget {
  final String title;
  final String description;
  final String footer;
  final IconData? icon;
  final String? imageAsset;
  final VoidCallback onTap;

  const _ReportOptionCard({
    required this.title,
    required this.description,
    required this.footer,
    required this.onTap,
    this.icon,
    this.imageAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.colors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: imageAsset != null
                    ? Image.asset(imageAsset!, width: 31, height: 31)
                    : Icon(icon, color: context.colors.primary, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: context.colors.primary,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            footer,
                            style: TextStyle(
                              color: context.colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: context.colors.textSecondary,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryFilterPanel extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final String regionLabel;
  final String userLabel;
  final VoidCallback onStartDate;
  final VoidCallback onEndDate;
  final VoidCallback onRegions;
  final VoidCallback onUser;
  final VoidCallback? onClearUser;
  final VoidCallback onApply;
  final bool applying;

  const _HistoryFilterPanel({
    required this.startDate,
    required this.endDate,
    required this.regionLabel,
    required this.userLabel,
    required this.onStartDate,
    required this.onEndDate,
    required this.onRegions,
    required this.onUser,
    required this.onClearUser,
    required this.onApply,
    required this.applying,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool compact = constraints.maxWidth < 720;
            final Widget start = _HistoryFilterField(
              label: 'Data inicial',
              value: DateFormat('dd/MM/yyyy').format(startDate),
              icon: Icons.calendar_today_outlined,
              onTap: onStartDate,
            );
            final Widget end = _HistoryFilterField(
              label: 'Data final',
              value: DateFormat('dd/MM/yyyy').format(endDate),
              icon: Icons.calendar_today_outlined,
              onTap: onEndDate,
            );
            final Widget regions = _HistoryFilterField(
              label: 'Regiões',
              value: regionLabel,
              icon: Icons.location_on_outlined,
              onTap: onRegions,
            );
            final Widget user = _HistoryFilterField(
              label: 'Usuário',
              value: userLabel,
              icon: Icons.person_search_outlined,
              onTap: onUser,
              onClear: onClearUser,
            );
            final Widget apply = SizedBox(
              height: 45,
              child: FilledButton.icon(
                onPressed: applying ? null : onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: const Text('FILTRAR'),
              ),
            );
            if (compact) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: start),
                      const SizedBox(width: 7),
                      Expanded(child: end),
                    ],
                  ),
                  const SizedBox(height: 7),
                  regions,
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(child: user),
                      const SizedBox(width: 7),
                      apply,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: start),
                const SizedBox(width: 7),
                Expanded(child: end),
                const SizedBox(width: 7),
                Expanded(flex: 2, child: regions),
                const SizedBox(width: 7),
                Expanded(flex: 2, child: user),
                const SizedBox(width: 7),
                apply,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryFilterField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _HistoryFilterField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.divider),
          ),
          child: Row(
            children: [
              Icon(icon, color: context.colors.primary, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                InkWell(
                  onTap: onClear,
                  child: Icon(
                    Icons.close_rounded,
                    color: context.colors.textSecondary,
                    size: 17,
                  ),
                )
              else
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: context.colors.textSecondary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTableHeader extends StatelessWidget {
  final String middleLabel;

  const _HistoryTableHeader({required this.middleLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.colors.divider),
      ),
      child: Row(
        children: [
          Expanded(flex: 145, child: Text('Entidade', style: _style(context))),
          Expanded(
            flex: 100,
            child: Text(
              middleLabel,
              textAlign: TextAlign.center,
              style: _style(context),
            ),
          ),
          Expanded(
            flex: 130,
            child: Text(
              'Data e Hora',
              textAlign: TextAlign.end,
              style: _style(context),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _style(BuildContext context) => TextStyle(
    color: context.colors.primary,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );
}

class _HistoryLine extends StatelessWidget {
  final AppAuditHistoryItem item;
  final bool showOperation;

  const _HistoryLine({required this.item, required this.showOperation});

  @override
  Widget build(BuildContext context) {
    final String entityId = item.entityId == null ? '' : '${item.entityId}';
    final String date = item.timestamp == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(item.timestamp!);
    return Material(
      color: context.colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.regionDescription != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.divider.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  item.regionDescription!,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              item.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  flex: 145,
                  child: Text(
                    '${item.displayEntityName} | $entityId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _lineStyle(context),
                  ),
                ),
                Expanded(
                  flex: 100,
                  child: Text(
                    showOperation ? item.operation : item.username,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _lineStyle(context),
                  ),
                ),
                Expanded(
                  flex: 130,
                  child: Text(
                    date,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _lineStyle(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: context.colors.divider),
          ],
        ),
      ),
    );
  }

  TextStyle _lineStyle(BuildContext context) =>
      TextStyle(color: context.colors.textPrimary, fontSize: 10.5);
}

Future<Set<String>?> showHistoryUserSelectionDialog({
  required BuildContext context,
  required List<String> users,
  required Set<String> selected,
}) => showAppDialog<Set<String>>(
  context: context,
  title: 'Usuários do histórico',
  subtitle: 'Marque os usuários que deseja consultar.',
  icon: Icons.person_search_outlined,
  maxWidth: 560,
  maxHeight: 640,
  builder: (_) => _HistoryUserDialog(users: users, selected: selected),
);

class _HistoryUserDialog extends StatefulWidget {
  final List<String> users;
  final Set<String> selected;

  const _HistoryUserDialog({required this.users, required this.selected});

  @override
  State<_HistoryUserDialog> createState() => _HistoryUserDialogState();
}

class _HistoryUserDialogState extends State<_HistoryUserDialog> {
  final TextEditingController _controller = TextEditingController();
  late final Set<String> _selected = Set<String>.from(widget.selected);
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> users = _query.isEmpty
        ? widget.users
        : widget.users
              .where((user) => user.toLowerCase().contains(_query))
              .toList(growable: false);
    return SizedBox(
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 7),
            child: TextField(
              controller: _controller,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Pesquisar usuário',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.colors.primary,
                ),
                filled: true,
                fillColor: context.colors.background,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.primary),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selected.isEmpty
                        ? 'Nenhum marcado: serão exibidos todos'
                        : '${_selected.length} usuário(s) marcado(s)',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    child: const Text(
                      'LIMPAR',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Material(
                color: context.colors.background.withValues(alpha: .62),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: BorderSide(
                    color: context.colors.divider.withValues(alpha: .8),
                  ),
                ),
                child: widget.users.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum usuário disponível.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : users.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum usuário encontrado.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        itemCount: users.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 43,
                          color: context.colors.divider.withValues(alpha: .55),
                        ),
                        itemBuilder: (context, index) {
                          final String user = users[index];
                          final bool selected = _selected.contains(user);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(user);
                              } else {
                                _selected.remove(user);
                              }
                            }),
                            dense: true,
                            visualDensity: const VisualDensity(
                              horizontal: -3,
                              vertical: -3,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 7,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: context.colors.primary,
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            title: Text(
                              user,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? context.colors.primary
                                    : context.colors.textPrimary,
                                fontSize: 10.8,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(
                top: BorderSide(
                  color: context.colors.divider.withValues(alpha: .7),
                ),
              ),
            ),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.textPrimary,
                        side: BorderSide(color: context.colors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('CANCELAR', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        Set<String>.unmodifiable(_selected),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('APLICAR', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _ReportMessage({
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
            Icon(icon, color: context.colors.primary, size: 44),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
