import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class DashboardScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final bool tutorialMode;
  final TutorialGuideController? tutorialController;

  const DashboardScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.tutorialMode = false,
    this.tutorialController,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final DashboardService _service = DashboardService();
  final RegionService _regionService = RegionService();
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _integer = NumberFormat.decimalPattern('pt_BR');

  AppDashboardData? _data;
  String? _error;
  bool _loading = true;
  bool _requestInFlight = false;
  int _requestSerial = 0;
  List<int> _requestedRegionIds = const [];
  String? _displayUserName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tutorialMode != widget.tutorialMode) {
      unawaited(_initialize());
      return;
    }
    if (widget.active && !oldWidget.active) unawaited(_refreshCurrent());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(_refreshCurrent());
    }
  }

  Future<void> _initialize() async {
    final int initializationSerial = ++_requestSerial;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        if (widget.tutorialMode) {
          _data = null;
          _requestedRegionIds = const [];
        }
      });
    }
    if (AuthService().currentSession == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Entre novamente para carregar o painel.';
        });
      }
      return;
    }
    int? regionId;
    if (widget.tutorialMode) {
      try {
        await AuthService().beginTutorial();
        final List<AppRegionOption> regions = await _regionService.fetchOptions(
          force: true,
          tutorialMode: true,
        );
        for (final AppRegionOption region in regions) {
          if (TutorialGuideController.isTutorialRegionName(region.name)) {
            regionId = region.id;
            break;
          }
        }
        if (!mounted || initializationSerial != _requestSerial) return;
      } on AuthenticationException catch (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = error.message;
        });
        return;
      } on RegionServiceException catch (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = error.message;
        });
        return;
      }
      if (regionId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'A região de tutorial não foi encontrada.';
        });
        return;
      }
    } else {
      _requestedRegionIds = await _service.lastRegionIds();
    }
    if (!mounted) return;
    if (regionId != null) _requestedRegionIds = <int>[regionId];
    final AppDashboardData? cached = _service.cachedDashboard(
      regionIds: _requestedRegionIds,
      tutorialMode: widget.tutorialMode,
    );
    if (cached != null) {
      setState(() {
        _data = cached;
        _displayUserName = cached.userName.trim().isEmpty
            ? _displayUserName
            : cached.userName;
        _loading = false;
      });
    }
    await _load(
      regionIds: _requestedRegionIds,
      keepContent: cached != null,
      forceRefresh: false,
    );
  }

  Future<void> _load({
    Iterable<int>? regionIds,
    bool keepContent = true,
    bool forceRefresh = true,
  }) async {
    final int requestSerial = ++_requestSerial;
    final List<int> requested =
        (regionIds ?? _requestedRegionIds).toSet().toList()..sort();
    final bool preserveContent = keepContent && _data != null;
    _requestInFlight = true;
    if (mounted) {
      setState(() {
        _requestedRegionIds = requested;
        _loading = !preserveContent;
        _error = null;
        if (!keepContent) _data = null;
      });
    }
    try {
      AppDashboardData result;
      try {
        result = await _service.fetchDashboard(
          regionIds: requested,
          forceRefresh: forceRefresh,
          persistSelection: !widget.tutorialMode,
          tutorialMode: widget.tutorialMode,
        );
      } on DashboardServiceException catch (error) {
        if (widget.tutorialMode ||
            requested.isEmpty ||
            error.statusCode != 403) {
          rethrow;
        }
        result = await _service.fetchDashboard(
          forceRefresh: forceRefresh,
          persistSelection: true,
        );
      }
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _data = result;
        if (result.userName.trim().isNotEmpty) {
          _displayUserName = result.userName;
        }
        _requestedRegionIds = result.selectedRegionIds;
        _loading = false;
      });
    } on DashboardServiceException catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } finally {
      if (requestSerial == _requestSerial) _requestInFlight = false;
    }
  }

  Future<void> _refreshCurrent({bool forceRefresh = false}) async {
    if (!mounted || !widget.active || _requestInFlight) return;
    await _load(
      regionIds: _requestedRegionIds.isNotEmpty
          ? _requestedRegionIds
          : _data?.selectedRegionIds,
      keepContent: _data != null,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _selectRegions(Set<int> selected) async {
    if (widget.tutorialMode) return;
    final AppDashboardData? data = _data;
    if (data == null || selected.isEmpty) return;
    final List<int> normalized = selected.toList()..sort();
    if (setEquals(normalized.toSet(), _requestedRegionIds.toSet())) return;
    final AppDashboardData? cached = _service.cachedDashboard(
      regionIds: normalized,
      tutorialMode: widget.tutorialMode,
    );
    if (mounted) {
      setState(() {
        _requestedRegionIds = normalized;
        _data = cached;
        _loading = cached == null;
        _error = null;
      });
    }
    await _load(
      regionIds: normalized,
      keepContent: cached != null,
      forceRefresh: false,
    );
  }

  Future<void> _openLoan(AppDashboardDueTodayLoan loan) async {
    final bool? confirmed = await showAppCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Abrir empréstimo?'),
        content: Text(
          'Deseja abrir o contrato #${loan.loanId} de ${loan.clientName}?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: dialogContext.colors.textPrimary),
            ),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await openLoanDetailScreen(context: context, loanId: loan.loanId);
    if (mounted) await _refreshCurrent(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.app_name,
              leading: AppSidebarMenuButton(
                key: widget.tutorialController?.active == true
                    ? widget.tutorialController!.mobileSidebarMenuButtonKey
                    : null,
              ),
            )
          : null,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final AppDashboardData? data = _data;
    if (data == null && !_loading) {
      return _DashboardError(
        message: _error ?? 'Não foi possível carregar o painel.',
        onRetry: () =>
            _load(regionIds: _requestedRegionIds, keepContent: false),
      );
    }
    final AppDashboardData visibleData = data ?? _loadingDashboardData();
    final List<AppDashboardRegion> visibleRegions = widget.tutorialMode
        ? visibleData.regions
              .where(
                (region) =>
                    TutorialGuideController.isTutorialRegionName(region.name),
              )
              .toList(growable: false)
        : visibleData.regions;

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _load(
        regionIds: _requestedRegionIds.isNotEmpty
            ? _requestedRegionIds
            : data?.selectedRegionIds,
        keepContent: data != null,
        forceRefresh: true,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool desktop = kIsWeb && constraints.maxWidth >= 900;
          final EdgeInsets padding = EdgeInsets.fromLTRB(
            desktop ? 10 : 10,
            desktop ? 18 : 7,
            desktop ? 10 : 10,
            widget.showAppBar ? 132 : 30,
          );
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: _DashboardContent(
                  data: visibleData,
                  regions: visibleRegions,
                  userName: _displayUserName ?? visibleData.userName,
                  selectedRegionIds: _requestedRegionIds.isNotEmpty
                      ? _requestedRegionIds.toSet()
                      : visibleData.selectedRegionIds.toSet(),
                  loading: data == null || _loading,
                  desktop: desktop,
                  currency: _currency,
                  integer: _integer,
                  onSelectRegions: data == null ? (_) {} : _selectRegions,
                  onOpenLoan: data == null ? (_) {} : _openLoan,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  AppDashboardData _loadingDashboardData() {
    final int regionId = _requestedRegionIds.isEmpty
        ? 0
        : _requestedRegionIds.first;
    return AppDashboardData(
      userName: AuthService().currentSession?.name ?? 'Usuário',
      date: DateTime.now(),
      selectedRegionId: regionId,
      selectedRegionName: 'Carregando região...',
      selectedRegionIds: <int>[if (regionId > 0) regionId],
      regions: [AppDashboardRegion(id: regionId, name: 'Carregando região...')],
      metrics: const AppDashboardMetrics(
        overdueClients: 0,
        overdueLoans: 0,
        overdueAmount: 0,
        receivedTodayAmount: 0,
        receivedTodayPayments: 0,
        profitTodayAmount: 0,
        settledTodayLoans: 0,
        renewedTodayLoans: 0,
        overdueInstallments: 0,
        oldestOverdueDays: 0,
        dueTodayLoans: 0,
        dueTodayInstallments: 0,
        dueTodayAmount: 0,
      ),
      financial: const AppDashboardFinancialSummary(
        loanedAmount: 0,
        receivedAmount: 0,
        overdueAmount: 0,
        profitAmount: 0,
        points: [],
      ),
      dueToday: const [],
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final AppDashboardData data;
  final List<AppDashboardRegion> regions;
  final String userName;
  final Set<int> selectedRegionIds;
  final bool loading;
  final bool desktop;
  final NumberFormat currency;
  final NumberFormat integer;
  final ValueChanged<Set<int>> onSelectRegions;
  final ValueChanged<AppDashboardDueTodayLoan> onOpenLoan;

  const _DashboardContent({
    required this.data,
    required this.regions,
    required this.userName,
    required this.selectedRegionIds,
    required this.loading,
    required this.desktop,
    required this.currency,
    required this.integer,
    required this.onSelectRegions,
    required this.onOpenLoan,
  });

  @override
  Widget build(BuildContext context) {
    final int receivedPayments = data.metrics.receivedTodayPayments;
    final int settledTodayLoans = data.metrics.settledTodayLoans;
    final int renewedTodayLoans = data.metrics.renewedTodayLoans;
    const Color profitColor = Color(0xFF496FB5);
    final List<Widget> metrics = [
      DashboardMetricCard(
        icon: Icons.person_off_outlined,
        label: 'Valor em atraso',
        value: currency.format(data.metrics.overdueAmount),
        detail:
            '${integer.format(data.metrics.overdueLoans)} ${data.metrics.overdueLoans == 1 ? 'Empréstimo' : 'Empréstimos'}',
        loading: loading,
        detailLoads: true,
        accentColor: context.colors.error,
      ),
      DashboardMetricCard(
        icon: Icons.payments_outlined,
        label: 'Recebido hoje',
        value: currency.format(data.metrics.receivedTodayAmount),
        detail:
            '${integer.format(receivedPayments)} ${receivedPayments == 1 ? 'pagamento' : 'pagamentos'}',
        loading: loading,
        detailLoads: true,
      ),
      DashboardMetricCard(
        icon: Icons.trending_up_rounded,
        label: 'Lucro do dia',
        value: currency.format(data.metrics.profitTodayAmount),
        detail: renewedTodayLoans > 0
            ? '${integer.format(settledTodayLoans)} quitados e '
                  '${integer.format(renewedTodayLoans)} Renov/Abat'
            : '${integer.format(settledTodayLoans)} quitados',
        loading: loading,
        detailLoads: true,
        accentColor: profitColor,
      ),
      DashboardMetricCard(
        icon: Icons.calendar_today_outlined,
        label: 'Vencimentos hoje',
        value: currency.format(data.metrics.dueTodayAmount),
        detail:
            '${integer.format(data.metrics.dueTodayLoans)} ${data.metrics.dueTodayLoans == 1 ? 'Empréstimo' : 'Empréstimos'}',
        loading: loading,
        detailLoads: true,
        accentColor: const Color(0xFFE59B2F),
      ),
    ];

    final Widget financial = _FinancialCard(
      summary: data.financial,
      date: data.date,
      currency: currency,
      loading: loading,
    );
    final Widget dueToday = _DueTodayCard(
      loans: data.dueToday,
      date: data.date,
      currency: currency,
      loading: loading,
      onOpenLoan: onOpenLoan,
    );
    final Widget activeGoals = _DashboardActiveGoals(
      goals: data.activeGoals,
      desktop: desktop,
    );
    final Widget regionNotice = Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: desktop ? 410 : double.infinity,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: desktop ? 14 : 10),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: desktop ? 16 : 13,
                color: context.colors.textSecondary,
              ),
              SizedBox(width: desktop ? 6 : 4),
              Expanded(
                child: Text(
                  selectedRegionIds.length > 1
                      ? 'Os dados abaixo somam as regiões selecionadas.'
                      : 'Os dados abaixo referem-se à região selecionada.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: desktop ? 12 : 9.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final Widget metricsGrid = GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: 2,
      crossAxisSpacing: desktop ? 12 : 6,
      mainAxisSpacing: desktop ? 12 : 6,
      mainAxisExtent: desktop ? 116 : null,
      childAspectRatio: desktop ? 1 : 2.25,
      children: metrics,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DashboardHero(
                      data: data,
                      regions: regions,
                      userName: userName,
                      selectedRegionIds: selectedRegionIds,
                      desktop: true,
                      onSelectRegions: onSelectRegions,
                    ),
                    const SizedBox(height: 10),
                    regionNotice,
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(child: metricsGrid),
            ],
          )
        else ...[
          _DashboardHero(
            data: data,
            regions: regions,
            userName: userName,
            selectedRegionIds: selectedRegionIds,
            desktop: false,
            onSelectRegions: onSelectRegions,
          ),
          const SizedBox(height: 5),
          regionNotice,
          const SizedBox(height: 7),
          metricsGrid,
        ],
        SizedBox(height: desktop ? 14 : 6),
        financial,
        if (data.activeGoals.isNotEmpty) ...[
          SizedBox(height: desktop ? 14 : 8),
          activeGoals,
        ],
        SizedBox(height: desktop ? 14 : 8),
        dueToday,
      ],
    );
  }
}

class _DashboardActiveGoals extends StatelessWidget {
  final List<AppFinancialGoal> goals;
  final bool desktop;

  const _DashboardActiveGoals({required this.goals, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (desktop) {
      content = GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: goals.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: goals.any((goal) => goal.type.isClient) ? 240 : 218,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) => FinancialGoalCard(
          key: ValueKey('dashboard_financial_goal_${goals[index].id}'),
          goal: goals[index],
          compact: true,
          onEdit: null,
          onDelete: null,
        ),
      );
    } else {
      final double cardWidth = (MediaQuery.sizeOf(context).width - 44).clamp(
        286.0,
        340.0,
      );
      content = SizedBox(
        height: 242,
        child: ListView.separated(
          key: const ValueKey('dashboard_financial_goals_horizontal_list'),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          itemCount: goals.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => SizedBox(
            width: cardWidth,
            child: FinancialGoalCard(
              key: ValueKey('dashboard_financial_goal_${goals[index].id}'),
              goal: goals[index],
              compact: true,
              onEdit: null,
              onDelete: null,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Metas em andamento',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: desktop ? 16 : 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: desktop ? 10 : 7),
        content,
      ],
    );
  }
}

class _DashboardHero extends StatelessWidget {
  final AppDashboardData data;
  final List<AppDashboardRegion> regions;
  final String userName;
  final Set<int> selectedRegionIds;
  final bool desktop;
  final ValueChanged<Set<int>> onSelectRegions;

  const _DashboardHero({
    required this.data,
    required this.regions,
    required this.userName,
    required this.selectedRegionIds,
    required this.desktop,
    required this.onSelectRegions,
  });

  @override
  Widget build(BuildContext context) {
    final String firstName = userName.trim().isEmpty
        ? 'Usuário'
        : userName.trim().split(RegExp(r'\s+')).first;
    return SizedBox(
      height: desktop ? 218 : 145,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            start: 0,
            end: desktop ? 220 : null,
            top: desktop ? 34 : 30,
            child: Text(
              'Olá, $firstName! 👋',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: desktop ? 30 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            end: desktop ? 220 : null,
            top: desktop ? 78 : 58,
            child: Text(
              'Aqui está o resumo da sua operação hoje.',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: desktop ? 15 : 9.5,
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            bottom: desktop ? 8 : 2,
            width: desktop ? 410 : 202,
            child: _RegionSelector(
              regions: regions,
              selectedRegionIds: selectedRegionIds,
              desktop: desktop,
              onSelected: onSelectRegions,
            ),
          ),
          PositionedDirectional(
            end: desktop ? 4 : -3,
            top: 0,
            bottom: desktop ? -40 : 0,
            width: desktop ? 245 : 108,
            child: Transform.translate(
              offset: Offset(0, desktop ? 0 : 25),
              child: Image.asset(
                AppImages.virtualDashboard,
                fit: BoxFit.contain,
                alignment: AlignmentDirectional.bottomCenter,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionSelector extends StatelessWidget {
  final List<AppDashboardRegion> regions;
  final Set<int> selectedRegionIds;
  final bool desktop;
  final ValueChanged<Set<int>> onSelected;

  const _RegionSelector({
    required this.regions,
    required this.selectedRegionIds,
    required this.desktop,
    required this.onSelected,
  });

  String _regionName(AppDashboardRegion region) {
    return region.name.isEmpty ? 'Região #${region.id}' : region.name;
  }

  @override
  Widget build(BuildContext context) {
    final List<AppDashboardRegion> selected = regions
        .where((region) => selectedRegionIds.contains(region.id))
        .toList(growable: false);
    final String label = selected.length > 1
        ? '${selected.length} regiões selecionadas'
        : selected.isEmpty
        ? 'Selecione as regiões'
        : _regionName(selected.first);

    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: context.colors.divider.withValues(alpha: .7)),
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('dashboard_region_selector'),
        hoverColor: context.colors.primary.withValues(alpha: .06),
        focusColor: context.colors.primary.withValues(alpha: .08),
        onTap: regions.length > 1 ? () => _openDialog(context) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: desktop ? 42 : 32),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: desktop ? 14 : 10,
              end: desktop ? 8 : 5,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: context.colors.primary,
                  size: desktop ? 21 : 17,
                ),
                SizedBox(width: desktop ? 8 : 5),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: selected.length > 1 ? 'Regiões: ' : 'Região: ',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: label,
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: desktop ? 14 : 10.5),
                  ),
                ),
                if (regions.length > 1)
                  Icon(
                    Icons.tune_rounded,
                    color: context.colors.textSecondary,
                    size: desktop ? 21 : 17,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    final Set<int>? result = await showRegionSelectionDialog(
      context: context,
      options: regions
          .map((region) => AppRegionOption(id: region.id, name: region.name))
          .toList(growable: false),
      selected: selectedRegionIds,
      title: 'Regiões do dashboard',
      subtitle: 'Selecione uma ou mais regiões para somar os dados.',
      emptySelectionLabel: 'Selecione ao menos uma região',
    );
    if (result == null || result.isEmpty) return;
    onSelected(result);
  }
}

class DashboardMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool loading;
  final bool detailLoads;
  final Color? accentColor;

  const DashboardMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.loading,
    this.detailLoads = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 900;
    final Color accent = accentColor ?? context.colors.primary;
    return _DashboardCard(
      padding: EdgeInsets.all(compact ? 6 : 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double cardWidth = constraints.maxWidth;
          final double labelFont = compact
              ? (cardWidth * .052).clamp(8.5, 11).toDouble()
              : 12;
          final double valueFont = compact
              ? (cardWidth * .095).clamp(15, 21).toDouble()
              : 23;
          final double detailFont = compact
              ? (cardWidth * .06).clamp(10, 12.5).toDouble()
              : 13;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 25 : 38,
                    height: compact ? 25 : 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(compact ? 8 : 10),
                    ),
                    child: Icon(icon, color: accent, size: compact ? 15 : 22),
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: labelFont,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, contentConstraints) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: contentConstraints.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (loading)
                              _DashboardLoadingValueLine(
                                width: compact ? 54 : 76,
                                height: valueFont * .72,
                              )
                            else
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(
                                  value,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: valueFont,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            SizedBox(height: compact ? 3 : 7),
                            if (loading && detailLoads)
                              _DashboardLoadingValueLine(
                                width: compact ? 68 : 96,
                                height: detailFont * .8,
                              )
                            else
                              Text(
                                detail,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: detailFont,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FinancialCard extends StatelessWidget {
  final AppDashboardFinancialSummary summary;
  final DateTime date;
  final NumberFormat currency;
  final bool loading;

  const _FinancialCard({
    required this.summary,
    required this.date,
    required this.currency,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 900;
    final Color loanedColor = context.colors.textPrimary;
    const Color profitColor = Color(0xFF4776B9);
    final DateFormat periodFormat = DateFormat('dd/MM/yyyy');
    final DateTime periodStart = summary.points.isEmpty
        ? date.subtract(const Duration(days: 30))
        : summary.points.first.date;
    final DateTime periodEnd = summary.points.isEmpty
        ? date
        : summary.points.last.date;
    final String periodLabel =
        '${periodFormat.format(periodStart)} até ${periodFormat.format(periodEnd)}';
    return _DashboardCard(
      padding: compact
          ? const EdgeInsets.fromLTRB(8, 8, 8, 6)
          : const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Resumo financeiro',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: compact ? 12 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 7 : 10,
                  vertical: compact ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: context.colors.divider),
                ),
                child: Text(
                  periodLabel,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: compact ? 8.5 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 16),
          Wrap(
            spacing: compact ? 10 : 22,
            runSpacing: compact ? 4 : 10,
            children: [
              _FinancialValue(
                label: 'Emprestado',
                value: currency.format(summary.loanedAmount),
                color: loanedColor,
                loading: loading,
              ),
              _FinancialValue(
                label: 'Recebido',
                value: currency.format(summary.receivedAmount),
                color: context.colors.primary,
                loading: loading,
              ),
              _FinancialValue(
                label: 'Lucro',
                value: currency.format(summary.profitAmount),
                color: profitColor,
                loading: loading,
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 12),
          SizedBox(
            height: compact ? 145 : 285,
            child: _InteractiveFinancialChart(
              points: summary.points,
              currency: currency,
              loading: loading,
              loanedColor: loanedColor,
              receivedColor: context.colors.primary,
              profitColor: profitColor,
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Legend(color: loanedColor, text: 'Emprestado'),
              const SizedBox(width: 13),
              _Legend(color: context.colors.primary, text: 'Recebido'),
              const SizedBox(width: 13),
              const _Legend(color: profitColor, text: 'Lucro'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinancialValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool loading;

  const _FinancialValue({
    required this.label,
    required this.value,
    required this.color,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 900;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: compact ? 88 : 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 8.5 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 1 : 3),
          if (loading)
            _DashboardLoadingValueLine(
              width: compact ? 72 : 94,
              height: compact ? 9 : 12,
            )
          else
            Text(
              value,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: compact ? 10.5 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardLoadingValueLine extends StatelessWidget {
  final double width;
  final double height;

  const _DashboardLoadingValueLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.colors.divider.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

class _InteractiveFinancialChart extends StatefulWidget {
  final List<AppDashboardFinancialPoint> points;
  final NumberFormat currency;
  final bool loading;
  final Color loanedColor;
  final Color receivedColor;
  final Color profitColor;

  const _InteractiveFinancialChart({
    required this.points,
    required this.currency,
    required this.loading,
    required this.loanedColor,
    required this.receivedColor,
    required this.profitColor,
  });

  @override
  State<_InteractiveFinancialChart> createState() =>
      _InteractiveFinancialChartState();
}

class _InteractiveFinancialChartState
    extends State<_InteractiveFinancialChart> {
  int? _selectedIndex;

  void _selectPoint(Offset position, double width) {
    if (widget.loading || widget.points.isEmpty) return;
    const double chartLeft = 42;
    final double chartWidth = math.max(1, width - chartLeft - 7);
    final double fraction = ((position.dx - chartLeft) / chartWidth).clamp(
      0.0,
      1.0,
    );
    final int index = widget.points.length == 1
        ? 0
        : (fraction * (widget.points.length - 1)).round();
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  @override
  void didUpdateWidget(covariant _InteractiveFinancialChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.loading ||
        _selectedIndex != null && _selectedIndex! >= widget.points.length) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int? selectedIndex = _selectedIndex;
        final bool compact = constraints.maxWidth < 600;
        final double cockpitWidth = compact ? 154 : 198;
        double cockpitLeft = 0;
        if (selectedIndex != null && widget.points.isNotEmpty) {
          final double pointX = widget.points.length == 1
              ? constraints.maxWidth / 2
              : 42 +
                    (constraints.maxWidth - 49) *
                        selectedIndex /
                        (widget.points.length - 1);
          cockpitLeft = pointX + cockpitWidth + 12 <= constraints.maxWidth
              ? pointX + 10
              : pointX - cockpitWidth - 10;
          cockpitLeft = cockpitLeft
              .clamp(42.0, constraints.maxWidth - cockpitWidth - 4)
              .toDouble();
        }

        return MouseRegion(
          cursor: widget.loading || widget.points.isEmpty
              ? MouseCursor.defer
              : SystemMouseCursors.precise,
          onHover: (event) =>
              _selectPoint(event.localPosition, constraints.maxWidth),
          onExit: (_) {
            if (_selectedIndex != null) setState(() => _selectedIndex = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _selectPoint(details.localPosition, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _selectPoint(details.localPosition, constraints.maxWidth),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FinancialChartPainter(
                      points: widget.points,
                      loanedColor: widget.loanedColor,
                      receivedColor: widget.receivedColor,
                      profitColor: widget.profitColor,
                      gridColor: context.colors.divider,
                      labelColor: context.colors.textSecondary,
                      highlightedIndex: selectedIndex,
                    ),
                  ),
                ),
                if (selectedIndex != null && widget.points.isNotEmpty)
                  PositionedDirectional(
                    start: cockpitLeft,
                    top: compact ? 4 : 10,
                    width: cockpitWidth,
                    child: _FinancialCockpit(
                      point: widget.points[selectedIndex],
                      currency: widget.currency,
                      loanedColor: widget.loanedColor,
                      receivedColor: widget.receivedColor,
                      profitColor: widget.profitColor,
                      compact: compact,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FinancialCockpit extends StatelessWidget {
  final AppDashboardFinancialPoint point;
  final NumberFormat currency;
  final Color loanedColor;
  final Color receivedColor;
  final Color profitColor;
  final bool compact;

  const _FinancialCockpit({
    required this.point,
    required this.currency,
    required this.loanedColor,
    required this.receivedColor,
    required this.profitColor,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Detalhes de ${DateFormat('dd/MM/yyyy').format(point.date)}',
      child: Container(
        padding: EdgeInsets.all(compact ? 7 : 10),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? .3 : .12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              DateFormat('dd/MM/yyyy').format(point.date),
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: compact ? 9.5 : 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: compact ? 4 : 7),
            _CockpitValue(
              label: 'Emprestado',
              value: currency.format(point.loanedAmount),
              color: loanedColor,
              compact: compact,
            ),
            _CockpitValue(
              label: 'Recebido',
              value: currency.format(point.receivedAmount),
              color: receivedColor,
              compact: compact,
            ),
            _CockpitValue(
              label: 'Lucro',
              value: currency.format(point.profitAmount),
              color: profitColor,
              compact: compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _CockpitValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _CockpitValue({
    required this.label,
    required this.value,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 2 : 3),
      child: Row(
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: compact ? 8 : 9.5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: compact ? 8 : 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;

  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}

class _DueTodayCard extends StatefulWidget {
  final List<AppDashboardDueTodayLoan> loans;
  final DateTime date;
  final NumberFormat currency;
  final bool loading;
  final ValueChanged<AppDashboardDueTodayLoan> onOpenLoan;

  const _DueTodayCard({
    required this.loans,
    required this.date,
    required this.currency,
    required this.loading,
    required this.onOpenLoan,
  });

  @override
  State<_DueTodayCard> createState() => _DueTodayCardState();
}

class _DueTodayCardState extends State<_DueTodayCard> {
  static const int _pageSize = 10;
  int _page = 0;

  int get _pageCount => math.max(1, (widget.loans.length / _pageSize).ceil());

  @override
  void didUpdateWidget(covariant _DueTodayCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String previousLoans = oldWidget.loans
        .map((loan) => loan.loanId)
        .join(',');
    final String currentLoans = widget.loans
        .map((loan) => loan.loanId)
        .join(',');
    if (previousLoans != currentLoans) {
      _page = 0;
    } else if (_page >= _pageCount) {
      _page = _pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).width < 900;
    final int start = _page * _pageSize;
    final int end = math.min(start + _pageSize, widget.loans.length);
    final List<AppDashboardDueTodayLoan> visibleLoans = widget.loans.sublist(
      start,
      end,
    );
    return _DashboardCard(
      padding: compact
          ? const EdgeInsets.fromLTRB(10, 10, 10, 5)
          : const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Vence hoje',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                DateFormat('dd/MM/yyyy').format(widget.date),
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: compact ? 9 : 11,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 9),
          if (widget.loans.isEmpty && widget.loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 22 : 38),
              child: const Center(
                child: _DashboardLoadingValueLine(width: 150, height: 11),
              ),
            )
          else if (widget.loans.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 14 : 28),
              child: Column(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    color: context.colors.primary,
                    size: compact ? 28 : 40,
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  Text(
                    'Nenhum vencimento hoje',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 12 : null,
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 3),
                  Text(
                    'Não há parcelas vencendo nesta região.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: compact ? 9 : 11,
                    ),
                  ),
                ],
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double horizontalMargin = compact ? 7 : 12;
                  final double columnSpacing = compact ? 4 : 14;
                  final double contentWidth = math.max(
                    0,
                    constraints.maxWidth -
                        horizontalMargin * 2 -
                        columnSpacing * 3,
                  );
                  final double clientWidth = contentWidth * .40;
                  final double contractWidth = contentWidth * .16;
                  final double periodWidth = contentWidth * .20;
                  final double valueWidth = contentWidth * .24;
                  final Color rowDividerColor = context.colors.divider
                      .withValues(alpha: context.isDark ? .45 : .32);
                  final TextStyle headingStyle = TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: compact ? 8 : 10,
                    fontWeight: FontWeight.w800,
                  );

                  Widget heading(
                    String text,
                    double width, {
                    bool end = false,
                  }) {
                    return SizedBox(
                      width: width,
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: end ? TextAlign.end : TextAlign.start,
                        style: headingStyle,
                      ),
                    );
                  }

                  return SizedBox(
                    width: constraints.maxWidth,
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowHeight: compact ? 30 : 34,
                      dataRowMinHeight: compact ? 40 : 46,
                      dataRowMaxHeight: compact ? 40 : 46,
                      horizontalMargin: horizontalMargin,
                      columnSpacing: columnSpacing,
                      dividerThickness: 0,
                      headingRowColor: WidgetStatePropertyAll(
                        context.colors.primary.withValues(alpha: .1),
                      ),
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: rowDividerColor,
                          width: .5,
                        ),
                        bottom: BorderSide(color: rowDividerColor, width: .5),
                      ),
                      columns: [
                        DataColumn(label: heading('CLIENTE', clientWidth)),
                        DataColumn(label: heading('CONTRATO', contractWidth)),
                        DataColumn(label: heading('PERÍODO', periodWidth)),
                        DataColumn(
                          numeric: true,
                          label: heading('VALOR', valueWidth, end: true),
                        ),
                      ],
                      rows: [
                        for (final AppDashboardDueTodayLoan loan
                            in visibleLoans)
                          DataRow(
                            onSelectChanged: widget.loading
                                ? null
                                : (_) => widget.onOpenLoan(loan),
                            cells: [
                              DataCell(
                                _DashboardTableText(
                                  value: loan.clientName,
                                  width: clientWidth,
                                  compact: compact,
                                  bold: true,
                                ),
                              ),
                              DataCell(
                                _DashboardTableText(
                                  value: '#${loan.loanId}',
                                  width: contractWidth,
                                  compact: compact,
                                ),
                              ),
                              DataCell(
                                _DashboardTableText(
                                  value: loan.paymentType,
                                  width: periodWidth,
                                  compact: compact,
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: valueWidth,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: widget.loading
                                        ? _DashboardLoadingValueLine(
                                            width: compact ? 48 : 70,
                                            height: compact ? 8 : 10,
                                          )
                                        : Text(
                                            widget.currency.format(loan.amount),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: context.colors.primary,
                                              fontSize: compact ? 8.5 : 10.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (widget.loans.isNotEmpty) ...[
            SizedBox(height: compact ? 3 : 5),
            _DashboardPagination(
              page: _page,
              pageCount: _pageCount,
              start: start + 1,
              end: end,
              total: widget.loans.length,
              compact: compact,
              onPrevious: widget.loading || _page == 0
                  ? null
                  : () => setState(() => _page--),
              onNext: widget.loading || _page + 1 >= _pageCount
                  ? null
                  : () => setState(() => _page++),
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardTableText extends StatelessWidget {
  final String value;
  final double width;
  final bool compact;
  final bool bold;

  const _DashboardTableText({
    required this.value,
    required this.width,
    required this.compact,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Tooltip(
        message: value,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: compact ? 8.5 : 10.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DashboardPagination extends StatelessWidget {
  final int page;
  final int pageCount;
  final int start;
  final int end;
  final int total;
  final bool compact;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _DashboardPagination({
    required this.page,
    required this.pageCount,
    required this.start,
    required this.end,
    required this.total,
    required this.compact,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '$start–$end de $total · Página ${page + 1} de $pageCount',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: compact ? 8 : 9.5,
          ),
        ),
      ),
      IconButton(
        onPressed: onPrevious,
        tooltip: 'Página anterior',
        visualDensity: VisualDensity.compact,
        constraints: BoxConstraints.tightFor(
          width: compact ? 30 : 34,
          height: compact ? 30 : 34,
        ),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.chevron_left_rounded, size: compact ? 18 : 20),
      ),
      IconButton(
        onPressed: onNext,
        tooltip: 'Próxima página',
        visualDensity: VisualDensity.compact,
        constraints: BoxConstraints.tightFor(
          width: compact ? 30 : 34,
          height: compact ? 30 : 34,
        ),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.chevron_right_rounded, size: compact ? 18 : 20),
      ),
    ],
  );
}

class _DashboardCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _DashboardCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 900;
    final double blur = desktop ? 6 : 12;
    final Offset offset = desktop ? const Offset(0, 1) : const Offset(0, 3);
    final double alpha = context.isDark
        ? (desktop ? .12 : .18)
        : (desktop ? .03 : .055);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: context.colors.divider.withValues(alpha: .8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: alpha),
            blurRadius: blur,
            offset: offset,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FinancialChartPainter extends CustomPainter {
  final List<AppDashboardFinancialPoint> points;
  final Color loanedColor;
  final Color receivedColor;
  final Color profitColor;
  final Color gridColor;
  final Color labelColor;
  final int? highlightedIndex;

  const _FinancialChartPainter({
    required this.points,
    required this.loanedColor,
    required this.receivedColor,
    required this.profitColor,
    required this.gridColor,
    required this.labelColor,
    required this.highlightedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect chart = Rect.fromLTRB(42, 8, size.width - 7, size.height - 25);
    final Paint grid = Paint()
      ..color = gridColor.withValues(alpha: .75)
      ..strokeWidth = 1;
    final double maxValue = points.fold<double>(0, (maximum, point) {
      return math.max(
        maximum,
        math.max(
          point.loanedAmount,
          math.max(point.receivedAmount, point.profitAmount),
        ),
      );
    });
    final double scaleMax = maxValue <= 0 ? 1 : maxValue * 1.12;
    for (int i = 0; i <= 3; i++) {
      final double y = chart.bottom - (chart.height * i / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _paintText(
        canvas,
        _compactMoney(scaleMax * i / 3),
        Offset(0, y - 7),
        labelColor,
      );
    }
    if (points.isEmpty) return;
    _drawSeries(
      canvas,
      chart,
      points.map((point) => point.loanedAmount).toList(growable: false),
      loanedColor,
      scaleMax,
    );
    _drawSeries(
      canvas,
      chart,
      points.map((point) => point.receivedAmount).toList(growable: false),
      receivedColor,
      scaleMax,
    );
    _drawSeries(
      canvas,
      chart,
      points.map((point) => point.profitAmount).toList(growable: false),
      profitColor,
      scaleMax,
    );
    for (int index = 0; index < points.length; index++) {
      final double x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (points.length - 1);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 3),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
    }
    final int maxLabels = math.max(2, chart.width ~/ 48);
    final int labelStep = math.max(
      1,
      ((points.length - 1) / (maxLabels - 1)).ceil(),
    );
    final List<int> labels = <int>[
      for (int index = 0; index < points.length; index += labelStep) index,
      if ((points.length - 1) % labelStep != 0) points.length - 1,
    ];
    for (final int index in labels) {
      final double x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (points.length - 1);
      _paintText(
        canvas,
        DateFormat('dd/MM').format(points[index].date),
        Offset(x - 13, chart.bottom + 7),
        labelColor,
      );
    }
    final int? selected = highlightedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      final double x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * selected / (points.length - 1);
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        Paint()
          ..color = labelColor.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      final AppDashboardFinancialPoint point = points[selected];
      final List<(double, Color)> selectedValues = [
        (point.loanedAmount, loanedColor),
        (point.receivedAmount, receivedColor),
        (point.profitAmount, profitColor),
      ];
      for (final (double value, Color color) in selectedValues) {
        final double y = chart.bottom - chart.height * value / scaleMax;
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
      }
    }
  }

  void _drawSeries(
    Canvas canvas,
    Rect chart,
    List<double> values,
    Color color,
    double maxValue,
  ) {
    if (values.isEmpty) return;
    final List<Offset> offsets = List<Offset>.generate(values.length, (index) {
      final double x = values.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (values.length - 1);
      final double y = chart.bottom - chart.height * values[index] / maxValue;
      return Offset(x, y);
    });
    final Path path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      final Offset previous = offsets[i - 1];
      final Offset current = offsets[i];
      final double middleX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        middleX,
        previous.dy,
        middleX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintText(Canvas canvas, String text, Offset offset, Color color) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 8),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  String _compactMoney(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)} mi';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)} mil';
    }
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _FinancialChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.loanedColor != loanedColor ||
      oldDelegate.receivedColor != receivedColor ||
      oldDelegate.profitColor != profitColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.highlightedIndex != highlightedIndex;
}

class _DashboardError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DashboardError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              color: context.colors.primary,
              size: 52,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: const Text('TENTAR NOVAMENTE'),
            ),
          ],
        ),
      ),
    );
  }
}
