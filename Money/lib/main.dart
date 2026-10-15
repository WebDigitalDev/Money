import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:no_screenshot/no_screenshot.dart';
import 'package:money/money.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PersistentCacheService().initialize();

  final SharedPreferencesService preferencesService =
      SharedPreferencesService();
  final AppSettings settings = await preferencesService.getSettings();

  if (!kIsWeb) {
    if (settings.enableScreenshot) {
      NoScreenshot.instance.screenshotOn();
    } else {
      NoScreenshot.instance.screenshotOff();
    }
  }

  runApp(MoneyApp(themeMode: settings.themeMode));
}
