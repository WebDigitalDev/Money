import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class FinancialGoalsScreenController {
  VoidCallback? _openCreate;

  void openCreate() => _openCreate?.call();
}

typedef FinancialGoalRegionsCallback = Future<List<AppRegionOption>> Function({
  required bool force,
});

class FinancialGoalsScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final FinancialGoalsScreenController? controller;
  final FinancialGoalService? service;
  final bool? administrator;
  final FinancialGoalRegionsCallback? fetchRegions;

  const FinancialGoalsScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
    this.service,
    this.administrator,
    this.fetchRegions,
  });

  @override
  State<FinancialGoalsScreen> createState() => _FinancialGoalsScreenState();
}

class _FinancialGoalsScreenState extends State<FinancialGoalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static const double _mobileFloatingActionClearance = 82;

  late final FinancialGoalService _service;
  final RegionService _regionService = RegionService();
  final List<AppFinancialGoal> _goals = [];

  List<AppRegionOption> _regions = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _clientsTab = false;

  bool get _administrator =>
      widget.administrator ??
      (AuthService().currentSession?.administrator == true);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (_clientsTab != (_tabs.index == 1)) {
          setState(() => _clientsTab = _tabs.index == 1);
        }
      });
    _service = widget.service ?? FinancialGoalService();
    _goals.addAll(_service.cachedGoals);
    _attachController(widget.controller);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FinancialGoalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (!oldWidget.active && widget.active) unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController(FinancialGoalsScreenController? controller) {
    controller?._openCreate = _openCreate;
  }

  void _detachController(FinancialGoalsScreenController? controller) {
    controller?._openCreate = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.sidebar_financial_goals,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: _buildContent(),
              ),
            ),
            if (_saving)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: context.colors.primary,
                  backgroundColor: context.colors.primary.withValues(
                    alpha: .12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final bool mobile = MediaQuery.sizeOf(context).width < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? 12 : 8,
        mobile ? 12 : 14,
        mobile ? 12 : 8,
        mobile ? 0 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showAppBar) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Metas',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Acompanhe o desempenho financeiro de cada região.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_administrator)
                  FilledButton.icon(
                    onPressed: _saving ? null : _openCreate,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('NOVA META'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Material(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              controller: _tabs,
              indicatorColor: context.colors.primary,
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(height: 39, text: 'Financeiro'),
                Tab(height: 39, text: 'Clientes'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildGoals(mobile, false), _buildGoals(mobile, true)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoals(bool mobile, bool clientsTab) {
    final goals = _goals.where((g) => g.type.isClient == clientsTab).toList();
    if (_loading && _goals.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_error != null && _goals.isEmpty) {
      return _GoalMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar as metas',
        message: _error!,
        actionLabel: 'TENTAR NOVAMENTE',
        onAction: _load,
      );
    }
    if (goals.isEmpty) {
      return _GoalMessage(
        icon: Icons.track_changes_rounded,
        title: clientsTab
            ? 'Nenhuma meta de clientes criada'
            : 'Nenhuma meta financeira criada',
        message: _administrator
            ? 'Crie a primeira meta para acompanhar uma região.'
            : 'Ainda não existem metas para suas regiões.',
        actionLabel: _administrator ? 'CRIAR META' : null,
        onAction: _administrator ? _openCreate : null,
      );
    }

    final double mobileBottomPadding = widget.showAppBar
        ? MediaQuery.viewPaddingOf(context).bottom +
              kBottomNavigationBarHeight +
              _mobileFloatingActionClearance
        : 12;
    final Widget list = mobile
        ? ListView.separated(
            key: const ValueKey('financial_goals_mobile_list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: mobileBottomPadding),
            itemCount: goals.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) => SizedBox(
              height: clientsTab ? null : 242,
              child: FinancialGoalCard(
                key: ValueKey('financial_goal_card_${goals[index].id}'),
                goal: goals[index],
                compact: true,
                onEdit:
                    _administrator &&
                        goals[index].canManage &&
                        goals[index].status != AppFinancialGoalStatus.completed
                    ? () => _openForm(goals[index])
                    : null,
                onDelete: _administrator
                    ? () => _deleteGoal(goals[index])
                    : null,
              ),
            ),
          )
        : GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: goals.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 560,
              mainAxisExtent: clientsTab ? 240 : 218,
              crossAxisSpacing: 13,
              mainAxisSpacing: 13,
            ),
            itemBuilder: (_, index) => FinancialGoalCard(
              key: ValueKey('financial_goal_card_${goals[index].id}'),
              goal: goals[index],
              compact: true,
              onEdit:
                  _administrator &&
                      goals[index].canManage &&
                      goals[index].status != AppFinancialGoalStatus.completed
                  ? () => _openForm(goals[index])
                  : null,
              onDelete: _administrator ? () => _deleteGoal(goals[index]) : null,
            ),
          );
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: _load,
      child: list,
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchGoals();
      if (!mounted) return;
      setState(() {
        _goals
          ..clear()
          ..addAll(result);
      });
    } on FinancialGoalServiceException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (error.statusCode == 401 || error.statusCode == 403) {
            _goals.clear();
          }
        });
      }
    } on RegionServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCreate() {
    if (!_administrator || _saving) return;
    unawaited(_openForm());
  }

  Future<void> _openForm([AppFinancialGoal? goal]) async {
    if (!_administrator || _saving) return;
    if (_regions.isEmpty) {
      try {
        final List<AppRegionOption> regions = await _fetchRegions(force: true);
        if (!mounted) return;
        setState(() => _regions = regions);
      } on RegionServiceException catch (error) {
        _showMessage(error.message);
        return;
      }
    }
    if (!mounted) return;
    final bool mobile = MediaQuery.sizeOf(context).width < 700;
    final AppFinancialGoalDraft? draft = await showAppDialog(
      context: context,
      title: _clientsTab
          ? (goal == null ? 'Nova meta de clientes' : 'Editar meta de clientes')
          : (goal == null ? 'Nova meta financeira' : 'Editar meta financeira'),
      subtitle: 'Defina as regiões, o indicador, o valor e o período.',
      icon: Icons.track_changes_rounded,
      maxWidth: mobile ? 440 : 520,
      maxHeight: _clientsTab ? (mobile ? 515 : 485) : (mobile ? 455 : 430),
      builder: (_) => _FinancialGoalForm(
        regions: _regions,
        initial: goal,
        compact: true,
        clients: _clientsTab,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (goal == null) {
        await _service.createGoal(draft);
        _showMessage('Meta financeira criada com sucesso.');
      } else {
        await _service.updateGoal(goal.id, draft);
        _showMessage('Meta financeira atualizada com sucesso.');
      }
      await _load();
    } on FinancialGoalServiceException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<AppRegionOption>> _fetchRegions({bool force = false}) =>
      widget.fetchRegions == null
      ? _regionService.fetchOptions(force: force)
      : widget.fetchRegions!(force: force);

  Future<void> _deleteGoal(AppFinancialGoal goal) async {
    if (!_administrator || _saving) return;
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Excluir meta financeira?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'A meta de ${goal.type.label.toLowerCase()} de '
                '${goal.isRegionGroup ? 'um grupo de regiões' : goal.regionName} '
                'será removida.',
              ),
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
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.deleteGoal(goal.id);
      _showMessage('Meta financeira excluída.');
      await _load();
    } on FinancialGoalServiceException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class FinancialGoalCard extends StatelessWidget {
  final AppFinancialGoal goal;
  final bool compact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const FinancialGoalCard({
    super.key,
    required this.goal,
    this.compact = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = _goalColor(context, goal.type);
    if (goal.type.isClient) {
      return _ClientGoalCard(goal: goal, onEdit: onEdit, onDelete: onDelete);
    }
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Material(
      color: context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 15 : 18),
        side: BorderSide(color: context.colors.divider),
      ),
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(11, 10, 8, 9)
            : const EdgeInsets.fromLTRB(15, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 33 : 39,
                  height: compact ? 33 : 39,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(compact ? 9 : 11),
                  ),
                  child: Icon(
                    _goalIcon(goal.type),
                    color: accent,
                    size: compact ? 18 : 22,
                  ),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.isRegionGroup
                            ? 'GRUPO DE REGIÕES'
                            : goal.regionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: compact ? 12.5 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (goal.isRegionGroup) ...[
                        SizedBox(height: compact ? 1 : 2),
                        Text(
                          goal.regionNames.join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.primary,
                            fontSize: compact ? 8 : 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 1 : 2),
                      Text(
                        'Meta de ${goal.type.label.toLowerCase()}',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: compact ? 9 : 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _GoalStatusChip(
                  status: goal.status,
                  accent: accent,
                  compact: compact,
                ),
                if (onEdit != null)
                  IconButton(
                    key: ValueKey('financial_goal_edit_${goal.id}'),
                    tooltip: 'Editar meta',
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: context.colors.textSecondary,
                      size: compact ? 18 : 21,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(
                      width: compact ? 32 : 40,
                      height: compact ? 32 : 40,
                    ),
                  ),
                if (onDelete != null)
                  IconButton(
                    key: ValueKey('financial_goal_delete_${goal.id}'),
                    tooltip: 'Excluir meta',
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: context.colors.error,
                      size: compact ? 18 : 21,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(
                      width: compact ? 32 : 40,
                      height: compact ? 32 : 40,
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 7 : 13),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GoalValueLine(
                          label: 'Valor da meta',
                          value: currency.format(goal.targetAmount),
                          color: accent,
                          icon: Icons.flag_outlined,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 7 : 12),
                        _GoalValueLine(
                          label: 'Valor alcançado',
                          value: currency.format(goal.achievedAmount),
                          color: context.colors.primary,
                          icon: Icons.check_circle_outline_rounded,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 7 : 12),
                        _GoalValueLine(
                          label: 'Valor restante',
                          value: currency.format(goal.remainingAmount),
                          color: context.colors.textSecondary,
                          icon: Icons.hourglass_bottom_rounded,
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 13),
                  _GoalProgressCircle(
                    goal: goal,
                    color: accent,
                    compact: compact,
                  ),
                ],
              ),
            ),
            Divider(height: compact ? 13 : 17, color: context.colors.divider),
            Row(
              children: [
                Icon(
                  Icons.date_range_outlined,
                  color: context.colors.textSecondary,
                  size: compact ? 13 : 15,
                ),
                SizedBox(width: compact ? 4 : 5),
                Expanded(
                  child: Text(
                    '${_shortDate(goal.startDate)} até ${_shortDate(goal.endDate)}',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: compact ? 9 : 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  goal.percentage >= 100 ? 'Meta alcançada' : _daysLabel(goal),
                  style: TextStyle(
                    color: goal.percentage >= 100
                        ? context.colors.primary
                        : context.colors.textSecondary,
                    fontSize: compact ? 8.5 : 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _daysLabel(AppFinancialGoal goal) {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    if (goal.status == AppFinancialGoalStatus.upcoming) {
      final int days = goal.startDate.difference(today).inDays;
      return 'Inicia em $days dia${days == 1 ? '' : 's'}';
    }
    if (goal.status == AppFinancialGoalStatus.completed) {
      return 'Período encerrado';
    }
    final int days = goal.endDate.difference(today).inDays;
    return '$days dia${days == 1 ? '' : 's'} restante${days == 1 ? '' : 's'}';
  }
}

class _ClientGoalCard extends StatelessWidget {
  final AppFinancialGoal goal;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _ClientGoalCard({required this.goal, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = _goalColor(context, goal.type);
    String percent(int count) => goal.activeClients == 0
        ? '0'
        : NumberFormat(
            '0.##',
            'pt_BR',
          ).format(count * 100 / goal.activeClients);
    final target = NumberFormat('0.##', 'pt_BR').format(goal.targetAmount);
    final objective = goal.type == AppFinancialGoalType.overdueClients
        ? 'No máximo $target% em atraso'
        : goal.type.isPercentage
        ? 'Pelo menos $target% em dia'
        : '$target novos clientes ativos';
    return Card(
      margin: EdgeInsets.zero,
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: context.colors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_goalIcon(goal.type), color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goal.regionName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    tooltip: 'Editar meta',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    tooltip: 'Excluir meta',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
              ],
            ),
            Text(
              '${_shortDate(goal.startDate)} até ${_shortDate(goal.endDate)}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              objective,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Clientes ativos: ${goal.activeClients}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Clientes em dia: ${goal.onTimeClients} — ${percent(goal.onTimeClients)}%',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Clientes em atraso: ${goal.overdueClients} — ${percent(goal.overdueClients)}%',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Novos clientes no período: ${goal.newClients}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            _AnimatedGoalBar(progress: goal.progress, color: color),
            const SizedBox(height: 7),
            Text(
              '${goal.percentage >= 100 ? 'Meta alcançada' : goal.status.label} • ${NumberFormat('0.##', 'pt_BR').format(goal.displayPercentage)}%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedGoalBar extends StatefulWidget {
  final double progress;
  final Color color;
  const _AnimatedGoalBar({required this.progress, required this.color});
  @override
  State<_AnimatedGoalBar> createState() => _AnimatedGoalBarState();
}

class _AnimatedGoalBarState extends State<_AnimatedGoalBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shine.stop();
    } else {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Progresso da meta',
    value: '${(widget.progress * 100).round()}%',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 9,
        child: AnimatedBuilder(
          animation: _shine,
          builder: (context, _) => Stack(
            children: [
              LinearProgressIndicator(
                value: widget.progress,
                minHeight: 9,
                color: widget.color,
                backgroundColor: widget.color.withValues(alpha: .12),
              ),
              FractionallySizedBox(
                widthFactor: widget.progress,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-3 + _shine.value * 6, 0),
                      end: Alignment(-2 + _shine.value * 6, 0),
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: .4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _GoalValueLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool compact;

  const _GoalValueLine({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: compact ? 28 : 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Icon(icon, color: color, size: compact ? 15 : 18),
        SizedBox(width: compact ? 5 : 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: compact ? 8.5 : 9.5,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: compact ? 11.5 : 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoalProgressCircle extends StatefulWidget {
  final AppFinancialGoal goal;
  final Color color;
  final bool compact;

  const _GoalProgressCircle({
    required this.goal,
    required this.color,
    required this.compact,
  });

  @override
  State<_GoalProgressCircle> createState() => _GoalProgressCircleState();
}

class _GoalProgressCircleState extends State<_GoalProgressCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  AppFinancialGoal get goal => widget.goal;
  Color get color => widget.color;
  bool get compact => widget.compact;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shine.stop();
    } else {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double displayedPercentage = goal.displayPercentage;
    final String percentage =
        displayedPercentage == displayedPercentage.roundToDouble()
        ? '${displayedPercentage.round()}%'
        : '${displayedPercentage.toStringAsFixed(1)}%';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: goal.progress),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox.square(
        dimension: compact ? 88 : 116,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: CustomPaint(
                key: const ValueKey('financial_goal_progress_arc'),
                painter: FinancialGoalProgressPainter(
                  progress: value,
                  color: color,
                  trackColor: color.withValues(alpha: .12),
                  strokeWidth: compact ? 8 : 10,
                  shine: MediaQuery.disableAnimationsOf(context)
                      ? null
                      : _shine,
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      percentage,
                      style: TextStyle(
                        color: color,
                        fontSize: compact ? 19 : 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    'alcançado',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: compact ? 8 : 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FinancialGoalProgressPainter extends CustomPainter {
  final Animation<double>? shine;
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  FinancialGoalProgressPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    this.shine,
  }) : super(repaint: shine);

  Color get startColor => Color.lerp(color, Colors.white, .55)!;

  Color get endColor => color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final Rect arcBounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final double effectiveProgress = progress.clamp(0, 1);
    if (effectiveProgress <= 0) return;
    const double startAngle = -math.pi / 2;
    final double sweepAngle = effectiveProgress * (math.pi * 2 - .001);
    final Paint progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        transform: const GradientRotation(startAngle),
        colors: [startColor, Color.lerp(startColor, endColor, .5)!, endColor],
        stops: const [0, .5, 1],
        tileMode: TileMode.clamp,
      ).createShader(arcBounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcBounds, startAngle, sweepAngle, false, progressPaint);

    if (shine != null) {
      final position = shine!.value;
      final highlight = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweepAngle,
          transform: const GradientRotation(startAngle),
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: .55),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [
            0,
            (position - .12).clamp(0, 1),
            position,
            (position + .12).clamp(0, 1),
            1,
          ],
        ).createShader(arcBounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcBounds, startAngle, sweepAngle, false, highlight);
    }

    final double endAngle = startAngle + sweepAngle;
    final Offset end =
        center + Offset(math.cos(endAngle), math.sin(endAngle)) * radius;
    canvas.drawCircle(end, 3.8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant FinancialGoalProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.shine != shine ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _GoalStatusChip extends StatelessWidget {
  final AppFinancialGoalStatus status;
  final Color accent;
  final bool compact;

  const _GoalStatusChip({
    required this.status,
    required this.accent,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      AppFinancialGoalStatus.active => context.colors.primary,
      AppFinancialGoalStatus.upcoming => accent,
      AppFinancialGoalStatus.completed => context.colors.textSecondary,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 7.5 : 8.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FinancialGoalForm extends StatefulWidget {
  final List<AppRegionOption> regions;
  final AppFinancialGoal? initial;
  final bool compact;
  final bool clients;

  const _FinancialGoalForm({
    required this.regions,
    required this.initial,
    required this.compact,
    this.clients = false,
  });

  @override
  State<_FinancialGoalForm> createState() => _FinancialGoalFormState();
}

class _FinancialGoalFormState extends State<_FinancialGoalForm> {
  final TextEditingController _amountController = TextEditingController();
  late Set<int> _regionIds;
  late AppFinancialGoalType _type;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _repeatFrequency;
  String? _error;

  @override
  void initState() {
    super.initState();
    final AppFinancialGoal? initial = widget.initial;
    _regionIds = initial == null
        ? <int>{if (widget.regions.isNotEmpty) widget.regions.first.id}
        : initial.regionIds.toSet();
    _type =
        initial?.type ??
        (widget.clients
            ? AppFinancialGoalType.onTimeClients
            : AppFinancialGoalType.loaned);
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    _startDate = initial?.startDate ?? today;
    _endDate = initial?.endDate ?? today.add(const Duration(days: 30));
    _repeatFrequency = initial?.repeatFrequency ?? false;
    if (initial != null) {
      _amountController.text = NumberFormat(
        _type.isClient ? '0.##' : '#,##0.00',
        'pt_BR',
      ).format(initial.targetAmount);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.compact
          ? (widget.clients ? 475 : 425)
          : (widget.clients ? 600 : 545),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: widget.compact
                  ? const EdgeInsets.fromLTRB(12, 7, 12, 5)
                  : const EdgeInsets.fromLTRB(15, 12, 15, 8),
              children: [
                _sectionTitle(context, 'Regiões'),
                SizedBox(height: widget.compact ? 4 : 6),
                InkWell(
                  key: const ValueKey('financial_goal_regions_button'),
                  onTap: _openRegionSelection,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration(
                      context,
                      Icons.location_on_outlined,
                      'Selecione as regiões',
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _regionSelectionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: widget.compact ? 12 : 14,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: context.colors.textSecondary,
                          size: widget.compact ? 18 : 21,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: widget.compact ? 9 : 15),
                _sectionTitle(context, 'Indicador da meta'),
                SizedBox(height: widget.compact ? 4 : 7),
                Wrap(
                  spacing: widget.compact ? 5 : 7,
                  runSpacing: widget.compact ? 5 : 7,
                  children: [
                    for (final AppFinancialGoalType type
                        in AppFinancialGoalType.values.where(
                          (t) => t.isClient == widget.clients,
                        ))
                      ChoiceChip(
                        selected: _type == type,
                        showCheckmark: false,
                        avatar: Icon(
                          _goalIcon(type),
                          size: widget.compact ? 14 : 17,
                          color: _type == type
                              ? Colors.white
                              : _goalColor(context, type),
                        ),
                        label: Text(type.label),
                        selectedColor: _goalColor(context, type),
                        backgroundColor: context.colors.background,
                        side: BorderSide(color: context.colors.divider),
                        visualDensity: widget.compact
                            ? const VisualDensity(horizontal: -2, vertical: -3)
                            : VisualDensity.standard,
                        materialTapTargetSize: widget.compact
                            ? MaterialTapTargetSize.shrinkWrap
                            : MaterialTapTargetSize.padded,
                        labelPadding: EdgeInsets.symmetric(
                          horizontal: widget.compact ? 4 : 8,
                        ),
                        labelStyle: TextStyle(
                          color: _type == type
                              ? Colors.white
                              : context.colors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: widget.compact ? 9.5 : 11,
                        ),
                        onSelected: (_) => setState(() {
                          _type = type;
                          _amountController.clear();
                        }),
                      ),
                  ],
                ),
                SizedBox(height: widget.compact ? 9 : 15),
                _sectionTitle(
                  context,
                  _type.isPercentage
                      ? (_type == AppFinancialGoalType.overdueClients
                            ? 'Percentual máximo em atraso'
                            : 'Percentual mínimo em dia')
                      : _type.isClient
                      ? 'Quantidade de novos clientes'
                      : 'Valor da meta',
                ),
                SizedBox(height: widget.compact ? 4 : 6),
                TextField(
                  controller: _amountController,
                  style: TextStyle(fontSize: widget.compact ? 12.5 : 14),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: _type.isClient
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))]
                      : const [_GoalMoneyInputFormatter()],
                  decoration:
                      _inputDecoration(
                        context,
                        Icons.attach_money_rounded,
                        '0,00',
                      ).copyWith(
                        prefixText: _type.isClient ? null : 'R\$ ',
                        suffixText: _type.isPercentage ? '%' : null,
                      ),
                ),
                SizedBox(height: widget.compact ? 9 : 15),
                _sectionTitle(context, 'Período da meta'),
                SizedBox(height: widget.compact ? 4 : 6),
                Row(
                  children: [
                    Expanded(
                      child: _GoalDateField(
                        label: 'Data inicial',
                        value: _startDate,
                        compact: widget.compact,
                        onTap: () => _selectDate(start: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GoalDateField(
                        label: 'Data final',
                        value: _endDate,
                        compact: widget.compact,
                        onTap: () => _selectDate(start: false),
                      ),
                    ),
                  ],
                ),
                if (widget.clients) ...[
                  SizedBox(height: widget.compact ? 7 : 11),
                  Material(
                    color: context.colors.background,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: context.colors.divider),
                    ),
                    child: InkWell(
                      onTap: () =>
                          setState(() => _repeatFrequency = !_repeatFrequency),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.compact ? 10 : 12,
                          vertical: widget.compact ? 5 : 7,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.repeat_rounded,
                              color: context.colors.primary,
                              size: widget.compact ? 18 : 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Repetir frequência',
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: widget.compact ? 11.5 : 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Criar o próximo período automaticamente.',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: widget.compact ? 9 : 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: widget.compact ? .72 : .8,
                              child: Switch.adaptive(
                                value: _repeatFrequency,
                                onChanged: (value) =>
                                    setState(() => _repeatFrequency = value),
                                activeThumbColor: context.colors.primary,
                                activeTrackColor: context.colors.primary
                                    .withValues(alpha: .45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  SizedBox(height: widget.compact ? 7 : 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: widget.compact ? 9.5 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: widget.compact
                ? const EdgeInsets.fromLTRB(12, 7, 12, 9)
                : const EdgeInsets.fromLTRB(15, 10, 15, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.colors.divider)),
            ),
            child: SizedBox(
              height: widget.compact ? 36 : 42,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.textPrimary,
                        side: BorderSide(color: context.colors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            widget.compact ? 10 : 12,
                          ),
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: TextStyle(fontSize: widget.compact ? 11 : 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            widget.compact ? 10 : 12,
                          ),
                        ),
                      ),
                      child: Text(
                        'SALVAR',
                        style: TextStyle(fontSize: widget.compact ? 11 : 14),
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

  Future<void> _selectDate({required bool start}) async {
    final DateTime? selected = await showAppDatePickerDialog(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      title: start ? 'Início da meta' : 'Final da meta',
      subtitle: 'Selecione a data do período da meta financeira.',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
        if (_endDate.isBefore(selected)) _endDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  String get _regionSelectionLabel {
    if (_regionIds.isEmpty) return 'Selecione as regiões';
    if (_regionIds.length == 1) {
      final int id = _regionIds.first;
      return widget.regions
          .firstWhere(
            (region) => region.id == id,
            orElse: () => AppRegionOption(id: id, name: 'Região #$id'),
          )
          .name;
    }
    return '${_regionIds.length} regiões selecionadas';
  }

  Future<void> _openRegionSelection() async {
    final Set<int>? selected = await showRegionSelectionDialog(
      context: context,
      options: widget.regions,
      selected: _regionIds,
      title: 'Regiões da meta',
      subtitle: 'Selecione uma ou mais regiões para compor a meta.',
      emptySelectionLabel: 'Selecione ao menos uma região',
    );
    if (selected == null || !mounted) return;
    setState(() => _regionIds = selected);
  }

  void _submit() {
    if (_type.isClient &&
        !RegExp(r'^\d+(,\d{1,2})?$').hasMatch(_amountController.text)) {
      setState(() => _error = 'Informe uma quantidade ou percentual válido.');
      return;
    }
    final double amount = _parseMoney(_amountController.text);
    if (_regionIds.isEmpty) {
      setState(() => _error = 'Selecione ao menos uma região.');
      return;
    }
    if (amount < 0 ||
        _amountController.text.isEmpty ||
        (amount == 0 && _type != AppFinancialGoalType.overdueClients) ||
        (_type.isPercentage && amount > 100) ||
        (_type == AppFinancialGoalType.newClients &&
            amount != amount.truncateToDouble())) {
      setState(
        () => _error = _type.isPercentage
            ? 'Informe um percentual válido entre 0 e 100.'
            : 'Informe uma quantidade ou valor válido maior que zero.',
      );
      return;
    }
    if (_startDate.isAfter(_endDate)) {
      setState(() => _error = 'A data inicial deve ser anterior à data final.');
      return;
    }
    Navigator.pop(
      context,
      AppFinancialGoalDraft(
        regionIds: widget.regions
            .where((region) => _regionIds.contains(region.id))
            .map((region) => region.id)
            .toList(growable: false),
        type: _type,
        targetAmount: amount,
        startDate: _startDate,
        endDate: _endDate,
        repeatFrequency: widget.clients && _repeatFrequency,
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String value) => Text(
    value,
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: widget.compact ? 10 : 11.5,
      fontWeight: FontWeight.w800,
    ),
  );

  InputDecoration _inputDecoration(
    BuildContext context,
    IconData icon,
    String hint,
  ) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(
      icon,
      color: context.colors.primary,
      size: widget.compact ? 17 : 20,
    ),
    prefixIconConstraints: widget.compact
        ? const BoxConstraints.tightFor(width: 37, height: 38)
        : null,
    filled: true,
    fillColor: context.colors.background,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: widget.compact ? 10 : 12,
      vertical: widget.compact ? 10 : 13,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.colors.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.colors.primary, width: 1.2),
    ),
  );
}

class _GoalDateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool compact;
  final VoidCallback onTap;

  const _GoalDateField({
    required this.label,
    required this.value,
    required this.compact,
    required this.onTap,
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
          height: compact ? 42 : 50,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.divider),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: context.colors.primary,
                size: compact ? 15 : 18,
              ),
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: compact ? 7.5 : 8.5,
                      ),
                    ),
                    Text(
                      _shortDate(value),
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: compact ? 10 : 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalMoneyInputFormatter extends TextInputFormatter {
  const _GoalMoneyInputFormatter();

  static final NumberFormat _formatter = NumberFormat('#,##0.00', 'pt_BR');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > 15) digits = digits.substring(0, 15);
    final String formatted = _formatter.format(
      (int.tryParse(digits) ?? 0) / 100,
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _GoalMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GoalMessage({
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
            Icon(icon, color: context.colors.primary, size: 48),
            const SizedBox(height: 11),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

Color _goalColor(BuildContext context, AppFinancialGoalType type) =>
    switch (type) {
      AppFinancialGoalType.loaned => context.colors.primary,
      AppFinancialGoalType.received => const Color(0xFF3F83C5),
      AppFinancialGoalType.profit => const Color(0xFF7C65B7),
      AppFinancialGoalType.newClients => const Color(0xFF4285B4),
      AppFinancialGoalType.onTimeClients => const Color(0xFF459B61),
      AppFinancialGoalType.overdueClients => const Color(0xFFD47542),
    };

IconData _goalIcon(AppFinancialGoalType type) => switch (type) {
  AppFinancialGoalType.loaned => Icons.payments_outlined,
  AppFinancialGoalType.received => Icons.account_balance_wallet_outlined,
  AppFinancialGoalType.profit => Icons.trending_up_rounded,
  AppFinancialGoalType.newClients => Icons.person_add_alt_1,
  AppFinancialGoalType.onTimeClients => Icons.verified_user_outlined,
  AppFinancialGoalType.overdueClients => Icons.person_off_outlined,
};

double _parseMoney(String value) =>
    double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
