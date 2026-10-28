import 'package:money/data/models/app_update.dart';

enum AndroidInstallOutcome { installerOpened, permissionRequested }

Future<AndroidInstallOutcome> downloadAndInstallAndroidUpdate(
  RequiredAppUpdate update,
  void Function(double progress) onProgress,
) {
  throw UnsupportedError(
    'A instalação de APK não é suportada nesta plataforma.',
  );
}
