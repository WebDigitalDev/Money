import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:money/money.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

final NumberFormat _loanCurrencyFormatter = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
);
final NumberFormat _loanPlainMoneyFormatter = NumberFormat('0.00', 'pt_BR');
final DateFormat _loanDateFormatter = DateFormat('dd/MM/yyyy');
final DateFormat _loanDateTimeFormatter = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat _loanIsoDateFormatter = DateFormat('yyyy-MM-dd');

@visibleForTesting
double suggestedInstallmentPaymentAmount(AppLoanDetail loan) {
  if (loan.installmentAmount > 0) return loan.installmentAmount;
  if (loan.installmentCount <= 0) return 0;
  final double total =
      loan.loanedAmount + loan.interestAmount - loan.discountAmount;
  if (!total.isFinite || total <= 0) return 0;
  return double.parse((total / loan.installmentCount).toStringAsFixed(2));
}

Future<bool?> openLoanDetailScreen({
  required BuildContext context,
  int? loanId,
  int? clientId,
  String? clientName,
  int? regionId,
  String? regionName,
  ValueChanged<int>? onOpenClient,
}) {
  assert(
    loanId != null ||
        (clientId != null &&
            clientName != null &&
            regionId != null &&
            regionName != null),
  );

  final ValueChanged<int>? clientNavigation =
      onOpenClient ?? AppSidebarScope.maybeOf(context)?.openClient;

  Widget buildScreen() => loanId != null
      ? LoanDetailScreen(loanId: loanId, onOpenClient: clientNavigation)
      : LoanDetailScreen.newLoan(
          clientId: clientId!,
          clientName: clientName!,
          regionId: regionId!,
          regionName: regionName!,
          onOpenClient: clientNavigation,
        );

  final Size screenSize = MediaQuery.sizeOf(context);
  if (kIsWeb && screenSize.width >= 1024) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: math.min(980, screenSize.width - 80),
          height: math.min(760, screenSize.height - 80),
          child: buildScreen(),
        ),
      ),
    );
  }

  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => buildScreen(),
    ),
  );
}

class LoanDetailScreen extends StatefulWidget {
  final int? loanId;
  final int? clientId;
  final String? clientName;
  final int? regionId;
  final String? regionName;
  final ValueChanged<int>? onOpenClient;

  const LoanDetailScreen({super.key, required this.loanId, this.onOpenClient})
    : clientId = null,
      clientName = null,
      regionId = null,
      regionName = null,
      assert(loanId != null);

  const LoanDetailScreen.newLoan({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.regionId,
    required this.regionName,
    this.onOpenClient,
  }) : loanId = null,
       assert(clientId != null),
       assert(clientName != null),
       assert(regionId != null),
       assert(regionName != null);

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen>
    with SingleTickerProviderStateMixin {
  final LoanService _service = LoanService();
  late final TabController _tabs;
  AppLoanDetail? _loan;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _didSave = false;
  int _activeTab = 0;
  bool _supplementalLoaded = false;
  bool _loadingSupplemental = false;
  bool _feedbacksLoaded = false;
  bool _loadingFeedbacks = false;
  bool _savingFeedback = false;
  List<AppLoanFeedback> _feedbacks = const [];

  final _contractDate = TextEditingController();
  final _firstDueDate = TextEditingController();
  final _installments = TextEditingController();
  final _loaned = TextEditingController();
  final _negotiated = TextEditingController();
  final _discount = TextEditingController();
  final _lateFee = TextEditingController();
  final _owner = TextEditingController();
  final _collateral = TextEditingController();
  final _notes = TextEditingController();
  String _paymentType = 'D';
  bool _missing = false;

  bool get _isNew => widget.loanId == null;

  static const Map<String, String> _paymentTypes = {
    'D': 'Diário',
    'S': 'Semanal',
    'Q': 'Quinzenal',
    'M': 'Mensal',
    'Z': 'Diário Seg-Sab',
    'A': 'Dia sim e Dia não',
    'B': 'Todo Sábado',
    'C': 'Todo Domingo',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this)
      ..addListener(_handleTabChanged);
    for (final controller in [
      _contractDate,
      _firstDueDate,
      _installments,
      _loaned,
      _negotiated,
      _discount,
      _lateFee,
      _owner,
      _collateral,
      _notes,
    ]) {
      controller.addListener(_refreshFormState);
    }
    if (_isNew) {
      _initializeDraft();
    } else {
      _load();
    }
  }

  void _initializeDraft() {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final AuthSession? session = AuthService().currentSession;
    final AppLoanDetail draft = AppLoanDetail(
      id: 0,
      clientId: widget.clientId!,
      clientName: widget.clientName!,
      regionId: widget.regionId!,
      regionName: widget.regionName!,
      contractDate: today,
      firstDueDate: today.add(const Duration(days: 1)),
      installmentCount: 1,
      notes: null,
      paymentTypeCode: 'D',
      paymentType: 'Diário',
      loanedAmount: 0,
      originalLoanAmount: 0,
      discountAmount: 0,
      interestAmount: 0,
      negotiatedAmount: 0,
      negotiatedOrigin: false,
      lateFeeAmount: 10,
      totalAmount: 0,
      installmentAmount: 0,
      receivedAmount: 0,
      receivableAmount: 0,
      profitAmount: 0,
      collateral: null,
      clientOwner: null,
      missing: false,
      active: true,
      refinanced: false,
      renewed: false,
      numericStatus: 1,
      status: 'Novo',
      approvalStatus: 'RASCUNHO',
      operationLocked: false,
      hasPendingPix: false,
      lockReason: null,
      canEdit: session?.administrator == true || session?.canEdit == true,
      administrator: session?.administrator == true,
      installments: const [],
      history: const [],
      approvals: const [],
      origins: const [],
    );
    _loan = draft;
    _loading = false;
    _fill(draft);
  }

  void _handleTabChanged() {
    if (_tabs.index == _activeTab || !mounted) return;
    setState(() => _activeTab = _tabs.index);
    if (_tabs.index == 2 || _tabs.index == 3) {
      unawaited(_loadSupplemental());
    } else if (_tabs.index == 4) {
      unawaited(_loadFeedbacks());
    }
  }

  void _refreshFormState() {
    if (mounted && _loan != null) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final controller in [
      _contractDate,
      _firstDueDate,
      _installments,
      _loaned,
      _negotiated,
      _discount,
      _lateFee,
      _owner,
      _collateral,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLoanDetail? loan = _loan;
    final bool desktopModal =
        kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    final bool showTotals =
        loan != null && !_loading && (_activeTab == 0 || _activeTab == 1);
    final Widget? totalsFooter = showTotals
        ? _LoanTotalsFooter(
            installmentView: _activeTab == 1,
            installmentAmount: _draftInstallmentAmount(loan),
            totalAmount: _draftTotalAmount(loan),
            overdueAmount: loan.installments.fold<double>(
              0,
              (total, item) => total + item.overdueAmount,
            ),
            overdueWithInterest: loan.installments.fold<double>(
              0,
              (total, item) =>
                  total + item.overdueAmount + item.overdueInterestAmount,
            ),
            safeBottom: false,
          )
        : null;
    final Widget? bottomBar = loan == null || _loading
        ? null
        : _isNew
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?totalsFooter,
              _NewLoanActionBar(
                saving: _saving,
                canSave: loan.canEdit,
                onSave: _saveNewLoan,
                onCancel: _closeScreen,
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?totalsFooter,
              _ExistingLoanActionBar(
                saving: _saving,
                hasChanges:
                    loan.canEdit &&
                    !loan.operationLocked &&
                    _hasLoanChanges(loan),
                onSave: _saveExistingLoan,
                onBack: _closeScreen,
              ),
            ],
          );
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeScreen());
      },
      child: Scaffold(
        backgroundColor: Color.alphaBlend(
          context.colors.surface.withValues(alpha: 0.68),
          context.colors.background,
        ),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: 62,
          backgroundColor: context.colors.surface,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leading: desktopModal
              ? IconButton(
                  onPressed: _saving || _closing ? null : _closeScreen,
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          titleSpacing: desktopModal ? 0 : 16,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isNew
                    ? 'Novo Empréstimo'
                    : loan == null
                    ? 'Empréstimo'
                    : 'Empréstimo #${loan.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (loan != null && !_isNew)
                Text(
                  loan.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
            ],
          ),
          actions: [
            if (loan != null && !_isNew)
              PopupMenuButton<String>(
                enabled: !_saving,
                onSelected: _handleAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'client',
                    child: _MenuLabel(
                      Icons.person_outline_rounded,
                      'Abrir cliente',
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (_canGeneratePix(loan))
                    const PopupMenuItem(
                      value: 'pix',
                      child: _MenuLabel(Icons.qr_code_2_rounded, 'Gerar PIX'),
                    ),
                  if (loan.hasPendingPix)
                    const PopupMenuItem(
                      value: 'cancel-pix',
                      child: _MenuLabel(
                        Icons.cancel_outlined,
                        'Cancelar PIX aguardando',
                      ),
                    ),
                  if (loan.canEdit && !loan.operationLocked) ...[
                    const PopupMenuItem(
                      value: 'payment',
                      child: _MenuLabel(
                        Icons.payments_outlined,
                        'Lançar pagamento',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'installment-payment',
                      child: _MenuLabel(
                        Icons.receipt_long_outlined,
                        'Pagamento parcela',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'interest-roll',
                      child: _MenuLabel(
                        Icons.update_rounded,
                        'Baixar só juros',
                      ),
                    ),
                    if (!loan.hasPendingPix) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'refinance',
                        child: _MenuLabel(
                          Icons.autorenew_rounded,
                          'Refinanciar',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'renew',
                        child: _MenuLabel(Icons.update_rounded, 'Renovar'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'cancel',
                        child: _MenuLabel(
                          Icons.block_rounded,
                          'Cancelar contrato',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'finish',
                        child: _MenuLabel(
                          Icons.delete_outline_rounded,
                          'Finalizar contrato',
                        ),
                      ),
                    ],
                  ],
                  const PopupMenuItem(
                    value: 'message-contract',
                    child: _MenuLabel(Icons.message_outlined, 'Gerar mensagem'),
                  ),
                  const PopupMenuItem(
                    value: 'message-debt',
                    child: _MenuLabel(
                      Icons.request_quote_outlined,
                      'Gerar mensagem da dívida',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: _MenuLabel(Icons.refresh_rounded, 'Atualizar'),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(top: false, child: _buildBody()),
        bottomNavigationBar: bottomBar,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (_error != null || _loan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 46,
                color: context.colors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Empréstimo não encontrado.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
    final loan = _loan!;
    return Column(
      children: [
        Material(
          color: context.colors.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: context.colors.primary,
            labelColor: context.colors.primary,
            unselectedLabelColor: context.colors.textSecondary,
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Identificação'),
              Tab(text: 'Parcelas'),
              Tab(text: 'Histórico'),
              Tab(text: 'Conferências'),
              Tab(text: 'Feedbacks'),
            ],
          ),
        ),
        if (loan.operationLocked)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF4D8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              loan.lockReason ?? 'Operação aguardando aprovação.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF7B5700),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (loan.hasPendingPix)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF4D8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: const Text(
              'Há um PIX aguardando pagamento. Refinanciamento, renovação, cancelamento e finalização estão bloqueados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7B5700),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _identificationTab(loan),
              _installmentsTab(loan),
              _historyTab(loan),
              _approvalsTab(loan),
              _feedbacksTab(loan),
            ],
          ),
        ),
      ],
    );
  }

  Widget _identificationTab(AppLoanDetail loan) {
    final bool enabled = loan.canEdit && !loan.operationLocked && !_saving;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool twoColumns = constraints.maxWidth >= 340;
        final bool roomy = constraints.maxWidth >= 900;
        final double fieldFontSize = roomy ? 15 : 14;
        final double gap = roomy ? 12 : 6;
        final double horizontalPadding = roomy ? 20 : 14;

        Widget pair(Widget first, Widget second) {
          if (!twoColumns) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                first,
                SizedBox(height: gap),
                second,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              SizedBox(width: gap),
              Expanded(child: second),
            ],
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            roomy ? 14 : 12,
            horizontalPadding,
            24,
          ),
          children: [
            _ReadOnlyValue(
              label: 'Status',
              value: loan.status,
              spacious: true,
              fontSize: fieldFontSize,
              loanFieldStyle: true,
            ),
            SizedBox(height: gap),
            pair(
              _DateField(
                label: 'Data do empréstimo',
                controller: _contractDate,
                enabled: enabled,
                spacious: true,
                fontSize: fieldFontSize,
                leadingIcon: true,
                loanFieldStyle: true,
                onTap: () => _pickDate(_contractDate),
              ),
              _DateField(
                label: 'Data do primeiro pagamento',
                controller: _firstDueDate,
                enabled: enabled,
                spacious: true,
                fontSize: fieldFontSize,
                leadingIcon: true,
                loanFieldStyle: true,
                onTap: () => _pickDate(_firstDueDate, preventPastDates: true),
              ),
            ),
            SizedBox(height: gap),
            pair(
              DropdownButtonFormField<String>(
                initialValue: _paymentTypes.containsKey(_paymentType)
                    ? _paymentType
                    : 'D',
                isExpanded: true,
                style: TextStyle(
                  color: enabled
                      ? context.colors.textPrimary
                      : context.colors.textPrimary.withValues(alpha: 0.42),
                  fontSize: fieldFontSize,
                  fontWeight: FontWeight.normal,
                ),
                decoration: _loanFieldDecoration(
                  context,
                  'Tipo de vencimento',
                  editable: enabled,
                  spacious: true,
                ),
                items: _paymentTypes.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: fieldFontSize),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: enabled
                    ? (value) => setState(() => _paymentType = value ?? 'D')
                    : null,
              ),
              _CompactField(
                label: 'Parcelas',
                controller: _installments,
                enabled: enabled,
                keyboardType: TextInputType.number,
                fontSize: fieldFontSize,
                spacious: true,
                loanFieldStyle: true,
              ),
            ),
            SizedBox(height: gap),
            pair(
              _MoneyField(
                label: 'Valor emprestado',
                controller: _loaned,
                enabled: enabled && !loan.negotiatedOrigin,
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
              _MoneyField(
                label: loan.negotiatedOrigin
                    ? 'Valor do Negociado'
                    : 'Valor Juros',
                controller: _negotiated,
                enabled: enabled,
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
            ),
            SizedBox(height: gap),
            pair(
              _MoneyField(
                label: 'Valor de desconto',
                controller: _discount,
                enabled: enabled,
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
              _ReadOnlyValue(
                label: 'Valor total',
                value: _currency(_draftTotalAmount(loan)),
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
            ),
            SizedBox(height: gap),
            pair(
              _MoneyField(
                label: 'Multa por atraso',
                controller: _lateFee,
                enabled: enabled,
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
              _ReadOnlyValue(
                label: 'Valor da parcela',
                value: _currency(_draftInstallmentAmount(loan)),
                spacious: true,
                fontSize: fieldFontSize,
                loanFieldStyle: true,
              ),
            ),
            SizedBox(height: gap),
            _ReadOnlyValue(
              label: 'Lucro',
              value: _currency(loan.profitAmount),
              spacious: true,
              fontSize: fieldFontSize,
              loanFieldStyle: true,
            ),
            SizedBox(height: gap),
            _CompactField(
              label: 'Observações',
              controller: _notes,
              enabled: enabled,
              maxLines: roomy ? 3 : 2,
              fontSize: fieldFontSize,
              spacious: true,
              loanFieldStyle: true,
            ),
            SizedBox(height: gap),
            _CompactField(
              label: 'Penhora',
              controller: _collateral,
              enabled: enabled,
              fontSize: fieldFontSize,
              spacious: true,
              loanFieldStyle: true,
            ),
            SizedBox(height: gap),
            _CompactField(
              label: 'Dono do cliente',
              controller: _owner,
              enabled: enabled,
              fontSize: fieldFontSize,
              spacious: true,
              loanFieldStyle: true,
            ),
            const SizedBox(height: 3),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                minLeadingWidth: 40,
                leading: Transform.scale(
                  scale: 0.75,
                  child: Switch.adaptive(
                    value: _missing,
                    onChanged: enabled
                        ? (value) => setState(() => _missing = value)
                        : null,
                    activeThumbColor: context.colors.primary,
                    activeTrackColor: context.colors.primary.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                title: Text(
                  'Cliente desaparecido?',
                  style: TextStyle(
                    fontSize: fieldFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _installmentsTab(AppLoanDetail loan) {
    if (loan.installments.isEmpty) {
      return const _EmptyTab(
        icon: Icons.event_busy_outlined,
        text: 'Nada encontrado',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const double horizontalListPadding = 16;
        final double cardWidth = constraints.maxWidth - horizontalListPadding;
        final bool wide = cardWidth >= 680;
        final bool veryCompact = cardWidth < 390;
        final double itemExtent = wide ? 136 : (veryCompact ? 110 : 120);
        final bool desktopWeb = kIsWeb && wide;
        final Widget list = ListView.builder(
          key: const ValueKey('loan_installments_list'),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
          itemExtent: itemExtent,
          scrollCacheExtent: ScrollCacheExtent.pixels(itemExtent * 5),
          addAutomaticKeepAlives: false,
          itemCount: loan.installments.length,
          itemBuilder: (_, index) {
            final installment = loan.installments[index];
            return _LegacyInstallmentCard(
              installment: installment,
              refinanced: loan.numericStatus == 3 || loan.refinanced,
              onTap: () => _openInstallment(installment),
            );
          },
        );
        if (desktopWeb) return list;
        return RefreshIndicator(
          color: context.colors.primary,
          onRefresh: _load,
          child: list,
        );
      },
    );
  }

  Widget _historyTab(AppLoanDetail loan) {
    if (_loadingSupplemental) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (loan.origins.isEmpty) {
      return const _EmptyTab(
        icon: Icons.history_toggle_off_rounded,
        text: 'Nada encontrado',
      );
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: context.colors.primary,
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
              itemCount: loan.origins.length,
              itemBuilder: (_, index) => _LegacyHistoryCard(
                origin: loan.origins[index],
                position: index + 1,
                onTap: () => _openHistoricalLoan(loan.origins[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _approvalsTab(AppLoanDetail loan) {
    if (_loadingSupplemental) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    if (loan.approvals.isEmpty) {
      return const _EmptyTab(
        icon: Icons.fact_check_outlined,
        text: 'Nenhuma conferência encontrada.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(11),
      itemCount: loan.approvals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, index) => _ApprovalCard(item: loan.approvals[index]),
    );
  }

  Widget _feedbacksTab(AppLoanDetail loan) {
    if (_isNew) {
      return const _EmptyTab(
        icon: Icons.chat_bubble_outline_rounded,
        text: 'Salve o empréstimo para adicionar feedbacks.',
      );
    }
    if (_loadingFeedbacks) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Feedbacks do contrato',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _savingFeedback ? null : _addFeedback,
                icon: _savingFeedback
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_comment_outlined, size: 17),
                label: const Text('Adicionar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _feedbacks.isEmpty
              ? const _EmptyTab(
                  icon: Icons.chat_bubble_outline_rounded,
                  text: 'Nenhum feedback registrado.',
                )
              : RefreshIndicator(
                  color: context.colors.primary,
                  onRefresh: () => _loadFeedbacks(force: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(11, 5, 11, 18),
                    itemCount: _feedbacks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) {
                      final AppLoanFeedback feedback = _feedbacks[index];
                      return _LoanFeedbackCard(
                        feedback: feedback,
                        canDelete: loan.administrator && !_savingFeedback,
                        onDelete: () => _deleteFeedback(feedback),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _loadSupplemental() async {
    if (_isNew || _supplementalLoaded || _loadingSupplemental) return;
    setState(() => _loadingSupplemental = true);
    try {
      final AppLoanDetail detail = await _service.fetchDetail(widget.loanId!);
      if (!mounted) return;
      setState(() {
        _loan = detail;
        _supplementalLoaded = true;
        _loadingSupplemental = false;
      });
    } on LoanServiceException catch (error) {
      if (!mounted) return;
      setState(() => _loadingSupplemental = false);
      await _alert('Não foi possível carregar', error.message);
    }
  }

  Future<void> _loadFeedbacks({bool force = false}) async {
    if (_isNew || _loadingFeedbacks || (_feedbacksLoaded && !force)) return;
    setState(() => _loadingFeedbacks = true);
    try {
      final List<AppLoanFeedback> feedbacks = await _service.fetchFeedbacks(
        widget.loanId!,
      );
      if (!mounted) return;
      setState(() {
        _feedbacks = feedbacks;
        _feedbacksLoaded = true;
        _loadingFeedbacks = false;
      });
    } on LoanServiceException catch (error) {
      if (!mounted) return;
      setState(() => _loadingFeedbacks = false);
      await _alert('Não foi possível carregar os feedbacks', error.message);
    }
  }

  Future<void> _addFeedback() async {
    if (_isNew || _savingFeedback) return;
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar feedback'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Registre uma observação importante sobre o contrato.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final String value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() => _savingFeedback = true);
    try {
      await _service.addFeedback(widget.loanId!, text);
      if (!mounted) return;
      _feedbacksLoaded = false;
      await _loadFeedbacks(force: true);
      if (mounted) _toast('Feedback adicionado.');
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _alert('Não foi possível adicionar', error.message);
      }
    } finally {
      if (mounted) setState(() => _savingFeedback = false);
    }
  }

  Future<void> _deleteFeedback(AppLoanFeedback feedback) async {
    final AppLoanDetail? loan = _loan;
    if (loan == null || !loan.administrator || _savingFeedback) return;
    final bool confirmed = await _confirm(
      'Remover feedback?',
      'O feedback será removido deste contrato.',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _savingFeedback = true);
    try {
      await _service.deleteFeedback(loan.id, feedback.id);
      if (!mounted) return;
      setState(
        () => _feedbacks = _feedbacks
            .where((item) => item.id != feedback.id)
            .toList(growable: false),
      );
      _toast('Feedback removido.');
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _alert('Não foi possível remover', error.message);
      }
    } finally {
      if (mounted) setState(() => _savingFeedback = false);
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loan = await _service.fetchDetail(widget.loanId!, compact: true);
      if (!mounted) return;
      setState(() {
        _loan = loan;
        _loading = false;
        _supplementalLoaded = false;
        _loadingSupplemental = false;
        _feedbacksLoaded = false;
        _loadingFeedbacks = false;
        _feedbacks = const [];
      });
      _fill(loan);
    } on LoanServiceException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  void _fill(AppLoanDetail loan) {
    _contractDate.text = _date(loan.contractDate);
    _firstDueDate.text = _date(loan.firstDueDate);
    _installments.text = '${loan.installmentCount}';
    _loaned.text = _plainMoney(
      loan.negotiatedOrigin ? loan.originalLoanAmount : loan.loanedAmount,
    );
    _negotiated.text = _plainMoney(loan.negotiatedAmount);
    _discount.text = _plainMoney(loan.discountAmount);
    _lateFee.text = _plainMoney(loan.lateFeeAmount);
    _owner.text = loan.clientOwner ?? '';
    _collateral.text = loan.collateral ?? '';
    _notes.text = loan.notes ?? '';
    _paymentType = loan.paymentTypeCode;
    _missing = loan.missing;
  }

  double _draftTotalAmount(AppLoanDetail loan) {
    if (!loan.canEdit || loan.operationLocked) return loan.totalAmount;
    final double total =
        _parseMoney(_negotiated.text) +
        (loan.negotiatedOrigin
            ? loan.interestAmount
            : _parseMoney(_loaned.text)) -
        _parseMoney(_discount.text);
    return total.isFinite ? total : loan.totalAmount;
  }

  double _draftInstallmentAmount(AppLoanDetail loan) {
    final int count = int.tryParse(_installments.text) ?? loan.installmentCount;
    return count > 0 ? _draftTotalAmount(loan) / count : 0;
  }

  bool _hasLoanChanges(AppLoanDetail loan) {
    if (!loan.canEdit || loan.operationLocked) return false;
    return _contractDate.text != _date(loan.contractDate) ||
        _firstDueDate.text != _date(loan.firstDueDate) ||
        _installments.text != '${loan.installmentCount}' ||
        (!loan.negotiatedOrigin &&
            _plainMoney(_parseMoney(_loaned.text)) !=
                _plainMoney(loan.loanedAmount)) ||
        _plainMoney(_parseMoney(_negotiated.text)) !=
            _plainMoney(loan.negotiatedAmount) ||
        _plainMoney(_parseMoney(_discount.text)) !=
            _plainMoney(loan.discountAmount) ||
        _plainMoney(_parseMoney(_lateFee.text)) !=
            _plainMoney(loan.lateFeeAmount) ||
        _owner.text.trim() != (loan.clientOwner ?? '').trim() ||
        _collateral.text.trim() != (loan.collateral ?? '').trim() ||
        _notes.text.trim() != (loan.notes ?? '').trim() ||
        _paymentType != loan.paymentTypeCode ||
        _missing != loan.missing;
  }

  Future<bool> _saveLoan({bool showSuccess = false}) async {
    final AppLoanDetail? loan = _loan;
    if (loan == null) return true;
    if (_saving) return false;
    if (!_isNew && !_hasLoanChanges(loan)) return true;
    final bool structural =
        _installments.text != '${loan.installmentCount}' ||
        (!loan.negotiatedOrigin &&
            _loaned.text != _plainMoney(loan.loanedAmount)) ||
        _negotiated.text != _plainMoney(loan.negotiatedAmount) ||
        _discount.text != _plainMoney(loan.discountAmount) ||
        _firstDueDate.text != _date(loan.firstDueDate) ||
        _paymentType != loan.paymentTypeCode;
    if (structural && !_isNew) {
      final bool confirmed = await _confirm(
        'Recalcular parcelas?',
        'Alterações em valores, quantidade, tipo ou primeiro vencimento recriam as parcelas quando ainda não há pagamentos. Deseja continuar?',
      );
      if (!confirmed) return false;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> data = {
        'contractDate': _isoDate(_contractDate.text),
        'firstDueDate': _isoDate(_firstDueDate.text),
        'installmentCount': int.tryParse(_installments.text),
        'notes': _notes.text,
        'paymentType': _paymentType,
        'loanedAmount': loan.negotiatedOrigin
            ? loan.loanedAmount
            : _parseMoney(_loaned.text),
        'discountAmount': _parseMoney(_discount.text),
        'negotiatedAmount': _parseMoney(_negotiated.text),
        'lateFeeAmount': _parseMoney(_lateFee.text),
        'collateral': _collateral.text,
        'clientOwner': _owner.text,
        'missing': _missing,
      };
      final result = _isNew
          ? await _service.createLoan({...data, 'clientId': widget.clientId})
          : await _service.updateLoan(loan.id, data);
      if (!mounted) return false;
      setState(() => _loan = result);
      _fill(result);
      if (!_isNew) _didSave = true;
      if (showSuccess) {
        _toast(_isNew ? 'Empréstimo cadastrado.' : 'Empréstimo atualizado.');
      }
      return true;
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _alert('Não foi possível salvar', error.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeScreen() async {
    if (_closing || _saving) return;
    setState(() => _closing = true);
    if (_isNew) {
      final AppLoanDetail? loan = _loan;
      final bool discard = loan == null || !_hasLoanChanges(loan)
          ? true
          : await _confirm(
              'Descartar novo empréstimo?',
              'As informações preenchidas ainda não foram salvas.',
              destructive: true,
            );
      if (!mounted) return;
      if (!discard) {
        setState(() => _closing = false);
        return;
      }
      await _finishScreen(false);
      return;
    }
    final AppLoanDetail? loan = _loan;
    if (loan != null && _hasLoanChanges(loan)) {
      final bool discard = await _confirm(
        'Descartar alterações?',
        'As alterações realizadas neste empréstimo serão perdidas.',
        destructive: true,
      );
      if (!mounted) return;
      if (!discard) {
        setState(() => _closing = false);
        return;
      }
    }
    await _finishScreen(_didSave);
  }

  Future<void> _saveNewLoan() async {
    if (!_isNew || _closing || _saving) return;
    final bool saved = await _saveLoan();
    if (saved && mounted) await _finishScreen(true);
  }

  Future<void> _saveExistingLoan() async {
    if (_isNew || _closing || _saving) return;
    await _saveLoan(showSuccess: true);
  }

  Future<void> _finishScreen([bool result = true]) async {
    if (!mounted) return;
    setState(() {
      _allowPop = true;
      _closing = false;
    });
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _openInstallment(AppLoanInstallment installment) async {
    final AppLoanDetail loan = _loan!;
    if (loan.operationLocked) {
      await _alert(
        'Aguardando aprovação',
        loan.lockReason ?? 'Este contrato possui uma operação pendente.',
      );
      return;
    }
    Widget buildScreen(BuildContext _) =>
        _LegacyInstallmentEditScreen(loan: loan, installment: installment);
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      await showAppSideDrawer<bool>(
        context: context,
        maxWidth: 560,
        builder: buildScreen,
      );
    } else {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(fullscreenDialog: true, builder: buildScreen),
      );
    }
    if (mounted) await _load();
  }

  Future<void> _openHistoricalLoan(AppLoanOrigin origin) async {
    final bool open = await _confirm(
      'Abrir empréstimo',
      'Deseja abrir o empréstimo nº ${origin.id} ?',
    );
    if (!open || !mounted) return;
    final bool? changed = await openLoanDetailScreen(
      context: context,
      loanId: origin.id,
      onOpenClient: widget.onOpenClient,
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _handleAction(String action) async {
    switch (action) {
      case 'client':
        await _openClient();
      case 'pix':
        await _openPix();
      case 'cancel-pix':
        await _cancelPendingPix();
      case 'payment':
        await _showContractPayment();
      case 'installment-payment':
        await _showInstallmentPayment();
      case 'interest-roll':
        await _showInterestOnlyPayment();
      case 'refinance':
        await _showNegotiation('REFINANCIAMENTO');
      case 'renew':
        await _showNegotiation('RENOVACAO');
      case 'cancel':
        await _closeLoan('CANCELAR');
      case 'finish':
        await _closeLoan('FINALIZAR');
      case 'message-contract':
        await _showGeneratedMessage('CONTRATO');
      case 'message-debt':
        await _showGeneratedMessage('DIVIDA');
      case 'refresh':
        await _load();
    }
  }

  Future<void> _openClient() async {
    final AppLoanDetail? loan = _loan;
    if (loan == null || _saving) return;
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      final ClientDetailScreenController controller =
          ClientDetailScreenController();
      await showAppSideDrawer<void>(
        context: context,
        fromStart: true,
        maxWidth: 500,
        builder: (drawerContext) => Column(
          children: [
            AppPanelHeader(
              title: 'Detalhes do cliente',
              subtitle: 'Consulte e altere os dados do cliente.',
              icon: Icons.person_outline_rounded,
              onClose: controller.requestClose,
            ),
            Expanded(
              child: ClientDetailScreen(
                clientId: loan.clientId,
                showAppBar: false,
                embedded: true,
                showEmbeddedHeader: true,
                onBack: () => Navigator.pop(drawerContext),
                controller: controller,
              ),
            ),
          ],
        ),
      );
      if (mounted) await _load();
      return;
    }
    final ValueChanged<int>? openClient = widget.onOpenClient;
    if (openClient != null) {
      if (_hasLoanChanges(loan)) {
        final bool discard = await _confirm(
          'Abrir cliente?',
          'As alterações não salvas deste empréstimo serão descartadas.',
          destructive: true,
        );
        if (!discard || !mounted) return;
      }
      final NavigatorState navigator = Navigator.of(context);
      setState(() {
        _allowPop = true;
        _closing = true;
      });
      navigator.pop(_didSave);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openClient(loan.clientId);
      });
      return;
    }
    await _alert(
      'Cliente indisponível',
      'Não foi possível abrir a página de clientes neste contexto.',
    );
  }

  Future<void> _openPix({AppLoanInstallment? installment}) async {
    final AppLoanDetail loan = _loan!;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final AppPixCharge? current = await _service.fetchCurrentPix(
        loan.id,
        installmentId: installment?.id,
      );
      if (!mounted) return;
      final double available =
          installment?.balanceAmount ??
          loan.installments.fold<double>(
            0,
            (total, item) => total + item.balanceAmount,
          );
      bool pixChanged = false;
      await showAppDialog<void>(
        context: context,
        title: 'Cobrança PIX',
        subtitle: installment == null
            ? 'Pagamento no contrato'
            : '${installment.number}ª parcela',
        icon: Icons.qr_code_2_rounded,
        maxWidth: 520,
        builder: (_) => _PixSheet(
          loanId: loan.id,
          installmentId: installment?.id,
          installmentLabel: installment == null
              ? null
              : '${installment.number}ª parcela',
          availableAmount: available,
          initialCharge: current,
          canGenerate: _canGeneratePix(loan),
          onChanged: () => pixChanged = true,
        ),
      );
      if (pixChanged && mounted) await _load();
    } on LoanServiceException catch (error) {
      if (mounted) await _alert('Não foi possível abrir o PIX', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _canGeneratePix(AppLoanDetail loan) =>
      loan.numericStatus != 3 && !loan.refinanced && !loan.operationLocked;

  Future<void> _cancelPendingPix() async {
    final AppLoanDetail? loan = _loan;
    if (loan == null || _saving || !loan.hasPendingPix) return;
    final bool confirmed = await _confirm(
      'Cancelar PIX aguardando?',
      'As cobranças PIX pendentes deste contrato serão canceladas diretamente no Sicredi. Se algum pagamento já tiver sido concluído, ele será registrado normalmente. O contrato só será liberado após a confirmação do banco.',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final AppPixCancellationResult result = await _service.cancelPendingPix(
        loan.id,
      );
      final AppLoanDetail updated = await _service.fetchDetail(
        loan.id,
        compact: true,
      );
      if (!mounted) return;
      setState(() => _loan = updated);
      _fill(updated);
      final String message = result.pendingCount > 0
          ? 'Ainda há ${result.pendingCount} PIX aguardando confirmação; o contrato continua bloqueado.'
          : result.cancelledCount > 0 && result.paidCount > 0
          ? '${result.cancelledCount} PIX cancelado(s) e ${result.paidCount} pagamento(s) registrado(s). Contrato atualizado.'
          : result.cancelledCount > 0
          ? 'PIX cancelado no Sicredi. O contrato foi liberado.'
          : result.paidCount > 0
          ? 'O PIX já havia sido pago e o pagamento foi registrado; nenhum PIX aguardando permaneceu.'
          : 'Não havia PIX aguardando; contrato atualizado.';
      _toast(message);
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _alert('Não foi possível cancelar o PIX', error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showContractPayment() async {
    final Map<String, dynamic>? data = await _paymentDialog(
      title: 'Lançar pagamento no contrato',
    );
    if (data != null) {
      await _run(
        () => _service.distributePayment(widget.loanId!, data),
        success: 'Pagamento distribuído entre as parcelas.',
      );
    }
  }

  Future<void> _showInstallmentPayment() async {
    final AppLoanDetail loan = _loan!;
    final double installmentAmount = suggestedInstallmentPaymentAmount(loan);
    if (installmentAmount <= 0) {
      await _alert(
        'Pagamento parcela',
        'Não foi possível identificar o valor da parcela deste contrato.',
      );
      return;
    }
    final Map<String, dynamic>? data = await _paymentDialog(
      title: 'Pagamento parcela',
      initialAmount: installmentAmount,
    );
    if (data != null) {
      await _run(
        () => _service.distributePayment(widget.loanId!, data),
        success: 'Pagamento da parcela lançado com sucesso.',
      );
    }
  }

  Future<void> _showInterestOnlyPayment() async {
    final AppLoanDetail loan = _loan!;
    final List<AppLoanInstallment> pending = loan.installments
        .where((item) => item.pending && item.balanceAmount > 0)
        .toList(growable: false);
    if (pending.isEmpty) {
      await _alert(
        'Baixar só juros',
        'Este contrato não possui parcela pendente.',
      );
      return;
    }
    final AppLoanInstallment installment = pending.first;
    final Map<String, dynamic>?
    data = await showAppDialog<Map<String, dynamic>>(
      context: context,
      title: 'Baixar só juros',
      subtitle:
          'Parcela ${installment.number} • vencimento ${_date(installment.dueDate)}',
      icon: Icons.percent_rounded,
      maxWidth: 520,
      builder: (_) => _InterestRollDialog(loan: loan, installment: installment),
    );
    if (data == null) return;
    await _run(
      () => _service.interestOnlyPayment(loan.id, data),
      success: 'Juros lançados, vencimento prorrogado e operação enviada para conferência.',
    );
  }

  Future<void> _showGeneratedMessage(String type) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final String message = await _service.fetchLoanMessage(
        widget.loanId!,
        type,
      );
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        title: type == 'DIVIDA' ? 'Mensagem da dívida' : 'Mensagem do contrato',
        subtitle: 'Edite o texto antes de copiar ou enviar.',
        icon: type == 'DIVIDA'
            ? Icons.request_quote_outlined
            : Icons.message_outlined,
        maxWidth: 500,
        maxHeight: 520,
        builder: (_) => _LoanMessageEditor(initialText: message),
      );
    } on LoanServiceException catch (error) {
      if (mounted) await _alert('Não foi possível gerar', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showNegotiation(String mode) async {
    final loan = _loan!;
    if (loan.hasPendingPix) {
      await _alert(
        'PIX aguardando pagamento',
        'Atualize ou cancele a cobrança PIX antes de refinanciar ou renovar este contrato.',
      );
      return;
    }
    final bool renewal = mode == 'RENOVACAO';
    final result = await showAppDialog<Map<String, dynamic>>(
      context: context,
      title: renewal ? 'Renovar empréstimo' : 'Refinanciar empréstimo',
      subtitle: 'Informe as condições da nova negociação.',
      icon: Icons.swap_horiz_rounded,
      maxWidth: 560,
      builder: (_) => _NegotiationDialog(loan: loan, renewal: renewal),
    );
    if (result == null) return;
    await _run(
      () => _service.negotiate(loan.id, mode, result),
      success:
          '${mode == 'RENOVACAO' ? 'Renovação' : 'Refinanciamento'} criado.',
    );
  }

  Future<void> _closeLoan(String action) async {
    if (_loan?.hasPendingPix == true) {
      await _alert(
        'PIX aguardando pagamento',
        'Atualize ou cancele a cobrança PIX antes de cancelar ou finalizar este contrato.',
      );
      return;
    }
    final bool destructive = action == 'FINALIZAR';
    final bool confirmed = await _confirm(
      destructive ? 'Finalizar definitivamente?' : 'Cancelar empréstimo?',
      destructive
          ? 'A finalização remove o contrato e seu fluxo financeiro. Esta ação exige conferência e não deve ser usada para simples cancelamento.'
          : 'O contrato ficará cancelado e não aceitará novos lançamentos.',
      destructive: true,
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      final result = await _service.closeLoan(widget.loanId!, action);
      if (!mounted) return;
      if (result == null) {
        await _finishScreen();
      } else {
        setState(() => _loan = result);
        _fill(result);
        _toast(
          result.operationLocked
              ? 'Solicitação enviada para conferência.'
              : 'Contrato atualizado.',
        );
      }
    } on LoanServiceException catch (error) {
      if (mounted) await _alert('Não foi possível concluir', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _run(
    Future<AppLoanDetail> Function() operation, {
    required String success,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await operation();
      if (!mounted) return;
      setState(() => _loan = result);
      _fill(result);
      _toast(success);
    } on LoanServiceException catch (error) {
      if (mounted) await _alert('Não foi possível concluir', error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>?> _paymentDialog({
    required String title,
    AppLoanPayment? payment,
    double? initialAmount,
  }) async {
    return _showPaymentDialog(
      context,
      title: title,
      payment: payment,
      initialAmount: initialAmount,
    );
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    bool preventPastDates = false,
  }) async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime firstDate = preventPastDates
        ? today
        : DateTime(today.year - 5);
    final DateTime lastDate = DateTime(today.year + 5, 12, 31);
    final DateTime initial = _parseDate(controller.text) ?? today;
    final selected = await showAppDatePickerDialog(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('pt', 'BR'),
    );
    if (selected != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(selected);
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    bool destructive = false,
  }) async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext, false),
              textStyle: TextStyle(color: context.colors.textPrimary),
              child: const Text('Cancelar'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: destructive,
              isDefaultAction: !destructive,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _alert(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 7),
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

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

class _LoanTotalsFooter extends StatelessWidget {
  final bool installmentView;
  final double installmentAmount;
  final double totalAmount;
  final double overdueAmount;
  final double overdueWithInterest;
  final bool safeBottom;

  const _LoanTotalsFooter({
    required this.installmentView,
    required this.installmentAmount,
    required this.totalAmount,
    required this.overdueAmount,
    required this.overdueWithInterest,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .18),
      child: SafeArea(
        top: false,
        bottom: safeBottom,
        minimum: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          children: [
            Expanded(
              child: _FooterMetric(
                label: installmentView
                    ? 'Vencidos s/ juros'
                    : 'Valor da parcela',
                value: installmentView ? overdueAmount : installmentAmount,
              ),
            ),
            Container(width: 1, height: 38, color: context.colors.divider),
            Expanded(
              child: _FooterMetric(
                label: installmentView ? 'Vencidos c/ juros' : 'Valor total',
                value: installmentView ? overdueWithInterest : totalAmount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewLoanActionBar extends StatelessWidget {
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _NewLoanActionBar({
    required this.saving,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .18),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: CustomFloatingActionButton.gradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FilledButton(
                      onPressed: saving || !canSave ? null : onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: saving
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('SALVAR EMPRÉSTIMO'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    onPressed: saving ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(color: context.colors.divider),
                    ),
                    child: const Text('CANCELAR'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExistingLoanActionBar extends StatelessWidget {
  final bool saving;
  final bool hasChanges;
  final VoidCallback onSave;
  final VoidCallback onBack;

  const _ExistingLoanActionBar({
    required this.saving,
    required this.hasChanges,
    required this.onSave,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final String backLabel = kIsWeb && MediaQuery.sizeOf(context).width >= 1024
        ? 'FECHAR'
        : 'VOLTAR';
    return Material(
      color: context.colors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: .18),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasChanges) ...[
                    SizedBox(
                      height: 46,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: CustomFloatingActionButton.gradient,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: FilledButton(
                          onPressed: saving ? null : onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('SALVAR ALTERAÇÕES'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: saving ? null : onBack,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.textSecondary,
                        side: BorderSide(color: context.colors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(backLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterMetric extends StatelessWidget {
  final String label;
  final double value;

  const _FooterMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        _currency(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.colors.primary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});
  @override
  Widget build(BuildContext context) {
    final String normalized = status.trim().toUpperCase();
    final Color color =
        normalized.contains('CANCEL') ||
            normalized.contains('ATRAS') ||
            normalized.contains('REPROV')
        ? Colors.red
        : normalized.contains('AGUARD')
        ? Colors.blue.shade600
        : normalized.contains('PENDENTE') || normalized.contains('APROVAÇÃO')
        ? Colors.amber.shade700
        : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;
  final int maxLines;
  final double fontSize;
  final bool spacious;
  final bool loanFieldStyle;
  const _CompactField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.keyboardType,
    this.maxLines = 1,
    this.fontSize = 12,
    this.spacious = false,
    this.loanFieldStyle = false,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    keyboardType: keyboardType,
    maxLines: maxLines,
    style: TextStyle(
      color: loanFieldStyle
          ? enabled
                ? context.colors.textPrimary
                : context.colors.textPrimary.withValues(alpha: 0.42)
          : null,
      fontSize: fontSize,
      fontWeight: loanFieldStyle ? FontWeight.normal : null,
    ),
    decoration: loanFieldStyle
        ? _loanFieldDecoration(
            context,
            label,
            editable: enabled,
            spacious: spacious,
          )
        : _fieldDecoration(context, label, spacious: spacious),
  );
}

class _MoneyField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool spacious;
  final double? fontSize;
  final bool loanFieldStyle;
  const _MoneyField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.spacious = false,
    this.fontSize,
    this.loanFieldStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle valueStyle = TextStyle(
      color: loanFieldStyle
          ? enabled
                ? context.colors.textPrimary
                : context.colors.textPrimary.withValues(alpha: 0.42)
          : null,
      fontSize: fontSize ?? 12,
      fontWeight: loanFieldStyle
          ? FontWeight.normal
          : spacious
          ? FontWeight.w600
          : FontWeight.normal,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_BrazilianMoneyInputFormatter()],
      style: valueStyle,
      decoration:
          (loanFieldStyle
                  ? _loanFieldDecoration(
                      context,
                      label,
                      editable: enabled,
                      prefix: 'R\$ ',
                      spacious: spacious,
                    )
                  : _fieldDecoration(
                      context,
                      label,
                      prefix: 'R\$ ',
                      spacious: spacious,
                    ))
              .copyWith(isDense: !spacious, prefixStyle: valueStyle),
    );
  }
}

class _BrazilianMoneyInputFormatter extends TextInputFormatter {
  const _BrazilianMoneyInputFormatter();

  static final NumberFormat _formatter = NumberFormat('#,##0.00', 'pt_BR');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();

    // Mantém o valor dentro de uma faixa segura para conversão e para a API.
    if (digits.length > 15) digits = digits.substring(0, 15);
    final double value = (int.tryParse(digits) ?? 0) / 100;
    final String formatted = _formatter.format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _BrazilianDateInputFormatter extends TextInputFormatter {
  const _BrazilianDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final StringBuffer formatted = StringBuffer();
    for (int index = 0; index < digits.length; index++) {
      if (index == 2 || index == 4) formatted.write('/');
      formatted.write(digits[index]);
    }
    final String text = formatted.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onTap;
  final bool spacious;
  final double fontSize;
  final bool leadingIcon;
  final bool loanFieldStyle;
  const _DateField({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onTap,
    this.spacious = false,
    this.fontSize = 12,
    this.leadingIcon = false,
    this.loanFieldStyle = false,
  });
  @override
  Widget build(BuildContext context) {
    final Widget calendarIcon = Icon(
      Icons.calendar_month_outlined,
      size: spacious ? 21 : 18,
      color: enabled
          ? context.colors.textPrimary
          : context.colors.textPrimary.withValues(alpha: 0.42),
    );
    final BorderRadius borderRadius = BorderRadius.circular(spacious ? 12 : 10);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: borderRadius,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => InputDecorator(
            isEmpty: value.text.isEmpty,
            decoration:
                (loanFieldStyle
                        ? _loanFieldDecoration(
                            context,
                            label,
                            editable: enabled,
                            spacious: spacious,
                          )
                        : _fieldDecoration(context, label, spacious: spacious))
                    .copyWith(
                      enabled: enabled,
                      prefixIcon: leadingIcon ? calendarIcon : null,
                      suffixIcon: leadingIcon ? null : calendarIcon,
                    ),
            child: Text(
              value.text,
              style: TextStyle(
                color: loanFieldStyle
                    ? enabled
                          ? context.colors.textPrimary
                          : context.colors.textPrimary.withValues(alpha: 0.42)
                    : null,
                fontSize: fontSize,
                fontWeight: loanFieldStyle
                    ? FontWeight.normal
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  final String label, value;
  final bool spacious;
  final double fontSize;
  final bool loanFieldStyle;
  const _ReadOnlyValue({
    required this.label,
    required this.value,
    this.spacious = false,
    this.fontSize = 12,
    this.loanFieldStyle = false,
  });
  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: loanFieldStyle
        ? _loanFieldDecoration(
            context,
            label,
            editable: false,
            spacious: spacious,
          )
        : _fieldDecoration(context, label, spacious: spacious),
    child: Text(
      value,
      style: TextStyle(
        color: loanFieldStyle
            ? context.colors.textPrimary.withValues(alpha: 0.42)
            : null,
        fontSize: fontSize,
        fontWeight: loanFieldStyle ? FontWeight.normal : FontWeight.w800,
      ),
    ),
  );
}

class _LegacyInstallmentCard extends StatelessWidget {
  final AppLoanInstallment installment;
  final bool refinanced;
  final VoidCallback onTap;

  const _LegacyInstallmentCard({
    required this.installment,
    required this.refinanced,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String status = installment.status;
    Color color = context.colors.textSecondary;
    IconData statusIcon = Icons.hourglass_empty_rounded;

    if (refinanced && status != 'Pago') {
      status = 'Refinanciado';
      color = context.colors.primary;
      statusIcon = Icons.autorenew_rounded;
    } else if (status == 'Vencido') {
      color = context.isDark ? Colors.red.shade300 : Colors.red.shade700;
      statusIcon = Icons.error_outline_rounded;
    } else if (status == 'Parcial') {
      color = context.isDark ? Colors.orange.shade300 : Colors.orange.shade800;
      statusIcon = Icons.timelapse_rounded;
    } else if (status == 'Pago') {
      color = context.colors.primary;
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (status == 'Vence hoje' || status == 'Vencendo') {
      color = context.isDark ? Colors.amber.shade300 : Colors.amber.shade800;
      statusIcon = Icons.schedule_rounded;
    }

    final bool overdue = status == 'Vencido';
    final bool paid = status == 'Pago';
    final double displayedAmount = paid
        ? installment.totalAmount
        : installment.amount;
    final double displayedTotal = overdue
        ? installment.amount + installment.overdueInterestAmount
        : displayedAmount;
    final Color interestColor = context.isDark
        ? Colors.red.shade300
        : Colors.red.shade600;
    final Color totalInterestColor = context.isDark
        ? Colors.red.shade400
        : Colors.red.shade900;

    String? statusDetail;
    if (overdue) {
      statusDetail = 'Dias venc.: ${installment.overdueDays}';
    } else if (status == 'Parcial') {
      statusDetail = 'Pendente: ${_currency(installment.balanceAmount)}';
    } else if (paid && installment.lastPaymentDate != null) {
      statusDetail = 'Pago em ${_date(installment.lastPaymentDate)}';
    } else if (installment.paymentPendingApproval) {
      statusDetail = 'Pagamento em análise';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool wide = constraints.maxWidth >= 680;
          final bool optimizedDesktopWeb = kIsWeb && wide;
          return Material(
            color: context.colors.surface,
            elevation: optimizedDesktopWeb ? 0 : 2,
            shadowColor: Colors.black.withValues(
              alpha: context.isDark ? .22 : .09,
            ),
            clipBehavior: optimizedDesktopWeb ? Clip.hardEdge : Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: .18)),
            ),
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, color: color),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 14 : 12,
                      wide ? 12 : 10,
                      wide ? 14 : 12,
                      wide ? 12 : 10,
                    ),
                    child: wide
                        ? _WideInstallmentContent(
                            installment: installment,
                            status: status,
                            statusDetail: statusDetail,
                            statusIcon: statusIcon,
                            color: color,
                            displayedAmount: displayedAmount,
                            displayedTotal: displayedTotal,
                            interestColor: interestColor,
                            totalColor: overdue
                                ? totalInterestColor
                                : _installmentTotalColor(
                                    context,
                                    status,
                                    color,
                                  ),
                          )
                        : _CompactInstallmentContent(
                            installment: installment,
                            status: status,
                            statusDetail: statusDetail,
                            statusIcon: statusIcon,
                            color: color,
                            displayedAmount: displayedAmount,
                            displayedTotal: displayedTotal,
                            interestColor: interestColor,
                            totalColor: overdue
                                ? totalInterestColor
                                : _installmentTotalColor(
                                    context,
                                    status,
                                    color,
                                  ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WideInstallmentContent extends StatelessWidget {
  final AppLoanInstallment installment;
  final String status;
  final String? statusDetail;
  final IconData statusIcon;
  final Color color;
  final double displayedAmount;
  final double displayedTotal;
  final Color interestColor;
  final Color totalColor;

  const _WideInstallmentContent({
    required this.installment,
    required this.status,
    required this.statusDetail,
    required this.statusIcon,
    required this.color,
    required this.displayedAmount,
    required this.displayedTotal,
    required this.interestColor,
    required this.totalColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 104,
            child: _InstallmentNumber(
              number: installment.number,
              color: color,
              large: true,
            ),
          ),
          _InstallmentDivider(color: color),
          Expanded(
            flex: 15,
            child: _InstallmentDueDate(
              dueDate: installment.dueDate,
              color: color,
            ),
          ),
          _InstallmentDivider(color: color),
          Expanded(
            flex: 16,
            child: _InstallmentAmountAndInterest(
              amount: displayedAmount,
              interest: installment.overdueInterestAmount,
              interestColor: interestColor,
            ),
          ),
          _InstallmentDivider(color: color),
          Expanded(
            flex: 13,
            child: _InstallmentValue(
              label: 'Total c/ juros',
              value: _currency(displayedTotal),
              valueColor: totalColor,
              largeValue: true,
            ),
          ),
          _InstallmentDivider(color: color),
          Expanded(
            flex: 13,
            child: _InstallmentStatus(
              status: status,
              detail: statusDetail,
              icon: statusIcon,
              color: color,
              centered: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInstallmentContent extends StatelessWidget {
  final AppLoanInstallment installment;
  final String status;
  final String? statusDetail;
  final IconData statusIcon;
  final Color color;
  final double displayedAmount;
  final double displayedTotal;
  final Color interestColor;
  final Color totalColor;

  const _CompactInstallmentContent({
    required this.installment,
    required this.status,
    required this.statusDetail,
    required this.statusIcon,
    required this.color,
    required this.displayedAmount,
    required this.displayedTotal,
    required this.interestColor,
    required this.totalColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool veryCompact = constraints.maxWidth < 390;
        return SizedBox(
          height: veryCompact ? 82 : 92,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: veryCompact ? 49 : 66,
                child: _InstallmentNumber(
                  number: installment.number,
                  color: color,
                  compact: veryCompact,
                ),
              ),
              _InstallmentDivider(color: color, height: veryCompact ? 58 : 68),
              Expanded(
                flex: 15,
                child: _InstallmentDueDate(
                  dueDate: installment.dueDate,
                  color: color,
                  compact: true,
                  veryCompact: veryCompact,
                ),
              ),
              _InstallmentDivider(color: color, height: veryCompact ? 58 : 68),
              Expanded(
                flex: 17,
                child: _InstallmentAmountAndInterest(
                  amount: displayedAmount,
                  interest: installment.overdueInterestAmount,
                  interestColor: interestColor,
                  compact: true,
                  veryCompact: veryCompact,
                ),
              ),
              _InstallmentDivider(color: color, height: veryCompact ? 58 : 68),
              Expanded(
                flex: 14,
                child: _InstallmentValue(
                  label: 'Total c/ juros',
                  value: _currency(displayedTotal),
                  valueColor: totalColor,
                  compact: true,
                  veryCompact: veryCompact,
                ),
              ),
              _InstallmentDivider(color: color, height: veryCompact ? 58 : 68),
              Expanded(
                flex: 15,
                child: _InstallmentStatus(
                  status: status,
                  detail: statusDetail,
                  icon: statusIcon,
                  color: color,
                  centered: true,
                  compact: true,
                  veryCompact: veryCompact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InstallmentNumber extends StatelessWidget {
  final String number;
  final Color color;
  final bool large;
  final bool compact;

  const _InstallmentNumber({
    required this.number,
    required this.color,
    this.large = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$numberº',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: large ? 27 : (compact ? 19 : 22),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Parcela',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: large ? 11.5 : (compact ? 9 : 9),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstallmentDueDate extends StatelessWidget {
  final DateTime? dueDate;
  final Color color;
  final bool compact;
  final bool veryCompact;

  const _InstallmentDueDate({
    required this.dueDate,
    required this.color,
    this.compact = false,
    this.veryCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: compact ? (veryCompact ? 13 : 16) : 20,
            color: color,
          ),
          SizedBox(height: compact ? 2 : 3),
          Text(
            'Vence em',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: compact ? (veryCompact ? 8 : 9) : 11,
            ),
          ),
          if (!veryCompact) const SizedBox(height: 1),
          Text(
            dueDate == null ? 'Sem data' : _date(dueDate),
            maxLines: 1,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: compact ? (veryCompact ? 9.5 : 11) : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (dueDate != null)
            Text(
              _weekday(dueDate!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: compact ? (veryCompact ? 8 : 9.5) : 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _InstallmentAmountAndInterest extends StatelessWidget {
  final double amount;
  final double interest;
  final Color interestColor;
  final bool compact;
  final bool veryCompact;

  const _InstallmentAmountAndInterest({
    required this.amount,
    required this.interest,
    required this.interestColor,
    this.compact = false,
    this.veryCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InstallmentValue(
            label: 'Valor da parcela',
            value: _currency(amount),
            largeValue: true,
            alignStart: true,
            compact: compact,
            veryCompact: veryCompact,
          ),
          SizedBox(height: compact ? 4 : 9),
          _InstallmentValue(
            label: 'Juros',
            value: interest > 0 ? _currency(interest) : '—',
            valueColor: interest > 0
                ? interestColor
                : context.colors.textPrimary,
            largeValue: true,
            alignStart: true,
            compact: compact,
            veryCompact: veryCompact,
          ),
        ],
      ),
    );
  }
}

class _InstallmentValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool largeValue;
  final bool alignStart;
  final bool compact;
  final bool veryCompact;

  const _InstallmentValue({
    required this.label,
    required this.value,
    this.valueColor,
    this.largeValue = false,
    this.alignStart = false,
    this.compact = false,
    this.veryCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: alignStart
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: compact
                ? (veryCompact ? 7.5 : 9)
                : (largeValue ? 12 : 10),
          ),
        ),
        SizedBox(height: compact ? 1 : 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? context.colors.textPrimary,
            fontSize: compact
                ? (veryCompact ? 9.5 : 12)
                : (largeValue ? 16 : 13),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _InstallmentStatus extends StatelessWidget {
  final String status;
  final String? detail;
  final IconData icon;
  final Color color;
  final bool centered;
  final bool compact;
  final bool veryCompact;

  const _InstallmentStatus({
    required this.status,
    required this.detail,
    required this.icon,
    required this.color,
    this.centered = false,
    this.compact = false,
    this.veryCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? (veryCompact ? 3 : 5) : 9,
            vertical: compact ? 5 : 7,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? (veryCompact ? 11 : 14) : 17,
                color: color,
              ),
              SizedBox(width: compact ? 3 : 5),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? (veryCompact ? 8 : 9.5) : 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (detail != null) ...[
          SizedBox(height: compact ? 3 : 5),
          Text(
            detail!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: compact ? (veryCompact ? 7.5 : 9) : 10.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _InstallmentDivider extends StatelessWidget {
  final Color color;
  final double height;

  const _InstallmentDivider({required this.color, this.height = 72});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 1,
      height: height,
      color: color.withValues(alpha: .12),
    ),
  );
}

Color _installmentTotalColor(
  BuildContext context,
  String status,
  Color statusColor,
) {
  if (status == 'Vence hoje' ||
      status == 'Vencendo' ||
      status == 'Pago' ||
      status == 'Refinanciado') {
    return statusColor;
  }
  return context.colors.textPrimary;
}

class _LegacyHistoryCard extends StatelessWidget {
  final AppLoanOrigin origin;
  final int position;
  final VoidCallback onTap;

  const _LegacyHistoryCard({
    required this.origin,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = context.colors.textSecondary;
    final Color edgeColor = context.colors.divider;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 430;
        return Material(
          color: context.colors.surface,
          elevation: 2,
          shadowColor: Colors.black.withValues(
            alpha: context.isDark ? .24 : .10,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: edgeColor.withValues(alpha: .48)),
          ),
          child: InkWell(
            onTap: onTap,
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
                      _HistoryCardHeader(
                        origin: origin,
                        position: position,
                        color: accentColor,
                        compact: compact,
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      _HistoryCardOverview(origin: origin, color: accentColor),
                      SizedBox(height: compact ? 8 : 10),
                      _HistoryMetricsPanel(
                        origin: origin,
                        color: accentColor,
                        compact: compact,
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

class _HistoryCardHeader extends StatelessWidget {
  final AppLoanOrigin origin;
  final int position;
  final Color color;
  final bool compact;

  const _HistoryCardHeader({
    required this.origin,
    required this.position,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final String region = origin.regionName.trim();
    final String city = origin.cityName?.trim() ?? '';
    return SizedBox(
      height: compact ? 54 : 58,
      child: Row(
        children: [
          Container(
            width: compact ? 40 : 46,
            height: compact ? 40 : 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: .38)),
            ),
            child: Text(
              '$position',
              style: TextStyle(
                color: color,
                fontSize: compact ? 18 : 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(width: compact ? 9 : 11),
          Container(width: 1, height: 34, color: color.withValues(alpha: .24)),
          SizedBox(width: compact ? 9 : 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  origin.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: compact ? 12.5 : 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (region.isNotEmpty || city.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 13, color: color),
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
            constraints: BoxConstraints(maxWidth: compact ? 96 : 112),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              origin.paymentType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 9.5 : 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCardOverview extends StatelessWidget {
  final AppLoanOrigin origin;
  final Color color;

  const _HistoryCardOverview({required this.origin, required this.color});

  @override
  Widget build(BuildContext context) {
    final Widget contractStatus = _HistoryContractStatus(
      loanId: origin.id,
      status: origin.status,
      color: color,
    );
    final Widget due = _HistoryOverviewValue(
      label: 'Próx. venc.',
      value: origin.nextDueDate == null
          ? 'Não definida'
          : _date(origin.nextDueDate),
      icon: Icons.calendar_month_outlined,
      alignEnd: true,
    );

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
}

class _HistoryContractStatus extends StatelessWidget {
  final int loanId;
  final String status;
  final Color color;

  const _HistoryContractStatus({
    required this.loanId,
    required this.status,
    required this.color,
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
              child: _HistoryStatusChip(status: status, color: color),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryStatusChip extends StatelessWidget {
  final String status;
  final Color color;

  const _HistoryStatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
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

class _HistoryOverviewValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool alignEnd;

  const _HistoryOverviewValue({
    required this.label,
    required this.value,
    this.icon,
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

class _HistoryMetricsPanel extends StatelessWidget {
  final AppLoanOrigin origin;
  final Color color;
  final bool compact;

  const _HistoryMetricsPanel({
    required this.origin,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> metrics = [
      _HistoryMetric(
        icon: Icons.handshake_outlined,
        label: origin.negotiated ? 'Negociado' : 'Emprestado',
        value: _currency(origin.loanedAmount),
        color: color,
      ),
      _HistoryMetric(
        icon: Icons.payments_outlined,
        label: 'Recebido',
        value: _currency(origin.receivedAmount),
        color: color,
      ),
      _HistoryMetric(
        icon: Icons.account_balance_wallet_outlined,
        label: 'A receber',
        value: _currency(origin.receivableAmount),
        color: color,
      ),
      _HistoryMetric(
        icon: Icons.bar_chart_rounded,
        label: 'Lucro',
        value: _currency(origin.profitAmount),
        color: color,
      ),
    ];
    final Color divider = color.withValues(alpha: .16);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 5,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(
          alpha: context.isDark ? .44 : .68,
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: SizedBox(
        height: compact ? 58 : 67,
        child: Row(
          children: [
            for (int index = 0; index < metrics.length; index++) ...[
              Expanded(child: metrics[index]),
              if (index < metrics.length - 1)
                Container(width: 1, height: compact ? 42 : 48, color: divider),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _HistoryMetric({
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

String _weekday(DateTime value) {
  const names = [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];
  return names[value.weekday - 1];
}

class _ApprovalCard extends StatelessWidget {
  final AppLoanApproval item;
  const _ApprovalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final bool pixApproval =
        item.type.trim().toUpperCase() == 'PIX' ||
        item.description.toUpperCase().contains('PIX');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.type,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(status: item.status),
            ],
          ),
          const SizedBox(height: 5),
          Text(item.description, style: const TextStyle(fontSize: 10.5)),
          if (pixApproval) ...[
            const SizedBox(height: 5),
            Text(
              'Valor do PIX: ${_currency(item.amount)}',
              style: TextStyle(
                color: context.colors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Solicitado por ${item.requester} • ${_dateTime(item.createdAt)}',
            style: TextStyle(fontSize: 9, color: context.colors.textSecondary),
          ),
          if (item.rejectionReason != null)
            Text(
              'Motivo: ${item.rejectionReason}',
              style: const TextStyle(fontSize: 9.5, color: Colors.red),
            ),
        ],
      ),
    );
  }
}

class _LoanFeedbackCard extends StatelessWidget {
  final AppLoanFeedback feedback;
  final bool canDelete;
  final VoidCallback onDelete;

  const _LoanFeedbackCard({
    required this.feedback,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 11),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feedback.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _dateTime(feedback.createdAt),
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Remover feedback',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: context.colors.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feedback.text,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12,
              height: 1.42,
            ),
          ),
          if (feedback.inherited && feedback.inheritedFromLoanId != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Herdado do contrato #${feedback.inheritedFromLoanId}',
                  style: TextStyle(
                    color: context.colors.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyTab({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: context.colors.primary),
        const SizedBox(height: 7),
        Text(text, style: TextStyle(color: context.colors.textSecondary)),
      ],
    ),
  );
}

class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuLabel(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: context.colors.primary),
      const SizedBox(width: 8),
      Text(label),
    ],
  );
}

class _LoanMessageEditor extends StatefulWidget {
  final String initialText;

  const _LoanMessageEditor({required this.initialText});

  @override
  State<_LoanMessageEditor> createState() => _LoanMessageEditorState();
}

class _LoanMessageEditorState extends State<_LoanMessageEditor> {
  late String _message = widget.initialText;

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final double systemNavigation = MediaQuery.viewPaddingOf(context).bottom;
    final double bottomInset = keyboard > systemNavigation
        ? keyboard
        : systemNavigation;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      child: Column(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: widget.initialText,
              onChanged: (value) => _message = value,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 14, height: 1.4),
              decoration: _dialogFieldDecoration(
                context,
                'Mensagem',
              ).copyWith(alignLabelWithHint: true),
            ),
          ),
          const SizedBox(height: 10),
          _DialogActionButtons(
            cancelLabel: 'Copiar',
            confirmLabel: 'Enviar',
            onCancel: () async {
              await Clipboard.setData(ClipboardData(text: _message));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mensagem copiada.')),
                );
              }
            },
            onConfirm: () => SharePlus.instance.share(
              ShareParams(text: _message, subject: 'Money'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyInstallmentEditScreen extends StatefulWidget {
  final AppLoanDetail loan;
  final AppLoanInstallment installment;

  const _LegacyInstallmentEditScreen({
    required this.loan,
    required this.installment,
  });

  @override
  State<_LegacyInstallmentEditScreen> createState() =>
      _LegacyInstallmentEditScreenState();
}

class _LegacyInstallmentEditScreenState
    extends State<_LegacyInstallmentEditScreen> {
  final LoanService _service = LoanService();
  late AppLoanInstallment _installment = widget.installment;
  late final TextEditingController _due = TextEditingController(
    text: _date(widget.installment.dueDate),
  );
  late final TextEditingController _amount = TextEditingController(
    text: _plainMoney(widget.installment.amount),
  );
  late final TextEditingController _interest = TextEditingController(
    text: _plainMoney(widget.installment.interestAmount),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.installment.dueDateNote ?? '',
  );
  AppPixCharge? _pix;
  bool _loadingPix = true;
  bool _saving = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _syncingControllers = false;

  bool get _editingAllowed =>
      widget.loan.canEdit && !widget.loan.operationLocked;
  bool get _canEdit => _editingAllowed && !_saving && !_closing;
  bool get _canGeneratePix =>
      widget.loan.numericStatus != 3 &&
      !widget.loan.refinanced &&
      !widget.loan.operationLocked &&
      !_saving &&
      !_closing;

  bool get _hasChanges =>
      _due.text != _date(_installment.dueDate) ||
      (_parseMoney(_amount.text) - _installment.amount).abs() > 0.004 ||
      (_parseMoney(_interest.text) - _installment.interestAmount).abs() >
          0.004 ||
      _note.text.trim() != (_installment.dueDateNote ?? '').trim();

  @override
  void initState() {
    super.initState();
    for (final TextEditingController controller in [
      _due,
      _amount,
      _interest,
      _note,
    ]) {
      controller.addListener(_refreshFormState);
    }
    unawaited(_loadPix());
  }

  @override
  void dispose() {
    for (final TextEditingController controller in [
      _due,
      _amount,
      _interest,
      _note,
    ]) {
      controller.removeListener(_refreshFormState);
    }
    _due.dispose();
    _amount.dispose();
    _interest.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadPix() async {
    try {
      final AppPixCharge? charge = await _service.fetchCurrentPix(
        widget.loan.id,
        installmentId: _installment.id,
      );
      if (mounted) setState(() => _pix = charge);
    } on LoanServiceException {
      // A parcela continua utilizável mesmo quando a consulta PIX falha.
    } finally {
      if (mounted) setState(() => _loadingPix = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool desktopModal =
        kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    final bool showSaveAction = _editingAllowed && _hasChanges;
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeScreen());
      },
      child: Scaffold(
        backgroundColor: Color.alphaBlend(
          context.colors.surface.withValues(alpha: 0.68),
          context.colors.background,
        ),
        appBar: AppBar(
          backgroundColor: context.colors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: desktopModal ? 'Fechar' : 'Voltar',
            onPressed: _saving || _closing ? null : _closeScreen,
            icon: Icon(
              desktopModal ? Icons.close_rounded : Icons.arrow_back_rounded,
            ),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Editando parcela',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                '${_installment.number}ª parcela • ${widget.loan.clientName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              enabled: !_saving && !_closing,
              onSelected: (value) => unawaited(_handleMenuAction(value)),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'sendPix',
                  child: _MenuLabel(
                    Icons.chat_outlined,
                    'Enviar PIX pelo WhatsApp',
                  ),
                ),
                const PopupMenuItem(
                  value: 'pix',
                  child: _MenuLabel(
                    Icons.qr_code_2_rounded,
                    'Gerar PIX de pagamento',
                  ),
                ),
                PopupMenuItem(
                  value: 'payments',
                  enabled: _editingAllowed,
                  child: const _MenuLabel(
                    Icons.payments_outlined,
                    'Adicionar/Remover pagamento',
                  ),
                ),
                const PopupMenuItem(
                  value: 'collectionMessage',
                  child: _MenuLabel(
                    Icons.request_quote_outlined,
                    'Gerar mensagem de cobrança',
                  ),
                ),
                const PopupMenuItem(
                  value: 'overdueMessage',
                  child: _MenuLabel(
                    Icons.notification_important_outlined,
                    'Gerar mensagem de atraso',
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(top: false, child: _buildResponsiveContent()),
        bottomNavigationBar: _ExistingLoanActionBar(
          saving: _saving,
          hasChanges: showSaveAction,
          onSave: _saveChanges,
          onBack: _closeScreen,
        ),
        floatingActionButton: _editingAllowed
            ? FloatingActionButton(
                heroTag: 'payments-${_installment.id}',
                tooltip: 'Pagamentos',
                onPressed: _saving || _closing ? null : _openPayments,
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                child: const Icon(Icons.payments_outlined),
              )
            : null,
      ),
    );
  }

  Widget _buildResponsiveContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool twoColumns = constraints.maxWidth >= 340;
        final bool roomy = constraints.maxWidth >= 500;
        final double fontSize = roomy ? 15 : 14;
        final double gap = roomy ? 12 : 7;
        final double horizontalPadding = roomy ? 18 : 14;

        Widget pair(Widget first, Widget second) {
          if (!twoColumns) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                first,
                SizedBox(height: gap),
                second,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              SizedBox(width: gap),
              Expanded(child: second),
            ],
          );
        }

        Widget readOnly(String label, String value) => _ReadOnlyValue(
          label: label,
          value: value,
          spacious: true,
          fontSize: fontSize,
          loanFieldStyle: true,
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            roomy ? 16 : 14,
            horizontalPadding,
            28,
          ),
          children: [
            pair(
              readOnly('ID da parcela', '${_installment.id}'),
              readOnly('Número da parcela', _installment.number),
            ),
            SizedBox(height: gap),
            _DateField(
              label: 'Data de vencimento',
              controller: _due,
              enabled: _canEdit,
              spacious: true,
              fontSize: fontSize,
              leadingIcon: true,
              loanFieldStyle: true,
              onTap: _pickDueDate,
            ),
            if (_due.text != _date(_installment.dueDate)) ...[
              SizedBox(height: gap),
              _CompactField(
                label: 'Observação da alteração da data',
                controller: _note,
                enabled: _canEdit,
                maxLines: 2,
                fontSize: fontSize,
                spacious: true,
                loanFieldStyle: true,
              ),
            ],
            SizedBox(height: gap),
            pair(
              _MoneyField(
                label: 'Valor da parcela',
                controller: _amount,
                enabled: _canEdit,
                spacious: true,
                fontSize: fontSize,
                loanFieldStyle: true,
              ),
              _MoneyField(
                label: 'Valor dos juros',
                controller: _interest,
                enabled: _canEdit,
                spacious: true,
                fontSize: fontSize,
                loanFieldStyle: true,
              ),
            ),
            SizedBox(height: gap),
            pair(
              readOnly(
                'Valor total da parcela',
                _currency(
                  _parseMoney(_amount.text) + _parseMoney(_interest.text),
                ),
              ),
              readOnly('Valor pago', _currency(_installment.paidAmount)),
            ),
            SizedBox(height: gap),
            pair(
              readOnly('Saldo a pagar', _currency(_installment.balanceAmount)),
              readOnly('Último pagamento', _date(_installment.lastPaymentDate)),
            ),
            SizedBox(height: gap),
            readOnly(
              'Status PIX',
              _loadingPix ? 'Consultando...' : (_pix?.status ?? '—'),
            ),
            SizedBox(height: gap),
            _LegacyCopyValue(
              label: 'PIX copia e cola',
              value: _pix?.copyAndPaste ?? '—',
              spacious: true,
              fontSize: fontSize,
              loanFieldStyle: true,
            ),
            SizedBox(height: gap),
            pair(
              readOnly('Emissão do PIX', _dateTime(_pix?.createdAt)),
              readOnly('Atualização do PIX', _dateTime(_pix?.updatedAt)),
            ),
          ],
        );
      },
    );
  }

  void _refreshFormState() {
    if (!mounted || _syncingControllers) return;
    setState(() {});
  }

  Future<void> _pickDueDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime? selected = await showAppDatePickerDialog(
      context: context,
      initialDate: _parseDate(_due.text) ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5, 12, 31),
      locale: const Locale('pt', 'BR'),
    );
    if (selected != null) {
      setState(() => _due.text = DateFormat('dd/MM/yyyy').format(selected));
    }
  }

  Future<bool> _saveChanges() async {
    if (!_hasChanges) return true;
    if (!_editingAllowed) return false;
    if (_due.text != _date(_installment.dueDate) && _note.text.trim().isEmpty) {
      await _legacyAlert(
        context,
        'Observação obrigatória',
        'Informe o motivo da alteração da data de vencimento.',
      );
      return false;
    }
    setState(() => _saving = true);
    try {
      final AppLoanDetail detail = await _service.updateInstallment(
        widget.loan.id,
        _installment.id,
        {
          'dueDate': _isoDate(_due.text),
          'amount': _parseMoney(_amount.text),
          'interestAmount': _parseMoney(_interest.text),
          'dueDateNote': _note.text,
        },
      );
      if (!mounted) return false;
      _replaceInstallment(detail);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Parcela atualizada.')));
      return true;
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _legacyAlert(context, 'Não foi possível salvar', error.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeScreen() async {
    if (_closing || _saving) return;
    setState(() => _closing = true);
    if (_hasChanges) {
      final bool discard = await _confirmDiscardChanges();
      if (!mounted) return;
      if (!discard) {
        setState(() => _closing = false);
        return;
      }
    }
    setState(() {
      _allowPop = true;
      _closing = false;
    });
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _handleMenuAction(String value) async {
    if (!await _ensureChangesSaved()) return;
    switch (value) {
      case 'sendPix':
        await _sendPixWhatsapp();
      case 'pix':
        await _openPix();
      case 'payments':
        await _openPayments();
      case 'collectionMessage':
        await _showInstallmentMessage('COBRANCA');
      case 'overdueMessage':
        await _showInstallmentMessage('ATRASO');
    }
  }

  Future<void> _openPayments() async {
    if (!await _ensureChangesSaved()) return;
    if (!mounted) return;
    final Widget screen = _LegacyPaymentsScreen(
      loan: widget.loan,
      installment: _installment,
    );
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 1024) {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 620, height: 720, child: screen),
        ),
      );
    } else {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(fullscreenDialog: true, builder: (_) => screen),
      );
    }
    await _reloadInstallment();
  }

  Future<void> _openPix() async {
    if (!mounted) return;
    if (_installment.balanceAmount <= 0 && _pix == null) {
      await showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('PIX indisponível'),
          content: const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'Esta parcela não possui saldo disponível para gerar um PIX.',
            ),
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
      return;
    }
    bool pixChanged = false;
    await showAppDialog<void>(
      context: context,
      title: 'Cobrança PIX',
      subtitle: '${_installment.number}ª parcela',
      icon: Icons.qr_code_2_rounded,
      maxWidth: 520,
      builder: (_) => _PixSheet(
        loanId: widget.loan.id,
        installmentId: _installment.id,
        installmentLabel: '${_installment.number}ª parcela',
        availableAmount: _installment.balanceAmount,
        initialCharge: _pix,
        canGenerate: _canGeneratePix,
        onChanged: () => pixChanged = true,
      ),
    );
    if (pixChanged && mounted) {
      await _reloadInstallment();
      await _loadPix();
    }
  }

  Future<void> _sendPixWhatsapp() async {
    if (_loadingPix) await _loadPix();
    final AppPixCharge? charge = _pix;
    if (charge == null || charge.status.toUpperCase() != 'AGUARDANDO') {
      if (mounted) {
        await _legacyAlert(
          context,
          'PIX não encontrado',
          'Esta parcela não possui um PIX aguardando pagamento.',
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final AppPixCharge updated = await _service.sendPixWhatsapp(charge.id);
      if (!mounted) return;
      setState(() => _pix = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIX enviado pelo WhatsApp.')),
      );
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _legacyAlert(context, 'Não foi possível enviar', error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showInstallmentMessage(String type) async {
    setState(() => _saving = true);
    try {
      final String message = await _service.fetchInstallmentMessage(
        widget.loan.id,
        _installment.id,
        type,
      );
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        title: type == 'ATRASO' ? 'Mensagem de atraso' : 'Mensagem de cobrança',
        subtitle: 'Edite o texto antes de copiar ou enviar.',
        icon: type == 'ATRASO'
            ? Icons.notification_important_outlined
            : Icons.request_quote_outlined,
        maxWidth: 500,
        maxHeight: 520,
        builder: (_) => _LoanMessageEditor(initialText: message),
      );
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _legacyAlert(context, 'Não foi possível gerar', error.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reloadInstallment() async {
    try {
      final AppLoanDetail detail = await _service.fetchDetail(widget.loan.id);
      if (!mounted) return;
      _replaceInstallment(detail);
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _legacyAlert(
          context,
          'Não foi possível atualizar',
          error.message,
        );
      }
    }
  }

  void _replaceInstallment(AppLoanDetail detail) {
    final AppLoanInstallment current = detail.installments.firstWhere(
      (item) => item.id == _installment.id,
      orElse: () => _installment,
    );
    _syncingControllers = true;
    _installment = current;
    try {
      _due.text = _date(current.dueDate);
      _amount.text = _plainMoney(current.amount);
      _interest.text = _plainMoney(current.interestAmount);
      _note.text = current.dueDateNote ?? '';
    } finally {
      _syncingControllers = false;
    }
    if (mounted) setState(() {});
  }

  Future<bool> _ensureChangesSaved() async {
    if (!_hasChanges) return true;
    await _legacyAlert(
      context,
      'Alterações não salvas',
      'Salve as alterações da parcela antes de continuar.',
    );
    return false;
  }

  Future<bool> _confirmDiscardChanges() async =>
      await showAppCupertinoDialog<bool>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Descartar alterações?'),
          content: const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'As alterações realizadas nesta parcela serão perdidas.',
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
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;
}

class _LegacyCopyValue extends StatelessWidget {
  final String label;
  final String value;
  final bool spacious;
  final double fontSize;
  final bool loanFieldStyle;

  const _LegacyCopyValue({
    required this.label,
    required this.value,
    this.spacious = false,
    this.fontSize = 12,
    this.loanFieldStyle = false,
  });

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration:
        (loanFieldStyle
                ? _loanFieldDecoration(
                    context,
                    label,
                    editable: false,
                    spacious: spacious,
                  )
                : _fieldDecoration(context, label, spacious: spacious))
            .copyWith(
              suffixIcon: value == '—'
                  ? null
                  : IconButton(
                      tooltip: 'Copiar',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: value));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Código PIX copiado.'),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        Icons.copy_all_outlined,
                        size: 18,
                        color: loanFieldStyle
                            ? context.colors.textPrimary.withValues(alpha: 0.42)
                            : null,
                      ),
                    ),
            ),
    child: SelectableText(
      value,
      maxLines: 3,
      style: TextStyle(
        color: loanFieldStyle
            ? context.colors.textPrimary.withValues(alpha: 0.42)
            : null,
        fontSize: fontSize,
        height: 1.3,
      ),
    ),
  );
}

class _LegacyPaymentsScreen extends StatefulWidget {
  final AppLoanDetail loan;
  final AppLoanInstallment installment;

  const _LegacyPaymentsScreen({required this.loan, required this.installment});

  @override
  State<_LegacyPaymentsScreen> createState() => _LegacyPaymentsScreenState();
}

class _LegacyPaymentsScreenState extends State<_LegacyPaymentsScreen> {
  final LoanService _service = LoanService();
  late AppLoanInstallment _installment = widget.installment;
  bool _working = false;

  bool get _canEdit =>
      widget.loan.canEdit && !widget.loan.operationLocked && !_working;

  @override
  Widget build(BuildContext context) {
    final double received = _installment.payments.fold<double>(
      0,
      (total, payment) => total + payment.amount,
    );
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pagamentos da parcela ${_installment.number}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              'Cliente: ${widget.loan.clientName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: _installment.payments.isEmpty
          ? const _EmptyTab(
              icon: Icons.payments_outlined,
              text: 'Nada encontrado',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 92),
              itemCount: _installment.payments.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.colors.divider),
              itemBuilder: (_, index) => _LegacyPaymentRow(
                payment: _installment.payments[index],
                canEdit: _canEdit,
                onEdit: () => _editPayment(_installment.payments[index]),
                onDelete: () => _deletePayment(_installment.payments[index]),
              ),
            ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              heroTag: 'new-payment-${_installment.id}',
              tooltip: 'Adicionar pagamento',
              onPressed: _addPayment,
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegacyPaymentTotals(
            installmentAmount: _installment.totalAmount,
            receivedAmount: received,
            balanceAmount: _installment.balanceAmount,
            safeBottom: false,
          ),
          _PageCloseActionBar(
            busy: _working,
            onClose: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Future<void> _addPayment() async {
    final Map<String, dynamic>? data = await _showPaymentDialog(
      context,
      title: 'Adicionar pagamento',
    );
    if (data == null) return;
    await _execute(
      () =>
          _service.addInstallmentPayment(widget.loan.id, _installment.id, data),
    );
  }

  Future<void> _editPayment(AppLoanPayment payment) async {
    if (payment.automatic) return;
    final Map<String, dynamic>? data = await _showPaymentDialog(
      context,
      title: 'Editar pagamento',
      payment: payment,
    );
    if (data == null) return;
    await _execute(
      () => _service.updateInstallmentPayment(
        widget.loan.id,
        _installment.id,
        payment.id,
        data,
      ),
    );
  }

  Future<void> _deletePayment(AppLoanPayment payment) async {
    if (payment.automatic) return;
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Excluir pagamento?'),
            content: Text(
              'O lançamento de ${_currency(payment.amount)} será removido.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
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
    if (!confirmed) return;
    await _execute(
      () => _service.deleteInstallmentPayment(
        widget.loan.id,
        _installment.id,
        payment.id,
      ),
    );
  }

  Future<void> _execute(Future<AppLoanDetail> Function() operation) async {
    setState(() => _working = true);
    try {
      final AppLoanDetail detail = await operation();
      if (!mounted) return;
      setState(() {
        _installment = detail.installments.firstWhere(
          (item) => item.id == _installment.id,
          orElse: () => _installment,
        );
      });
    } on LoanServiceException catch (error) {
      if (mounted) {
        await _legacyAlert(context, 'Não foi possível concluir', error.message);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _LegacyPaymentRow extends StatelessWidget {
  final AppLoanPayment payment;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LegacyPaymentRow({
    required this.payment,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _currency(payment.amount),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _date(payment.date),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                if ((payment.note ?? '').trim().isNotEmpty)
                  Text(
                    payment.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: context.colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: canEdit && !payment.automatic ? onEdit : null,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: canEdit && !payment.automatic ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _LegacyPaymentTotals extends StatelessWidget {
  final double installmentAmount;
  final double receivedAmount;
  final double balanceAmount;
  final bool safeBottom;

  const _LegacyPaymentTotals({
    required this.installmentAmount,
    required this.receivedAmount,
    required this.balanceAmount,
    this.safeBottom = true,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    elevation: 8,
    child: SafeArea(
      top: false,
      bottom: safeBottom,
      minimum: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _LegacyPaymentMetric('Valor Parcela', installmentAmount),
          _LegacyPaymentMetric('Recebido', receivedAmount),
          _LegacyPaymentMetric('À Receber', balanceAmount),
        ],
      ),
    ),
  );
}

class _PageCloseActionBar extends StatelessWidget {
  final bool busy;
  final VoidCallback onClose;

  const _PageCloseActionBar({required this.busy, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final String label = kIsWeb && MediaQuery.sizeOf(context).width >= 1024
        ? 'FECHAR'
        : 'VOLTAR';
    return Material(
      color: context.colors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: busy ? null : onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side: BorderSide(color: context.colors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegacyPaymentMetric extends StatelessWidget {
  final String label;
  final double value;

  const _LegacyPaymentMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5)),
        const SizedBox(height: 2),
        Text(
          _currency(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.primary,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

Future<void> _legacyAlert(BuildContext context, String title, String message) =>
    showAppCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 6),
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

class _PixSheet extends StatefulWidget {
  final int loanId;
  final int? installmentId;
  final String? installmentLabel;
  final double availableAmount;
  final AppPixCharge? initialCharge;
  final bool canGenerate;
  final VoidCallback onChanged;

  const _PixSheet({
    required this.loanId,
    required this.installmentId,
    required this.installmentLabel,
    required this.availableAmount,
    required this.initialCharge,
    required this.canGenerate,
    required this.onChanged,
  });

  @override
  State<_PixSheet> createState() => _PixSheetState();
}

class _PixSheetState extends State<_PixSheet> {
  final LoanService _service = LoanService();
  late final TextEditingController _amount = TextEditingController(
    text: _plainMoney(widget.availableAmount),
  );
  late AppPixCharge? _charge = widget.initialCharge;
  bool _working = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPixCharge? charge = _charge;
    return Material(
      color: context.colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool compact = constraints.maxWidth < 600;
          final double horizontalPadding = compact ? 12 : 18;
          return ListView(
            primary: false,
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              2,
              horizontalPadding,
              compact ? 9 : 13,
            ),
            children: [
              if (charge != null) _chargeCard(charge),
              if (charge != null &&
                  widget.canGenerate &&
                  widget.availableAmount > 0)
                SizedBox(height: compact ? 7 : 9),
              if (widget.canGenerate && widget.availableAmount > 0)
                _PixSectionCard(
                  icon: Icons.add_card_rounded,
                  title: charge == null ? 'Gerar PIX' : 'Gerar novo PIX',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _dialogMoneyField(
                        context,
                        label: 'Valor da cobrança',
                        controller: _amount,
                        enabled: !_working,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Saldo disponível: ${_currency(widget.availableAmount)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DialogActionButtons(
                        confirmLabel: charge == null
                            ? 'Gerar PIX'
                            : 'Substituir',
                        loading: _working,
                        onCancel: () => Navigator.pop(context),
                        onConfirm: _generate,
                      ),
                    ],
                  ),
                ),
              if (charge != null &&
                  widget.canGenerate &&
                  widget.availableAmount > 0) ...[
                SizedBox(height: compact ? 7 : 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ao substituir, o PIX atual será cancelado automaticamente.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 10.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _chargeCard(AppPixCharge charge) {
    final String normalizedStatus = charge.status.trim().toUpperCase();
    final Color statusColor = normalizedStatus.contains('AGUARD')
        ? Colors.blue.shade600
        : switch (normalizedStatus) {
            'PAGO' => context.colors.primary,
            'CANCELADO' || 'ERRO' => Colors.red,
            _ => Colors.orange,
          };
    return _PixSectionCard(
      icon: Icons.pix_rounded,
      title: 'PIX atual',
      tinted: true,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          charge.status,
          style: TextStyle(
            color: statusColor,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixInfoRow(
            label: 'Valor',
            value: _currency(charge.amount),
            valueColor: context.colors.primary,
          ),
          _PixInfoRow(label: 'TXID', value: charge.transactionId),
          if (charge.error != null) ...[
            const SizedBox(height: 5),
            Text(
              charge.error!,
              style: const TextStyle(color: Colors.red, fontSize: 10.5),
            ),
          ],
          if (charge.copyAndPaste != null) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.divider),
              ),
              child: SelectableText(
                charge.copyAndPaste!,
                maxLines: 5,
                style: const TextStyle(fontSize: 10.5, height: 1.25),
              ),
            ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final List<Widget> actions = [
                if (charge.copyAndPaste != null)
                  _PixActionButton(
                    icon: Icons.copy_all_outlined,
                    label: 'Copiar',
                    onPressed: _working ? null : _copy,
                  ),
                if (charge.copyAndPaste != null)
                  _PixActionButton(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    onPressed: _working ? null : _sendWhatsapp,
                  ),
                _PixActionButton(
                  icon: Icons.update_rounded,
                  label: 'Consultar',
                  onPressed: _working ? null : _refresh,
                ),
              ];
              return Row(
                children: [
                  for (int index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Expanded(child: actions[index]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    final double amount = _parseMoney(_amount.text);
    if (amount <= 0 || amount > widget.availableAmount + .001) {
      await _alert(
        'Valor inválido',
        'Informe um valor entre R\$ 0,01 e ${_currency(widget.availableAmount)}.',
      );
      return;
    }
    final bool confirmed =
        await showAppCupertinoDialog<bool>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Gerar cobrança PIX?'),
            content: Text(
              _charge == null
                  ? 'Será criada uma cobrança real no Sicredi no valor de ${_currency(amount)}.'
                  : 'O PIX atual será cancelado no Sicredi e substituído por uma cobrança de ${_currency(amount)}.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Gerar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _execute(() async {
      _charge = await _service.generatePix(
        widget.loanId,
        installmentId: widget.installmentId,
        amount: amount,
      );
    }, success: 'PIX gerado com segurança.');
  }

  Future<void> _refresh() => _execute(() async {
    _charge = await _service.refreshPix(_charge!.id);
  }, success: 'Situação do PIX atualizada.');

  Future<void> _sendWhatsapp() => _execute(() async {
    _charge = await _service.sendPixWhatsapp(_charge!.id);
  }, success: 'PIX enviado pelo WhatsApp.');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _charge!.copyAndPaste!));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Código PIX copiado.')));
    }
  }

  Future<void> _execute(
    Future<void> Function() operation, {
    required String success,
  }) async {
    setState(() => _working = true);
    try {
      await operation();
      if (!mounted) return;
      widget.onChanged();
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } on LoanServiceException catch (error) {
      if (mounted) await _alert('Não foi possível concluir', error.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _alert(String title, String message) =>
      showAppCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
}

class _PixInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _PixInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PixSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool tinted;

  const _PixSectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color background = tinted
        ? Color.alphaBlend(
            context.colors.primary.withValues(alpha: 0.025),
            context.colors.surface,
          )
        : context.colors.surface;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 7), trailing!],
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _PixActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PixActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.primary,
        disabledForegroundColor: context.colors.disabled,
        side: BorderSide(color: context.colors.primary, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: const EdgeInsets.symmetric(horizontal: 3),
      ),
      icon: Icon(icon, size: 14),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> _showPaymentDialog(
  BuildContext context, {
  required String title,
  AppLoanPayment? payment,
  double? initialAmount,
}) {
  return showAppDialog<Map<String, dynamic>>(
    context: context,
    title: title,
    subtitle: 'Informe o valor, a data e uma observação opcional.',
    icon: Icons.payments_outlined,
    maxWidth: 480,
    builder: (_) => _PaymentDialog(
      title: title,
      payment: payment,
      initialAmount: initialAmount,
    ),
  );
}

class _DialogActionButtons extends StatelessWidget {
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool loading;

  const _DialogActionButtons({
    this.cancelLabel = 'Cancelar',
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: loading ? null : onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
              side: BorderSide(color: context.colors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(cancelLabel.toUpperCase()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: loading ? null : onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: loading
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(confirmLabel.toUpperCase()),
          ),
        ),
      ],
    ),
  );
}

class _DialogDateTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _DialogDateTextField({required this.controller, this.label = 'Data'});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    inputFormatters: const [_BrazilianDateInputFormatter()],
    textInputAction: TextInputAction.next,
    style: TextStyle(fontSize: _dialogDateTextSize(context)),
    decoration: _dialogFieldDecoration(context, label).copyWith(
      suffixIcon: IconButton(
        tooltip: 'Selecionar data',
        onPressed: () => _pickCalendarDate(context, controller),
        icon: Icon(
          Icons.calendar_month_outlined,
          size: 19,
          color: context.colors.textSecondary,
        ),
      ),
    ),
  );
}

Widget _dialogMoneyField(
  BuildContext context, {
  required String label,
  required TextEditingController controller,
  bool enabled = true,
}) => TextField(
  controller: controller,
  enabled: enabled,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: const [_BrazilianMoneyInputFormatter()],
  textInputAction: TextInputAction.next,
  style: const TextStyle(fontSize: 14),
  decoration: _dialogFieldDecoration(context, label, prefix: 'R\$ '),
);

Future<void> _pickCalendarDate(
  BuildContext context,
  TextEditingController controller,
) async {
  FocusScope.of(context).unfocus();
  final DateTime today = DateUtils.dateOnly(DateTime.now());
  final DateTime firstDate = DateTime(today.year - 5);
  final DateTime lastDate = DateTime(today.year + 5, 12, 31);
  final DateTime typedDate = _parseDate(controller.text) ?? today;
  final DateTime initialDate = typedDate.isBefore(firstDate)
      ? firstDate
      : typedDate.isAfter(lastDate)
      ? lastDate
      : typedDate;
  final DateTime? selected = await showAppDatePickerDialog(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    locale: const Locale('pt', 'BR'),
  );
  if (selected != null) {
    controller.text = DateFormat('dd/MM/yyyy').format(selected);
  }
}

class _PaymentDialog extends StatefulWidget {
  final String title;
  final AppLoanPayment? payment;
  final double? initialAmount;

  const _PaymentDialog({required this.title, this.payment, this.initialAmount});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController amount = TextEditingController(
    text: widget.payment != null
        ? _plainMoney(widget.payment!.amount)
        : widget.initialAmount != null && widget.initialAmount! > 0
        ? _plainMoney(widget.initialAmount!)
        : '',
  );
  late final TextEditingController date = TextEditingController(
    text: _date(widget.payment?.date ?? DateTime.now()),
  );
  late final TextEditingController note = TextEditingController(
    text: widget.payment?.note ?? '',
  );
  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 600;
        return ListView(
          primary: false,
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            2,
            compact ? 12 : 18,
            compact ? 12 : 16,
          ),
          children: [
            _PixSectionCard(
              icon: Icons.receipt_long_outlined,
              title: 'Dados do pagamento',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _dialogMoneyField(
                          context,
                          label: 'Valor',
                          controller: amount,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DialogDateTextField(
                          controller: date,
                          label: 'Data',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(fontSize: 14),
                    decoration: _dialogFieldDecoration(
                      context,
                      'Observação',
                    ).copyWith(alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _DialogActionButtons(
              confirmLabel: 'Salvar',
              onCancel: () => Navigator.pop(context),
              onConfirm: _submit,
            ),
          ],
        );
      },
    ),
  );

  void _submit() {
    final DateTime? parsedDate = _parseDate(date.text);
    if (parsedDate == null) {
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Data inválida'),
          content: const Text('Informe uma data válida no formato dd/mm/aaaa.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'amount': _parseMoney(amount.text),
      'date': DateFormat('yyyy-MM-dd').format(parsedDate),
      'note': note.text,
    });
  }
}

class _InterestRollDialog extends StatefulWidget {
  final AppLoanDetail loan;
  final AppLoanInstallment installment;

  const _InterestRollDialog({required this.loan, required this.installment});

  @override
  State<_InterestRollDialog> createState() => _InterestRollDialogState();
}

class _InterestRollDialogState extends State<_InterestRollDialog> {
  late final TextEditingController amount = TextEditingController(
    text: _plainMoney(
      widget.loan.interestAmount > 0
          ? widget.loan.interestAmount
          : widget.installment.interestAmount,
    ),
  );
  late final TextEditingController paymentDate = TextEditingController(
    text: _date(DateTime.now()),
  );
  late final TextEditingController newDueDate = TextEditingController(
    text: _date(
      _nextInstallmentDue(
        widget.installment.dueDate,
        widget.loan.paymentTypeCode,
      ),
    ),
  );
  final TextEditingController note = TextEditingController();

  @override
  void dispose() {
    amount.dispose();
    paymentDate.dispose();
    newDueDate.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 600;
        return ListView(
          primary: false,
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            2,
            compact ? 12 : 18,
            compact ? 12 : 16,
          ),
          children: [
            _PixSectionCard(
              icon: Icons.percent_rounded,
              title: 'Dados do recebimento',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dialogMoneyField(
                    context,
                    label: 'Valor dos juros',
                    controller: amount,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _interestDateField(
                          context,
                          paymentDate,
                          'Data do recebimento',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _interestDateField(
                          context,
                          newDueDate,
                          'Novo vencimento',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(fontSize: 14),
                    decoration: _dialogFieldDecoration(
                      context,
                      'Observação',
                    ).copyWith(alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
            if (!widget.loan.administrator) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A prorrogação será aplicada somente após a conferência do administrador.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            _DialogActionButtons(
              confirmLabel: 'Lançar',
              onCancel: () => Navigator.pop(context),
              onConfirm: _submit,
            ),
          ],
        );
      },
    ),
  );

  Widget _interestDateField(
    BuildContext context,
    TextEditingController controller,
    String label,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    inputFormatters: const [_BrazilianDateInputFormatter()],
    textInputAction: TextInputAction.next,
    style: TextStyle(fontSize: _dialogDateTextSize(context)),
    decoration: _dialogFieldDecoration(context, label).copyWith(
      suffixIcon: IconButton(
        tooltip: 'Selecionar data',
        onPressed: () => _pickCalendarDate(context, controller),
        icon: Icon(
          Icons.calendar_month_outlined,
          size: 19,
          color: context.colors.textSecondary,
        ),
      ),
    ),
  );

  void _submit() {
    final double value = _parseMoney(amount.text);
    final DateTime? due = _parseDate(newDueDate.text);
    final DateTime? received = _parseDate(paymentDate.text);
    final DateTime? current = widget.installment.dueDate;
    if (value <= 0) {
      _showValidation('Informe um valor de juros maior que zero.');
      return;
    }
    if (due == null || received == null) {
      _showValidation('Informe datas válidas no formato dd/mm/aaaa.');
      return;
    }
    if (current != null && !due.isAfter(DateUtils.dateOnly(current))) {
      _showValidation(
        'O novo vencimento deve ser posterior ao vencimento atual.',
      );
      return;
    }
    Navigator.pop(context, {
      'installmentId': widget.installment.id,
      'amount': value,
      'date': DateFormat('yyyy-MM-dd').format(received),
      'newDueDate': DateFormat('yyyy-MM-dd').format(due),
      'note': note.text,
    });
  }

  void _showValidation(String message) {
    showAppCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Dados inválidos'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _NegotiationDialog extends StatefulWidget {
  final AppLoanDetail loan;
  final bool renewal;
  const _NegotiationDialog({required this.loan, required this.renewal});

  @override
  State<_NegotiationDialog> createState() => _NegotiationDialogState();
}

class _NegotiationDialogState extends State<_NegotiationDialog> {
  double get _pendingDebt => widget.loan.installments
      .where((item) => item.pending && item.balanceAmount > 0)
      .fold(0.0, (total, item) => total + item.balanceAmount);

  late final original = TextEditingController(
    text: _plainMoney(widget.loan.loanedAmount),
  );
  late final debt = TextEditingController(text: _plainMoney(_pendingDebt));
  final additional = TextEditingController(text: '0,00');
  final interest = TextEditingController(text: '0,00');
  final percent = TextEditingController(text: '0,00');
  final installments = TextEditingController(text: '1');
  bool _syncingInterest = false;

  double get _principal =>
      widget.renewal ? _parseMoney(additional.text) : _parseMoney(debt.text);

  bool get _canCalculate => !widget.renewal || _principal > 0;

  double get _total =>
      _canCalculate ? _principal + _parseMoney(interest.text) : 0;

  double get _clientReceives =>
      _canCalculate ? math.max(0, _principal - _parseMoney(debt.text)) : 0;

  double get _installmentValue {
    final count = int.tryParse(installments.text) ?? 0;
    return count > 0 ? _total / count : 0;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [debt, additional, installments]) {
      controller.addListener(_refreshValues);
    }
    interest.addListener(_interestChanged);
    percent.addListener(_percentChanged);
    // O aplicativo antigo inicia o refinanciamento com 10% de juros.
    if (!widget.renewal) percent.text = _plainMoney(10);
  }

  void _refreshValues() {
    if (mounted) setState(() {});
  }

  void _interestChanged() {
    if (!widget.renewal && !_syncingInterest) {
      _syncingInterest = true;
      final debtValue = _parseMoney(debt.text);
      final double value = debtValue <= 0
          ? 0.0
          : (_parseMoney(interest.text) / debtValue) * 100;
      percent.text = _plainMoney(value);
      _syncingInterest = false;
    }
    _refreshValues();
  }

  void _percentChanged() {
    if (!widget.renewal && !_syncingInterest) {
      _syncingInterest = true;
      interest.text = _plainMoney(
        _parseMoney(debt.text) * (_parseMoney(percent.text) / 100),
      );
      _syncingInterest = false;
    }
    _refreshValues();
  }

  @override
  void dispose() {
    for (final c in [
      original,
      debt,
      additional,
      interest,
      percent,
      installments,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 600;
        return ListView(
          primary: false,
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            2,
            compact ? 12 : 18,
            compact ? 12 : 16,
          ),
          children: [
            _PixSectionCard(
              icon: Icons.swap_horiz_rounded,
              title: 'Condições da negociação',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.renewal)
                    _responsivePair(
                      _moneyInput(
                        context,
                        'Restante a pagar',
                        debt,
                        readOnly: true,
                      ),
                      _moneyInput(context, 'Valor a emprestar', additional),
                    )
                  else
                    _responsivePair(
                      _moneyInput(
                        context,
                        'Valor emprestado',
                        original,
                        readOnly: true,
                      ),
                      _moneyInput(
                        context,
                        'Valor devedor',
                        debt,
                        readOnly: true,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (widget.renewal)
                    _responsivePair(
                      _moneyInput(context, 'Valor dos juros', interest),
                      _summaryValue(
                        context,
                        'Total a pagar',
                        _currency(_total),
                      ),
                    )
                  else
                    _responsivePair(
                      _percentInput(context),
                      _moneyInput(context, 'Valor dos juros', interest),
                    ),
                  const SizedBox(height: 8),
                  _responsivePair(
                    _summaryValue(
                      context,
                      widget.renewal
                          ? 'Valor que o cliente receberá'
                          : 'Valor total com juros',
                      _currency(widget.renewal ? _clientReceives : _total),
                    ),
                    TextField(
                      controller: installments,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 14),
                      decoration: _dialogFieldDecoration(
                        context,
                        'Nº de parcelas',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _summaryValue(
                    context,
                    'Valor da parcela',
                    _currency(_installmentValue),
                  ),
                ],
              ),
            ),
            if (widget.renewal) ...[
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A data e os demais dados poderão ser alterados depois da renovação.',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            _DialogActionButtons(
              confirmLabel: widget.renewal ? 'Renovar' : 'Refinanciar',
              onCancel: () => Navigator.pop(context),
              onConfirm: _submit,
            ),
          ],
        );
      },
    ),
  );

  Widget _responsivePair(Widget first, Widget second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: 8),
      Expanded(child: second),
    ],
  );

  Widget _moneyInput(
    BuildContext context,
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    final InputDecoration decoration = _dialogFieldDecoration(
      context,
      label,
      prefix: 'R\$ ',
    );
    return TextField(
      controller: controller,
      readOnly: readOnly,
      showCursor: !readOnly,
      enableInteractiveSelection: !readOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: readOnly
          ? const []
          : const [_BrazilianMoneyInputFormatter()],
      textInputAction: readOnly ? TextInputAction.none : TextInputAction.next,
      style: const TextStyle(fontSize: 14),
      decoration: readOnly
          ? decoration.copyWith(fillColor: _readOnlyDialogFill(context))
          : decoration,
    );
  }

  Widget _percentInput(BuildContext context) => TextField(
    controller: percent,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [_BrazilianMoneyInputFormatter()],
    textInputAction: TextInputAction.next,
    style: const TextStyle(fontSize: 14),
    decoration: _dialogFieldDecoration(
      context,
      '% Juros',
    ).copyWith(suffixText: '%'),
  );

  Widget _summaryValue(BuildContext context, String label, String value) =>
      InputDecorator(
        decoration: _dialogFieldDecoration(
          context,
          label,
        ).copyWith(fillColor: _readOnlyDialogFill(context)),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      );

  void _submit() {
    final count = int.tryParse(installments.text) ?? 0;
    if (_principal <= 0 || _total <= 0 || count < 1) {
      showAppCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Dados inválidos'),
          content: const Text(
            'Informe valores válidos e pelo menos uma parcela.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'debtAmount': _parseMoney(debt.text),
      'additionalAmount': widget.renewal ? _parseMoney(additional.text) : 0,
      'interestAmount': _parseMoney(interest.text),
      'interestPercent': widget.renewal ? 0 : _parseMoney(percent.text),
      'installmentCount': count,
      'firstDueDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'paymentType': widget.loan.paymentTypeCode,
      'notes': widget.loan.notes,
    });
  }
}

Color _readOnlyDialogFill(BuildContext context) => Color.alphaBlend(
  context.colors.primary.withValues(alpha: 0.11),
  context.colors.surface,
);

double _dialogDateTextSize(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 ? 12 : 14;

InputDecoration _dialogFieldDecoration(
  BuildContext context,
  String label, {
  String? prefix,
}) => _fieldDecoration(context, label, prefix: prefix, spacious: true).copyWith(
  fillColor: Color.alphaBlend(
    context.colors.surface.withValues(alpha: 0.82),
    context.colors.background,
  ),
  labelStyle: TextStyle(
    color: context.colors.primary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  ),
  floatingLabelStyle: TextStyle(
    color: context.colors.primary,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  ),
);

InputDecoration _loanFieldDecoration(
  BuildContext context,
  String label, {
  required bool editable,
  String? prefix,
  bool spacious = false,
}) {
  final BorderRadius borderRadius = BorderRadius.circular(spacious ? 12 : 10);
  final InputBorder editableBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(color: context.colors.textPrimary, width: 1),
  );
  final InputBorder readOnlyBorder = OutlineInputBorder(
    borderRadius: borderRadius,
    borderSide: BorderSide(
      color: context.colors.textPrimary.withValues(alpha: 0.14),
      width: 1,
    ),
  );
  final Color valueColor = editable
      ? context.colors.textPrimary
      : context.colors.textPrimary.withValues(alpha: 0.42);

  return InputDecoration(
    labelText: label,
    prefixText: prefix,
    prefixStyle: TextStyle(color: valueColor, fontWeight: FontWeight.normal),
    isDense: !spacious,
    filled: true,
    fillColor: Color.alphaBlend(
      context.colors.surface.withValues(alpha: 0.82),
      context.colors.background,
    ),
    contentPadding: EdgeInsets.symmetric(
      horizontal: spacious ? 14 : 11,
      vertical: spacious ? 15 : 11,
    ),
    labelStyle: TextStyle(
      color: context.colors.primary,
      fontSize: spacious ? 13 : null,
      fontWeight: FontWeight.w700,
    ),
    floatingLabelStyle: TextStyle(
      color: context.colors.primary,
      fontSize: spacious ? 12 : null,
      fontWeight: FontWeight.w700,
    ),
    border: editable ? editableBorder : readOnlyBorder,
    enabledBorder: editable ? editableBorder : readOnlyBorder,
    disabledBorder: readOnlyBorder,
    focusedBorder: editable ? editableBorder : readOnlyBorder,
  );
}

InputDecoration _fieldDecoration(
  BuildContext context,
  String label, {
  String? prefix,
  bool spacious = false,
}) => InputDecoration(
  labelText: label,
  prefixText: prefix,
  isDense: !spacious,
  filled: true,
  fillColor: context.colors.background,
  contentPadding: EdgeInsets.symmetric(
    horizontal: spacious ? 14 : 11,
    vertical: spacious ? 15 : 11,
  ),
  labelStyle: spacious ? const TextStyle(fontSize: 13) : null,
  floatingLabelStyle: spacious
      ? TextStyle(fontSize: 12, color: context.colors.primary)
      : null,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(spacious ? 12 : 10),
    borderSide: BorderSide(color: context.colors.divider),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(spacious ? 12 : 10),
    borderSide: BorderSide(color: context.colors.divider),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(spacious ? 12 : 10),
    borderSide: BorderSide(color: context.colors.primary, width: 1.3),
  ),
);

String _currency(double value) => _loanCurrencyFormatter.format(value);
String _plainMoney(double value) => _loanPlainMoneyFormatter.format(value);

DateTime _nextInstallmentDue(DateTime? current, String type) {
  final DateTime source = DateUtils.dateOnly(current ?? DateTime.now());
  DateTime result;
  switch (type.toUpperCase()) {
    case 'S':
      result = source.add(const Duration(days: 7));
    case 'Q':
      result = source.add(const Duration(days: 14));
    case 'M':
      final int lastDay = DateTime(source.year, source.month + 2, 0).day;
      final int day = source.day > lastDay ? lastDay : source.day;
      result = DateTime(source.year, source.month + 1, day);
    case 'A':
      result = source.add(const Duration(days: 2));
    case 'B':
      result = source.add(const Duration(days: 1));
      while (result.weekday != DateTime.saturday) {
        result = result.add(const Duration(days: 1));
      }
    case 'C':
      result = source.add(const Duration(days: 1));
      while (result.weekday != DateTime.sunday) {
        result = result.add(const Duration(days: 1));
      }
    case 'Z':
      result = source.add(const Duration(days: 1));
      while (result.weekday == DateTime.sunday) {
        result = result.add(const Duration(days: 1));
      }
    default:
      result = source.add(const Duration(days: 1));
      while (result.weekday == DateTime.saturday ||
          result.weekday == DateTime.sunday) {
        result = result.add(const Duration(days: 1));
      }
  }
  if (!{'A', 'B', 'C', 'D', 'Z'}.contains(type.toUpperCase())) {
    if (result.weekday == DateTime.saturday) {
      result = result.add(const Duration(days: 2));
    } else if (result.weekday == DateTime.sunday) {
      result = result.add(const Duration(days: 1));
    }
  }
  return result;
}

double _parseMoney(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^0-9,.-]'), '')
      .replaceAll('.', '')
      .replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

String _date(DateTime? value) =>
    value == null ? '—' : _loanDateFormatter.format(value);
String _dateTime(DateTime? value) =>
    value == null ? '—' : _loanDateTimeFormatter.format(value);
DateTime? _parseDate(String value) {
  try {
    return _loanDateFormatter.parseStrict(value);
  } catch (_) {
    return null;
  }
}

String? _isoDate(String value) {
  final date = _parseDate(value);
  return date == null ? null : _loanIsoDateFormatter.format(date);
}
