import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_client.dart';

/// Downloads the server-generated PDF (citizen-visible data only) and opens or shares it.
class PdfService {
  PdfService(this.api);
  final ApiClient api;

  Future<File> download(String reference) async {
    final bytes = await api.reportPdf(reference);
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$reference.pdf');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> open(String reference) async {
    final f = await download(reference);
    await OpenFilex.open(f.path, type: 'application/pdf');
  }

  Future<void> share(String reference) async {
    final f = await download(reference);
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')],
        text: 'Complaint $reference');
  }
}
