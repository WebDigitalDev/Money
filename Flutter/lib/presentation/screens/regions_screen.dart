import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class RegionsScreenController {
  bool Function()? _closeDetail;
  VoidCallback? _openCreate;

  bool closeDetail() => _closeDetail?.call() ?? false;

  void openCreate() => _openCreate?.call();
}

class RegionsScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final RegionsScreenController? controller;
  final ValueChanged<bool>? onDetailVisibilityChanged;

  const RegionsScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.controller,
    this.onDetailVisibilityChanged,
  });

  @override
  State<RegionsScreen> createState() => _RegionsScreenState();
}

class _RegionsScreenState extends State<RegionsScreen> {
  static const Duration _refreshInterval = Duration(seconds: 10);

  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _regionListController = ScrollController();
  AppRegionFilters _filters = AppRegionFilters.lastThirtyDays(DateTime.now());
  AppRegionListData? _data;
  List<AppRegionOption> _options = const [];
  Timer? _searchDebounce;
  Timer? _refreshTimer;
  bool _loading = true;
  bool _refreshing = false;
  bool _applyingFilters = false;
  String? _errorMessage;
  int _requestVersion = 0;
  int? _embeddedRegionId;
  bool _creatingRegion = false;
  bool _desktopDialogOpen = false;

  bool get _showingDetail => _embeddedRegionId != null || _creatingRegion;
  bool get _canEdit => AuthService().currentSession?.canManageRegions == true;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
    NetworkStatusService().statusListenable.addListener(_handleNetworkChanged);
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshSilently());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    final AppRegionFilters savedFilters = await _loadSavedFilters();
    if (!mounted) return;
    setState(() => _filters = savedFilters);
    if (!widget.active) return;
    unawaited(_loadOptions());
    await _load();
  }

  @override
  void didUpdateWidget(covariant RegionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
    if (!oldWidget.active && widget.active) {
      if (_data == null) {
        unawaited(_loadOptions());
        _load();
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
    NetworkStatusService().statusListenable.removeListener(
      _handleNetworkChanged,
    );
    _searchController.dispose();
    _regionListController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = _showingDetail
        ? _creatingRegion
              ? 'Nova região'
              : 'Detalhes da região'
        : context.tr!.sidebar_regions;
    return Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      appBar: widget.showAppBar
          ? HomeAppBar(title: title, leading: const AppSidebarMenuButton())
          : null,
      body: _showingDetail
          ? RegionDetailScreen(
              regionId: _embeddedRegionId,
              showAppBar: false,
              embedded: true,
              onBack: _closeDetail,
              onSaved: _refreshAfterChange,
              onCreated: _handleRegionCreated,
            )
          : _buildList(),
    );
  }

  Widget _buildList() {
    final bool compact = MediaQuery.sizeOf(context).width < 600;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 0 : (widget.showAppBar ? 10 : 8),
              compact ? 9 : 14,
              compact ? 0 : (widget.showAppBar ? 10 : 8),
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  _RegionsHeader(
                    regions: _data?.totals.regions ?? 0,
                    canEdit: _canEdit,
                    onExport: widget.showAppBar ? null : _confirmExport,
                    onCreate: _openCreate,
                  ),
                  const SizedBox(height: 13),
                ],
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          if (widget.showAppBar) ...[
                            AppMobileExcelExportButton(
                              onPressed: _confirmExport,
                              dimension: 44,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: _RegionSearchField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              onClear: _clearSearch,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterButton(
                            activeCount: _filters.activeCount,
                            onPressed: _openFilters,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      _AppliedPeriod(filters: _filters),
                      const SizedBox(height: 7),
                    ],
                  ),
                ),
                Expanded(
                  child: compact
                      ? _buildMobileContent()
                      : _buildContent(compact),
                ),
                if (!compact && _data != null) ...[
                  const SizedBox(height: 7),
                  _RegionTotalsPanel(
                    totals: _data!.totals,
                    loading: _applyingFilters,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileContent() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildContent(true),
          ),
        ),
        if (_data != null) ...[
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: context.colors.surface,
              elevation: 0,
              borderRadius: BorderRadius.zero,
              child: _RegionTotalsPanel(
                totals: _data!.totals,
                compact: true,
                loading: _applyingFilters,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(bool compact) {
    if (_loading && _data == null) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null && _data == null) {
      return _RegionsMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar as regiões',
        message: _errorMessage!,
        onRetry: _load,
      );
    }
    final AppRegionListData data =
        _data ??
        const AppRegionListData(
          items: [],
          totals: AppRegionTotals.empty(),
          startDate: null,
          endDate: null,
        );
    if (data.items.isEmpty) {
      return _RegionsMessage(
        icon: Icons.location_off_outlined,
        title: 'Nenhuma região encontrada',
        message: 'Ajuste a pesquisa ou os filtros aplicados.',
        onRetry: null,
      );
    }

    if (!compact) {
      return Scrollbar(
        controller: _regionListController,
        thumbVisibility: true,
        child: RefreshIndicator(
          color: context.colors.primary,
          onRefresh: () => _load(force: true),
          child: GridView.builder(
            controller: _regionListController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
              mainAxisExtent: 212,
            ),
            itemCount: data.items.length,
            itemBuilder: (context, index) => _RegionCard(
              region: data.items[index],
              loading: _applyingFilters,
              onTap: _applyingFilters
                  ? null
                  : () => _openDetail(data.items[index].id),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        controller: _regionListController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList.separated(
            itemCount: data.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) => _RegionCard(
              region: data.items[index],
              loading: _applyingFilters,
              onTap: _applyingFilters
                  ? null
                  : () => _openDetail(data.items[index].id),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: compact ? 8 : 16)),
        ],
      ),
    );
  }

  void _attachController(RegionsScreenController? controller) {
    controller?._closeDetail = _closeDetailFromController;
    controller?._openCreate = _openCreate;
  }

  void _detachController(RegionsScreenController? controller) {
    controller?._closeDetail = null;
    controller?._openCreate = null;
  }

  void _openCreate() {
    if (!_canEdit || _showingDetail) return;
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      if (!_desktopDialogOpen) unawaited(_openDesktopRegionDialog());
      return;
    }
    setState(() => _creatingRegion = true);
    widget.onDetailVisibilityChanged?.call(true);
  }

  void _openDetail(int id) {
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      if (!_desktopDialogOpen) unawaited(_openDesktopRegionDialog(id));
      return;
    }
    setState(() => _embeddedRegionId = id);
    widget.onDetailVisibilityChanged?.call(true);
  }

  Future<void> _openDesktopRegionDialog([int? regionId]) async {
    _desktopDialogOpen = true;
    bool created = false;
    try {
      await showAppSideDrawer<void>(
        context: context,
        fromStart: true,
        maxWidth: 500,
        builder: (drawerContext) => Column(
          children: [
            AppPanelHeader(
              title: regionId == null ? 'Nova região' : 'Detalhes da região',
              subtitle: regionId == null
                  ? 'Preencha os dados para cadastrar.'
                  : _canEdit
                  ? 'Consulte e altere os dados da região.'
                  : 'Consulte os dados da região.',
              icon: Icons.location_on_outlined,
              onClose: () => Navigator.pop(drawerContext),
            ),
            Expanded(
              child: RegionDetailScreen(
                regionId: regionId,
                showAppBar: false,
                embedded: true,
                showEmbeddedHeader: regionId != null,
                onBack: () => Navigator.pop(drawerContext),
                onSaved: _refreshAfterChange,
                onCreated: () {
                  created = true;
                  Navigator.pop(drawerContext);
                },
              ),
            ),
          ],
        ),
      );
    } finally {
      _desktopDialogOpen = false;
      if (mounted) {
        _refreshAfterChange();
        if (created) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_showRegionCreatedDialog());
          });
        }
      }
    }
  }

  void _handleRegionCreated() {
    _closeDetail();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showRegionCreatedDialog());
    });
  }

  Future<void> _showRegionCreatedDialog() => showAppCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('Região criada'),
      content: const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('A região foi cadastrada com sucesso.'),
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

  void _closeDetail() {
    if (!_showingDetail) return;
    setState(() {
      _embeddedRegionId = null;
      _creatingRegion = false;
    });
    widget.onDetailVisibilityChanged?.call(false);
  }

  bool _closeDetailFromController() {
    if (!_showingDetail) return false;
    _closeDetail();
    return true;
  }

  void _refreshAfterChange() {
    unawaited(_loadOptions(force: true));
    unawaited(_load(force: true));
  }

  Future<void> _load({bool force = false}) async {
    final int version = ++_requestVersion;
    final AppRegionListData? cached = force
        ? null
        : _regionService.cachedRegions(
            query: _searchController.text,
            filters: _filters,
          );
    if (mounted) {
      setState(() {
        if (cached != null) _data = cached;
        _loading = cached == null;
        _errorMessage = null;
      });
    }
    try {
      final AppRegionListData result = await _regionService.fetchRegions(
        query: _searchController.text,
        filters: _filters,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _data = result;
        _loading = false;
        _errorMessage = null;
      });
    } on RegionServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _errorMessage = _data == null ? error.message : null;
      });
    }
  }

  Future<void> _refreshSilently() async {
    if (!mounted ||
        !widget.active ||
        _refreshing ||
        _showingDetail ||
        !NetworkStatusService().isOnline) {
      return;
    }
    _refreshing = true;
    final int version = _requestVersion;
    try {
      final AppRegionListData result = await _regionService.fetchRegions(
        query: _searchController.text,
        filters: _filters,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() => _data = result);
    } on RegionServiceException {
      // Mantém o último conteúdo enquanto o monitor global avalia a conexão.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadOptions({bool force = false}) async {
    try {
      final List<AppRegionOption> options = await _regionService.fetchOptions(
        force: force,
      );
      if (mounted) setState(() => _options = options);
    } on RegionServiceException {
      // A listagem principal permanece disponível sem o seletor avançado.
    }
  }

  void _handleNetworkChanged() {
    if (widget.active && NetworkStatusService().isOnline) {
      unawaited(_load(force: true));
      unawaited(_loadOptions(force: true));
    }
  }

  void _onSearchChanged(String value) {
    // Mantém a digitação independente da lista e descarta qualquer resposta
    // pertencente ao texto anterior.
    _requestVersion++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _searchDebounce?.cancel();
    _load();
  }

  Future<void> _confirmExport() async {
    await showAppExcelExportFlow(
      context: context,
      title: 'Exportar regiões',
      confirmationMessage:
          'Deseja exportar as regiões em Excel considerando a pesquisa e os filtros atuais?',
      generate: (onProgress) async {
        try {
          onProgress(.02, 'Buscando as regiões filtradas...');
          final List<AppRegionSummary> regions = await _regionService
              .fetchRegionsForExport(
                query: _searchController.text,
                filters: _filters,
                onProgress: (value) => onProgress(
                  .02 + (value * .48),
                  'Recebendo dados das regiões...',
                ),
              );
          if (regions.isEmpty) {
            throw const AppExcelExportException(
              'Nenhuma região foi encontrada para exportar.',
            );
          }
          final AppRegionExcelFile file = await RegionExcelExportService()
              .create(
                regions,
                onProgress: (value, status) =>
                    onProgress(.50 + (value * .50), status),
              );
          return AppGeneratedExcelFile(
            bytes: file.bytes,
            fileName: file.fileName,
            successMessage: '${regions.length} região(ões) exportada(s).',
          );
        } on RegionServiceException catch (error) {
          throw AppExcelExportException(error.message);
        }
      },
    );
  }

  Future<void> _openFilters() async {
    final List<AppRegionOption> availableOptions = _options.isNotEmpty
        ? _options
        : (_data?.items ?? const <AppRegionSummary>[])
              .map(
                (region) =>
                    AppRegionOption(id: region.id, name: region.displayName),
              )
              .toList(growable: false);
    if (_options.isEmpty) unawaited(_loadOptions());
    final AppRegionFilters? selected = await showRegionFilterDrawer(
      context: context,
      initial: _filters,
      options: availableOptions,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _filters = selected;
      _applyingFilters = true;
    });
    try {
      await _saveFilters(selected);
      if (!mounted) return;
      await _load(force: true);
    } finally {
      if (mounted) setState(() => _applyingFilters = false);
    }
  }

  Future<AppRegionFilters> _loadSavedFilters() async {
    final AppRegionFilters fallback = AppRegionFilters.lastThirtyDays(
      DateTime.now(),
    );
    try {
      final int? userId = AuthService().currentSession?.userId;
      if (userId == null) return fallback;
      final Map<String, dynamic>? data = await _preferencesService
          .getUserFilters(scope: 'regions', userId: userId);
      if (data == null) return fallback;
      final Set<int> regionIds = ((data['regionIds'] as List?) ?? const [])
          .map((item) => int.tryParse('$item'))
          .whereType<int>()
          .toSet();
      return AppRegionFilters(
        startDate: DateTime.tryParse('${data['startDate'] ?? ''}'),
        endDate: DateTime.tryParse('${data['endDate'] ?? ''}'),
        regionIds: Set<int>.unmodifiable(regionIds),
      );
    } on Object {
      return fallback;
    }
  }

  Future<void> _saveFilters(AppRegionFilters filters) async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'regions',
      userId: userId,
      filters: {
        'startDate': filters.startDate?.toIso8601String(),
        'endDate': filters.endDate?.toIso8601String(),
        'regionIds': filters.regionIds.toList(growable: false),
      },
    );
  }
}

class _RegionsHeader extends StatelessWidget {
  final int regions;
  final bool canEdit;
  final VoidCallback? onExport;
  final VoidCallback onCreate;

  const _RegionsHeader({
    required this.regions,
    required this.canEdit,
    required this.onExport,
    required this.onCreate,
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
                'Gestão de regiões',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$regions ${regions == 1 ? 'região encontrada' : 'regiões encontradas'}',
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
              'NOVA REGIÃO',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _RegionSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _RegionSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_RegionSearchField> createState() => _RegionSearchFieldState();
}

class _RegionSearchFieldState extends State<_RegionSearchField> {
  late bool _showClearButton;

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _RegionSearchField oldWidget) {
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
      height: 44,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Pesquisar região, responsável ou ID',
          hintStyle: TextStyle(
            color: context.colors.textPlaceholder,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: context.colors.primary,
            size: 19,
          ),
          suffixIcon: !_showClearButton
              ? null
              : IconButton(
                  tooltip: 'Limpar pesquisa',
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
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

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _FilterButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.colors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.tune_rounded, color: context.colors.primary, size: 21),
              if (activeCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15),
                    height: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: context.colors.secondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$activeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppliedPeriod extends StatelessWidget {
  final AppRegionFilters filters;

  const _AppliedPeriod({required this.filters});

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat('dd/MM/yyyy');
    final String period = filters.startDate == null && filters.endDate == null
        ? 'Todo o período'
        : '${filters.startDate == null ? 'Início' : format.format(filters.startDate!)}'
              ' até ${filters.endDate == null ? 'Hoje' : format.format(filters.endDate!)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.date_range_outlined,
          size: 14,
          color: context.colors.primary,
        ),
        const SizedBox(width: 4),
        Text(
          period,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _RegionTotalsPanel extends StatelessWidget {
  final AppRegionTotals totals;
  final bool compact;
  final bool loading;

  const _RegionTotalsPanel({
    required this.totals,
    this.compact = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Container(
      padding: EdgeInsets.all(compact ? 7 : 9),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(13),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CountMetric(
                label: 'Ativos',
                value: totals.activeClients,
                dense: compact,
                loading: loading,
              ),
              _CountMetric(
                label: 'Em dia',
                value: totals.currentClients,
                dense: compact,
                loading: loading,
              ),
              _CountMetric(
                label: 'Atrasados',
                value: totals.overdueClients,
                dense: compact,
                loading: loading,
              ),
              _CountMetric(
                label: 'Desap.',
                value: totals.missingClients,
                dense: compact,
                loading: loading,
              ),
            ],
          ),
          Divider(height: compact ? 9 : 13, color: context.colors.divider),
          LayoutBuilder(
            builder: (context, constraints) {
              final int columns = compact
                  ? 3
                  : constraints.maxWidth >= 800
                  ? 4
                  : 2;
              final double spacing = compact ? 5 : 7;
              final double width =
                  (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
              final List<Widget> metrics = [
                _MoneyMetric(
                  label: 'Total a receber',
                  value: currency.format(totals.receivableAmount),
                  color: context.colors.primary,
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Atrasados',
                  value: currency.format(totals.overdueAmount),
                  color: context.colors.error,
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Lucro',
                  value: currency.format(totals.profitAmount),
                  color: context.colors.primary,
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Recebido',
                  value: currency.format(totals.receivedAmount),
                  color: const Color(0xFF2E9D62),
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Vencendo hoje',
                  value: currency.format(totals.dueTodayAmount),
                  color: const Color(0xFFE59B2F),
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Desaparecidos',
                  value: currency.format(totals.missingAmount),
                  color: context.colors.error,
                  dense: compact,
                  loading: loading,
                ),
                _MoneyMetric(
                  label: 'Emprestado',
                  value: currency.format(totals.loanedAmount),
                  color: const Color(0xFF4776B9),
                  dense: compact,
                  loading: loading,
                ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: compact ? 4 : 6,
                children: [
                  for (final Widget metric in metrics)
                    SizedBox(width: width, child: metric),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CountMetric extends StatelessWidget {
  final String label;
  final int value;
  final bool dense;
  final bool loading;

  const _CountMetric({
    required this.label,
    required this.value,
    this.dense = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: dense ? 8.5 : 9.5,
            ),
          ),
          const SizedBox(height: 1),
          if (loading)
            const _LoadingValueLine(width: 34, height: 13)
          else
            Text(
              '$value',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: dense ? 12 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _MoneyMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool dense;
  final bool loading;

  const _MoneyMetric({
    required this.label,
    required this.value,
    required this.color,
    this.dense = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 7,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: dense ? 8.5 : 9,
            ),
          ),
          const SizedBox(height: 1),
          if (loading)
            _LoadingValueLine(width: dense ? 68 : 82, height: dense ? 10 : 12)
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: dense ? 9.5 : 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  final AppRegionSummary region;
  final bool loading;
  final VoidCallback? onTap;

  const _RegionCard({
    required this.region,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    final double currentPercent = region.activeClients == 0
        ? 0
        : region.currentClients * 100 / region.activeClients;
    final double overduePercent = region.activeClients == 0
        ? 0
        : region.overdueClients * 100 / region.activeClients;
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: context.colors.divider),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.location_on_outlined,
                      color: context.colors.primary,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          region.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (loading)
                          const _LoadingValueLine(width: 145, height: 9)
                        else
                          Text(
                            'ID ${region.id} • ${region.activeClients} ativos • '
                            '${region.missingClients} desaparecidos',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 9.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: _RegionStatusLine(
                      label: 'Em dia',
                      count: region.currentClients,
                      percent: currentPercent,
                      color: const Color(0xFF2E9D62),
                      loading: loading,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _RegionStatusLine(
                      label: 'Atrasados',
                      count: region.overdueClients,
                      percent: overduePercent,
                      color: context.colors.error,
                      loading: loading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) {
                  final int columns = constraints.maxWidth >= 760 ? 4 : 2;
                  final double width =
                      (constraints.maxWidth - ((columns - 1) * 6)) / columns;
                  final List<Widget> metrics = [
                    _CompactValue(
                      'Recebido',
                      currency.format(region.receivedAmount),
                      const Color(0xFF2E9D62),
                      loading: loading,
                    ),
                    _CompactValue(
                      'A receber',
                      currency.format(region.receivableAmount),
                      context.colors.primary,
                      loading: loading,
                    ),
                    _CompactValue(
                      'Vence hoje',
                      currency.format(region.dueTodayAmount),
                      const Color(0xFFE59B2F),
                      loading: loading,
                    ),
                    _CompactValue(
                      'Atrasados',
                      currency.format(region.overdueAmount),
                      context.colors.error,
                      loading: loading,
                    ),
                    _CompactValue(
                      'Lucro',
                      currency.format(region.profitAmount),
                      context.colors.primary,
                      loading: loading,
                    ),
                    _CompactValue(
                      'Desaparecidos',
                      currency.format(region.missingAmount),
                      context.colors.error,
                      loading: loading,
                    ),
                    _CompactValue(
                      'Emprestado',
                      currency.format(region.loanedAmount),
                      const Color(0xFF4776B9),
                      loading: loading,
                    ),
                  ];
                  return Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      for (final Widget metric in metrics)
                        SizedBox(width: width, child: metric),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionStatusLine extends StatelessWidget {
  final String label;
  final int count;
  final double percent;
  final Color color;
  final bool loading;

  const _RegionStatusLine({
    required this.label,
    required this.count,
    required this.percent,
    required this.color,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: loading
          ? const _LoadingValueLine(width: 92, height: 10)
          : Text(
              '$count $label (${percent.toStringAsFixed(1)}%)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _CompactValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool loading;

  const _CompactValue(
    this.label,
    this.value,
    this.color, {
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 8.5,
                ),
              ),
              if (loading)
                const _LoadingValueLine(width: 72, height: 9)
              else
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingValueLine extends StatelessWidget {
  final double width;
  final double height;

  const _LoadingValueLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.colors.divider.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

class _RegionsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _RegionsMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.primary, size: 44),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 13),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<Set<int>?> showRegionSelectionDialog({
  required BuildContext context,
  required List<AppRegionOption> options,
  required Set<int> selected,
  String title = 'Selecionar regiões',
  String subtitle = 'Marque as regiões que deseja consultar.',
  String emptySelectionLabel = 'Nenhuma marcada: serão exibidas todas',
}) => showAppDialog<Set<int>>(
  context: context,
  title: title,
  subtitle: subtitle,
  icon: Icons.location_on_outlined,
  maxWidth: 560,
  maxHeight: 640,
  builder: (_) => _RegionSelectionDialog(
    options: options,
    selected: selected,
    emptySelectionLabel: emptySelectionLabel,
  ),
);

Future<AppRegionFilters?> showRegionFilterDrawer({
  required BuildContext context,
  required AppRegionFilters initial,
  required List<AppRegionOption> options,
}) {
  final double screenWidth = MediaQuery.sizeOf(context).width;
  final bool compact = screenWidth < 600;
  return showAppSideDrawer<AppRegionFilters>(
    context: context,
    maxWidth: compact ? screenWidth * appMobileFilterDrawerWidthFactor : 410,
    barrierDismissible: compact,
    builder: (_) => _RegionFilterDrawer(initial: initial, options: options),
  );
}

class _RegionFilterDrawer extends StatefulWidget {
  final AppRegionFilters initial;
  final List<AppRegionOption> options;

  const _RegionFilterDrawer({required this.initial, required this.options});

  @override
  State<_RegionFilterDrawer> createState() => _RegionFilterDrawerState();
}

class _RegionFilterDrawerState extends State<_RegionFilterDrawer> {
  DateTime? _startDate;
  DateTime? _endDate;
  late Set<int> _regionIds;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initial.startDate;
    _endDate = widget.initial.endDate;
    final Set<int> availableRegionIds = widget.options
        .map((region) => region.id)
        .toSet();
    final Set<int> selectedRegionIds = widget.initial.regionIds
        .where(availableRegionIds.contains)
        .toSet();
    _regionIds = selectedRegionIds;
  }

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
                title: 'Filtros de regiões',
                subtitle: 'Informe os filtros para a consulta.',
                icon: Icons.tune_rounded,
                compact: MediaQuery.sizeOf(context).width < 600,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: ListView(
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
                                onPressed: () => setState(_regionIds.clear),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                ),
                                child: const Text(
                                  'TODAS AS REGIÕES',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    AppFilterSectionCard(
                      title: 'Período dos indicadores',
                      icon: Icons.date_range_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DateFilterField(
                            label: 'Data inicial',
                            value: _startDate,
                            onTap: () => _selectDate(start: true),
                          ),
                          const SizedBox(height: 7),
                          _DateFilterField(
                            label: 'Data final',
                            value: _endDate,
                            onTap: () => _selectDate(start: false),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _PresetChip(label: 'Hoje', onTap: _today),
                              _PresetChip(
                                label: 'Últimos 30 dias',
                                onTap: _lastThirtyDays,
                              ),
                              _PresetChip(label: 'Este mês', onTap: _thisMonth),
                              _PresetChip(
                                label: 'Todo período',
                                onTap: _allPeriod,
                              ),
                            ],
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
      final int selectedId = _regionIds.first;
      AppRegionOption? selectedRegion;
      for (final AppRegionOption option in widget.options) {
        if (option.id == selectedId) {
          selectedRegion = option;
          break;
        }
      }
      return selectedRegion?.name ?? 'Região #$selectedId';
    }
    return '${_regionIds.length} regiões selecionadas';
  }

  Future<void> _openRegionPicker() async {
    final Set<int>? selected = await showRegionSelectionDialog(
      context: context,
      options: widget.options,
      selected: _regionIds,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _regionIds
        ..clear()
        ..addAll(selected);
    });
  }

  void _today() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today;
      _endDate = today;
    });
  }

  void _lastThirtyDays() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today.subtract(const Duration(days: 30));
      _endDate = today;
    });
  }

  void _thisMonth() {
    final DateTime now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month);
      _endDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _allPeriod() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  void _clear() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _regionIds.clear();
    });
  }

  Future<void> _selectDate({required bool start}) async {
    final DateTime initial = (start ? _startDate : _endDate) ?? DateTime.now();
    final DateTime? selected = await showAppDatePickerDialog(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: start ? 'Data inicial' : 'Data final',
      subtitle: start
          ? 'Escolha o início do período.'
          : 'Escolha o fim do período.',
      locale: const Locale('pt', 'BR'),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = selected;
      } else {
        _endDate = selected;
      }
    });
  }

  void _apply() {
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data inicial deve ser anterior à data final.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      AppRegionFilters(
        startDate: _startDate,
        endDate: _endDate,
        regionIds: Set<int>.unmodifiable(_regionIds),
      ),
    );
  }
}

class _RegionSelectionDialog extends StatefulWidget {
  final List<AppRegionOption> options;
  final Set<int> selected;
  final String emptySelectionLabel;

  const _RegionSelectionDialog({
    required this.options,
    required this.selected,
    required this.emptySelectionLabel,
  });

  @override
  State<_RegionSelectionDialog> createState() => _RegionSelectionDialogState();
}

class _RegionSelectionDialogState extends State<_RegionSelectionDialog> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<int> _selected = Set<int>.from(widget.selected);
  String _query = '';

  List<AppRegionOption> get _visibleOptions {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where(
          (option) =>
              option.name.toLowerCase().contains(query) ||
              '${option.id}'.contains(query),
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
    final List<AppRegionOption> visibleOptions = _visibleOptions;
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
                hintText: 'Pesquisar região',
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
                    _selected.isEmpty
                        ? widget.emptySelectionLabel
                        : '${_selected.length} região(ões) marcada(s)',
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
                child: widget.options.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma região disponível.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : visibleOptions.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma região encontrada.',
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
                          final AppRegionOption option = visibleOptions[index];
                          final bool selected = _selected.contains(option.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(option.id);
                              } else {
                                _selected.remove(option.id);
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
                              option.name.isEmpty
                                  ? 'Região #${option.id}'
                                  : option.name,
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
                        Set<int>.unmodifiable(_selected),
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

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      label: Text(label),
      labelStyle: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: context.colors.divider.withValues(alpha: .8)),
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DateFilterField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateFilterField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: .14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  color: context.colors.primary,
                  size: 15,
                ),
                const SizedBox(width: 5),
                Text(
                  value == null
                      ? 'Não definida'
                      : DateFormat('dd/MM/yyyy').format(value!),
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 11.5,
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
}
