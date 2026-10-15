import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:money/data/models/app_update.dart';
import 'package:path_provider/path_provider.dart';

enum AndroidInstallOutcome { installerOpened, permissionRequested }

const MethodChannel _installerChannel = MethodChannel(
  'com.webdigital.money/app_update',
);

Future<AndroidInstallOutcome> downloadAndInstallAndroidUpdate(
  RequiredAppUpdate update,
  void Function(double progress) onProgress,
) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('A instalação de APK exige um dispositivo Android.');
  }
  if (update.downloadUrl.isEmpty) {
    throw const FormatException('O endereço do APK não foi publicado.');
  }

  final http.Client client = http.Client();
  File? partialFile;
  try {
    final http.StreamedResponse response = await client.send(
      http.Request('GET', Uri.parse(update.downloadUrl)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'O servidor recusou o download (${response.statusCode}).',
      );
    }

    final Directory cache = await getTemporaryDirectory();
    final Directory updateDirectory = Directory('${cache.path}/updates');
    await updateDirectory.create(recursive: true);
    final String remoteName = Uri.parse(update.downloadUrl).pathSegments.isEmpty
        ? 'money-update.apk'
        : Uri.parse(update.downloadUrl).pathSegments.last;
    final String fileName = remoteName.toLowerCase().endsWith('.apk')
        ? remoteName.replaceAll(RegExp(r'[^a-zA-Z0-9._+-]'), '_')
        : 'money-update.apk';
    partialFile = File('${updateDirectory.path}/$fileName.part');
    if (await partialFile.exists()) await partialFile.delete();

    final IOSink sink = partialFile.openWrite();
    int received = 0;
    final int expectedSize = update.size > 0
        ? update.size
        : response.contentLength ?? 0;
    try {
      await for (final List<int> chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          expectedSize > 0 ? (received / expectedSize).clamp(0, 1) : 0,
        );
      }
    } finally {
      await sink.close();
    }

    if (update.size > 0 && received != update.size) {
      throw const FileSystemException('O APK foi baixado incompleto.');
    }
    if (update.sha256.isNotEmpty) {
      final Digest digest = await sha256.bind(partialFile.openRead()).first;
      if (digest.toString().toLowerCase() != update.sha256.toLowerCase()) {
        throw const FormatException(
          'A assinatura de integridade do APK não confere.',
        );
      }
    }

    final File apk = File('${updateDirectory.path}/$fileName');
    if (await apk.exists()) await apk.delete();
    await partialFile.rename(apk.path);
    partialFile = null;
    onProgress(1);

    final String? result = await _installerChannel.invokeMethod<String>(
      'installApk',
      <String, Object>{'path': apk.path},
    );
    return result == 'permission_requested'
        ? AndroidInstallOutcome.permissionRequested
        : AndroidInstallOutcome.installerOpened;
  } finally {
    client.close();
    if (partialFile != null && await partialFile.exists()) {
      await partialFile.delete();
    }
  }
}
