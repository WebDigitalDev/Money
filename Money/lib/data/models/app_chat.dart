import 'package:money/data/models/app_financial_goal.dart';

final class AppCodexConnection {
  final bool enabled;
  final bool available;
  final bool connected;
  final bool connecting;
  final String? email;
  final String? planType;
  final AppCodexUsage? usage;
  final List<AppChatModelOption> models;
  final String? defaultModel;
  final String? defaultServiceTier;
  final String? error;

  const AppCodexConnection({
    required this.enabled,
    required this.available,
    required this.connected,
    required this.connecting,
    this.email,
    this.planType,
    this.usage,
    this.models = const [],
    this.defaultModel,
    this.defaultServiceTier,
    this.error,
  });

  factory AppCodexConnection.fromJson(Map<String, dynamic> json) =>
      AppCodexConnection(
        enabled: json['enabled'] == true,
        available: json['available'] == true,
        connected: json['connected'] == true,
        connecting: json['connecting'] == true,
        email: _nullableText(json['email']),
        planType: _nullableText(json['planType']),
        usage: json['usage'] is Map
            ? AppCodexUsage.fromJson(
                Map<String, dynamic>.from(json['usage'] as Map),
              )
            : null,
        models: _maps(json['models'])
            .map(AppChatModelOption.fromJson)
            .toList(growable: false),
        defaultModel: _nullableText(json['defaultModel']),
        defaultServiceTier: _nullableText(json['defaultServiceTier']),
        error: _nullableText(json['error']),
      );
}

final class AppChatServiceTier {
  final String id;
  final String name;
  final String description;

  const AppChatServiceTier({
    required this.id,
    required this.name,
    required this.description,
  });

  factory AppChatServiceTier.fromJson(Map<String, dynamic> json) =>
      AppChatServiceTier(
        id: _text(json['id']),
        name: _text(json['name']),
        description: _text(json['description']),
      );
}

final class AppChatModelOption {
  final String id;
  final String name;
  final bool defaultModel;
  final bool acceptsImages;
  final String? defaultServiceTier;
  final List<AppChatServiceTier> serviceTiers;

  const AppChatModelOption({
    required this.id,
    required this.name,
    required this.defaultModel,
    required this.acceptsImages,
    required this.defaultServiceTier,
    required this.serviceTiers,
  });

  factory AppChatModelOption.fromJson(Map<String, dynamic> json) =>
      AppChatModelOption(
        id: _text(json['id']),
        name: _text(json['name']),
        defaultModel: json['defaultModel'] == true,
        acceptsImages: json['acceptsImages'] == true,
        defaultServiceTier: _nullableText(json['defaultServiceTier']),
        serviceTiers: _maps(json['serviceTiers'])
            .map(AppChatServiceTier.fromJson)
            .toList(growable: false),
      );

  AppChatServiceTier? tier(String? value) {
    for (final AppChatServiceTier tier in serviceTiers) {
      if (tier.id == value) return tier;
    }
    return null;
  }

  String? get preferredTier {
    for (final AppChatServiceTier tier in serviceTiers) {
      if (tier.id.toLowerCase() == 'fast') return tier.id;
    }
    return defaultServiceTier ??
        (serviceTiers.isEmpty ? null : serviceTiers.first.id);
  }
}

final class AppCodexUsage {
  final double usedPercent;
  final int? windowDurationMinutes;
  final DateTime? resetsAt;
  final String? limitName;

  const AppCodexUsage({
    required this.usedPercent,
    this.windowDurationMinutes,
    this.resetsAt,
    this.limitName,
  });

  double get progress => (usedPercent / 100).clamp(0, 1);
  double get remainingPercent => (100 - usedPercent).clamp(0, 100);
  double get remainingProgress => (remainingPercent / 100).clamp(0, 1);

  factory AppCodexUsage.fromJson(Map<String, dynamic> json) {
    final int? resetSeconds = _nullableInt(json['resetsAtEpochSeconds']);
    return AppCodexUsage(
      usedPercent: _double(json['usedPercent']).clamp(0, 100),
      windowDurationMinutes: _nullableInt(json['windowDurationMinutes']),
      resetsAt: resetSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              resetSeconds * 1000,
              isUtc: true,
            ),
      limitName: _nullableText(json['limitName']),
    );
  }
}

final class AppCodexLoginChallenge {
  final String loginId;
  final Uri verificationUrl;
  final String userCode;

  const AppCodexLoginChallenge({
    required this.loginId,
    required this.verificationUrl,
    required this.userCode,
  });

  /// Mantém exatamente o formato apresentado pelo ChatGPT, incluindo hífen.
  String get clipboardCode => userCode.trim().toUpperCase();

  /// Abre o formulário oficial já com o código informado, sem depender da
  /// colagem manual entre os campos separados da página.
  Uri get prefilledVerificationUrl {
    final Map<String, String> parameters = {
      ...verificationUrl.queryParameters,
      'user_code': userCode.trim(),
    };
    return verificationUrl.replace(queryParameters: parameters);
  }

  factory AppCodexLoginChallenge.fromJson(Map<String, dynamic> json) {
    final String url = _text(json['verificationUrl']);
    final Uri? parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null || !parsedUrl.hasScheme) {
      throw const FormatException('Endereço de autenticação inválido.');
    }
    return AppCodexLoginChallenge(
      loginId: _text(json['loginId']),
      verificationUrl: parsedUrl,
      userCode: _text(json['userCode']),
    );
  }
}

final class AppChatSuggestion {
  final String label;
  final String message;
  final int? clientId;
  final int? regionId;
  final String? action;

  const AppChatSuggestion({
    required this.label,
    required this.message,
    this.clientId,
    this.regionId,
    this.action,
  });

  factory AppChatSuggestion.fromJson(Map<String, dynamic> json) =>
      AppChatSuggestion(
        label: _text(json['label']),
        message: _text(json['message']),
        clientId: _nullableInt(json['clientId']),
        regionId: _nullableInt(json['regionId']),
        action: _nullableText(json['action']),
      );
}

final class AppChatLoan {
  final int loanId;
  final String clientName;
  final String regionName;
  final String paymentType;
  final DateTime? dueDate;
  final int installmentCount;
  final double amount;
  final String status;

  const AppChatLoan({
    required this.loanId,
    required this.clientName,
    required this.regionName,
    required this.paymentType,
    required this.dueDate,
    required this.installmentCount,
    required this.amount,
    required this.status,
  });

  factory AppChatLoan.fromJson(Map<String, dynamic> json) => AppChatLoan(
    loanId: _int(json['loanId']),
    clientName: _text(json['clientName'], fallback: 'Cliente'),
    regionName: _text(json['regionName'], fallback: 'Região'),
    paymentType: _text(json['paymentType'], fallback: 'Empréstimo'),
    dueDate: DateTime.tryParse(_text(json['dueDate'])),
    installmentCount: _int(json['installmentCount']),
    amount: _double(json['amount']),
    status: _text(json['status']),
  );
}

final class AppChatContractEvent {
  final String category;
  final String operation;
  final String description;
  final String username;
  final DateTime? occurredAt;

  const AppChatContractEvent({
    required this.category,
    required this.operation,
    required this.description,
    required this.username,
    required this.occurredAt,
  });

  factory AppChatContractEvent.fromJson(Map<String, dynamic> json) =>
      AppChatContractEvent(
        category: _text(json['category']),
        operation: _text(json['operation']),
        description: _text(json['description']),
        username: _text(json['username'], fallback: 'Sistema'),
        occurredAt: DateTime.tryParse(_text(json['occurredAt'])),
      );
}

final class AppChatContract {
  final int loanId;
  final int clientId;
  final String clientName;
  final int regionId;
  final String regionName;
  final DateTime? contractDate;
  final String paymentType;
  final int installmentCount;
  final int paidInstallments;
  final int openInstallments;
  final int overdueInstallments;
  final double loanedAmount;
  final double totalAmount;
  final double receivedAmount;
  final double receivableAmount;
  final double profitAmount;
  final String status;
  final String approvalStatus;
  final DateTime? lastPaymentDate;
  final double lastPaymentAmount;
  final String? lastPaymentInstallment;
  final DateTime? nextDueDate;
  final double nextDueAmount;
  final String? nextDueInstallment;
  final String? createdBy;
  final DateTime? createdAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? lastChangedBy;
  final DateTime? lastChangedAt;
  final List<AppChatContractEvent> history;

  const AppChatContract({
    required this.loanId,
    required this.clientId,
    required this.clientName,
    required this.regionId,
    required this.regionName,
    required this.contractDate,
    required this.paymentType,
    required this.installmentCount,
    required this.paidInstallments,
    required this.openInstallments,
    required this.overdueInstallments,
    required this.loanedAmount,
    required this.totalAmount,
    required this.receivedAmount,
    required this.receivableAmount,
    required this.profitAmount,
    required this.status,
    required this.approvalStatus,
    required this.lastPaymentDate,
    required this.lastPaymentAmount,
    required this.lastPaymentInstallment,
    required this.nextDueDate,
    required this.nextDueAmount,
    required this.nextDueInstallment,
    required this.createdBy,
    required this.createdAt,
    required this.approvedBy,
    required this.approvedAt,
    required this.lastChangedBy,
    required this.lastChangedAt,
    required this.history,
  });

  factory AppChatContract.fromJson(Map<String, dynamic> json) =>
      AppChatContract(
        loanId: _int(json['loanId']),
        clientId: _int(json['clientId']),
        clientName: _text(json['clientName'], fallback: 'Cliente'),
        regionId: _int(json['regionId']),
        regionName: _text(json['regionName'], fallback: 'Região'),
        contractDate: DateTime.tryParse(_text(json['contractDate'])),
        paymentType: _text(json['paymentType'], fallback: 'Empréstimo'),
        installmentCount: _int(json['installmentCount']),
        paidInstallments: _int(json['paidInstallments']),
        openInstallments: _int(json['openInstallments']),
        overdueInstallments: _int(json['overdueInstallments']),
        loanedAmount: _double(json['loanedAmount']),
        totalAmount: _double(json['totalAmount']),
        receivedAmount: _double(json['receivedAmount']),
        receivableAmount: _double(json['receivableAmount']),
        profitAmount: _double(json['profitAmount']),
        status: _text(json['status']),
        approvalStatus: _text(json['approvalStatus']),
        lastPaymentDate: DateTime.tryParse(_text(json['lastPaymentDate'])),
        lastPaymentAmount: _double(json['lastPaymentAmount']),
        lastPaymentInstallment: _nullableText(json['lastPaymentInstallment']),
        nextDueDate: DateTime.tryParse(_text(json['nextDueDate'])),
        nextDueAmount: _double(json['nextDueAmount']),
        nextDueInstallment: _nullableText(json['nextDueInstallment']),
        createdBy: _nullableText(json['createdBy']),
        createdAt: DateTime.tryParse(_text(json['createdAt'])),
        approvedBy: _nullableText(json['approvedBy']),
        approvedAt: DateTime.tryParse(_text(json['approvedAt'])),
        lastChangedBy: _nullableText(json['lastChangedBy']),
        lastChangedAt: DateTime.tryParse(_text(json['lastChangedAt'])),
        history: _maps(json['history'])
            .map(AppChatContractEvent.fromJson)
            .toList(growable: false),
      );

  AppChatLoan get asLoan => AppChatLoan(
    loanId: loanId,
    clientName: clientName,
    regionName: regionName,
    paymentType: paymentType,
    dueDate: nextDueDate,
    installmentCount: installmentCount,
    amount: receivableAmount,
    status: overdueInstallments > 0 ? 'ATRASADO' : status.toUpperCase(),
  );
}

final class AppChatLoanStatus {
  final int overdueCount;
  final double overdueAmount;
  final int onTimeCount;
  final double onTimeAmount;
  final int settledCount;
  final double settledAmount;

  const AppChatLoanStatus({
    required this.overdueCount,
    required this.overdueAmount,
    required this.onTimeCount,
    required this.onTimeAmount,
    required this.settledCount,
    required this.settledAmount,
  });

  factory AppChatLoanStatus.fromJson(Map<String, dynamic> json) =>
      AppChatLoanStatus(
        overdueCount: _int(json['overdueCount']),
        overdueAmount: _double(json['overdueAmount']),
        onTimeCount: _int(json['onTimeCount']),
        onTimeAmount: _double(json['onTimeAmount']),
        settledCount: _int(json['settledCount']),
        settledAmount: _double(json['settledAmount']),
      );
}

final class AppChatClientStatus {
  final int activeCount;
  final int withoutLoansCount;
  final int missingCount;

  const AppChatClientStatus({
    required this.activeCount,
    required this.withoutLoansCount,
    required this.missingCount,
  });

  factory AppChatClientStatus.fromJson(Map<String, dynamic> json) =>
      AppChatClientStatus(
        activeCount: _int(json['activeCount']),
        withoutLoansCount: _int(json['withoutLoansCount']),
        missingCount: _int(json['missingCount']),
      );
}

final class AppChatSummaryContext {
  final int regionId;
  final String regionName;
  final DateTime? startDate;
  final DateTime? endDate;

  const AppChatSummaryContext({
    required this.regionId,
    required this.regionName,
    required this.startDate,
    required this.endDate,
  });

  factory AppChatSummaryContext.fromJson(Map<String, dynamic> json) =>
      AppChatSummaryContext(
        regionId: _int(json['regionId']),
        regionName: _text(json['regionName'], fallback: 'Região'),
        startDate: DateTime.tryParse(_text(json['startDate'])),
        endDate: DateTime.tryParse(_text(json['endDate'])),
      );
}

final class AppChatClient {
  final int id;
  final String name;
  final String? document;
  final String? phone;
  final int regionId;
  final String regionName;
  final int openLoans;
  final double loaned;
  final double received;
  final double receivable;
  final double overdue;
  final double dueToday;

  const AppChatClient({
    required this.id,
    required this.name,
    required this.document,
    required this.phone,
    required this.regionId,
    required this.regionName,
    required this.openLoans,
    required this.loaned,
    required this.received,
    required this.receivable,
    required this.overdue,
    required this.dueToday,
  });

  factory AppChatClient.fromJson(Map<String, dynamic> json) => AppChatClient(
    id: _int(json['id']),
    name: _text(json['name'], fallback: 'Cliente'),
    document: _nullableText(json['document']),
    phone: _nullableText(json['phone']),
    regionId: _int(json['regionId']),
    regionName: _text(json['regionName'], fallback: 'Região sem nome'),
    openLoans: _int(json['openLoans']),
    loaned: _double(json['loaned']),
    received: _double(json['received']),
    receivable: _double(json['receivable']),
    overdue: _double(json['overdue']),
    dueToday: _double(json['dueToday']),
  );
}

final class AppChatFinancialSummary {
  final int clients;
  final int openLoans;
  final double loaned;
  final double received;
  final double receivable;
  final double overdue;
  final double profit;

  const AppChatFinancialSummary({
    required this.clients,
    required this.openLoans,
    required this.loaned,
    required this.received,
    required this.receivable,
    required this.overdue,
    required this.profit,
  });

  factory AppChatFinancialSummary.fromJson(Map<String, dynamic> json) =>
      AppChatFinancialSummary(
        clients: _int(json['clients']),
        openLoans: _int(json['openLoans']),
        loaned: _double(json['loaned']),
        received: _double(json['received']),
        receivable: _double(json['receivable']),
        overdue: _double(json['overdue']),
        profit: _double(json['profit']),
      );
}

final class AppChatResponse {
  final String message;
  final String mode;
  final List<AppChatSuggestion> suggestions;
  final List<AppChatClient> clients;
  final AppChatFinancialSummary? summary;
  final bool semanticSearch;
  final List<AppChatLoan> loans;
  final AppChatLoanStatus? loanStatus;
  final AppChatClientStatus? clientStatus;
  final AppFinancialGoal? financialGoal;
  final List<AppFinancialGoal> financialGoals;
  final AppChatSummaryContext? summaryContext;
  final AppChatContract? contract;

  const AppChatResponse({
    required this.message,
    required this.mode,
    required this.suggestions,
    required this.clients,
    required this.summary,
    required this.semanticSearch,
    this.loans = const [],
    this.loanStatus,
    this.clientStatus,
    this.financialGoal,
    this.financialGoals = const [],
    this.summaryContext,
    this.contract,
  });

  factory AppChatResponse.fromJson(Map<String, dynamic> json) {
    final AppFinancialGoal? financialGoal = json['financialGoal'] is Map
        ? AppFinancialGoal.fromJson(
            Map<String, dynamic>.from(json['financialGoal'] as Map),
          )
        : null;
    final List<AppFinancialGoal> financialGoals = _maps(json['financialGoals'])
        .map(AppFinancialGoal.fromJson)
        .toList(growable: false);
    return AppChatResponse(
      message: _text(json['message']),
      mode: _text(json['mode'], fallback: 'READY'),
      suggestions: _maps(json['suggestions'])
          .map(AppChatSuggestion.fromJson)
          .toList(growable: false),
      clients: _maps(json['clients'])
          .map(AppChatClient.fromJson)
          .toList(growable: false),
      summary: json['summary'] is Map
          ? AppChatFinancialSummary.fromJson(
              Map<String, dynamic>.from(json['summary'] as Map),
            )
          : null,
      semanticSearch: json['semanticSearch'] == true,
      loans: _maps(json['loans'])
          .map(AppChatLoan.fromJson)
          .toList(growable: false),
      loanStatus: json['loanStatus'] is Map
          ? AppChatLoanStatus.fromJson(
              Map<String, dynamic>.from(json['loanStatus'] as Map),
            )
          : null,
      clientStatus: json['clientStatus'] is Map
          ? AppChatClientStatus.fromJson(
              Map<String, dynamic>.from(json['clientStatus'] as Map),
            )
          : null,
      financialGoal: financialGoal,
      financialGoals: financialGoals.isNotEmpty
          ? financialGoals
          : financialGoal == null
          ? const []
          : [financialGoal],
      summaryContext: json['summaryContext'] is Map
          ? AppChatSummaryContext.fromJson(
              Map<String, dynamic>.from(json['summaryContext'] as Map),
            )
          : null,
      contract: json['contract'] is Map
          ? AppChatContract.fromJson(
              Map<String, dynamic>.from(json['contract'] as Map),
            )
          : null,
    );
  }
}

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
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
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableText(Object? value) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
