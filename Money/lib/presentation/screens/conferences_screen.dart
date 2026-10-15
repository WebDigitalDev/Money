import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

typedef ConferenceFetchCallback =
    Future<AppConferenceListData> Function({
      required AppConferenceCategory category,
      required String query,
      required Set<int> regionIds,
    });

typedef ConferenceRegionsCallback = Future<List<AppRegionOption>> Function();

class ConferencesScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final bool? administrator;
  final ConferenceFetchCallback? fetch;
  final ConferenceRegionsCallback? fetchRegions;

  const ConferencesScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.administrator,
    this.fetch,
    this.fetchRegions,
  });

  @override
  State<ConferencesScreen> createState() => _ConferencesScreenState();
}

class _ConferencesScreenState extends State<ConferencesScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _refreshInterval = Duration(seconds: 15);
  static const List<AppConferenceCategory> _categories = [
    AppConferenceCategory.payment,
    AppConferenceCategory.loan,
    AppConferenceCategory.negotiation,
    AppConferenceCategory.closure,
  ];

  final ConferenceService _service = ConferenceService();
  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  AppConferenceCategory _category = AppConferenceCategory.payment;
  AppConferenceListData? _data;
  Map<String, int> _counts = const {};
  final Map<AppConferenceCategory, AppConferenceListData> _cachedData = {};
  final Map<int, List<AppConferenceDetail>> _detailsCache = {};
  List<AppRegionOption> _regions = const [];
  Set<int> _selectedRegions = const {};
  Timer? _searchDebounce;
  Timer? _refreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  int? _processingId;
  String? _error;
  int _requestVersion = 0;
  double _tabDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this)
      ..addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshSilently());
  }

  Future<void> _initialize() async {
    final Set<int> selectedRegions = await _loadSavedFilters();
    if (!mounted) return;
    setState(() => _selectedRegions = selectedRegions);
    if (!widget.active) return;
    unawaited(_loadRegions());
    await _load();
  }

  @override
  void didUpdateWidget(covariant ConferencesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      if (_data == null) {
        unawaited(_loadRegions());
        _load();
      } else {
        unawaited(_refreshSilently());
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _refreshTimer?.cancel();
    _searchController.dispose();
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final AppConferenceCategory value = _categories[_tabController.index];
    if (value == _category) return;
    ++_requestVersion;
    setState(() {
      _category = value;
      _data = _cachedData[value];
      _loading = _data == null;
      _refreshing = false;
      _error = null;
    });
    // A lista em cache evita piscar a tela, mas a contagem e os itens precisam
    // ser consultados imediatamente: uma conferência pode ter sido decidida
    // por outro usuário desde a última visita à aba.
    unawaited(_load(silent: _data != null));
  }

  @override
  Widget build(BuildContext context) {
    final bool administrator =
        widget.administrator ??
        AuthService().currentSession?.administrator == true;
    return Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: 'Conferências',
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: administrator ? _buildContent() : _buildForbidden(),
    );
  }

  Widget _buildContent() {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 8,
              compact ? 9 : 14,
              compact ? 10 : 8,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conferência financeira',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_data?.total ?? 0} operações aguardando análise',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _refreshing ? null : _load,
                        tooltip: 'Atualizar',
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _buildSearch(compact),
                const SizedBox(height: 9),
                _buildTabs(compact),
                const SizedBox(height: 9),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _tabDragDistance = 0,
                    onHorizontalDragUpdate: (details) =>
                        _tabDragDistance += details.delta.dx,
                    onHorizontalDragEnd: _handleTabSwipe,
                    onHorizontalDragCancel: () => _tabDragDistance = 0,
                    child: _buildBody(compact, data: _data, active: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearch(bool compact) => Row(
    children: [
      Expanded(
        child: SizedBox(
          height: compact ? 48 : 46,
          child: TextField(
            controller: _searchController,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: 'Pesquisar contrato, cliente ou solicitante',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.colors.primary,
                size: 21,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _reloadForChangedFilters();
                      },
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
              filled: true,
              fillColor: context.colors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: context.colors.divider),
              ),
            ),
            onChanged: (_) {
              setState(() {});
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 320),
                _reloadForChangedFilters,
              );
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: compact ? 48 : 46,
        height: compact ? 48 : 46,
        child: Badge(
          isLabelVisible:
              _selectedRegions.isNotEmpty &&
              _selectedRegions.length != _regions.length,
          label: Text('${_selectedRegions.length}'),
          child: OutlinedButton(
            onPressed: _showRegionFilter,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(color: context.colors.divider),
              backgroundColor: context.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: context.colors.primary,
              size: 22,
            ),
          ),
        ),
      ),
    ],
  );

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

  Widget _buildTabs(bool compact) => Material(
    color: context.colors.surface,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerColor: context.colors.divider,
      indicatorColor: context.colors.primary,
      labelColor: context.colors.primary,
      unselectedLabelColor: context.colors.textSecondary,
      labelStyle: TextStyle(
        fontSize: compact ? 11.5 : 12,
        fontWeight: FontWeight.w700,
      ),
      padding: EdgeInsets.zero,
      labelPadding: EdgeInsets.symmetric(horizontal: compact ? 15 : 20),
      tabs: [
        for (final AppConferenceCategory value in _categories)
          Tab(
            height: compact ? 42 : 44,
            text: '${value.label} (${_counts[value.apiValue] ?? 0})',
          ),
      ],
    ),
  );

  Widget _buildBody(
    bool compact, {
    required AppConferenceListData? data,
    required bool active,
  }) {
    if (active && _loading && data == null) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (active && _error != null && data == null) {
      return _ConferenceEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar',
        message: _error!,
        buttonLabel: 'TENTAR NOVAMENTE',
        onPressed: _load,
      );
    }
    // Cobranças PIX pertencem exclusivamente à aba de conferências do
    // empréstimo. A filtragem defensiva evita que uma resposta antiga do
    // backend volte a exibi-las nesta página global.
    final List<AppConferenceItem> items = (data?.items ?? const [])
        .where((item) => !item.isPix)
        .toList(growable: false);
    if (items.isEmpty) {
      return _ConferenceEmptyState(
        icon: Icons.verified_rounded,
        title: active && _loading ? 'Carregando' : 'Tudo conferido',
        message: active && _loading
            ? 'Atualizando as conferências...'
            : 'Nenhuma operação foi encontrada neste filtro.',
      );
    }
    final double bottomPadding = compact && widget.showAppBar
        ? kBottomNavigationBarHeight + MediaQuery.paddingOf(context).bottom + 42
        : 12;
    final int columnCount = MediaQuery.sizeOf(context).width >= 900 ? 3 : 2;
    final Widget list = compact
        ? ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (_, index) =>
                _buildCard(items[index], position: index + 1),
          )
        : ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: (items.length + columnCount - 1) ~/ columnCount,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, rowIndex) {
              final int firstIndex = rowIndex * columnCount;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int column = 0; column < columnCount; column++) ...[
                    if (column > 0) const SizedBox(width: 10),
                    Expanded(
                      child: firstIndex + column < items.length
                          ? _buildCard(
                              items[firstIndex + column],
                              position: firstIndex + column + 1,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              );
            },
          );
    if (!compact) return list;
    return RefreshIndicator(
      color: context.colors.primary,
      backgroundColor: context.colors.surface,
      onRefresh: _load,
      child: list,
    );
  }

  Widget _buildCard(AppConferenceItem item, {required int position}) {
    final bool processing = _processingId == item.id;
    final ({String label, Color foreground, Color background}) status =
        _conferenceStatus(item);
    return _ConferenceCard(
      key: ValueKey<int>(item.id),
      item: item,
      position: position,
      processing: processing,
      status: status,
      onOpenDetails: () => _showDetails(item),
      onReject: () => _decide(item, false),
      onApprove: () => _decide(item, true),
    );
  }

  void _reloadForChangedFilters() {
    _cachedData.clear();
    _detailsCache.clear();
    _counts = const {};
    _load();
  }

  Future<List<AppConferenceDetail>> _detailsFor(int conferenceId) async {
    final List<AppConferenceDetail>? cached = _detailsCache[conferenceId];
    if (cached != null) return cached;
    final List<AppConferenceDetail> details = await _service.fetchDetails(
      conferenceId,
    );
    _detailsCache[conferenceId] = details;
    return details;
  }

  Future<void> _showDetails(AppConferenceItem item) async {
    final String subtitle = [
      item.clientName,
      item.regionName,
    ].where((value) => value.isNotEmpty).join(' • ');
    await showAppDialog<void>(
      context: context,
      title: item.title,
      subtitle: subtitle.isEmpty ? 'Detalhes da conferência' : subtitle,
      icon: _typeIcon(item.type),
      maxWidth: 620,
      maxHeight: 620,
      barrierDismissible: true,
      builder: (_) => _ConferenceDetailsDialog(
        item: item,
        loadDetails: () => _detailsFor(item.id),
      ),
    );
  }

  Future<void> _load({bool silent = false}) async {
    final int version = ++_requestVersion;
    final AppConferenceCategory requestedCategory = _category;
    if (mounted) {
      void updateLoadingState() {
        _loading = _data == null;
        _refreshing = _data != null;
        _error = null;
      }

      if (silent) {
        updateLoadingState();
      } else {
        setState(updateLoadingState);
      }
    }
    try {
      final AppConferenceListData data = widget.fetch == null
          ? await _service.fetch(
              category: requestedCategory,
              query: _searchController.text,
              regionIds: _selectedRegions,
            )
          : await widget.fetch!(
              category: requestedCategory,
              query: _searchController.text,
              regionIds: _selectedRegions,
            );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        if (silent) {
          _loading = false;
          _refreshing = false;
        }
        _data = data;
        _counts = data.counts;
        _cachedData[requestedCategory] = data;
      });
    } on ConferenceServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        if (silent) {
          _loading = false;
          _refreshing = false;
        }
        _error = error.message;
      });
    } finally {
      if (!silent && mounted && version == _requestVersion) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshSilently() async {
    if (!mounted ||
        !widget.active ||
        _loading ||
        _refreshing ||
        _processingId != null) {
      return;
    }
    await _load(silent: true);
  }

  Future<void> _loadRegions() async {
    try {
      final List<AppRegionOption> values = widget.fetchRegions == null
          ? await _regionService.fetchOptions()
          : await widget.fetchRegions!();
      if (mounted) {
        setState(() => _regions = values);
      }
    } catch (_) {}
  }

  Future<Set<int>> _loadSavedFilters() async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return const <int>{};
    final Map<String, dynamic>? data = await _preferencesService.getUserFilters(
      scope: 'conferences',
      userId: userId,
    );
    if (data == null) return const <int>{};
    return Set<int>.unmodifiable(
      ((data['regionIds'] as List?) ?? const <Object>[])
          .map((Object? item) => int.tryParse('$item'))
          .whereType<int>(),
    );
  }

  Future<void> _saveFilters(Set<int> regionIds) async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'conferences',
      userId: userId,
      filters: <String, Object?>{
        'regionIds': regionIds.toList(growable: false)..sort(),
      },
    );
  }

  Future<void> _showRegionFilter() async {
    if (_regions.isEmpty) await _loadRegions();
    if (!mounted) return;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool compact = screenWidth < 600;
    final Set<int>? value = await showAppSideDrawer<Set<int>>(
      context: context,
      maxWidth: compact ? screenWidth * appMobileFilterDrawerWidthFactor : 410,
      barrierDismissible: compact,
      builder: (_) => _ConferenceRegionFilter(
        regions: _regions,
        selected: _selectedRegions,
      ),
    );
    if (value == null || !mounted) return;
    setState(() => _selectedRegions = value);
    await _saveFilters(value);
    if (!mounted) return;
    _reloadForChangedFilters();
  }

  Future<void> _decide(AppConferenceItem item, bool approve) async {
    String? observation;
    if (item.isPayment || !approve) {
      observation = await showAppCupertinoTextInputDialog(
        context: context,
        title: item.isPayment
            ? (approve ? 'Conferir pagamento?' : 'Indeferir pagamento?')
            : 'Reprovar solicitação?',
        placeholder: approve ? 'Observação (opcional)' : 'Motivo obrigatório',
        confirmLabel: approve ? 'Conferir' : 'Indeferir',
      );
      if (observation == null || (!approve && observation.trim().isEmpty)) {
        return;
      }
    } else {
      final bool? confirmed = await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Aprovar solicitação?'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(item.description),
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
              child: const Text('Aprovar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _processingId = item.id);
    try {
      final String message = await _service.decide(
        item.id,
        approve: approve,
        observation: observation,
      );
      if (!mounted) return;
      _detailsCache.remove(item.id);
      _cachedData.clear();
      await showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(
            approve ? 'Conferência concluída' : 'Operação indeferida',
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _load();
    } on ConferenceServiceException catch (error) {
      if (!mounted) return;
      await showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Não foi possível concluir'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error.message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Widget _buildForbidden() => const _ConferenceEmptyState(
    icon: Icons.lock_outline_rounded,
    title: 'Acesso restrito',
    message: 'Somente administradores podem acessar as conferências.',
  );

  IconData _typeIcon(String type) => switch (type.toUpperCase()) {
    'PAGAMENTO' => Icons.payments_outlined,
    'PIX' => Icons.pix_rounded,
    'EMPRESTIMO' => Icons.request_quote_outlined,
    'RENOVACAO' => Icons.autorenew_rounded,
    'REFINANCIAMENTO' => Icons.swap_horiz_rounded,
    'FINALIZACAO' => Icons.fact_check_outlined,
    _ => Icons.notifications_active_outlined,
  };

  ({String label, Color foreground, Color background}) _conferenceStatus(
    AppConferenceItem item,
  ) {
    if (!item.isPix) {
      const Color color = Color(0xFFB87900);
      return (
        label: 'Pendente',
        foreground: color,
        background: const Color(0xFFFFC857).withValues(alpha: 0.16),
      );
    }
    return switch (item.status.toUpperCase()) {
      'PAGO' => (
        label: 'Pago',
        foreground: const Color(0xFF278A55),
        background: const Color(0xFF43B979).withValues(alpha: .14),
      ),
      'CANCELADO' => (
        label: 'Cancelado',
        foreground: context.colors.error,
        background: context.colors.error.withValues(alpha: .12),
      ),
      'ERRO' => (
        label: 'Erro',
        foreground: context.colors.error,
        background: context.colors.error.withValues(alpha: .12),
      ),
      _ => (
        label: 'Aguardando',
        foreground: const Color(0xFF287DB5),
        background: const Color(0xFF3A9BD6).withValues(alpha: .13),
      ),
    };
  }
}

class _ConferenceCard extends StatelessWidget {
  final AppConferenceItem item;
  final int position;
  final bool processing;
  final ({String label, Color foreground, Color background}) status;
  final VoidCallback onOpenDetails;
  final VoidCallback onReject;
  final VoidCallback onApprove;

  const _ConferenceCard({
    super.key,
    required this.item,
    required this.position,
    required this.processing,
    required this.status,
    required this.onOpenDetails,
    required this.onReject,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildCard(context, compact: constraints.maxWidth < 430),
  );

  Widget _buildCard(BuildContext context, {required bool compact}) {
    final Color accent = context.colors.textSecondary;
    final Color edgeColor = context.colors.divider;
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Material(
      color: context.colors.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: context.isDark ? .24 : .10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: edgeColor.withValues(alpha: .48)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetails,
        mouseCursor: SystemMouseCursors.click,
        child: Semantics(
          button: true,
          label: 'Abrir detalhes de ${item.title}',
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 5, color: edgeColor),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 13 : 16,
                  compact ? 10 : 13,
                  compact ? 12 : 14,
                  compact ? 10 : 13,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: compact ? 54 : 58,
                      child: Row(
                        children: [
                          Container(
                            width: compact ? 40 : 46,
                            height: compact ? 40 : 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accent.withValues(alpha: .38),
                              ),
                            ),
                            child: Text(
                              '$position',
                              style: TextStyle(
                                color: accent,
                                fontSize: compact ? 18 : 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          SizedBox(width: compact ? 9 : 11),
                          Container(
                            width: 1,
                            height: 34,
                            color: accent.withValues(alpha: .24),
                          ),
                          SizedBox(width: compact ? 9 : 11),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.clientName.isEmpty
                                      ? item.title
                                      : item.clientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: compact ? 12.5 : 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (item.regionName.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on_outlined,
                                        size: 13,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          item.regionName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: context.colors.textSecondary,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: compact ? 96 : 112,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _typeLabel(item.type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: accent,
                                fontSize: compact ? 9.5 : 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    _ConferenceCardOverview(
                      item: item,
                      statusLabel: status.label,
                      color: accent,
                      currency: currency,
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    _ConferenceRequestPanel(
                      item: item,
                      color: accent,
                      compact: compact,
                    ),
                    if (!item.isPix) ...[
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: processing ? null : onReject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.textSecondary,
                                backgroundColor: context.colors.surface,
                                side: BorderSide(color: context.colors.divider),
                                minimumSize: Size(0, compact ? 40 : 42),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: const Text('INDEFERIR'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: processing ? null : onApprove,
                              style: FilledButton.styleFrom(
                                backgroundColor: context.colors.primary,
                                foregroundColor: Colors.white,
                                minimumSize: Size(0, compact ? 40 : 42),
                                padding: EdgeInsets.zero,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: processing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      item.isPayment ? 'CONFERIR' : 'APROVAR',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(String value) => switch (value.toUpperCase()) {
    'PAGAMENTO' => 'Pagamento',
    'EMPRESTIMO' => 'Empréstimo',
    'REFINANCIAMENTO' => 'Refinanciamento',
    'RENOVACAO' => 'Renovação',
    'FINALIZACAO' => 'Finalização',
    _ => 'Conferência',
  };
}

class _ConferenceCardOverview extends StatelessWidget {
  final AppConferenceItem item;
  final String statusLabel;
  final Color color;
  final NumberFormat currency;

  const _ConferenceCardOverview({
    required this.item,
    required this.statusLabel,
    required this.color,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final Widget contract = _ConferenceContractStatus(
      item: item,
      statusLabel: statusLabel,
      color: color,
    );
    final Widget date = _ConferenceOverviewValue(
      label: 'Solicitado em',
      value: item.createdAt == null
          ? 'Não definida'
          : DateFormat('dd/MM/yyyy', 'pt_BR').format(item.createdAt!),
      icon: Icons.calendar_month_outlined,
      alignEnd: true,
    );
    final Widget amount = _ConferenceOverviewValue(
      label: 'Valor',
      value: currency.format(item.amount),
      valueColor: color,
      alignEnd: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useHorizontal = constraints.maxWidth >= 330;
        if (!useHorizontal) {
          return Column(
            children: [
              contract,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: date),
                  const SizedBox(width: 8),
                  Expanded(child: amount),
                ],
              ),
            ],
          );
        }
        final bool compact = constraints.maxWidth < 430;
        final bool veryCompact = constraints.maxWidth < 370;
        return SizedBox(
          height: 47,
          child: Row(
            children: [
              Expanded(child: contract),
              const SizedBox(width: 4),
              SizedBox(
                width: veryCompact ? 90 : (compact ? 98 : 112),
                child: date,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: veryCompact ? 74 : (compact ? 88 : 102),
                child: amount,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConferenceContractStatus extends StatelessWidget {
  final AppConferenceItem item;
  final String statusLabel;
  final Color color;

  const _ConferenceContractStatus({
    required this.item,
    required this.statusLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final String identifier = item.loanId == null
        ? item.title
        : '#${item.loanId}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.loanId == null ? 'Operação' : 'Contrato',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 8.5),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Flexible(
              child: Text(
                identifier,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 90),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConferenceOverviewValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final bool alignEnd;

  const _ConferenceOverviewValue({
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 8.5),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: context.colors.textSecondary),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? context.colors.textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConferenceRequestPanel extends StatelessWidget {
  final AppConferenceItem item;
  final Color color;
  final bool compact;

  const _ConferenceRequestPanel({
    required this.item,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 11,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(
          alpha: context.isDark ? .44 : .68,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.fact_check_outlined, size: 14, color: color),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  item.description.isEmpty
                      ? 'Operação aguardando conferência.'
                      : item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: compact ? 9.5 : 10,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.requester.isEmpty
                      ? 'Solicitante não informado'
                      : item.requester,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 8.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.format_list_numbered_rounded,
                size: 13,
                color: context.colors.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                '${item.itemCount} ${item.itemCount == 1 ? 'item' : 'itens'}',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 8.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConferenceDetailsDialog extends StatefulWidget {
  final AppConferenceItem item;
  final Future<List<AppConferenceDetail>> Function() loadDetails;

  const _ConferenceDetailsDialog({
    required this.item,
    required this.loadDetails,
  });

  @override
  State<_ConferenceDetailsDialog> createState() =>
      _ConferenceDetailsDialogState();
}

class _ConferenceDetailsDialogState extends State<_ConferenceDetailsDialog> {
  late Future<List<AppConferenceDetail>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadDetails();
  }

  void _retry() => setState(() => _future = widget.loadDetails());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AppConferenceDetail>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: context.colors.primary),
          );
        }
        if (snapshot.hasError) {
          final Object error = snapshot.error!;
          return _ConferenceDetailsMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Não foi possível carregar os detalhes',
            message: error is ConferenceServiceException
                ? error.message
                : 'Tente novamente em instantes.',
            buttonLabel: 'TENTAR NOVAMENTE',
            onPressed: _retry,
          );
        }
        final List<AppConferenceDetail> details = snapshot.data ?? const [];
        if (details.isEmpty) {
          return const _ConferenceDetailsMessage(
            icon: Icons.receipt_long_outlined,
            title: 'Sem detalhes disponíveis',
            message: 'Esta conferência não possui itens para exibir.',
          );
        }
        final bool compact = MediaQuery.sizeOf(context).width < 600;
        final NumberFormat currency = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConferenceDetailsSummary(
              itemCount: details.length,
              amount: widget.item.amount,
              currency: currency,
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 16,
                  10,
                  compact ? 12 : 16,
                  compact ? 12 : 16,
                ),
                itemCount: details.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (_, index) => _ConferenceDetailTile(
                  detail: details[index],
                  currency: currency,
                  compact: compact,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConferenceDetailsSummary extends StatelessWidget {
  final int itemCount;
  final double amount;
  final NumberFormat currency;

  const _ConferenceDetailsSummary({
    required this.itemCount,
    required this.amount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: context.colors.background.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.colors.divider.withValues(alpha: .8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.format_list_numbered_rounded,
            size: 17,
            color: context.colors.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$itemCount ${itemCount == 1 ? 'item' : 'itens'}',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (amount > 0)
            Text(
              currency.format(amount),
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _ConferenceDetailTile extends StatelessWidget {
  final AppConferenceDetail detail;
  final NumberFormat currency;
  final bool compact;

  const _ConferenceDetailTile({
    required this.detail,
    required this.currency,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final DateFormat date = DateFormat('dd/MM/yyyy', 'pt_BR');
    final String title = detail.installment.isEmpty
        ? (detail.description.isEmpty ? 'Pagamento' : detail.description)
        : 'Parcela ${detail.installment}';
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.divider.withValues(alpha: .8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 17,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: compact ? 11.5 : 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail.dueDate != null)
                      Text(
                        'Venc. ${date.format(detail.dueDate!)}',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: compact ? 9.5 : 10.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currency.format(detail.amount),
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (detail.dueDateObservation.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Obs. data: ${detail.dueDateObservation}',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: compact ? 9.5 : 10.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConferenceDetailsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _ConferenceDetailsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: context.colors.textSecondary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11.5,
              ),
            ),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConferenceRegionFilter extends StatefulWidget {
  final List<AppRegionOption> regions;
  final Set<int> selected;

  const _ConferenceRegionFilter({
    required this.regions,
    required this.selected,
  });

  @override
  State<_ConferenceRegionFilter> createState() =>
      _ConferenceRegionFilterState();
}

class _ConferenceRegionFilterState extends State<_ConferenceRegionFilter> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    final Set<int> availableRegionIds = widget.regions
        .map((region) => region.id)
        .toSet();
    _selected = widget.selected.where(availableRegionIds.contains).toSet();
  }

  bool get _allSelected =>
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
                title: 'Filtros de conferências',
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
                    trailing: _ConferenceRegionFilterToggle(
                      allSelected: _allSelected,
                      onPressed: _toggleAll,
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
                                  onChanged: (checked) =>
                                      _toggleRegion(region.id, checked == true),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
              AppFilterActionBar(
                onClear: () => setState(_selected.clear),
                onApply: _apply,
                equalWidths: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(widget.regions.map((region) => region.id));
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
      _allSelected ? <int>{} : Set<int>.unmodifiable(_selected),
    );
  }
}

class _ConferenceRegionFilterToggle extends StatelessWidget {
  final bool allSelected;
  final VoidCallback onPressed;

  const _ConferenceRegionFilterToggle({
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

class _ConferenceEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _ConferenceEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 58, color: context.colors.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
          ],
        ],
      ),
    ),
  );
}
