import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

class RoutesScreenController {
  VoidCallback? _openCreate;

  void openCreate() => _openCreate?.call();
}

class RoutesScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final RoutesScreenController? controller;

  const RoutesScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
  });

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  static const int _pageSize = 50;

  final CollectionRouteService _service = CollectionRouteService();
  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AppCollectionRouteItem> _items = [];
  List<AppRegionOption> _regions = const [];
  Set<int> _selectedRegionIds = {};
  AppCollectionRouteCollector? _selectedCollector;
  AppCityOption? _selectedCity;
  AppCollectionRouteSort _sort = AppCollectionRouteSort.overdueDays;
  Timer? _searchDebounce;
  int _requestVersion = 0;
  int _nextPage = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  String? _errorMessage;

  bool get _canCreateRoutes {
    final AuthSession? session = AuthService().currentSession;
    if (session == null) return false;
    return session.administrator || !session.collector || session.canEdit;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._openCreate = _canCreateRoutes ? _openAssignment : null;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void didUpdateWidget(covariant RoutesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._openCreate = null;
      widget.controller?._openCreate = _canCreateRoutes
          ? _openAssignment
          : null;
    }
    if (!oldWidget.active && widget.active) _load(reset: true, force: true);
  }

  @override
  void dispose() {
    widget.controller?._openCreate = null;
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final _RouteFilters saved = await _loadSavedRouteFilters(
      _preferencesService,
      'routes',
    );
    if (mounted) {
      setState(() {
        _selectedRegionIds = saved.regionIds;
        _selectedCollector = saved.collector;
        _selectedCity = saved.city;
        _sort = saved.sort;
      });
    }
    try {
      final List<AppRegionOption> regions = await _regionService.fetchOptions();
      if (mounted) setState(() => _regions = regions);
    } on RegionServiceException {
      // A rota continua disponível sem o seletor até uma nova tentativa.
    }
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Evita descontar a altura do teclado novamente dentro do Scaffold
      // principal. O teclado deve cobrir apenas a área inferior real, sem
      // levantar uma faixa vazia sobre os cards.
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      appBar: widget.showAppBar
          ? const HomeAppBar(title: 'Rotas', leading: AppSidebarMenuButton())
          : null,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.showAppBar ? 10 : 8,
                widget.showAppBar ? 8 : 14,
                widget.showAppBar ? 10 : 8,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _RouteSearchField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          hintText: 'Pesquisar cliente, região ou endereço',
                          onClear: () {
                            _searchController.clear();
                            setState(() {});
                            _load(reset: true, force: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 7),
                      _RouteFilterButton(
                        count: _activeFilterCount,
                        onTap: _openFilter,
                      ),
                      if (kIsWeb &&
                          MediaQuery.sizeOf(context).width >= 1024 &&
                          _canCreateRoutes) ...[
                        const SizedBox(width: 7),
                        FilledButton.icon(
                          onPressed: _openAssignment,
                          icon: const Icon(Icons.add_road_rounded, size: 19),
                          label: const Text('ADICIONAR ROTA'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 9),
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null && _items.isEmpty) {
      return _RouteEmptyState(
        icon: Icons.route_outlined,
        title: 'Não foi possível carregar as rotas',
        message: _errorMessage!,
        actionLabel: 'Tentar novamente',
        onAction: () => _load(reset: true, force: true),
      );
    }
    if (_items.isEmpty) {
      final bool canCreate = _canCreateRoutes;
      return _RouteEmptyState(
        icon: Icons.route_outlined,
        title: 'Nenhuma rota adicionada',
        message: _activeFilterCount == 0
            ? canCreate
                  ? 'Use Adicionar rota para selecionar os clientes e o cobrador responsável.'
                  : 'Nenhuma rota foi vinculada ao seu usuário.'
            : 'Não há rotas adicionadas com os filtros selecionados.',
        actionLabel: _activeFilterCount == 0 && canCreate
            ? 'Adicionar rota'
            : _activeFilterCount > 0
            ? 'Limpar filtro'
            : null,
        onAction: _activeFilterCount == 0 && canCreate
            ? _openAssignment
            : _activeFilterCount > 0
            ? () {
                setState(() {
                  _selectedRegionIds = {};
                  _selectedCollector = null;
                  _selectedCity = null;
                  _sort = AppCollectionRouteSort.overdueDays;
                });
                unawaited(
                  _saveRouteFilters(
                    _preferencesService,
                    'routes',
                    const _RouteFilters(
                      regionIds: {},
                      collector: null,
                      city: null,
                      sort: AppCollectionRouteSort.overdueDays,
                    ),
                  ),
                );
                _load(reset: true, force: true);
              }
            : null,
      );
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _load(reset: true, force: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.viewInsetsOf(context).bottom +
              (MediaQuery.sizeOf(context).width < 600 ? 76 : 8),
        ),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: context.colors.primary,
                ),
              ),
            );
          }
          final AppCollectionRouteItem item = _items[index];
          return _CollectionRouteCard(
            item: item,
            position: index + 1,
            onTap: () => _confirmOpen(item),
          );
        },
      ),
    );
  }

  Future<void> _load({required bool reset, bool force = false}) async {
    if (!mounted || (!reset && (_loadingMore || !_hasNext))) return;
    final int version = reset ? ++_requestVersion : _requestVersion;
    final int page = reset ? 0 : _nextPage;
    setState(() {
      if (reset && _items.isEmpty) _loading = true;
      if (!reset) _loadingMore = true;
      if (reset) _errorMessage = null;
    });
    try {
      final AppCollectionRoutePage result = await _service.fetchRoutes(
        regionIds: _selectedRegionIds,
        collectorId: _selectedCollector?.id,
        cityId: _selectedCity?.id,
        city: _selectedCity?.name ?? '',
        sort: _sort,
        query: _searchController.text,
        page: page,
        size: _pageSize,
        force: force,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        if (reset) _items.clear();
        final Set<int> known = _items.map((item) => item.clientId).toSet();
        _items.addAll(result.items.where((item) => known.add(item.clientId)));
        _nextPage = result.page + 1;
        _hasNext = result.hasNext;
        _loading = false;
        _loadingMore = false;
        _errorMessage = null;
      });
    } on CollectionRouteServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorMessage = error.message;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _load(reset: true, force: true),
    );
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 420) {
      _load(reset: false);
    }
  }

  int get _activeFilterCount =>
      (_selectedRegionIds.isEmpty ? 0 : 1) +
      (_selectedCollector == null ? 0 : 1) +
      (_selectedCity == null ? 0 : 1) +
      (_sort == AppCollectionRouteSort.overdueDays ? 0 : 1);

  Future<void> _openFilter() async {
    if (_regions.isEmpty) {
      try {
        _regions = await _regionService.fetchOptions(force: true);
      } on RegionServiceException catch (error) {
        if (mounted) _showMessage('Regiões indisponíveis', error.message);
        return;
      }
    }
    if (!mounted) return;
    final _RouteFilters? selected = await _showRouteFilterDrawer(
      context: context,
      regions: _regions,
      loadCities: (regionIds, collectorId) => _service.fetchAvailableCities(
        regionIds: regionIds,
        collectorId: collectorId,
        query: _searchController.text,
        assignedOnly: true,
      ),
      loadCollectors: (regionIds, cityId) => _service.fetchAssignedCollectors(
        regionIds: regionIds,
        cityId: cityId,
        query: _searchController.text,
      ),
      enableCollectorFilter: true,
      initial: _RouteFilters(
        regionIds: _selectedRegionIds,
        collector: _selectedCollector,
        city: _selectedCity,
        sort: _sort,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRegionIds = selected.regionIds;
      _selectedCollector = selected.collector;
      _selectedCity = selected.city;
      _sort = selected.sort;
    });
    unawaited(
      _saveRouteFilters(
        _preferencesService,
        'routes',
        _RouteFilters(
          regionIds: selected.regionIds,
          collector: selected.collector,
          city: selected.city,
          sort: selected.sort,
        ),
      ),
    );
    _load(reset: true, force: true);
  }

  Future<void> _confirmOpen(AppCollectionRouteItem item) async {
    final bool open =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Ver cobrança?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Deseja abrir a cobrança de ${item.clientName}?'),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  'Ver cobrança',
                  style: TextStyle(color: context.colors.primary),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!open || !mounted) return;
    await _openDetail(item);
  }

  Future<void> _openDetail(AppCollectionRouteItem item) async {
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    if (desktop) {
      await showAppSideDrawer<void>(
        context: context,
        maxWidth: 760,
        builder: (drawerContext) => Column(
          children: [
            AppPanelHeader(
              title: 'Cobrança',
              subtitle: item.clientName,
              icon: Icons.route_outlined,
              onClose: () => Navigator.pop(drawerContext),
            ),
            Expanded(
              child: CollectionRouteDetailView(
                clientId: item.clientId,
                onBack: () => Navigator.pop(drawerContext),
              ),
            ),
          ],
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (pageContext) => Scaffold(
            backgroundColor: context.colors.background,
            appBar: HomeAppBar(
              title: 'Cobrança',
              showDefaultActions: false,
              leading: Builder(
                builder: (pageContext) => IconButton(
                  tooltip: 'Voltar',
                  onPressed: () => Navigator.pop(pageContext),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
            body: CollectionRouteDetailView(
              clientId: item.clientId,
              onBack: () => Navigator.pop(pageContext),
            ),
          ),
        ),
      );
    }
    if (mounted) _load(reset: true, force: true);
  }

  Future<void> _openAssignment() async {
    if (!mounted || !_canCreateRoutes) return;
    final bool desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    bool? changed;
    if (desktop) {
      changed = await showAppSideDrawer<bool>(
        context: context,
        fromStart: true,
        maxWidth: 560,
        builder: (drawerContext) => Column(
          children: [
            AppPanelHeader(
              title: 'Adicionar rota',
              subtitle: 'Selecione os atrasados e atribua um cobrador.',
              icon: Icons.add_road_rounded,
              onClose: () => Navigator.pop(drawerContext),
            ),
            Expanded(
              child: CollectionRouteAssignmentView(
                regions: _regions,
                onBack: () => Navigator.pop(drawerContext, false),
                onSaved: () => Navigator.pop(drawerContext, true),
              ),
            ),
          ],
        ),
      );
    } else {
      changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (pageContext) => Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: context.colors.background,
            appBar: HomeAppBar(
              title: 'Adicionar rota',
              showDefaultActions: false,
              leading: IconButton(
                tooltip: 'Voltar',
                onPressed: () => Navigator.pop(pageContext, false),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            body: CollectionRouteAssignmentView(
              regions: _regions,
              onBack: () => Navigator.pop(pageContext, false),
              onSaved: () => Navigator.pop(pageContext, true),
            ),
          ),
        ),
      );
    }
    if (changed == true && mounted) {
      await _load(reset: true, force: true);
      if (mounted) {
        await _showMessage(
          'Rotas adicionadas',
          'Os clientes selecionados já estão vinculados ao cobrador.',
        );
      }
    }
  }

  Future<void> _showMessage(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
}

class CollectionRouteAssignmentView extends StatefulWidget {
  final List<AppRegionOption> regions;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const CollectionRouteAssignmentView({
    super.key,
    required this.regions,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<CollectionRouteAssignmentView> createState() =>
      _CollectionRouteAssignmentViewState();
}

class _CollectionRouteAssignmentViewState
    extends State<CollectionRouteAssignmentView> {
  static const int _pageSize = 50;
  static const int _selectionLimit = 100;

  final CollectionRouteService _service = CollectionRouteService();
  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AppCollectionRouteItem> _items = [];
  final Set<int> _selectedClientIds = {};
  List<AppCollectionRouteCollector> _collectors = const [];
  List<AppRegionOption> _regions = const [];
  Set<int> _selectedRegionIds = {};
  AppCityOption? _selectedCity;
  AppCollectionRouteSort _sort = AppCollectionRouteSort.overdueDays;
  Timer? _searchDebounce;
  int? _collectorId;
  int _nextPage = 0;
  int _requestVersion = 0;
  bool _hasNext = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _saving = false;
  bool _selectAllLoadedPages = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _regions = widget.regions;
    _scrollController.addListener(_handleScroll);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final _RouteFilters saved = await _loadSavedRouteFilters(
        _preferencesService,
        'route_candidates',
      );
      final List<AppCollectionRouteCollector> collectors = await _service
          .fetchCollectors();
      if (_regions.isEmpty) {
        try {
          _regions = await _regionService.fetchOptions();
        } on RegionServiceException {
          // A seleção continua disponível sem filtro regional.
        }
      }
      if (mounted) {
        setState(() {
          _selectedRegionIds = saved.regionIds;
          _selectedCity = saved.city;
          _sort = saved.sort;
          _collectors = collectors;
          if (collectors.length == 1) _collectorId = collectors.first.id;
        });
      }
      await _load(reset: true);
    } on CollectionRouteServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AppCollectionRouteCollector? get _selectedCollector {
    final int? selectedId = _collectorId;
    if (selectedId == null) return null;
    for (final AppCollectionRouteCollector collector in _collectors) {
      if (collector.id == selectedId) return collector;
    }
    return null;
  }

  Future<void> _selectCollector() async {
    final AppCollectionRouteCollector? selected =
        await showCollectorSelectionDialog(
          context: context,
          collectors: _collectors,
          selectedId: _collectorId,
        );
    if (selected != null && mounted) {
      setState(() => _collectorId = selected.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Column(
                children: [
                  _CollectorField(
                    collector: _selectedCollector,
                    enabled: !_saving && _collectors.isNotEmpty,
                    onTap: _selectCollector,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _RouteSearchField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          hintText: 'Pesquisar atrasados',
                          onClear: () {
                            _searchController.clear();
                            setState(() {});
                            unawaited(_load(reset: true));
                          },
                        ),
                      ),
                      const SizedBox(width: 7),
                      _RouteFilterButton(
                        count: _activeFilterCount,
                        onTap: _openFilter,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 32,
                        child: Checkbox(
                          value: _allLoadedSelected
                              ? true
                              : _selectedClientIds.isEmpty
                              ? false
                              : null,
                          tristate: true,
                          onChanged: _items.isEmpty
                              ? null
                              : (_) => _toggleAllLoaded(),
                          activeColor: context.colors.primary,
                        ),
                      ),
                      InkWell(
                        onTap: _items.isEmpty ? null : _toggleAllLoaded,
                        borderRadius: BorderRadius.circular(7),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 7,
                          ),
                          child: Text(
                            _allLoadedSelected
                                ? 'DESMARCAR TODOS'
                                : 'SELECIONAR TODOS',
                            style: TextStyle(
                              color: _items.isEmpty
                                  ? context.colors.textPlaceholder
                                  : context.colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_selectedClientIds.length} selecionado(s)',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_selectedClientIds.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpar seleção',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() {
                            _selectAllLoadedPages = false;
                            _selectedClientIds.clear();
                          }),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildContent()),
            _AssignmentActionBar(
              saving: _saving,
              onSave: _save,
              onBack: widget.onBack,
            ),
          ],
        ),
        if (_saving)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: .12),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _RouteEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Não foi possível carregar os atrasados',
        message: _error!,
        actionLabel: 'Tentar novamente',
        onAction: () => _load(reset: true),
      );
    }
    if (_collectors.isEmpty) {
      return const _RouteEmptyState(
        icon: Icons.person_off_outlined,
        title: 'Nenhum cobrador disponível',
        message: 'Ative a opção Cobrador em um usuário para criar rotas.',
        actionLabel: null,
        onAction: null,
      );
    }
    if (_items.isEmpty) {
      return const _RouteEmptyState(
        icon: Icons.task_alt_rounded,
        title: 'Nenhum cliente em atraso',
        message: 'Não há dívidas vencidas com os filtros selecionados.',
        actionLabel: null,
        onAction: null,
      );
    }
    return ListView.separated(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        10,
        2,
        10,
        MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        final AppCollectionRouteItem item = _items[index];
        return _AssignmentCandidateCard(
          item: item,
          selected: _selectedClientIds.contains(item.clientId),
          onTap: () => _toggle(item.clientId),
        );
      },
    );
  }

  Future<void> _load({required bool reset}) async {
    if (!mounted || (!reset && (_loadingMore || !_hasNext))) return;
    final int version = reset ? ++_requestVersion : _requestVersion;
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
      final AppCollectionRoutePage result = await _service.fetchCandidates(
        regionIds: _selectedRegionIds,
        cityId: _selectedCity?.id,
        city: _selectedCity?.name ?? '',
        sort: _sort,
        query: _searchController.text,
        page: page,
        size: _pageSize,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        if (reset) _items.clear();
        final Set<int> known = _items.map((item) => item.clientId).toSet();
        final List<AppCollectionRouteItem> added = result.items
            .where((item) => known.add(item.clientId))
            .toList(growable: false);
        _items.addAll(added);
        if (_selectAllLoadedPages) {
          for (final AppCollectionRouteItem item in added) {
            if (_selectedClientIds.length >= _selectionLimit) break;
            _selectedClientIds.add(item.clientId);
          }
          if (_selectedClientIds.length >= _selectionLimit) {
            _selectAllLoadedPages = false;
          }
        }
        _nextPage = result.page + 1;
        _hasNext = result.hasNext;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on CollectionRouteServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.message;
      });
    }
  }

  void _toggle(int clientId) {
    if (!_selectedClientIds.contains(clientId) &&
        _selectedClientIds.length >= _selectionLimit) {
      unawaited(
        _showMessage(
          'Limite de seleção',
          'É possível adicionar até $_selectionLimit clientes por vez.',
        ),
      );
      return;
    }
    setState(() {
      _selectAllLoadedPages = false;
      if (!_selectedClientIds.remove(clientId)) {
        _selectedClientIds.add(clientId);
      }
    });
  }

  bool get _allLoadedSelected =>
      _items.isNotEmpty &&
      _items.every((item) => _selectedClientIds.contains(item.clientId));

  void _toggleAllLoaded() {
    if (_items.isEmpty) return;
    final bool remove = _allLoadedSelected;
    bool reachedLimit = false;
    setState(() {
      if (remove) {
        _selectAllLoadedPages = false;
        _selectedClientIds.removeAll(
          _items.map((item) => item.clientId).toSet(),
        );
        return;
      }
      _selectAllLoadedPages = true;
      for (final AppCollectionRouteItem item in _items) {
        if (_selectedClientIds.length >= _selectionLimit) {
          reachedLimit = true;
          _selectAllLoadedPages = false;
          break;
        }
        _selectedClientIds.add(item.clientId);
      }
    });
    if (reachedLimit) {
      unawaited(
        _showMessage(
          'Limite de seleção',
          'Foram selecionados os primeiros $_selectionLimit clientes. Salve este lote antes de adicionar os demais.',
        ),
      );
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _selectAllLoadedPages = false;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _load(reset: true),
    );
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 360) {
      unawaited(_load(reset: false));
    }
  }

  int get _activeFilterCount =>
      (_selectedRegionIds.isEmpty ? 0 : 1) +
      (_selectedCity == null ? 0 : 1) +
      (_sort == AppCollectionRouteSort.overdueDays ? 0 : 1);

  Future<void> _openFilter() async {
    final _RouteFilters? filters = await _showRouteFilterDrawer(
      context: context,
      regions: _regions,
      loadCities: (regionIds, _) => _service.fetchAvailableCities(
        regionIds: regionIds,
        query: _searchController.text,
        assignedOnly: false,
      ),
      loadCollectors: (_, _) async => const [],
      initial: _RouteFilters(
        regionIds: _selectedRegionIds,
        collector: null,
        city: _selectedCity,
        sort: _sort,
      ),
    );
    if (filters == null || !mounted) return;
    setState(() {
      _selectAllLoadedPages = false;
      _selectedRegionIds = filters.regionIds;
      _selectedCity = filters.city;
      _sort = filters.sort;
    });
    unawaited(
      _saveRouteFilters(
        _preferencesService,
        'route_candidates',
        _RouteFilters(
          regionIds: filters.regionIds,
          collector: null,
          city: filters.city,
          sort: filters.sort,
        ),
      ),
    );
    await _load(reset: true);
  }

  Future<void> _save() async {
    if (_collectorId == null) {
      await _showMessage('Selecione o cobrador', 'Informe quem fará a rota.');
      return;
    }
    if (_selectedClientIds.isEmpty) {
      await _showMessage(
        'Selecione os clientes',
        'Marque pelo menos um cliente em atraso.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.assignRoutes(
        collectorId: _collectorId!,
        clientIds: _selectedClientIds,
      );
      if (mounted) widget.onSaved();
    } on CollectionRouteServiceException catch (error) {
      if (mounted) await _showMessage('Não foi possível salvar', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showMessage(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
}

Future<AppCollectionRouteCollector?> showCollectorSelectionDialog({
  required BuildContext context,
  required List<AppCollectionRouteCollector> collectors,
  required int? selectedId,
}) => showAppDialog<AppCollectionRouteCollector>(
  context: context,
  title: 'Selecionar cobrador',
  subtitle: 'Escolha o usuário responsável pelas rotas.',
  icon: Icons.person_pin_circle_outlined,
  maxWidth: 520,
  maxHeight: 620,
  builder: (_) =>
      _CollectorSelectionDialog(collectors: collectors, selectedId: selectedId),
);

class _CollectorSelectionDialog extends StatelessWidget {
  final List<AppCollectionRouteCollector> collectors;
  final int? selectedId;

  const _CollectorSelectionDialog({
    required this.collectors,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    itemCount: collectors.length,
    separatorBuilder: (_, _) =>
        Divider(height: 1, color: context.colors.divider),
    itemBuilder: (context, index) {
      final AppCollectionRouteCollector collector = collectors[index];
      final bool selected = collector.id == selectedId;
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected
              ? context.colors.primary
              : context.colors.textSecondary,
        ),
        title: Text(
          collector.name,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: collector.username.isEmpty
            ? null
            : Text('@${collector.username}'),
        onTap: () => Navigator.pop(context, collector),
      );
    },
  );
}

class _CollectorField extends StatelessWidget {
  final AppCollectionRouteCollector? collector;
  final bool enabled;
  final VoidCallback onTap;

  const _CollectorField({
    required this.collector,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Cobrador responsável',
        prefixIcon: Icon(
          Icons.person_pin_circle_outlined,
          color: context.colors.primary,
        ),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabled: enabled,
      ),
      child: Text(
        collector == null
            ? 'Selecione o cobrador'
            : collector!.username.isEmpty
            ? collector!.name
            : '${collector!.name} • @${collector!.username}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: collector == null
              ? context.colors.textPlaceholder
              : context.colors.textPrimary,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _RouteSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  const _RouteSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 45,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: context.colors.textPlaceholder,
          fontSize: 13.5,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: context.colors.primary,
          size: 20,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar pesquisa',
                onPressed: onClear,
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

class _AssignmentCandidateCard extends StatelessWidget {
  final AppCollectionRouteItem item;
  final bool selected;
  final VoidCallback onTap;

  const _AssignmentCandidateCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Material(
      color: selected
          ? context.colors.primary.withValues(alpha: .08)
          : context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected ? context.colors.primary : context.colors.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: (_) => onTap()),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.clientName,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 12,
                      runSpacing: 5,
                      children: [
                        _RouteCardInfo(
                          icon: Icons.location_on_outlined,
                          text: item.regionName,
                        ),
                        _RouteCardInfo(
                          icon: Icons.schedule_rounded,
                          text: '${item.overdueDays} dia(s) em atraso',
                          strong: true,
                        ),
                        _RouteCardInfo(
                          icon: Icons.account_balance_wallet_outlined,
                          text: 'Vencido ${currency.format(item.overdueDebt)}',
                          strong: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _RouteCardInfo(
                      icon: Icons.home_outlined,
                      text: item.address,
                      maxLines: null,
                    ),
                    if (item.collectorName != null) ...[
                      const SizedBox(height: 5),
                      _RouteCardInfo(
                        icon: Icons.person_pin_circle_outlined,
                        text: 'Rota atual: ${item.collectorName}',
                        strong: true,
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
}

class _AssignmentActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onBack;

  const _AssignmentActionBar({
    required this.saving,
    required this.onSave,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final bool mobile = MediaQuery.sizeOf(context).width < 600;
    final Widget backButton = OutlinedButton(
      onPressed: saving ? null : onBack,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.textSecondary,
        side: BorderSide(color: context.colors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('VOLTAR'),
    );
    final Widget saveButton = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9FD995), Color(0xFF4B7D60)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FilledButton(
        onPressed: saving ? null : onSave,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: saving
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('ADICIONAR ROTA'),
      ),
    );

    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
          child: mobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 42, child: saveButton),
                    const SizedBox(height: 6),
                    SizedBox(height: 42, child: backButton),
                  ],
                )
              : SizedBox(
                  height: 42,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: backButton),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: saveButton),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

final class _RouteFilters {
  final Set<int> regionIds;
  final AppCollectionRouteCollector? collector;
  final AppCityOption? city;
  final AppCollectionRouteSort sort;

  const _RouteFilters({
    required this.regionIds,
    this.collector,
    required this.city,
    required this.sort,
  });
}

Future<_RouteFilters> _loadSavedRouteFilters(
  SharedPreferencesService preferences,
  String scope,
) async {
  try {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) {
      return const _RouteFilters(
        regionIds: {},
        collector: null,
        city: null,
        sort: AppCollectionRouteSort.overdueDays,
      );
    }
    final Map<String, dynamic>? data = await preferences.getUserFilters(
      scope: scope,
      userId: userId,
    );
    if (data == null) {
      return const _RouteFilters(
        regionIds: {},
        collector: null,
        city: null,
        sort: AppCollectionRouteSort.overdueDays,
      );
    }
    final Set<int> regionIds = ((data['regionIds'] as List?) ?? const [])
        .map((item) => int.tryParse('$item'))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    final Map<String, dynamic>? cityData = data['city'] is Map
        ? Map<String, dynamic>.from(data['city'] as Map)
        : null;
    final int cityId = int.tryParse('${cityData?['id'] ?? ''}') ?? 0;
    final String cityName = '${cityData?['name'] ?? ''}'.trim();
    final String cityState = '${cityData?['state'] ?? ''}'.trim();
    final String cityDisplayName = '${cityData?['displayName'] ?? ''}'.trim();
    final AppCityOption? city = cityId > 0 && cityName.isNotEmpty
        ? AppCityOption(
            id: cityId,
            ibgeCode: int.tryParse('${cityData?['ibgeCode'] ?? ''}'),
            name: cityName,
            state: cityState,
            displayName: cityDisplayName.isEmpty
                ? [
                    cityName,
                    cityState,
                  ].where((part) => part.isNotEmpty).join(' - ')
                : cityDisplayName,
          )
        : null;
    final String sortValue = '${data['sort'] ?? ''}';
    final Map<String, dynamic>? collectorData = data['collector'] is Map
        ? Map<String, dynamic>.from(data['collector'] as Map)
        : null;
    final int collectorId = int.tryParse('${collectorData?['id'] ?? ''}') ?? 0;
    final String collectorName = '${collectorData?['name'] ?? ''}'.trim();
    final String collectorUsername = '${collectorData?['username'] ?? ''}'
        .trim();
    final AppCollectionRouteCollector? collector = collectorId > 0
        ? AppCollectionRouteCollector(
            id: collectorId,
            name: collectorName.isEmpty ? 'Cobrador' : collectorName,
            username: collectorUsername,
          )
        : null;
    AppCollectionRouteSort sort = AppCollectionRouteSort.overdueDays;
    for (final AppCollectionRouteSort option in AppCollectionRouteSort.values) {
      if (option.apiValue == sortValue) sort = option;
    }
    return _RouteFilters(
      regionIds: Set.unmodifiable(regionIds),
      collector: collector,
      city: city,
      sort: sort,
    );
  } on Object {
    return const _RouteFilters(
      regionIds: {},
      collector: null,
      city: null,
      sort: AppCollectionRouteSort.overdueDays,
    );
  }
}

Future<void> _saveRouteFilters(
  SharedPreferencesService preferences,
  String scope,
  _RouteFilters filters,
) async {
  final int? userId = AuthService().currentSession?.userId;
  if (userId == null) return;
  final AppCityOption? city = filters.city;
  await preferences.saveUserFilters(
    scope: scope,
    userId: userId,
    filters: {
      'regionIds': filters.regionIds.toList(growable: false),
      'sort': filters.sort.apiValue,
      'collector': filters.collector == null
          ? null
          : {
              'id': filters.collector!.id,
              'name': filters.collector!.name,
              'username': filters.collector!.username,
            },
      'city': city == null
          ? null
          : {
              'id': city.id,
              'ibgeCode': city.ibgeCode,
              'name': city.name,
              'state': city.state,
              'displayName': city.displayName,
            },
    },
  );
}

Future<_RouteFilters?> _showRouteFilterDrawer({
  required BuildContext context,
  required _RouteFilters initial,
  required List<AppRegionOption> regions,
  required Future<List<AppCityOption>> Function(
    Set<int> regionIds,
    int? collectorId,
  )
  loadCities,
  required Future<List<AppCollectionRouteCollector>> Function(
    Set<int> regionIds,
    int? cityId,
  )
  loadCollectors,
  bool enableCollectorFilter = false,
}) {
  final double screenWidth = MediaQuery.sizeOf(context).width;
  final bool compact = screenWidth < 600;
  return showAppSideDrawer<_RouteFilters>(
    context: context,
    maxWidth: compact ? screenWidth * appMobileFilterDrawerWidthFactor : 410,
    barrierDismissible: compact,
    builder: (_) => _RouteFilterDrawer(
      initial: initial,
      regions: regions,
      loadCities: loadCities,
      loadCollectors: loadCollectors,
      enableCollectorFilter: enableCollectorFilter,
    ),
  );
}

class _RouteFilterDrawer extends StatefulWidget {
  final _RouteFilters initial;
  final List<AppRegionOption> regions;
  final Future<List<AppCityOption>> Function(
    Set<int> regionIds,
    int? collectorId,
  )
  loadCities;
  final Future<List<AppCollectionRouteCollector>> Function(
    Set<int> regionIds,
    int? cityId,
  )
  loadCollectors;
  final bool enableCollectorFilter;

  const _RouteFilterDrawer({
    required this.initial,
    required this.regions,
    required this.loadCities,
    required this.loadCollectors,
    required this.enableCollectorFilter,
  });

  @override
  State<_RouteFilterDrawer> createState() => _RouteFilterDrawerState();
}

class _RouteFilterDrawerState extends State<_RouteFilterDrawer> {
  late Set<int> _regionIds;
  late AppCollectionRouteSort _sort;
  AppCollectionRouteCollector? _collector;
  AppCityOption? _city;
  bool _loadingCities = false;
  bool _loadingCollectors = false;

  @override
  void initState() {
    super.initState();
    final Set<int> available = widget.regions.map((item) => item.id).toSet();
    _regionIds = widget.initial.regionIds.where(available.contains).toSet();
    _sort = widget.initial.sort;
    _collector = widget.initial.collector;
    _city = widget.initial.city;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 18,
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPanelHeader(
                title: 'Filtros de rotas',
                subtitle: 'Filtre as dívidas e escolha a ordem da rota.',
                icon: Icons.tune_rounded,
                compact: MediaQuery.sizeOf(context).width < 600,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
                  children: [
                    AppFilterSectionCard(
                      title: 'Região',
                      icon: Icons.location_on_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: context.colors.surface,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: context.colors.divider),
                            ),
                            child: InkWell(
                              onTap: _openRegionPicker,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      color: context.colors.primary,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _regionSelectionLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Toque para escolher as regiões',
                                            style: TextStyle(
                                              color:
                                                  context.colors.textSecondary,
                                              fontSize: 9.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: context.colors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_regionIds.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _regionIds.clear();
                                  _collector = null;
                                  _city = null;
                                }),
                                child: const Text('TODAS AS REGIÕES'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (widget.enableCollectorFilter) ...[
                      AppFilterSectionCard(
                        title: 'Cobrador',
                        icon: Icons.person_pin_circle_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: _loadingCollectors
                                  ? null
                                  : _selectCollector,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  prefixIcon: Icon(
                                    Icons.person_pin_circle_outlined,
                                    color: context.colors.primary,
                                    size: 19,
                                  ),
                                  suffixIcon: _loadingCollectors
                                      ? const Padding(
                                          padding: EdgeInsets.all(13),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_drop_down_rounded,
                                        ),
                                  filled: true,
                                  fillColor: context.colors.surface,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _collector == null
                                      ? 'Todos os cobradores'
                                      : _collector!.username.isEmpty
                                      ? _collector!.name
                                      : '${_collector!.name} • @${_collector!.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _collector == null
                                        ? context.colors.textPlaceholder
                                        : context.colors.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            if (_collector != null) ...[
                              const SizedBox(height: 5),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  onPressed: () =>
                                      setState(() => _collector = null),
                                  child: const Text('TODOS OS COBRADORES'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                    AppFilterSectionCard(
                      title: 'Cidade',
                      icon: Icons.location_city_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: _loadingCities ? null : _selectCity,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: Icon(
                                  Icons.location_city_outlined,
                                  color: context.colors.primary,
                                  size: 19,
                                ),
                                suffixIcon: _loadingCities
                                    ? const Padding(
                                        padding: EdgeInsets.all(13),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_drop_down_rounded),
                                filled: true,
                                fillColor: context.colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _city?.displayName ?? 'Todas as cidades',
                                style: TextStyle(
                                  color: _city == null
                                      ? context.colors.textPlaceholder
                                      : context.colors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          if (_city != null) ...[
                            const SizedBox(height: 5),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () => setState(() => _city = null),
                                child: const Text('TODAS AS CIDADES'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    AppFilterSectionCard(
                      title: 'Ordenar por',
                      icon: Icons.sort_rounded,
                      child: Column(
                        children: [
                          for (final AppCollectionRouteSort option
                              in AppCollectionRouteSort.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: _RouteSortOption(
                                option: option,
                                selected: option == _sort,
                                onTap: () => setState(() => _sort = option),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppFilterActionBar(
                onClear: _clear,
                onApply: _apply,
                equalWidths: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _regionSelectionLabel {
    if (_regionIds.isEmpty) return 'Todas as regiões';
    if (_regionIds.length == 1) {
      final int id = _regionIds.first;
      for (final AppRegionOption region in widget.regions) {
        if (region.id == id) return region.name;
      }
      return 'Região #$id';
    }
    return '${_regionIds.length} regiões selecionadas';
  }

  Future<void> _openRegionPicker() async {
    final Set<int>? selected = await showRegionSelectionDialog(
      context: context,
      options: widget.regions,
      selected: _regionIds,
      title: 'Filtrar rotas por região',
      subtitle: 'Marque as regiões que deseja consultar.',
      emptySelectionLabel: 'Nenhuma marcada: todas as regiões permitidas',
    );
    if (selected != null && mounted) {
      setState(() {
        if (!setEquals(_regionIds, selected)) {
          _collector = null;
          _city = null;
        }
        _regionIds = selected;
      });
    }
  }

  Future<void> _selectCollector() async {
    setState(() => _loadingCollectors = true);
    try {
      final List<AppCollectionRouteCollector> options = await widget
          .loadCollectors(_regionIds, _city?.id);
      if (!mounted) return;
      final _RouteCollectorSelectionResult? result =
          await _showRouteCollectorSelectionDialog(
            context: context,
            options: options,
            selectedId: _collector?.id,
          );
      if (result == null || !mounted) return;
      AppCollectionRouteCollector? selected;
      for (final AppCollectionRouteCollector option in options) {
        if (option.id == result.collectorId) {
          selected = option;
          break;
        }
      }
      setState(() => _collector = selected);
    } on CollectionRouteServiceException catch (error) {
      if (mounted) {
        await showAppCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Cobradores indisponíveis'),
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
      }
    } finally {
      if (mounted) setState(() => _loadingCollectors = false);
    }
  }

  Future<void> _selectCity() async {
    setState(() => _loadingCities = true);
    try {
      final List<AppCityOption> options = await widget.loadCities(
        _regionIds,
        _collector?.id,
      );
      if (!mounted) return;
      final _RouteCitySelectionResult? result =
          await _showRouteCitySelectionDialog(
            context: context,
            options: options,
            selectedId: _city?.id,
          );
      if (result == null || !mounted) return;
      AppCityOption? selected;
      for (final AppCityOption option in options) {
        if (option.id == result.cityId) {
          selected = option;
          break;
        }
      }
      setState(() => _city = selected);
    } on CollectionRouteServiceException catch (error) {
      if (mounted) {
        await showAppCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Cidades indisponíveis'),
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
      }
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  void _clear() {
    setState(() {
      _regionIds.clear();
      _collector = null;
      _city = null;
      _sort = AppCollectionRouteSort.overdueDays;
    });
  }

  void _apply() => Navigator.pop(
    context,
    _RouteFilters(
      regionIds: Set.unmodifiable(_regionIds),
      collector: _collector,
      city: _city,
      sort: _sort,
    ),
  );
}

final class _RouteCollectorSelectionResult {
  final int? collectorId;

  const _RouteCollectorSelectionResult(this.collectorId);
}

Future<_RouteCollectorSelectionResult?> _showRouteCollectorSelectionDialog({
  required BuildContext context,
  required List<AppCollectionRouteCollector> options,
  required int? selectedId,
}) => showAppDialog<_RouteCollectorSelectionResult>(
  context: context,
  title: 'Cobradores das rotas',
  subtitle: 'Selecione um cobrador disponível na lista atual.',
  icon: Icons.person_pin_circle_outlined,
  maxWidth: 560,
  maxHeight: 640,
  builder: (_) =>
      _RouteCollectorSelectionDialog(options: options, selectedId: selectedId),
);

class _RouteCollectorSelectionDialog extends StatefulWidget {
  final List<AppCollectionRouteCollector> options;
  final int? selectedId;

  const _RouteCollectorSelectionDialog({
    required this.options,
    required this.selectedId,
  });

  @override
  State<_RouteCollectorSelectionDialog> createState() =>
      _RouteCollectorSelectionDialogState();
}

class _RouteCollectorSelectionDialogState
    extends State<_RouteCollectorSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  late int? _selectedId = widget.selectedId;
  String _query = '';

  List<AppCollectionRouteCollector> get _visibleOptions {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where(
          (option) =>
              option.name.toLowerCase().contains(query) ||
              option.username.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<AppCollectionRouteCollector> visibleOptions = _visibleOptions;
    return SizedBox(
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Pesquisar cobrador',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.colors.primary,
                  size: 20,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
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
                  borderSide: BorderSide(
                    color: context.colors.primary,
                    width: 1.2,
                  ),
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
                    _selectedId == null
                        ? 'Nenhum marcado: todos os cobradores disponíveis'
                        : '1 cobrador marcado',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedId != null)
                  TextButton(
                    onPressed: () => setState(() => _selectedId = null),
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
                child: widget.options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Nenhum cobrador possui rotas nesta lista.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : visibleOptions.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum cobrador encontrado.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        itemCount: visibleOptions.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 43,
                          color: context.colors.divider.withValues(alpha: .55),
                        ),
                        itemBuilder: (context, index) {
                          final AppCollectionRouteCollector option =
                              visibleOptions[index];
                          final bool selected = _selectedId == option.id;
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (checked) => setState(() {
                              _selectedId = checked == true ? option.id : null;
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
                              option.name,
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
                            subtitle: option.username.isEmpty
                                ? null
                                : Text(
                                    '@${option.username}',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 9.5,
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
                        _RouteCollectorSelectionResult(_selectedId),
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

final class _RouteCitySelectionResult {
  final int? cityId;

  const _RouteCitySelectionResult(this.cityId);
}

Future<_RouteCitySelectionResult?> _showRouteCitySelectionDialog({
  required BuildContext context,
  required List<AppCityOption> options,
  required int? selectedId,
}) => showAppDialog<_RouteCitySelectionResult>(
  context: context,
  title: 'Cidades das rotas',
  subtitle: 'Selecione uma cidade disponível na lista atual.',
  icon: Icons.location_city_outlined,
  maxWidth: 560,
  maxHeight: 640,
  builder: (_) =>
      _RouteCitySelectionDialog(options: options, selectedId: selectedId),
);

class _RouteCitySelectionDialog extends StatefulWidget {
  final List<AppCityOption> options;
  final int? selectedId;

  const _RouteCitySelectionDialog({
    required this.options,
    required this.selectedId,
  });

  @override
  State<_RouteCitySelectionDialog> createState() =>
      _RouteCitySelectionDialogState();
}

class _RouteCitySelectionDialogState extends State<_RouteCitySelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  late int? _selectedId = widget.selectedId;
  String _query = '';

  List<AppCityOption> get _visibleOptions {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where(
          (option) =>
              option.displayName.toLowerCase().contains(query) ||
              option.name.toLowerCase().contains(query) ||
              option.state.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<AppCityOption> visibleOptions = _visibleOptions;
    return SizedBox(
      height: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Pesquisar cidade ou UF',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.colors.primary,
                  size: 20,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
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
                  borderSide: BorderSide(
                    color: context.colors.primary,
                    width: 1.2,
                  ),
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
                    _selectedId == null
                        ? 'Nenhuma marcada: todas as cidades disponíveis'
                        : '1 cidade marcada',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_selectedId != null)
                  TextButton(
                    onPressed: () => setState(() => _selectedId = null),
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
                child: widget.options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Nenhuma cidade possui clientes nesta lista.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      )
                    : visibleOptions.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma cidade encontrada.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        itemCount: visibleOptions.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 43,
                          color: context.colors.divider.withValues(alpha: .55),
                        ),
                        itemBuilder: (context, index) {
                          final AppCityOption option = visibleOptions[index];
                          final bool selected = _selectedId == option.id;
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (checked) => setState(() {
                              _selectedId = checked == true ? option.id : null;
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
                              option.displayName,
                              maxLines: 2,
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
                        _RouteCitySelectionResult(_selectedId),
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

class _RouteSortOption extends StatelessWidget {
  final AppCollectionRouteSort option;
  final bool selected;
  final VoidCallback onTap;

  const _RouteSortOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.colors.primary.withValues(alpha: .07)
        : context.colors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected
            ? context.colors.primary.withValues(alpha: .35)
            : context.colors.divider,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? context.colors.primary
                  : context.colors.textSecondary,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CollectionRouteDetailView extends StatefulWidget {
  final int clientId;
  final VoidCallback? onBack;

  const CollectionRouteDetailView({
    super.key,
    required this.clientId,
    this.onBack,
  });

  @override
  State<CollectionRouteDetailView> createState() =>
      _CollectionRouteDetailViewState();
}

class _CollectionRouteDetailViewState extends State<CollectionRouteDetailView> {
  final CollectionRouteService _service = CollectionRouteService();
  AppCollectionRouteDetail? _detail;
  bool _loading = true;
  bool _saving = false;
  bool _removing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CollectionRouteDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null || _detail == null) {
      return _RouteEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Cobrança indisponível',
        message: _errorMessage ?? 'Não foi possível abrir esta cobrança.',
        actionLabel: 'Tentar novamente',
        onAction: _load,
      );
    }

    final AppCollectionRouteDetail detail = _detail!;
    final AuthSession? session = AuthService().currentSession;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: context.colors.primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _DebtDetailCard(debt: detail.debt),
                const SizedBox(height: 10),
                _DetailSection(
                  icon: Icons.receipt_long_outlined,
                  title: 'Contratos em atraso',
                  child: Column(
                    children: [
                      for (
                        int index = 0;
                        index < detail.contracts.length;
                        index++
                      ) ...[
                        _ContractDebtTile(
                          contract: detail.contracts[index],
                          onTap: () =>
                              _openContract(detail.contracts[index].loanId),
                        ),
                        if (index != detail.contracts.length - 1)
                          Divider(height: 1, color: context.colors.divider),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _DetailSection(
                  icon: Icons.history_rounded,
                  title: 'Histórico de cobranças',
                  child: detail.history.isEmpty
                      ? const _HistoryEmpty()
                      : CollectionHistoryList(items: detail.history),
                ),
              ],
            ),
          ),
        ),
        _RouteDetailActionBar(
          canRegister: detail.canRegisterCollection,
          canRemove:
              session?.administrator == true ||
              session?.collector != true ||
              session?.canEdit == true,
          busy: _saving || _removing,
          removing: _removing,
          onRegister: _saving || _removing ? null : _register,
          onRemove: _saving || _removing ? null : _removeRoute,
          onBack: widget.onBack ?? () => Navigator.maybePop(context),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final AppCollectionRouteDetail detail = await _service.fetchDetail(
        widget.clientId,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on CollectionRouteServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  Future<void> _register() async {
    final _CollectionRegistrationDraft? draft =
        await showAppDialog<_CollectionRegistrationDraft>(
          context: context,
          title: 'Registrar cobrança',
          subtitle: 'Descreva a visita e anexe uma comprovação, se desejar.',
          icon: Icons.add_task_rounded,
          maxWidth: 560,
          maxHeight: 510,
          builder: (_) => const _RegisterCollectionForm(),
        );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.registerCollection(
        clientId: widget.clientId,
        observation: draft.observation,
        attachmentBytes: draft.bytes,
        attachmentName: draft.fileName,
      );
      await _load();
      if (mounted) {
        await _message(
          'Cobrança registrada',
          'A cobrança foi adicionada ao histórico do cliente.',
        );
      }
    } on CollectionRouteServiceException catch (error) {
      if (mounted) await _message('Não foi possível salvar', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openContract(int loanId) async {
    await openLoanDetailScreen(context: context, loanId: loanId);
    if (mounted) await _load();
  }

  Future<void> _removeRoute() async {
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Remover da rota?'),
            content: const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Apenas a atribuição será removida. O cliente, os contratos e o histórico de cobranças serão mantidos.',
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remover'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    try {
      await _service.removeRoute(widget.clientId);
      if (mounted) {
        (widget.onBack ?? () => Navigator.maybePop(context))();
      }
    } on CollectionRouteServiceException catch (error) {
      if (mounted) await _message('Não foi possível remover', error.message);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  Future<void> _message(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
}

class _RouteDetailActionBar extends StatelessWidget {
  final bool canRegister;
  final bool canRemove;
  final bool busy;
  final bool removing;
  final VoidCallback? onRegister;
  final VoidCallback? onRemove;
  final VoidCallback onBack;

  const _RouteDetailActionBar({
    required this.canRegister,
    required this.canRemove,
    required this.busy,
    required this.removing,
    required this.onRegister,
    required this.onRemove,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final bool mobile = MediaQuery.sizeOf(context).width < 600;
    final Widget backButton = OutlinedButton(
      onPressed: busy ? null : onBack,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.textSecondary,
        side: BorderSide(color: context.colors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('VOLTAR'),
    );
    final Widget registerButton = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9FD995), Color(0xFF4B7D60)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FilledButton(
        onPressed: onRegister,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy && !removing
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('REGISTRAR COBRANÇA'),
      ),
    );
    final Widget removeButton = OutlinedButton(
      onPressed: onRemove,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.error,
        side: BorderSide(color: context.colors.error.withValues(alpha: .65)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: removing
          ? SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.error,
              ),
            )
          : const Text('REMOVER DA ROTA'),
    );

    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
          child: mobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (canRegister) ...[
                      SizedBox(height: 42, child: registerButton),
                      const SizedBox(height: 6),
                    ],
                    if (canRemove) ...[
                      SizedBox(height: 42, child: removeButton),
                      const SizedBox(height: 6),
                    ],
                    SizedBox(height: 42, child: backButton),
                  ],
                )
              : SizedBox(
                  height: 42,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: backButton),
                      if (canRemove) ...[
                        const SizedBox(width: 8),
                        Expanded(child: removeButton),
                      ],
                      if (canRegister) ...[
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: registerButton),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class ClientCollectionsPanel extends StatefulWidget {
  final int clientId;

  const ClientCollectionsPanel({super.key, required this.clientId});

  @override
  State<ClientCollectionsPanel> createState() => _ClientCollectionsPanelState();
}

class _ClientCollectionsPanelState extends State<ClientCollectionsPanel> {
  final CollectionRouteService _service = CollectionRouteService();
  List<AppCollectionHistory> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClientCollectionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientId != widget.clientId) _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: _DetailSection(
                icon: Icons.route_outlined,
                title: 'Cobranças do cliente',
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: context.colors.primary,
                          ),
                        ),
                      )
                    : _error != null
                    ? _InlineError(message: _error!, onRetry: _load)
                    : _items.isEmpty
                    ? const _HistoryEmpty()
                    : CollectionHistoryList(items: _items),
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
        _error = null;
      });
    }
    try {
      final List<AppCollectionHistory> items = await _service
          .fetchClientHistory(widget.clientId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on CollectionRouteServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }
}

class CollectionHistoryList extends StatelessWidget {
  final List<AppCollectionHistory> items;

  const CollectionHistoryList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int index = 0; index < items.length; index++) ...[
          _CollectionHistoryTile(item: items[index]),
          if (index != items.length - 1)
            Divider(height: 1, color: context.colors.divider),
        ],
      ],
    );
  }
}

class _CollectionHistoryTile extends StatefulWidget {
  final AppCollectionHistory item;

  const _CollectionHistoryTile({required this.item});

  @override
  State<_CollectionHistoryTile> createState() => _CollectionHistoryTileState();
}

class _CollectionHistoryTileState extends State<_CollectionHistoryTile> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final DateFormat date = DateFormat('dd/MM/yyyy HH:mm');
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    final AppCollectionHistory item = widget.item;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.task_alt_rounded,
              color: context.colors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.observation,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${item.collectorName} • ${item.createdAt == null ? 'Data não informada' : date.format(item.createdAt!)}',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${currency.format(item.debtAmount)} • ${item.overdueDays} dia(s) em atraso • ${item.regionName}',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
                if (item.attachmentName != null) ...[
                  const SizedBox(height: 7),
                  InkWell(
                    onTap: item.attachmentAvailable && !_downloading
                        ? _download
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _downloading
                              ? SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.attach_file_rounded,
                                  size: 17,
                                  color: context.colors.primary,
                                ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.attachmentAvailable
                                  ? item.attachmentName!
                                  : '${item.attachmentName!} (indisponível)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: item.attachmentAvailable
                                    ? context.colors.primary
                                    : context.colors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final AppCollectionAttachment file = await CollectionRouteService()
          .downloadAttachment(widget.item);
      final XFile shared = XFile.fromData(
        file.bytes,
        mimeType: file.contentType,
        name: file.fileName,
      );
      if (kIsWeb) {
        await shared.saveTo('');
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [shared],
            fileNameOverrides: [file.fileName],
            title: 'Anexo da cobrança',
          ),
        );
      }
    } on CollectionRouteServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

class _RegisterCollectionForm extends StatefulWidget {
  const _RegisterCollectionForm();

  @override
  State<_RegisterCollectionForm> createState() =>
      _RegisterCollectionFormState();
}

class _RegisterCollectionFormState extends State<_RegisterCollectionForm> {
  final TextEditingController _observation = TextEditingController();
  Uint8List? _bytes;
  String? _fileName;
  String? _fileError;

  @override
  void dispose() {
    _observation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool valid = _observation.text.trim().isNotEmpty;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _observation,
                  onChanged: (_) => setState(() {}),
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Observação da cobrança *',
                    hintText: 'Descreva a visita, contato ou acordo realizado.',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: context.colors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _fileName == null
                        ? 'ANEXAR FOTO OU ARQUIVO'
                        : 'TROCAR ANEXO',
                  ),
                ),
                if (_fileName != null) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        color: context.colors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _fileName!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover anexo',
                        onPressed: () => setState(() {
                          _bytes = null;
                          _fileName = null;
                        }),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ],
                if (_fileError != null)
                  Text(
                    _fileError!,
                    style: TextStyle(color: context.colors.error, fontSize: 12),
                  ),
                Text(
                  'O anexo é opcional e pode ter até 15 MB.',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: valid
                      ? () => Navigator.pop(
                          context,
                          _CollectionRegistrationDraft(
                            observation: _observation.text.trim(),
                            bytes: _bytes,
                            fileName: _fileName,
                          ),
                        )
                      : null,
                  child: const Text('REGISTRAR'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final XFile? file = await openFile();
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length > 15 * 1024 * 1024) {
      setState(() => _fileError = 'O arquivo selecionado excede 15 MB.');
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = file.name;
      _fileError = null;
    });
  }
}

final class _CollectionRegistrationDraft {
  final String observation;
  final Uint8List? bytes;
  final String? fileName;

  const _CollectionRegistrationDraft({
    required this.observation,
    required this.bytes,
    required this.fileName,
  });
}

class _CollectionRouteCard extends StatelessWidget {
  final AppCollectionRouteItem item;
  final int position;
  final VoidCallback onTap;

  const _CollectionRouteCard({
    required this.item,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool completed = item.status == AppCollectionRouteStatus.completed;
    final Color statusColor = completed
        ? const Color(0xFF2E9D57)
        : const Color(0xFFF08A24);
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Material(
      color: statusColor.withValues(alpha: context.isDark ? .12 : .06),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 5),
              top: BorderSide(color: statusColor.withValues(alpha: .42)),
              right: BorderSide(color: statusColor.withValues(alpha: .42)),
              bottom: BorderSide(color: statusColor.withValues(alpha: .42)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: statusColor.withValues(alpha: .35)),
                ),
                child: Text(
                  '$position',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        _RouteStatusBadge(
                          label: item.status.label,
                          color: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 14,
                      runSpacing: 5,
                      children: [
                        _RouteCardInfo(
                          icon: Icons.location_on_outlined,
                          text: item.regionName,
                        ),
                        _RouteCardInfo(
                          icon: Icons.account_balance_wallet_outlined,
                          text: 'Dívida ${currency.format(item.totalDebt)}',
                          strong: true,
                        ),
                        _RouteCardInfo(
                          icon: Icons.schedule_rounded,
                          text: '${item.overdueDays} dia(s) em atraso',
                          strong: true,
                        ),
                        _RouteCardInfo(
                          icon: Icons.receipt_long_outlined,
                          text: '${item.overdueLoans} contrato(s)',
                        ),
                      ],
                    ),
                    if (item.collectorName != null) ...[
                      const SizedBox(height: 6),
                      _RouteCardInfo(
                        icon: Icons.person_pin_circle_outlined,
                        text: 'Cobrador: ${item.collectorName}',
                        strong: true,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _RouteCardInfo(
                      icon: Icons.home_outlined,
                      text: item.address,
                      maxLines: null,
                    ),
                    if (item.lastCollectionAt != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Última cobrança: ${DateFormat('dd/MM/yyyy HH:mm').format(item.lastCollectionAt!)}',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteCardInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  final int? maxLines;

  const _RouteCardInfo({
    required this.icon,
    required this.text,
    this.strong = false,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: context.colors.textSecondary),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: maxLines,
          overflow: maxLines == null
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            color: strong
                ? context.colors.textPrimary
                : context.colors.textSecondary,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    ],
  );
}

class _RouteStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RouteStatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DebtDetailCard extends StatelessWidget {
  final AppCollectionRouteItem debt;

  const _DebtDetailCard({required this.debt});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            debt.clientName,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          _RouteCardInfo(
            icon: Icons.location_on_outlined,
            text: debt.regionName,
          ),
          if (debt.collectorName != null) ...[
            const SizedBox(height: 4),
            _RouteCardInfo(
              icon: Icons.person_pin_circle_outlined,
              text: 'Cobrador: ${debt.collectorName}',
              strong: true,
            ),
          ],
          const SizedBox(height: 4),
          _RouteCardInfo(
            icon: Icons.home_outlined,
            text: debt.address,
            maxLines: null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DebtMetric(
                  label: 'Dívida total',
                  value: currency.format(debt.totalDebt),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DebtMetric(
                  label: 'Dias em atraso',
                  value: '${debt.overdueDays} dias',
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DebtMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DebtMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.colors.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: context.colors.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _DetailSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(13, 12, 13, 5),
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
            Icon(icon, color: context.colors.primary, size: 20),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

class _ContractDebtTile extends StatelessWidget {
  final AppCollectionContract contract;
  final VoidCallback onTap;

  const _ContractDebtTile({required this.contract, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE76F51).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: Color(0xFFE76F51),
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contrato #${contract.loanId} • ${contract.type}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Dívida ${currency.format(contract.totalDebt)} • Vencido ${currency.format(contract.overdueDebt)}',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${contract.overdueDays} dias',
              style: const TextStyle(
                color: Color(0xFFE76F51),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.textSecondary,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteFilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _RouteFilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      SizedBox.square(
        dimension: 45,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: context.colors.surface,
            side: BorderSide(color: context.colors.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: Icon(Icons.tune_rounded, color: context.colors.primary),
        ),
      ),
      if (count > 0)
        Positioned(
          right: -3,
          top: -5,
          child: Container(
            constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: context.colors.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.surface, width: 1.5),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
              ),
            ),
          ),
        ),
    ],
  );
}

class _RouteEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _RouteEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 90, left: 24, right: 24),
        child: Column(
          children: [
            Icon(icon, color: context.colors.primary, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ],
  );
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        Icon(
          Icons.history_toggle_off_rounded,
          color: context.colors.textSecondary,
          size: 34,
        ),
        const SizedBox(height: 7),
        Text(
          'Nenhuma cobrança registrada.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ],
    ),
  );
}
