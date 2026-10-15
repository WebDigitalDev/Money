import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money/money.dart';

void main() {
  const AppClientDocument legacyDocument = AppClientDocument(
    id: 17,
    clientId: 8,
    description: 'Comprovante',
    fileName: 'arquivo.bin',
    contentType: 'content/unknown',
    available: true,
    createdAt: null,
    updatedAt: null,
  );

  test('download recupera extensão PDF pelo conteúdo real', () async {
    final ClientService service = ClientService.forTesting(
      MockClient(
        (_) async => http.Response.bytes(
          Uint8List.fromList('%PDF-1.7'.codeUnits),
          200,
          headers: {
            'content-type': 'content/unknown',
            'content-disposition':
                "attachment; filename*=UTF-8''comprovante%20cliente",
          },
        ),
      ),
    );

    final AppDownloadedDocument result = await service.downloadDocument(
      8,
      legacyDocument,
    );

    expect(result.fileName, 'comprovante cliente.pdf');
    expect(result.contentType, 'application/pdf');
  });

  test('download troca extensão bin por extensão da imagem', () async {
    final ClientService service = ClientService.forTesting(
      MockClient(
        (_) async => http.Response.bytes(
          Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0, 0x00]),
          200,
          headers: {
            'content-type': 'application/octet-stream',
            'content-disposition': 'attachment; filename="foto.bin"',
          },
        ),
      ),
    );

    final AppDownloadedDocument result = await service.downloadDocument(
      8,
      legacyDocument,
    );

    expect(result.fileName, 'foto.jpg');
    expect(result.contentType, 'image/jpeg');
  });
}
