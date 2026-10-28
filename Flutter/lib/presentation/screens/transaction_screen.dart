import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';

class TransactionScreen extends StatefulWidget {
  final bool showAppBar;
  final bool active;
  final bool tutorialMode;
  final VoidCallback? onNewLoan;
  final Key? newLoanButtonKey;

  const TransactionScreen({
    super.key,
    this.showAppBar = true,
    this.active = true,
    this.tutorialMode = false,
    this.onNewLoan,
    this.newLoanButtonKey,
  });

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  static const int _pageSize = 50;

  final LoanService _loanService = LoanService();
  final RegionService _regionService = RegionService();
  final SharedPreferencesService _preferencesService =
      SharedPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  AppLoanFilters _filters = const AppLoanFilters();
  List<AppLoanSummary> _loans = const [];
  List<AppRegionOption> _regionOptions = const [];
  Timer? _searchDebounce;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _hasNext = false;
  int _nextPage = 0;
  int _totalItems = 0;
  AppLoanTotals _totals = const AppLoanTotals.empty();
  int _requestVersion = 0;
  String? _errorMessage;
  bool _desktopListMode = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    NetworkStatusService().statusListenable.addListener(_handleNetworkChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    if (widget.tutorialMode && mounted) {
      _requestVersion++;
      setState(() {
        _filters = const AppLoanFilters(regionIds: {-1});
        _loans = const [];
        _regionOptions = const [];
        _loading = true;
        _loadingMore = false;
        _hasNext = false;
        _nextPage = 0;
        _totalItems = 0;
        _totals = const AppLoanTotals.empty();
        _errorMessage = null;
      });
    }
    final List<Object> preferences = await Future.wait<Object>([
      widget.tutorialMode ? _loadTutorialFilters() : _loadSavedFilters(),
      widget.tutorialMode
          ? Future<bool>.value(false)
          : _loadDesktopListPreference(),
    ]);
    if (!mounted) return;
    setState(() {
      _filters = preferences[0] as AppLoanFilters;
      _desktopListMode = preferences[1] as bool;
    });
    if (!widget.active) return;
    if (!widget.tutorialMode) unawaited(_loadRegionOptions());
    await _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant TransactionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tutorialMode != widget.tutorialMode) {
      unawaited(_initialize());
      return;
    }
    if (!oldWidget.active && widget.active) {
      if (_loans.isEmpty) {
        unawaited(_loadRegionOptions());
        _load(reset: true);
      } else {
        unawaited(_refreshSilently());
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    NetworkStatusService().statusListenable.removeListener(
      _handleNetworkChanged,
    );
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      appBar: widget.showAppBar
          ? HomeAppBar(
              title: context.tr!.sidebar_loans,
              leading: const AppSidebarMenuButton(),
            )
          : null,
      body: SafeArea(top: false, child: _buildPage()),
    );
  }

  Widget _buildPage() {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool compact = screenWidth < 600;
    final bool desktopLayout = kIsWeb && screenWidth >= 900;
    final bool desktopGrid = desktopLayout && !_desktopListMode;
    return Center(
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
                _LoansPageHeader(
                  totalItems: _totalItems,
                  onExport: widget.showAppBar ? null : _confirmExport,
                  onNewLoan: widget.onNewLoan,
                  newLoanButtonKey: widget.newLoanButtonKey,
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
                            dimension: 47,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: _LoanSearchField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            onClear: _clearSearch,
                          ),
                        ),
                        if (desktopLayout) ...[
                          const SizedBox(width: 8),
                          _LoanViewModeButton(
                            listMode: _desktopListMode,
                            onPressed: _toggleDesktopListMode,
                          ),
                        ],
                        const SizedBox(width: 8),
                        _LoanFilterButton(
                          activeCount: _filters.activeCount,
                          onPressed: _openFilters,
                        ),
                      ],
                    ),
                    if (_filters.activeCount > 0) ...[
                      const SizedBox(height: 6),
                      _AppliedLoanFilters(filters: _filters),
                    ],
                    const SizedBox(height: 7),
                  ],
                ),
              ),
              Expanded(
                child: compact
                    ? _buildMobileBody()
                    : Column(
                        children: [
                          Expanded(
                            child: _buildList(
                              compact: false,
                              grid: desktopGrid,
                              desktopList: desktopLayout && _desktopListMode,
                            ),
                          ),
                          const SizedBox(height: 7),
                          _LoanTotalsBar(totals: _totals),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildList(compact: true),
          ),
        ),
        if (_loans.isNotEmpty) ...[
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: _LoanTotalsBar(totals: _totals, compact: true),
          ),
        ],
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _buildList({
    required bool compact,
    bool grid = false,
    bool desktopList = false,
  }) {
    if (_loading && _loans.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_errorMessage != null && _loans.isEmpty) {
      return _LoansMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Não foi possível carregar os empréstimos',
        message: _errorMessage!,
        onRetry: () => _load(reset: true, force: true),
      );
    }
    if (_loans.isEmpty) {
      return const _LoansMessage(
        svgIcon: AppIcons.loan,
        title: 'Nenhum empréstimo encontrado',
        message: 'Ajuste a pesquisa ou os filtros aplicados.',
      );
    }

    if (grid) {
      final Widget gridView = RefreshIndicator(
        color: context.colors.primary,
        onRefresh: () => _load(reset: true, force: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverGrid.builder(
              itemCount: _loans.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 6,
                mainAxisExtent: 238,
              ),
              itemBuilder: (context, index) {
                final AppLoanSummary loan = _loans[index];
                return _LoanCard(
                  loan: loan,
                  position: index + 1,
                  onTap: () => _confirmAndOpenLoan(loan),
                );
              },
            ),
            if (_loadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      );
      return Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: gridView,
      );
    }

    final Widget list = RefreshIndicator(
      color: context.colors.primary,
      onRefresh: () => _load(reset: true, force: true),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: _loans.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == _loans.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox.square(
                  dimension: 23,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: context.colors.primary,
                  ),
                ),
              ),
            );
          }
          final AppLoanSummary loan = _loans[index];
          return desktopList
              ? _DesktopLoanListCard(
                  loan: loan,
                  position: index + 1,
                  onTap: () => _confirmAndOpenLoan(loan),
                )
              : _LoanCard(
                  loan: loan,
                  position: index + 1,
                  onTap: () => _confirmAndOpenLoan(loan),
                );
        },
      ),
    );
    if (compact) return list;
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: list,
    );
  }

  Future<void> _load({required bool reset, bool force = false}) async {
    if ((!reset && (!_hasNext || _loadingMore)) || (!mounted)) return;
    final int version = reset ? ++_requestVersion : _requestVersion;
    final int page = reset ? 0 : _nextPage;

    if (reset) {
      final AppLoanPage? cached = _loanService.cachedLoans(
        query: _searchController.text,
        filters: _filters,
        page: 0,
        size: _pageSize,
        tutorialMode: widget.tutorialMode,
      );
      if (cached != null) _applyFirstPage(cached);
      setState(() {
        _loading = cached == null;
        _loadingMore = false;
        _errorMessage = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final AppLoanPage result = await _loanService.fetchLoans(
        query: _searchController.text,
        filters: _filters,
        page: page,
        size: _pageSize,
        force: force,
        tutorialMode: widget.tutorialMode,
      );
      if (!mounted || version != _requestVersion) return;
      setState(() {
        if (reset) {
          _loans = result.items;
        } else {
          final Set<int> existing = _loans.map((loan) => loan.id).toSet();
          _loans = [
            ..._loans,
            ...result.items.where((loan) => existing.add(loan.id)),
          ];
        }
        _totalItems = result.totalItems;
        _totals = result.totals;
        _nextPage = result.page + 1;
        _hasNext = result.hasNext;
        _errorMessage = null;
      });
    } on LoanServiceException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _applyFirstPage(AppLoanPage page) {
    _loans = page.items;
    _totalItems = page.totalItems;
    _totals = page.totals;
    _nextPage = page.page + 1;
    _hasNext = page.hasNext;
  }

  Future<void> _refreshSilently() async {
    if (!mounted || !widget.active || _refreshing || _loading) return;
    _refreshing = true;
    final int version = _requestVersion;
    final int loadedPages = _nextPage.clamp(1, 20);
    try {
      final List<AppLoanSummary> refreshed = [];
      AppLoanPage? firstPage;
      for (int page = 0; page < loadedPages; page++) {
        final AppLoanPage result = await _loanService.fetchLoans(
          query: _searchController.text,
          filters: _filters,
          page: page,
          size: _pageSize,
          force: true,
          tutorialMode: widget.tutorialMode,
        );
        firstPage ??= result;
        refreshed.addAll(result.items);
        if (!result.hasNext) break;
      }
      if (!mounted || version != _requestVersion || firstPage == null) return;
      final AppLoanPage refreshedFirstPage = firstPage;
      final Set<int> seen = {};
      setState(() {
        _loans = refreshed.where((loan) => seen.add(loan.id)).toList();
        _totalItems = refreshedFirstPage.totalItems;
        _totals = refreshedFirstPage.totals;
        _nextPage = (refreshed.length / _pageSize).ceil().clamp(1, 20);
        _hasNext = _loans.length < _totalItems;
      });
    } on LoanServiceException {
      // Mantém a última lista válida e tenta novamente no próximo ciclo.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadRegionOptions({bool force = false}) async {
    try {
      final List<AppRegionOption> options = await _regionService.fetchOptions(
        force: force,
        tutorialMode: widget.tutorialMode,
      );
      if (!mounted) return;
      setState(() {
        _regionOptions = widget.tutorialMode
            ? options
                  .where(
                    (region) => TutorialGuideController.isTutorialRegionName(
                      region.name,
                    ),
                  )
                  .toList(growable: false)
            : options;
      });
    } on RegionServiceException {
      // O filtro continua utilizável e tenta atualizar na próxima abertura.
    }
  }

  Future<AppLoanFilters> _loadTutorialFilters() async {
    try {
      await AuthService().beginTutorial();
      final List<AppRegionOption> options = await _regionService.fetchOptions(
        force: true,
        tutorialMode: true,
      );
      final List<AppRegionOption> tutorialRegions = options
          .where(
            (region) =>
                TutorialGuideController.isTutorialRegionName(region.name),
          )
          .toList(growable: false);
      if (mounted) setState(() => _regionOptions = tutorialRegions);
      return AppLoanFilters(
        regionIds: {tutorialRegions.isEmpty ? -1 : tutorialRegions.first.id},
      );
    } on AuthenticationException {
      return const AppLoanFilters(regionIds: {-1});
    } on RegionServiceException {
      return const AppLoanFilters(regionIds: {-1});
    }
  }

  Future<void> _openFilters() async {
    if (widget.tutorialMode) return;
    await _loadRegionOptions(force: true);
    if (!mounted) return;
    final AppLoanFilters? selected = await showLoanFilterPanel(
      context: context,
      initial: _filters,
      regions: _regionOptions,
    );
    if (selected == null || !mounted) return;
    setState(() => _filters = selected);
    await _saveFilters(selected);
    if (!mounted) return;
    _load(reset: true, force: true);
  }

  Future<AppLoanFilters> _loadSavedFilters() async {
    try {
      final int? userId = AuthService().currentSession?.userId;
      if (userId == null) return const AppLoanFilters();
      final Map<String, dynamic>? data = await _preferencesService
          .getUserFilters(scope: 'loans', userId: userId);
      if (data == null) return const AppLoanFilters();
      final Set<String> statuses = ((data['statuses'] as List?) ?? const [])
          .map((item) => '$item')
          .where(appLoanStatuses.contains)
          .toSet();
      final Set<int> regionIds = ((data['regionIds'] as List?) ?? const [])
          .map((item) => int.tryParse('$item'))
          .whereType<int>()
          .toSet();
      return AppLoanFilters(
        statuses: Set<String>.unmodifiable(statuses),
        regionIds: Set<int>.unmodifiable(regionIds),
        startDate: DateTime.tryParse('${data['startDate'] ?? ''}'),
        endDate: DateTime.tryParse('${data['endDate'] ?? ''}'),
      );
    } on Object {
      return const AppLoanFilters();
    }
  }

  Future<void> _saveFilters(AppLoanFilters filters) async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'loans',
      userId: userId,
      filters: {
        'statuses': filters.statuses.toList(growable: false),
        'regionIds': filters.regionIds.toList(growable: false),
        'startDate': filters.startDate?.toIso8601String(),
        'endDate': filters.endDate?.toIso8601String(),
      },
    );
  }

  Future<bool> _loadDesktopListPreference() async {
    try {
      final int? userId = AuthService().currentSession?.userId;
      if (userId == null) return false;
      final Map<String, dynamic>? data = await _preferencesService
          .getUserFilters(scope: 'loans_layout', userId: userId);
      return data?['desktopList'] == true;
    } on Object {
      return false;
    }
  }

  void _toggleDesktopListMode() {
    final bool listMode = !_desktopListMode;
    setState(() => _desktopListMode = listMode);
    unawaited(_saveDesktopListPreference(listMode));
  }

  Future<void> _saveDesktopListPreference(bool listMode) async {
    final int? userId = AuthService().currentSession?.userId;
    if (userId == null) return;
    await _preferencesService.saveUserFilters(
      scope: 'loans_layout',
      userId: userId,
      filters: {'desktopList': listMode},
    );
  }

  void _onSearchChanged(String value) {
    // Invalida imediatamente uma resposta da pesquisa anterior, mas mantém a
    // digitação independente da reconstrução da lista de empréstimos.
    _requestVersion++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _searchDebounce?.cancel();
    _load(reset: true);
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 420) {
      _load(reset: false);
    }
  }

  void _handleNetworkChanged() {
    if (NetworkStatusService().isOnline && widget.active) {
      unawaited(_refreshSilently());
    }
  }

  Future<void> _confirmExport() async {
    await showAppExcelExportFlow(
      context: context,
      title: 'Exportar empréstimos',
      confirmationMessage: 'Deseja exportar os empréstimos em Excel considerando a pesquisa e os filtros atuais?',
      generate: (onProgress) async {
        try {
          onProgress(.02, 'Buscando os empréstimos filtrados...');
          final List<AppLoanSummary> loans = await _loanService
              .fetchLoansForExport(
                query: _searchController.text,
                filters: _filters,
                tutorialMode: widget.tutorialMode,
                onProgress: (value) => onProgress(
                  .02 + (value * .48),
                  'Recebendo dados dos empréstimos...',
                ),
              );
          if (loans.isEmpty) {
            throw const AppExcelExportException(
              'Nenhum empréstimo foi encontrado para exportar.',
            );
          }
          final AppLoanExcelFile file = await LoanExcelExportService().create(
            loans,
            onProgress: (value, status) =>
                onProgress(.50 + (value * .50), status),
          );
          return AppGeneratedExcelFile(
            bytes: file.bytes,
            fileName: file.fileName,
            successMessage: '${loans.length} empréstimo(s) exportado(s).',
          );
        } on LoanServiceException catch (error) {
          throw AppExcelExportException(error.message);
        }
      },
    );
  }

  Future<void> _confirmAndOpenLoan(AppLoanSummary loan) async {
    if (loan.status.trim().toLowerCase() == 'pendente aprovação') {
      await showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Aguardando aprovação'),
          content: const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text('Empréstimo aguardando aprovação do administrador.'),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    final bool open =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Abrir empréstimo?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Deseja abrir o contrato #${loan.id} de ${loan.clientName}?',
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
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Abrir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!open || !mounted) return;
    final bool? changed = await openLoanDetailScreen(
      context: context,
      loanId: loan.id,
    );
    if (changed == true && mounted) {
      await _load(reset: true, force: true);
    }
  }
}

class _LoansPageHeader extends StatelessWidget {
  final int totalItems;
  final VoidCallback? onExport;
  final VoidCallback? onNewLoan;
  final Key? newLoanButtonKey;

  const _LoansPageHeader({
    required this.totalItems,
    this.onExport,
    this.onNewLoan,
    this.newLoanButtonKey,
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
                'Gestão de empréstimos',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$totalItems empréstimo(s) encontrado(s)',
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
        if (onNewLoan != null)
          FilledButton(
            key: newLoanButtonKey,
            onPressed: onNewLoan,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'NOVO EMPRÉSTIMO',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _LoanSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _LoanSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_LoanSearchField> createState() => _LoanSearchFieldState();
}

class _LoanSearchFieldState extends State<_LoanSearchField> {
  late bool _showClearButton;

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _LoanSearchField oldWidget) {
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
      height: 47,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Pesquisar contrato ou cliente',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 21,
            color: context.colors.primary,
          ),
          suffixIcon: !_showClearButton
              ? null
              : IconButton(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
          filled: true,
          fillColor: context.colors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: context.colors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: context.colors.primary, width: 1.3),
          ),
        ),
      ),
    );
  }
}

class _LoanFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const _LoanFilterButton({required this.activeCount, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: activeCount > 0,
      label: Text('$activeCount'),
      backgroundColor: context.colors.secondary,
      child: SizedBox.square(
        dimension: 47,
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: context.colors.divider),
          ),
          child: IconButton(
            onPressed: onPressed,
            tooltip: 'Filtrar empréstimos',
            icon: Icon(
              Icons.tune_rounded,
              color: context.colors.primary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoanViewModeButton extends StatelessWidget {
  final bool listMode;
  final VoidCallback onPressed;

  const _LoanViewModeButton({required this.listMode, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 47,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: context.colors.divider),
        ),
        child: IconButton(
          key: const ValueKey('loan_view_mode_button'),
          onPressed: onPressed,
          tooltip: listMode ? 'Exibir em grade' : 'Exibir em lista',
          icon: _LoanViewModeGlyph(
            showGrid: listMode,
            color: context.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _LoanViewModeGlyph extends StatelessWidget {
  final bool showGrid;
  final Color color;

  const _LoanViewModeGlyph({required this.showGrid, required this.color});

  @override
  Widget build(BuildContext context) {
    if (showGrid) {
      return SizedBox.square(
        dimension: 20,
        child: Wrap(
          spacing: 3,
          runSpacing: 3,
          children: List.generate(
            4,
            (_) => Container(
              width: 8.5,
              height: 8.5,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 21,
      height: 19,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          3,
          (_) => Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1),
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

class _AppliedLoanFilters extends StatelessWidget {
  final AppLoanFilters filters;

  const _AppliedLoanFilters({required this.filters});

  @override
  Widget build(BuildContext context) {
    final DateFormat date = DateFormat('dd/MM/yyyy');
    final List<String> labels = [
      if (filters.startDate != null || filters.endDate != null)
        '${filters.startDate == null ? 'Início' : date.format(filters.startDate!)} até '
            '${filters.endDate == null ? 'Hoje' : date.format(filters.endDate!)}',
      if (filters.statuses.isNotEmpty)
        '${filters.statuses.length} status selecionado(s)',
      if (filters.regionIds.isNotEmpty)
        '${filters.regionIds.length} região(ões)',
    ];
    return Row(
      children: [
        Icon(
          Icons.filter_alt_outlined,
          size: 14,
          color: context.colors.primary,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            labels.join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopLoanListCard extends StatelessWidget {
  final AppLoanSummary loan;
  final int position;
  final VoidCallback onTap;

  const _DesktopLoanListCard({
    required this.loan,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _loanStatusColor(loan);
    final bool dark = context.isDark;
    final Color cardColor = Color.alphaBlend(
      statusColor.withValues(alpha: dark ? .24 : .18),
      context.colors.surface,
    );
    final Color edgeColor = statusColor.computeLuminance() > .96
        ? context.colors.divider
        : statusColor;
    final Color leadingEdgeColor = statusColor.computeLuminance() > .96
        ? edgeColor
        : _strongLoanStatusEdgeColor(edgeColor);
    final Color accentColor = statusColor.computeLuminance() > .96
        ? _readableLoanStatusColor(context, statusColor)
        : leadingEdgeColor;
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    final String dueDate = loan.nextDueDate == null
        ? 'Não definida'
        : DateFormat('dd/MM/yyyy').format(loan.nextDueDate!);

    return SizedBox(
      height: 88,
      child: Material(
        color: cardColor,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: dark ? .24 : .10),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: edgeColor.withValues(alpha: .72)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 6, color: leadingEdgeColor),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(13, 7, 10, 7),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: accentColor.withValues(alpha: .38),
                        ),
                      ),
                      child: Text(
                        '$position',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 28,
                      child: _DesktopLoanClientIdentity(
                        loan: loan,
                        accentColor: accentColor,
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 15,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _DesktopLoanLabel('Contrato'),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  '#${loan.id}',
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: _LoanStatusChip(
                                    status: loan.status,
                                    color: accentColor,
                                  ),
                                ),
                                if (loan.showPendingPix) ...[
                                  const SizedBox(width: 5),
                                  const _PendingPixIcon(),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 14,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _DesktopLoanLabel('Próx. venc.'),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: 13,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    dueDate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 11,
                      child: _DesktopLoanMetric(
                        icon: Icons.handshake_outlined,
                        label: loan.negotiated ? 'Negociado' : 'Emprestado',
                        value: currency.format(loan.loanedAmount),
                        color: accentColor,
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 11,
                      child: _DesktopLoanMetric(
                        icon: Icons.payments_outlined,
                        label: 'Recebido',
                        value: currency.format(loan.receivedAmount),
                        color: accentColor,
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 11,
                      child: _DesktopLoanMetric(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'A receber',
                        value: currency.format(loan.receivableAmount),
                        color: accentColor,
                      ),
                    ),
                    _DesktopLoanDivider(color: accentColor),
                    Expanded(
                      flex: 11,
                      child: _DesktopLoanMetric(
                        icon: Icons.bar_chart_rounded,
                        label: 'Lucro',
                        value: currency.format(loan.profitAmount),
                        color: accentColor,
                      ),
                    ),
                    Expanded(
                      flex: 8,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            loan.paymentType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
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

class _DesktopLoanClientIdentity extends StatelessWidget {
  final AppLoanSummary loan;
  final Color accentColor;

  const _DesktopLoanClientIdentity({
    required this.loan,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final String city = loan.cityName?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loan.clientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 12, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  loan.regionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (city.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: Text(
                city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 8.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopLoanMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DesktopLoanMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 8.2,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopLoanLabel extends StatelessWidget {
  final String text;

  const _DesktopLoanLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: context.colors.textSecondary, fontSize: 8.2),
  );
}

class _DesktopLoanDivider extends StatelessWidget {
  final Color color;

  const _DesktopLoanDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 56, color: color.withValues(alpha: .18));
}

class _LoanCard extends StatelessWidget {
  final AppLoanSummary loan;
  final int position;
  final VoidCallback onTap;

  const _LoanCard({
    required this.loan,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _loanStatusColor(loan);
    final bool dark = context.isDark;
    final Color cardColor = Color.alphaBlend(
      statusColor.withValues(alpha: dark ? .24 : .18),
      context.colors.surface,
    );
    final Color edgeColor = statusColor.computeLuminance() > .96
        ? context.colors.divider
        : statusColor;
    final Color leadingEdgeColor = statusColor.computeLuminance() > .96
        ? edgeColor
        : _strongLoanStatusEdgeColor(edgeColor);
    final Color accentColor = statusColor.computeLuminance() > .96
        ? _readableLoanStatusColor(context, statusColor)
        : leadingEdgeColor;
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 520;
        final bool horizontalOverview = constraints.maxWidth >= 330;
        return Material(
          color: cardColor,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: dark ? .24 : .10),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: edgeColor.withValues(alpha: .72)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 6, color: leadingEdgeColor),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 16 : 13,
                    wide ? 13 : 10,
                    wide ? 14 : 12,
                    wide ? 13 : 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LoanCardHeader(
                        loan: loan,
                        position: position,
                        accentColor: accentColor,
                        wide: wide,
                      ),
                      SizedBox(height: wide ? 10 : 8),
                      _LoanCardOverview(
                        loan: loan,
                        accentColor: accentColor,
                        wide: horizontalOverview,
                      ),
                      SizedBox(height: wide ? 10 : 8),
                      _LoanMetricsPanel(
                        loan: loan,
                        currency: currency,
                        accentColor: accentColor,
                        wide: wide,
                      ),
                    ],
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

class _LoanCardHeader extends StatelessWidget {
  final AppLoanSummary loan;
  final int position;
  final Color accentColor;
  final bool wide;

  const _LoanCardHeader({
    required this.loan,
    required this.position,
    required this.accentColor,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final String region = loan.regionName.trim();
    final String city = loan.cityName?.trim() ?? '';
    return SizedBox(
      height: wide ? 58 : 54,
      child: Row(
        children: [
          Container(
            width: wide ? 46 : 40,
            height: wide ? 46 : 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withValues(alpha: .38)),
            ),
            child: Text(
              '$position',
              style: TextStyle(
                color: accentColor,
                fontSize: wide ? 20 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: wide ? 11 : 9),
          Container(
            width: 1,
            height: 34,
            color: accentColor.withValues(alpha: .24),
          ),
          SizedBox(width: wide ? 11 : 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: wide ? 13 : 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (region.isNotEmpty || city.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: accentColor,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (region.isNotEmpty)
                              Text(
                                region,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (city.isNotEmpty)
                              Text(
                                city,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 9,
                                ),
                              ),
                          ],
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
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 10 : 8,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              loan.paymentType,
              style: TextStyle(
                color: accentColor,
                fontSize: wide ? 10 : 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoanCardOverview extends StatelessWidget {
  final AppLoanSummary loan;
  final Color accentColor;
  final bool wide;

  const _LoanCardOverview({
    required this.loan,
    required this.accentColor,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final String dueDate = loan.nextDueDate == null
        ? 'Não definida'
        : DateFormat('dd/MM/yyyy').format(loan.nextDueDate!);
    final Widget contractStatus = _LoanContractStatus(
      loanId: loan.id,
      status: loan.status,
      color: accentColor,
      showPendingPix: loan.showPendingPix,
    );
    final Widget due = _LoanOverviewValue(
      label: 'Próx. venc.',
      value: dueDate,
      icon: Icons.calendar_month_outlined,
      iconColor: accentColor,
      alignEnd: true,
    );

    if (wide) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final bool compact = constraints.maxWidth < 390;
          return SizedBox(
            height: 47,
            child: Row(
              children: [
                Expanded(child: contractStatus),
                const SizedBox(width: 8),
                SizedBox(width: compact ? 100 : 118, child: due),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      height: 47,
      child: Row(
        children: [
          Expanded(child: contractStatus),
          const SizedBox(width: 6),
          SizedBox(width: 94, child: due),
        ],
      ),
    );
  }
}

class _LoanContractStatus extends StatelessWidget {
  final int loanId;
  final String status;
  final Color color;
  final bool showPendingPix;

  const _LoanContractStatus({
    required this.loanId,
    required this.status,
    required this.color,
    required this.showPendingPix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contrato',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 8.5),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              '#$loanId',
              maxLines: 1,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: _LoanStatusChip(status: status, color: color),
            ),
            if (showPendingPix) ...[
              const SizedBox(width: 5),
              const _PendingPixIcon(),
            ],
          ],
        ),
      ],
    );
  }
}

class _PendingPixIcon extends StatelessWidget {
  const _PendingPixIcon();

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'PIX aguardando pagamento',
    child: Semantics(
      label: 'PIX aguardando pagamento',
      image: true,
      child: Image.asset(
        'assets/icons/pix.png',
        width: 16,
        height: 16,
        filterQuality: FilterQuality.high,
      ),
    ),
  );
}

class _LoanOverviewValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final bool alignEnd;

  const _LoanOverviewValue({
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
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
              Icon(
                icon,
                size: 14,
                color: iconColor ?? context.colors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                value,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textPrimary,
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

class _LoanStatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _LoanStatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LoanMetricsPanel extends StatelessWidget {
  final AppLoanSummary loan;
  final NumberFormat currency;
  final Color accentColor;
  final bool wide;

  const _LoanMetricsPanel({
    required this.loan,
    required this.currency,
    required this.accentColor,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> metrics = [
      _LoanMetric(
        icon: Icons.handshake_outlined,
        label: loan.negotiated ? 'Negociado' : 'Emprestado',
        value: currency.format(loan.loanedAmount),
        color: accentColor,
      ),
      _LoanMetric(
        icon: Icons.payments_outlined,
        label: 'Recebido',
        value: currency.format(loan.receivedAmount),
        color: accentColor,
      ),
      _LoanMetric(
        icon: Icons.account_balance_wallet_outlined,
        label: 'A receber',
        value: currency.format(loan.receivableAmount),
        color: accentColor,
      ),
      _LoanMetric(
        icon: Icons.bar_chart_rounded,
        label: 'Lucro',
        value: currency.format(loan.profitAmount),
        color: accentColor,
      ),
    ];
    final Color divider = accentColor.withValues(alpha: .16);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 5 : 4,
        vertical: wide ? 7 : 5,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(
          alpha: context.isDark ? .44 : .68,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accentColor.withValues(alpha: .16)),
      ),
      child: SizedBox(
        height: wide ? 67 : 58,
        child: Row(
          children: [
            for (int index = 0; index < metrics.length; index++) ...[
              Expanded(child: metrics[index]),
              if (index < metrics.length - 1)
                Container(width: 1, height: wide ? 48 : 42, color: divider),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoanMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _LoanMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 8.5),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _LoanTotalsBar extends StatelessWidget {
  final AppLoanTotals totals;
  final bool compact;

  const _LoanTotalsBar({required this.totals, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final NumberFormat currency = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );
    return Material(
      color: context.colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: compact ? BorderRadius.zero : BorderRadius.circular(13),
        side: BorderSide(color: context.colors.divider),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 16,
          vertical: compact ? 12 : 11,
        ),
        child: Row(
          children: [
            _LoanTotalMetric(
              label: 'Recebido',
              value: currency.format(totals.receivedAmount),
              color: const Color(0xFF249B67),
            ),
            _LoanTotalMetric(
              label: 'A receber',
              value: currency.format(totals.receivableAmount),
              color: context.colors.textPrimary,
            ),
            _LoanTotalMetric(
              label: 'Lucro',
              value: currency.format(totals.profitAmount),
              color: const Color(0xFF496FB5),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanTotalMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LoanTotalMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoansMessage extends StatelessWidget {
  final IconData? icon;
  final String? svgIcon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _LoansMessage({
    this.icon,
    this.svgIcon,
    required this.title,
    required this.message,
    this.onRetry,
  }) : assert(icon != null || svgIcon != null);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (svgIcon != null)
              SvgIcon(
                icon: svgIcon!,
                width: 46,
                height: 46,
                color: context.colors.primary,
              )
            else
              Icon(icon, size: 46, color: context.colors.primary),
            const SizedBox(height: 9),
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
                fontSize: 12,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 11),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<AppLoanFilters?> showLoanFilterPanel({
  required BuildContext context,
  required AppLoanFilters initial,
  required List<AppRegionOption> regions,
}) {
  final double screenWidth = MediaQuery.sizeOf(context).width;
  final bool compact = screenWidth < 600;
  return showAppSideDrawer<AppLoanFilters>(
    context: context,
    maxWidth: compact ? screenWidth * appMobileFilterDrawerWidthFactor : 410,
    barrierDismissible: compact,
    builder: (_) => _LoanFilterPanel(initial: initial, regions: regions),
  );
}

class _LoanFilterPanel extends StatefulWidget {
  final AppLoanFilters initial;
  final List<AppRegionOption> regions;

  const _LoanFilterPanel({required this.initial, required this.regions});

  @override
  State<_LoanFilterPanel> createState() => _LoanFilterPanelState();
}

class _LoanFilterPanelState extends State<_LoanFilterPanel> {
  late final Set<String> _statuses;
  late final Set<int> _regionIds;
  late DateTime? _startDate = widget.initial.startDate;
  late DateTime? _endDate = widget.initial.endDate;

  @override
  void initState() {
    super.initState();
    final Set<String> availableStatuses = appLoanStatuses.toSet();
    _statuses = widget.initial.statuses
        .where(availableStatuses.contains)
        .toSet();
    final Set<int> availableRegionIds = _allRegionIds;
    _regionIds = widget.initial.regionIds
        .where(availableRegionIds.contains)
        .toSet();
  }

  Set<int> get _allRegionIds =>
      widget.regions.map((region) => region.id).toSet();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 18,
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPanelHeader(
                title: 'Filtros de empréstimos',
                subtitle: 'Informe os filtros para a consulta.',
                icon: Icons.tune_rounded,
                compact: MediaQuery.sizeOf(context).width < 600,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                                color:
                                                    context.colors.textPrimary,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Toque para escolher as regiões',
                                              style: TextStyle(
                                                color: context
                                                    .colors
                                                    .textSecondary,
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
                        title: 'Status',
                        icon: Icons.fact_check_outlined,
                        child: Column(
                          children: [
                            for (final String status in appLoanStatuses)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                  color: _statuses.contains(status)
                                      ? context.colors.primary.withValues(
                                          alpha: .07,
                                        )
                                      : context.colors.surface,
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: _statuses.contains(status)
                                          ? context.colors.primary.withValues(
                                              alpha: .28,
                                            )
                                          : context.colors.divider.withValues(
                                              alpha: .75,
                                            ),
                                    ),
                                  ),
                                  child: CheckboxListTile(
                                    value: _statuses.contains(status),
                                    onChanged: (selected) =>
                                        _toggleStatus(status, selected == true),
                                    dense: true,
                                    visualDensity: const VisualDensity(
                                      horizontal: -3,
                                      vertical: -3,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    activeColor: context.colors.primary,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    title: Row(
                                      children: [
                                        Container(
                                          key: ValueKey(
                                            'loan_status_color_$status',
                                          ),
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: _loanStatusFilterColor(
                                              status,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: context
                                                  .colors
                                                  .textSecondary
                                                  .withValues(alpha: .35),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              color: context.colors.textPrimary,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                      AppFilterSectionCard(
                        title: 'Período dos contratos quitados',
                        icon: Icons.date_range_outlined,
                        child: Column(
                          children: [
                            _LoanDateField(
                              label: 'Data inicial',
                              value: _startDate,
                              onTap: () => _selectDate(start: true),
                            ),
                            const SizedBox(height: 7),
                            _LoanDateField(
                              label: 'Data final',
                              value: _endDate,
                              onTap: () => _selectDate(start: false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
      AppRegionOption? region;
      for (final AppRegionOption item in widget.regions) {
        if (item.id == selectedId) {
          region = item;
          break;
        }
      }
      return region?.name ?? 'Região #$selectedId';
    }
    return '${_regionIds.length} regiões selecionadas';
  }

  Future<void> _openRegionPicker() async {
    final Set<int>? selected = await showAppDialog<Set<int>>(
      context: context,
      title: 'Selecionar regiões',
      subtitle: 'Marque as regiões que deseja consultar.',
      icon: Icons.location_on_outlined,
      maxWidth: 560,
      maxHeight: 640,
      builder: (_) =>
          _LoanRegionPicker(regions: widget.regions, selected: _regionIds),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _regionIds
        ..clear()
        ..addAll(selected);
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
          ? 'Escolha o início do período dos contratos quitados.'
          : 'Escolha o fim do período dos contratos quitados.',
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

  void _clear() {
    setState(() {
      _statuses.clear();
      _regionIds.clear();
      _startDate = null;
      _endDate = null;
    });
  }

  void _toggleStatus(String status, bool selected) {
    setState(() {
      if (selected) {
        _statuses.add(status);
      } else {
        _statuses.remove(status);
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
      AppLoanFilters(
        statuses: Set<String>.unmodifiable(_statuses),
        regionIds: Set<int>.unmodifiable(_regionIds),
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }
}

class _LoanRegionPicker extends StatefulWidget {
  final List<AppRegionOption> regions;
  final Set<int> selected;

  const _LoanRegionPicker({required this.regions, required this.selected});

  @override
  State<_LoanRegionPicker> createState() => _LoanRegionPickerState();
}

class _LoanRegionPickerState extends State<_LoanRegionPicker> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<int> _selected = Set<int>.from(widget.selected);
  String _query = '';

  List<AppRegionOption> get _visibleRegions {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.regions;
    return widget.regions
        .where(
          (region) =>
              region.name.toLowerCase().contains(query) ||
              '${region.id}'.contains(query),
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
    final List<AppRegionOption> visibleRegions = _visibleRegions;
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
                        ? 'Nenhuma marcada: serão exibidas todas'
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
                child: widget.regions.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhuma região disponível.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      )
                    : visibleRegions.isEmpty
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
                        itemCount: visibleRegions.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 43,
                          color: context.colors.divider.withValues(alpha: .55),
                        ),
                        itemBuilder: (context, index) {
                          final AppRegionOption region = visibleRegions[index];
                          final bool selected = _selected.contains(region.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(region.id);
                              } else {
                                _selected.remove(region.id);
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
                              region.name.isEmpty
                                  ? 'Região #${region.id}'
                                  : region.name,
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

class _LoanDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _LoanDateField({
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
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    value == null
                        ? 'Não definida'
                        : DateFormat('dd/MM/yyyy').format(value!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
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

Color _parseHexColor(String value) {
  final String hex = value.replaceAll('#', '').trim();
  if (hex.length != 6) return Colors.white;
  final int? parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? Colors.white : Color(0xFF000000 | parsed);
}

Color _loanStatusColor(AppLoanSummary loan) =>
    _increaseLoanStatusSaturation(_parseHexColor(loan.statusColor));

const Color _loanStatusGreen = Color(0xFF68D978);
const Color _loanStatusBlue = Color(0xFF6BBFDF);
const Color _loanStatusYellow = Color(0xFFF1D83F);
const Color _loanStatusPurple = Color(0xFFB46FE2);
const Color _loanStatusTurquoise = Color(0xFF2FCABB);

Color _loanStatusFilterColor(String status) => switch (status) {
  'Pendente Aprovação' ||
  'Lançamento' ||
  'Vence hoje' ||
  'Cancelado' => Colors.white,
  'Em dia' || 'Refinanciado' => _loanStatusGreen,
  'Desaparecido' => const Color(0xFFF03E46),
  'Em atraso' => const Color(0xFFF57575),
  'Quitado' || 'Renov/Abat' => _loanStatusPurple,
  _ => Colors.white,
};

Color _increaseLoanStatusSaturation(Color color) {
  if (color.computeLuminance() > .97) return color;
  final int value = color.toARGB32();
  if (value == const Color(0xFFAAF0B1).toARGB32()) return _loanStatusGreen;
  if (value == const Color(0xFFADD8E6).toARGB32()) return _loanStatusBlue;
  if (value == const Color(0xFFFCF883).toARGB32()) return _loanStatusYellow;
  if (value == const Color(0xFFCEAAF0).toARGB32()) return _loanStatusPurple;
  if (value == const Color(0xFF40E0D0).toARGB32()) {
    return _loanStatusTurquoise;
  }
  final HSLColor hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation((hsl.saturation * 1.18).clamp(0.0, 1.0))
      .withLightness((hsl.lightness - .035).clamp(0.0, 1.0))
      .toColor();
}

Color _strongLoanStatusEdgeColor(Color color) {
  if (color.computeLuminance() > .96) return color;
  return Color.alphaBlend(Colors.black.withValues(alpha: .18), color);
}

Color _readableLoanStatusColor(BuildContext context, Color statusColor) {
  final double luminance = statusColor.computeLuminance();
  if (luminance > .96) return context.colors.textSecondary;
  if (!context.isDark && luminance > .55) {
    return Color.alphaBlend(Colors.black.withValues(alpha: .34), statusColor);
  }
  return statusColor;
}
