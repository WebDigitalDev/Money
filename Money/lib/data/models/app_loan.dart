final class AppLoanSummary {
  final int id;
  final String clientName;
  final int regionId;
  final String regionName;
  final String? cityName;
  final DateTime? nextDueDate;
  final DateTime? createdAt;
  final String status;
  final String statusColor;
  final double receivableAmount;
  final double receivedAmount;
  final double loanedAmount;
  final double profitAmount;
  final String paymentType;
  final bool negotiated;
  final String installmentProgress;
  final bool hasPendingPix;
  final String? collateral;

  const AppLoanSummary({
    required this.id,
    required this.clientName,
    required this.regionId,
    required this.regionName,
    required this.cityName,
    required this.nextDueDate,
    required this.createdAt,
    required this.status,
    required this.statusColor,
    required this.receivableAmount,
    required this.receivedAmount,
    required this.loanedAmount,
    required this.profitAmount,
    required this.paymentType,
    required this.negotiated,
    required this.installmentProgress,
    this.hasPendingPix = false,
    required this.collateral,
  });

  bool get showPendingPix => hasPendingPix;

  factory AppLoanSummary.fromJson(Map<String, dynamic> json) => AppLoanSummary(
    id: _int(json['id']),
    clientName: _text(json['clientName'], fallback: 'Cliente sem nome'),
    regionId: _int(json['regionId']),
    regionName: _text(json['regionName'], fallback: 'Região sem nome'),
    cityName: _nullableText(json['cityName']),
    nextDueDate: _dateTime(json['nextDueDate']),
    createdAt: _dateTime(json['createdAt']),
    status: _text(json['status']),
    statusColor: _text(json['statusColor'], fallback: '#FFFFFF'),
    receivableAmount: _double(json['receivableAmount']),
    receivedAmount: _double(json['receivedAmount']),
    loanedAmount: _double(json['loanedAmount']),
    profitAmount: _double(json['profitAmount']),
    paymentType: _text(json['paymentType']),
    negotiated: json['negotiated'] == true,
    installmentProgress: _text(json['installmentProgress']),
    hasPendingPix: json['hasPendingPix'] == true,
    collateral: _nullableText(json['collateral']),
  );
}

final class AppLoanTotals {
  final int loans;
  final double receivableAmount;
  final double receivedAmount;
  final double profitAmount;
  final double loanedAmount;

  const AppLoanTotals({
    required this.loans,
    required this.receivableAmount,
    required this.receivedAmount,
    required this.profitAmount,
    required this.loanedAmount,
  });

  const AppLoanTotals.empty()
    : loans = 0,
      receivableAmount = 0,
      receivedAmount = 0,
      profitAmount = 0,
      loanedAmount = 0;

  factory AppLoanTotals.fromVisibleLoans(
    Iterable<AppLoanSummary> visibleLoans,
  ) {
    int loans = 0;
    double receivableAmount = 0;
    double receivedAmount = 0;
    double profitAmount = 0;
    double loanedAmount = 0;

    for (final AppLoanSummary loan in visibleLoans) {
      loans++;
      receivableAmount += loan.receivableAmount;
      receivedAmount += loan.receivedAmount;
      loanedAmount += loan.loanedAmount;

      final String status = loan.status.trim().toLowerCase();
      if (status == 'quitado' || status == 'renov/abat') {
        profitAmount += loan.profitAmount;
      }
    }

    return AppLoanTotals(
      loans: loans,
      receivableAmount: receivableAmount,
      receivedAmount: receivedAmount,
      profitAmount: profitAmount,
      loanedAmount: loanedAmount,
    );
  }

  factory AppLoanTotals.fromJson(Map<String, dynamic> json) => AppLoanTotals(
    loans: _int(json['loans']),
    receivableAmount: _double(json['receivableAmount']),
    receivedAmount: _double(json['receivedAmount']),
    profitAmount: _double(json['profitAmount']),
    loanedAmount: _double(json['loanedAmount']),
  );
}

final class AppLoanPage {
  final List<AppLoanSummary> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;
  final bool hasNext;
  final AppLoanTotals totals;

  const AppLoanPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
    required this.hasNext,
    required this.totals,
  });

  factory AppLoanPage.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    return AppLoanPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      AppLoanSummary.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      page: _int(json['page']),
      size: _int(json['size']),
      totalItems: _int(json['totalItems']),
      totalPages: _int(json['totalPages']),
      hasNext: json['hasNext'] == true,
      totals: json['totals'] is Map
          ? AppLoanTotals.fromJson(
              Map<String, dynamic>.from(json['totals'] as Map),
            )
          : const AppLoanTotals.empty(),
    );
  }
}

final class AppLoanFilters {
  final Set<String> statuses;
  final Set<int> regionIds;
  final DateTime? startDate;
  final DateTime? endDate;

  const AppLoanFilters({
    this.statuses = const {},
    this.regionIds = const {},
    this.startDate,
    this.endDate,
  });

  int get activeCount =>
      statuses.length +
      regionIds.length +
      (startDate == null && endDate == null ? 0 : 1);
}

const List<String> appLoanStatuses = [
  'Pendente Aprovação',
  'Lançamento',
  'Em dia',
  'Vence hoje',
  'Desaparecido',
  'Em atraso',
  'Cancelado',
  'Quitado',
  'Renov/Abat',
  'Refinanciado',
];

final class AppLoanDetail {
  final int id;
  final int clientId;
  final String clientName;
  final int regionId;
  final String regionName;
  final DateTime? contractDate;
  final DateTime? firstDueDate;
  final int installmentCount;
  final String? notes;
  final String paymentTypeCode;
  final String paymentType;
  final double loanedAmount;
  final double originalLoanAmount;
  final double discountAmount;
  final double interestAmount;
  final double negotiatedAmount;
  final bool negotiatedOrigin;
  final double lateFeeAmount;
  final double totalAmount;
  final double installmentAmount;
  final double receivedAmount;
  final double receivableAmount;
  final double profitAmount;
  final String? collateral;
  final String? clientOwner;
  final bool missing;
  final bool active;
  final bool refinanced;
  final bool renewed;
  final int numericStatus;
  final String status;
  final String approvalStatus;
  final bool operationLocked;
  final bool hasPendingPix;
  final String? lockReason;
  final bool canEdit;
  final bool administrator;
  final List<AppLoanInstallment> installments;
  final List<AppLoanHistory> history;
  final List<AppLoanApproval> approvals;
  final List<AppLoanOrigin> origins;

  const AppLoanDetail({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.regionId,
    required this.regionName,
    required this.contractDate,
    required this.firstDueDate,
    required this.installmentCount,
    required this.notes,
    required this.paymentTypeCode,
    required this.paymentType,
    required this.loanedAmount,
    required this.originalLoanAmount,
    required this.discountAmount,
    required this.interestAmount,
    required this.negotiatedAmount,
    required this.negotiatedOrigin,
    required this.lateFeeAmount,
    required this.totalAmount,
    required this.installmentAmount,
    required this.receivedAmount,
    required this.receivableAmount,
    required this.profitAmount,
    required this.collateral,
    required this.clientOwner,
    required this.missing,
    required this.active,
    required this.refinanced,
    required this.renewed,
    required this.numericStatus,
    required this.status,
    required this.approvalStatus,
    required this.operationLocked,
    required this.hasPendingPix,
    required this.lockReason,
    required this.canEdit,
    required this.administrator,
    required this.installments,
    required this.history,
    required this.approvals,
    required this.origins,
  });

  factory AppLoanDetail.fromJson(Map<String, dynamic> json) => AppLoanDetail(
    id: _int(json['id']),
    clientId: _int(json['clientId']),
    clientName: _text(json['clientName'], fallback: 'Cliente sem nome'),
    regionId: _int(json['regionId']),
    regionName: _text(json['regionName'], fallback: 'Região sem nome'),
    contractDate: _dateTime(json['contractDate']),
    firstDueDate: _dateTime(json['firstDueDate']),
    installmentCount: _int(json['installmentCount']),
    notes: _nullableText(json['notes']),
    paymentTypeCode: _text(json['paymentTypeCode']),
    paymentType: _text(json['paymentType']),
    loanedAmount: _double(json['loanedAmount']),
    originalLoanAmount: _double(json['originalLoanAmount']),
    discountAmount: _double(json['discountAmount']),
    interestAmount: _double(json['interestAmount']),
    negotiatedAmount: json['negotiatedAmount'] == null
        ? _double(json['interestAmount'])
        : _double(json['negotiatedAmount']),
    negotiatedOrigin: json['negotiatedOrigin'] == true,
    lateFeeAmount: _double(json['lateFeeAmount']),
    totalAmount: _double(json['totalAmount']),
    installmentAmount: _double(json['installmentAmount']),
    receivedAmount: _double(json['receivedAmount']),
    receivableAmount: _double(json['receivableAmount']),
    profitAmount: _double(json['profitAmount']),
    collateral: _nullableText(json['collateral']),
    clientOwner: _nullableText(json['clientOwner']),
    missing: json['missing'] == true,
    active: json['active'] == true,
    refinanced: json['refinanced'] == true,
    renewed: json['renewed'] == true,
    numericStatus: _int(json['numericStatus']),
    status: _text(json['status']),
    approvalStatus: _text(json['approvalStatus']),
    operationLocked: json['operationLocked'] == true,
    hasPendingPix: json['hasPendingPix'] == true,
    lockReason: _nullableText(json['lockReason']),
    canEdit: json['canEdit'] == true,
    administrator: json['administrator'] == true,
    installments: _mapList(json['installments'], AppLoanInstallment.fromJson),
    history: _mapList(json['history'], AppLoanHistory.fromJson),
    approvals: _mapList(json['approvals'], AppLoanApproval.fromJson),
    origins: _mapList(json['origins'], AppLoanOrigin.fromJson),
  );
}

final class AppLoanFeedback {
  final int id;
  final int loanId;
  final String text;
  final int? authorId;
  final String authorName;
  final DateTime? createdAt;
  final int? inheritedFromLoanId;
  final bool inherited;

  const AppLoanFeedback({
    required this.id,
    required this.loanId,
    required this.text,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.inheritedFromLoanId,
    required this.inherited,
  });

  factory AppLoanFeedback.fromJson(Map<String, dynamic> json) =>
      AppLoanFeedback(
        id: _int(json['id']),
        loanId: _int(json['loanId']),
        text: _text(json['text']),
        authorId: _nullableInt(json['authorId']),
        authorName: _text(json['authorName'], fallback: 'Usuário'),
        createdAt: _dateTime(json['createdAt']),
        inheritedFromLoanId: _nullableInt(json['inheritedFromLoanId']),
        inherited: json['inherited'] == true,
      );
}

final class AppLoanInstallment {
  final int id;
  final String number;
  final DateTime? dueDate;
  final DateTime? lastPaymentDate;
  final double amount;
  final double interestAmount;
  final double totalAmount;
  final double paidAmount;
  final double balanceAmount;
  final double overdueAmount;
  final double overdueInterestAmount;
  final int overdueDays;
  final String status;
  final String? dueDateNote;
  final bool pending;
  final bool paymentPendingApproval;
  final List<AppLoanPayment> payments;

  const AppLoanInstallment({
    required this.id,
    required this.number,
    required this.dueDate,
    required this.lastPaymentDate,
    required this.amount,
    required this.interestAmount,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.overdueAmount,
    required this.overdueInterestAmount,
    required this.overdueDays,
    required this.status,
    required this.dueDateNote,
    required this.pending,
    required this.paymentPendingApproval,
    required this.payments,
  });

  factory AppLoanInstallment.fromJson(Map<String, dynamic> json) =>
      AppLoanInstallment(
        id: _int(json['id']),
        number: _text(json['number']),
        dueDate: _dateTime(json['dueDate']),
        lastPaymentDate: _dateTime(json['lastPaymentDate']),
        amount: _double(json['amount']),
        interestAmount: _double(json['interestAmount']),
        totalAmount: _double(json['totalAmount']),
        paidAmount: _double(json['paidAmount']),
        balanceAmount: _double(json['balanceAmount']),
        overdueAmount: _double(json['overdueAmount']),
        overdueInterestAmount: _double(json['overdueInterestAmount']),
        overdueDays: _int(json['overdueDays']),
        status: _text(json['status']),
        dueDateNote: _nullableText(json['dueDateNote']),
        pending: json['pending'] == true,
        paymentPendingApproval: json['paymentPendingApproval'] == true,
        payments: _mapList(json['payments'], AppLoanPayment.fromJson),
      );
}

final class AppLoanPayment {
  final int id;
  final DateTime? date;
  final double amount;
  final String? note;
  final bool automatic;
  final String approvalStatus;
  final String type;

  const AppLoanPayment({
    required this.id,
    required this.date,
    required this.amount,
    required this.note,
    required this.automatic,
    required this.approvalStatus,
    required this.type,
  });

  factory AppLoanPayment.fromJson(Map<String, dynamic> json) => AppLoanPayment(
    id: _int(json['id']),
    date: _dateTime(json['date']),
    amount: _double(json['amount']),
    note: _nullableText(json['note']),
    automatic: json['automatic'] == true,
    approvalStatus: _text(json['approvalStatus']),
    type: _text(json['type']),
  );
}

final class AppLoanHistory {
  final int id;
  final String category;
  final String operation;
  final String description;
  final String username;
  final DateTime? occurredAt;
  const AppLoanHistory({
    required this.id,
    required this.category,
    required this.operation,
    required this.description,
    required this.username,
    required this.occurredAt,
  });
  factory AppLoanHistory.fromJson(Map<String, dynamic> json) => AppLoanHistory(
    id: _int(json['id']),
    category: _text(json['category']),
    operation: _text(json['operation']),
    description: _text(json['description']),
    username: _text(json['username']),
    occurredAt: _dateTime(json['occurredAt']),
  );
}

final class AppLoanApproval {
  final int id;
  final String type;
  final String? action;
  final String status;
  final String description;
  final double amount;
  final String requester;
  final String? approver;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  const AppLoanApproval({
    required this.id,
    required this.type,
    required this.action,
    required this.status,
    required this.description,
    required this.amount,
    required this.requester,
    required this.approver,
    required this.rejectionReason,
    required this.createdAt,
    required this.decidedAt,
  });
  factory AppLoanApproval.fromJson(Map<String, dynamic> json) =>
      AppLoanApproval(
        id: _int(json['id']),
        type: _text(json['type']),
        action: _nullableText(json['action']),
        status: _text(json['status']),
        description: _text(json['description']),
        amount: _double(json['amount']),
        requester: _text(json['requester']),
        approver: _nullableText(json['approver']),
        rejectionReason: _nullableText(json['rejectionReason']),
        createdAt: _dateTime(json['createdAt']),
        decidedAt: _dateTime(json['decidedAt']),
      );
}

final class AppLoanOrigin {
  final int id;
  final String clientName;
  final String regionName;
  final String? cityName;
  final DateTime? nextDueDate;
  final String status;
  final String statusColor;
  final double loanedAmount;
  final double receivedAmount;
  final double receivableAmount;
  final double profitAmount;
  final String paymentType;
  final bool negotiated;
  const AppLoanOrigin({
    required this.id,
    required this.clientName,
    required this.regionName,
    required this.cityName,
    required this.nextDueDate,
    required this.status,
    required this.statusColor,
    required this.loanedAmount,
    required this.receivedAmount,
    required this.receivableAmount,
    required this.profitAmount,
    required this.paymentType,
    required this.negotiated,
  });
  factory AppLoanOrigin.fromJson(Map<String, dynamic> json) => AppLoanOrigin(
    id: _int(json['id']),
    clientName: _text(json['clientName']),
    regionName: _text(json['regionName']),
    cityName: _nullableText(json['cityName']),
    nextDueDate: _dateTime(json['nextDueDate']),
    status: _text(json['status']),
    statusColor: _text(json['statusColor'], fallback: '#FFFFFF'),
    loanedAmount: _double(json['loanedAmount']),
    receivedAmount: _double(json['receivedAmount']),
    receivableAmount: _double(json['receivableAmount']),
    profitAmount: _double(json['profitAmount']),
    paymentType: _text(json['paymentType']),
    negotiated: json['negotiated'] == true,
  );
}

final class AppPixCharge {
  final int id;
  final int loanId;
  final int? installmentId;
  final int? paymentId;
  final int bankAccountId;
  final String transactionId;
  final double amount;
  final String status;
  final String? copyAndPaste;
  final String? qrCode;
  final String? location;
  final String? error;
  final bool paymentProcessed;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AppPixCharge({
    required this.id,
    required this.loanId,
    required this.installmentId,
    required this.paymentId,
    required this.bankAccountId,
    required this.transactionId,
    required this.amount,
    required this.status,
    required this.copyAndPaste,
    required this.qrCode,
    required this.location,
    required this.error,
    required this.paymentProcessed,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppPixCharge.fromJson(Map<String, dynamic> json) => AppPixCharge(
    id: _int(json['id']),
    loanId: _int(json['loanId']),
    installmentId: json['installmentId'] == null
        ? null
        : _int(json['installmentId']),
    paymentId: json['paymentId'] == null ? null : _int(json['paymentId']),
    bankAccountId: _int(json['bankAccountId']),
    transactionId: _text(json['transactionId']),
    amount: _double(json['amount']),
    status: _text(json['status']),
    copyAndPaste: _nullableText(json['copyAndPaste']),
    qrCode: _nullableText(json['qrCode']),
    location: _nullableText(json['location']),
    error: _nullableText(json['error']),
    paymentProcessed: json['paymentProcessed'] == true,
    paidAt: _dateTime(json['paidAt']),
    createdAt: _dateTime(json['createdAt']),
    updatedAt: _dateTime(json['updatedAt']),
  );
}

final class AppPixCancellationResult {
  final int cancelledCount;
  final int paidCount;
  final int pendingCount;

  const AppPixCancellationResult({
    required this.cancelledCount,
    required this.paidCount,
    required this.pendingCount,
  });

  factory AppPixCancellationResult.fromJson(Map<String, dynamic> json) =>
      AppPixCancellationResult(
        cancelledCount: _int(json['cancelledCount']),
        paidCount: _int(json['paidCount']),
        pendingCount: _int(json['pendingCount']),
      );
}

List<T> _mapList<T>(Object? value, T Function(Map<String, dynamic>) convert) =>
    value is List
    ? value
          .whereType<Map>()
          .map((item) => convert(Map<String, dynamic>.from(item)))
          .toList(growable: false)
    : const [];

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

int? _nullableInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse('$value');
}

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

String _text(Object? value, {String fallback = ''}) {
  final String result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

String? _nullableText(Object? value) {
  final String result = _text(value);
  return result.isEmpty ? null : result;
}

DateTime? _dateTime(Object? value) => DateTime.tryParse(_text(value));
