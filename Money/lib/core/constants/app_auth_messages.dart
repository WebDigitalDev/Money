import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

abstract final class AppAuthMessages {
  static const List<AuthMessages> portugueseBrazil = <AuthMessages>[
    AndroidAuthMessages(
      signInTitle: 'Autenticação necessária',
      signInHint: 'Confirme sua identidade',
      cancelButton: 'Cancelar',
    ),
    IOSAuthMessages(
      cancelButton: 'Cancelar',
      localizedFallbackTitle: 'Usar código',
    ),
  ];
}
