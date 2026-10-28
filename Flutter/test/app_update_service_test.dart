import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  final AppUpdateManifest manifest = AppUpdateManifest.fromJson(
    <String, dynamic>{
      'schema': 1,
      'android': <String, dynamic>{
        'available': true,
        'minimumBuild': 4,
        'latestBuild': 5,
        'version': '1.2.0',
        'downloadUrl': 'https://moneyapp.site/appupdate/android/money.apk',
      },
      'ios': <String, dynamic>{
        'available': true,
        'minimumBuild': 7,
        'latestBuild': 7,
        'version': '1.3.0',
        'installUrl': 'itms-services://?action=download-manifest',
      },
      'web': <String, dynamic>{'available': true, 'releaseId': '2026.08.22.2'},
    },
  );

  test('requires Android update below minimum build', () {
    final RequiredAppUpdate? update = AppUpdateService.evaluateRequirement(
      manifest: manifest,
      target: AppUpdateTarget.android,
      installedBuild: 3,
      installedWebReleaseId: 'ignored',
    );

    expect(update, isNotNull);
    expect(update!.minimumBuild, 4);
    expect(update.downloadUrl, contains('/android/'));
  });

  test('allows Android build at minimum version', () {
    expect(
      AppUpdateService.evaluateRequirement(
        manifest: manifest,
        target: AppUpdateTarget.android,
        installedBuild: 4,
        installedWebReleaseId: 'ignored',
      ),
      isNull,
    );
  });

  test('requires web refresh only when release ids differ', () {
    expect(
      AppUpdateService.evaluateRequirement(
        manifest: manifest,
        target: AppUpdateTarget.web,
        installedBuild: 1,
        installedWebReleaseId: '2026.08.22.1',
      ),
      isNotNull,
    );
    expect(
      AppUpdateService.evaluateRequirement(
        manifest: manifest,
        target: AppUpdateTarget.web,
        installedBuild: 1,
        installedWebReleaseId: '2026.08.22.2',
      ),
      isNull,
    );
  });

  test('development web build is never blocked by production release id', () {
    expect(
      AppUpdateService.evaluateRequirement(
        manifest: manifest,
        target: AppUpdateTarget.web,
        installedBuild: 1,
        installedWebReleaseId: 'development',
      ),
      isNull,
    );
  });
}
