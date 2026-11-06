import 'dart:io';
import 'l10n.dart';

import 'package:http/http.dart' as http;

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Downloads [url] to [target], showing progress through [onProgress] (0 to 1).
///
/// Bytes go to a ".part" file first and the download picks up where it stopped if it's run again,
/// so a dropped connection halfway through a large model doesn't start it over.
Future<void> downloadFile(
  Uri url,
  File target, {
  void Function(double progress)? onProgress,
  bool Function()? isCancelled,
  http.Client? client,
}) async {
  final part = File('${target.path}.part');
  await target.parent.create(recursive: true);
  final have = await part.exists() ? await part.length() : 0;
  final web = client ?? _newClient();
  try {
    final request = _request(url, have);
    final response = await web.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw DownloadException('The download failed (error {code}). Try again later.'.trf({'code': response.statusCode}));
    }
    final resumed = response.statusCode == 206;
    final length = response.contentLength;
    final total = length == null ? null : length + (resumed ? have : 0);
    var received = resumed ? have : 0;

    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    if (total != null && received < total) {
      throw DownloadException('The download was cut off. Try again to carry on from where it stopped.'.tr);
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    onProgress?.call(1);
  } on SocketException {
    throw DownloadException('No internet connection. Connect to Wi-Fi and try again.'.tr);
  } on http.ClientException {
    throw DownloadException('The connection dropped. Try again to carry on from where it stopped.'.tr);
  } finally {
    if (client == null) web.close();
  }
}

http.Client _newClient() => http.Client();

http.Request _request(Uri url, int have) {
  final request = http.Request('GET', url);
  if (have > 0) request.headers['Range'] = 'bytes=$have-';
  return request;
}
