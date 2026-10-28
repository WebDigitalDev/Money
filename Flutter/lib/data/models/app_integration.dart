final class AppBankAccount {
  final int id;
  final String name;
  final String bank;
  final bool active;
  final bool clientIdConfigured;
  final bool clientSecretConfigured;
  final String? pixKey;
  final List<int> regionIds;
  final List<String> regionNames;
  final String? certificateName;
  final String? privateKeyName;
  final String? certificateChainName;
  final DateTime? updatedAt;

  const AppBankAccount({
    required this.id,
    required this.name,
    required this.bank,
    required this.active,
    required this.clientIdConfigured,
    required this.clientSecretConfigured,
    required this.pixKey,
    required this.regionIds,
    required this.regionNames,
    required this.certificateName,
    required this.privateKeyName,
    required this.certificateChainName,
    required this.updatedAt,
  });

  factory AppBankAccount.fromJson(Map<String, dynamic> json) => AppBankAccount(
    id: _int(json['id']),
    name: _text(json['name']),
    bank: _text(json['bank']),
    active: json['active'] == true,
    clientIdConfigured: json['clientIdConfigured'] == true,
    clientSecretConfigured: json['clientSecretConfigured'] == true,
    pixKey: _nullableText(json['pixKey']),
    regionIds: _intList(json['regionIds']),
    regionNames: _textList(json['regionNames']),
    certificateName: _nullableText(json['certificateName']),
    privateKeyName: _nullableText(json['privateKeyName']),
    certificateChainName: _nullableText(json['certificateChainName']),
    updatedAt: DateTime.tryParse(_text(json['updatedAt'])),
  );

  bool get credentialsReady =>
      clientIdConfigured &&
      clientSecretConfigured &&
      certificateName != null &&
      privateKeyName != null;
}

final class AppWhatsappConfig {
  final bool active;
  final bool tokenConfigured;
  final String baseUrl;
  final String overdueMessage;
  final String dueTodayMessage;
  final String missingMessage;
  final String acquisitionMessage;
  final String pixMessage;
  final String pixReceivedMessage;

  const AppWhatsappConfig({
    required this.active,
    required this.tokenConfigured,
    required this.baseUrl,
    required this.overdueMessage,
    required this.dueTodayMessage,
    required this.missingMessage,
    required this.acquisitionMessage,
    required this.pixMessage,
    required this.pixReceivedMessage,
  });

  factory AppWhatsappConfig.fromJson(Map<String, dynamic> json) =>
      AppWhatsappConfig(
        active: json['active'] == true,
        tokenConfigured: json['tokenConfigured'] == true,
        baseUrl: _text(json['baseUrl']),
        overdueMessage: _text(json['overdueMessage']),
        dueTodayMessage: _text(json['dueTodayMessage']),
        missingMessage: _text(json['missingMessage']),
        acquisitionMessage: _text(json['acquisitionMessage']),
        pixMessage: _text(json['pixMessage']),
        pixReceivedMessage: _text(json['pixReceivedMessage']),
      );
}

final class AppWhatsappDevice {
  final int id;
  final String? remoteId;
  final String name;
  final String? phone;
  final String status;
  final String? provider;
  final bool connected;
  final bool pixCopySupported;
  final bool dispatching;
  final String? dispatchType;
  final int dispatchTotal;
  final int dispatchProcessed;
  final int dispatchSucceeded;
  final int dispatchErrors;
  final int dispatchIgnored;
  final List<int> regionIds;
  final List<String> regionNames;
  final DateTime? dispatchStartedAt;
  final DateTime? updatedAt;

  const AppWhatsappDevice({
    required this.id,
    required this.remoteId,
    required this.name,
    required this.phone,
    required this.status,
    required this.provider,
    required this.connected,
    required this.pixCopySupported,
    required this.dispatching,
    required this.dispatchType,
    required this.dispatchTotal,
    required this.dispatchProcessed,
    required this.dispatchSucceeded,
    required this.dispatchErrors,
    required this.dispatchIgnored,
    required this.regionIds,
    required this.regionNames,
    required this.dispatchStartedAt,
    required this.updatedAt,
  });

  factory AppWhatsappDevice.fromJson(Map<String, dynamic> json) =>
      AppWhatsappDevice(
        id: _int(json['id']),
        remoteId: _nullableText(json['remoteId']),
        name: _nullableText(json['name']) ?? 'Dispositivo WhatsApp',
        phone: _nullableText(json['phone']),
        status: _whatsappStatus(json['status'], json['connected'] == true),
        provider: _nullableText(json['provider']),
        connected: json['connected'] == true,
        pixCopySupported: json['pixCopySupported'] == true,
        dispatching: json['dispatching'] == true,
        dispatchType: _nullableText(json['dispatchType']),
        dispatchTotal: _int(json['dispatchTotal']),
        dispatchProcessed: _int(json['dispatchProcessed']),
        dispatchSucceeded: _int(json['dispatchSucceeded']),
        dispatchErrors: _int(json['dispatchErrors']),
        dispatchIgnored: _int(json['dispatchIgnored']),
        regionIds: _intList(json['regionIds']),
        regionNames: _textList(json['regionNames']),
        dispatchStartedAt: DateTime.tryParse(_text(json['dispatchStartedAt'])),
        updatedAt: DateTime.tryParse(_text(json['updatedAt'])),
      );

  double get dispatchProgress => dispatchTotal <= 0
      ? 0
      : (dispatchProcessed / dispatchTotal).clamp(0.0, 1.0);
}

String _whatsappStatus(dynamic rawStatus, bool connected) {
  if (connected) return 'CONECTADO';
  final String status = _nullableText(rawStatus)?.toLowerCase() ?? '';
  if ({
    'close',
    'closed',
    'disconnected',
    'desconectado',
    'offline',
  }.contains(status)) {
    return 'DESCONECTADO';
  }
  return status.isEmpty ? 'SEM STATUS' : status.toUpperCase();
}

final class AppWhatsappLog {
  final int id;
  final int? deviceId;
  final String? deviceName;
  final int? clientId;
  final int? loanId;
  final int? installmentId;
  final String type;
  final String? phone;
  final String? clientName;
  final String? regionName;
  final String status;
  final String? message;
  final String? error;
  final DateTime? createdAt;

  const AppWhatsappLog({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.clientId,
    required this.loanId,
    required this.installmentId,
    required this.type,
    required this.phone,
    required this.clientName,
    required this.regionName,
    required this.status,
    required this.message,
    required this.error,
    required this.createdAt,
  });

  factory AppWhatsappLog.fromJson(Map<String, dynamic> json) => AppWhatsappLog(
    id: _int(json['id']),
    deviceId: _nullableInt(json['deviceId']),
    deviceName: _nullableText(json['deviceName']),
    clientId: _nullableInt(json['clientId']),
    loanId: _nullableInt(json['loanId']),
    installmentId: _nullableInt(json['installmentId']),
    type: _nullableText(json['type']) ?? 'SISTEMA',
    phone: _nullableText(json['phone']),
    clientName: _nullableText(json['clientName']),
    regionName: _nullableText(json['regionName']),
    status: _nullableText(json['status']) ?? 'INDEFINIDO',
    message: _nullableText(json['message']),
    error: _nullableText(json['error']),
    createdAt: DateTime.tryParse(_text(json['createdAt'])),
  );
}

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

int? _nullableInt(Object? value) => value == null ? null : _int(value);

String _text(Object? value) => value?.toString().trim() ?? '';

String? _nullableText(Object? value) {
  final String result = _text(value);
  return result.isEmpty ? null : result;
}

List<int> _intList(Object? value) => value is List
    ? value.map(_int).where((item) => item > 0).toList(growable: false)
    : const [];

List<String> _textList(Object? value) => value is List
    ? value.map(_text).where((item) => item.isNotEmpty).toList(growable: false)
    : const [];
