enum AppConferenceCategory { all, payment, loan, negotiation, closure }

extension AppConferenceCategoryValue on AppConferenceCategory {
  String get apiValue => switch (this) {
    AppConferenceCategory.all => 'ALL',
    AppConferenceCategory.payment => 'PAYMENT',
    AppConferenceCategory.loan => 'LOAN',
    AppConferenceCategory.negotiation => 'NEGOTIATION',
    AppConferenceCategory.closure => 'CLOSURE',
  };

  String get label => switch (this) {
    AppConferenceCategory.all => 'Todas',
    AppConferenceCategory.payment => 'Pagamentos',
    AppConferenceCategory.loan => 'Empréstimos',
    AppConferenceCategory.negotiation => 'Refinanciamentos',
    AppConferenceCategory.closure => 'Finalizações',
  };
}

final class AppConferenceItem {
  final int id;
  final String type;
  final String? action;
  final String status;
  final int? loanId;
  final int? originLoanId;
  final int? installmentId;
  final int? regionId;
  final String regionName;
  final String clientName;
  final String description;
  final double amount;
  final String requester;
  final DateTime? createdAt;
  final int itemCount;
  final List<AppConferenceDetail> details;

  const AppConferenceItem({
    required this.id,
    required this.type,
    required this.action,
    required this.status,
    required this.loanId,
    required this.originLoanId,
    required this.installmentId,
    required this.regionId,
    required this.regionName,
    required this.clientName,
    required this.description,
    required this.amount,
    required this.requester,
    required this.createdAt,
    required this.itemCount,
    required this.details,
  });

  factory AppConferenceItem.fromJson(Map<String, dynamic> json) =>
      AppConferenceItem(
        id: _int(json['id']) ?? 0,
        type: _text(json['type']),
        action: _nullableText(json['action']),
        status: _text(json['status']),
        loanId: _int(json['loanId']),
        originLoanId: _int(json['originLoanId']),
        installmentId: _int(json['installmentId']),
        regionId: _int(json['regionId']),
        regionName: _text(json['regionName']),
        clientName: _text(json['clientName']),
        description: _text(json['description']),
        amount: _double(json['amount']),
        requester: _text(json['requester']),
        createdAt: DateTime.tryParse(_text(json['createdAt'])),
        itemCount: _int(json['itemCount']) ?? 0,
        details: json['details'] is List
            ? (json['details'] as List)
                  .whereType<Map>()
                  .map(
                    (detail) => AppConferenceDetail.fromJson(
                      Map<String, dynamic>.from(detail),
                    ),
                  )
                  .toList(growable: false)
            : const [],
      );

  bool get isPayment => type.toUpperCase() == 'PAGAMENTO';
  bool get isPix => type.toUpperCase() == 'PIX';

  String get title {
    final String contract = loanId == null ? '' : ' #$loanId';
    return switch (type.toUpperCase()) {
      'PAGAMENTO' => 'Pagamento$contract',
      'PIX' => 'PIX$contract',
      'EMPRESTIMO' => 'Novo empréstimo$contract',
      'RENOVACAO' =>
        'Renovação${originLoanId == null ? contract : ' #$originLoanId'}',
      'REFINANCIAMENTO' =>
        'Refinanciamento${originLoanId == null ? contract : ' #$originLoanId'}',
      'FINALIZACAO' =>
        '${action?.toUpperCase() == 'CANCELAR' ? 'Cancelamento' : 'Finalização'}$contract',
      _ => 'Conferência$contract',
    };
  }
}

final class AppConferenceDetail {
  final int? approvalId;
  final int? paymentId;
  final int? installmentId;
  final String installment;
  final DateTime? dueDate;
  final double amount;
  final double installmentAmount;
  final double interestAmount;
  final double totalAmount;
  final String description;
  final String dueDateObservation;

  const AppConferenceDetail({
    required this.approvalId,
    required this.paymentId,
    required this.installmentId,
    required this.installment,
    required this.dueDate,
    required this.amount,
    required this.installmentAmount,
    required this.interestAmount,
    required this.totalAmount,
    required this.description,
    required this.dueDateObservation,
  });

  factory AppConferenceDetail.fromJson(Map<String, dynamic> json) =>
      AppConferenceDetail(
        approvalId: _int(json['approvalId']),
        paymentId: _int(json['paymentId']),
        installmentId: _int(json['installmentId']),
        installment: _text(json['installment']),
        dueDate: DateTime.tryParse(_text(json['dueDate'])),
        amount: _double(json['amount']),
        installmentAmount: _double(json['installmentAmount']),
        interestAmount: _double(json['interestAmount']),
        totalAmount: _double(json['totalAmount']),
        description: _text(json['description']),
        dueDateObservation: _text(json['dueDateObservation']),
      );
}

final class AppConferenceListData {
  final List<AppConferenceItem> items;
  final int total;
  final Map<String, int> counts;

  const AppConferenceListData({
    required this.items,
    required this.total,
    required this.counts,
  });

  factory AppConferenceListData.fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    final Object? rawCounts = json['counts'];
    return AppConferenceListData(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => AppConferenceItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      total: _int(json['total']) ?? 0,
      counts: rawCounts is Map
          ? rawCounts.map(
              (key, value) => MapEntry(key.toString(), _int(value) ?? 0),
            )
          : const {},
    );
  }
}

int? _int(Object? value) => value is num
    ? value.toInt()
    : value == null
    ? null
    : int.tryParse(value.toString());

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final String result = _text(value);
  return result.isEmpty ? null : result;
}
