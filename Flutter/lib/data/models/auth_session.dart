final class AuthSession {
  final String token;
  final String name;
  final int userId;
  final bool administrator;
  final bool canEdit;
  final bool collector;
  final bool forcePasswordChange;
  final bool tutorialCompleted;
  final String? expires;

  const AuthSession({
    required this.token,
    required this.name,
    required this.userId,
    required this.administrator,
    required this.canEdit,
    this.collector = false,
    required this.forcePasswordChange,
    this.tutorialCompleted = false,
    this.expires,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final Object? rawUserId = json['userId'];
    final int? userId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    final String token = json['token']?.toString().trim() ?? '';

    if (token.isEmpty || userId == null) {
      throw const FormatException('Resposta de autenticação incompleta.');
    }

    return AuthSession(
      token: token,
      name: json['name']?.toString().trim() ?? '',
      userId: userId,
      administrator: json['administrator'] == true,
      canEdit: json['canEdit'] != false,
      collector: json['collector'] == true,
      forcePasswordChange: json['forcePasswordChange'] == true,
      tutorialCompleted: json['tutorialCompleted'] == true,
      expires: json['expires']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'name': name,
    'userId': userId,
    'administrator': administrator,
    'canEdit': canEdit,
    'collector': collector,
    'forcePasswordChange': forcePasswordChange,
    'tutorialCompleted': tutorialCompleted,
    if (expires != null) 'expires': expires,
  };

  String get authorizationHeader => 'Bearer $token';

  bool get canManageRegions => administrator;
}

final class AuthCredentials {
  final String username;
  final String password;

  const AuthCredentials({required this.username, required this.password});
}
