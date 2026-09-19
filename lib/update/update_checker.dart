import 'dart:convert';
import 'dart:io';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.notes = '',
  });

  final String version;
  final String downloadUrl;
  final String notes;
}

abstract interface class UpdateChecker {
  Future<UpdateInfo?> check(String currentVersion);
}

class RemoteUpdateChecker implements UpdateChecker {
  const RemoteUpdateChecker(this.manifestUrl);

  final String manifestUrl;

  @override
  Future<UpdateInfo?> check(String currentVersion) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final latest = data['version'] as String?;
      final url = data['download_url'] as String?;
      if (latest == null || url == null || !_isNewer(latest, currentVersion)) {
        return null;
      }
      return UpdateInfo(
        version: latest,
        downloadUrl: url,
        notes: data['notes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

bool _isNewer(String candidate, String current) {
  List<int> parts(String value) => value
      .split('+').first
      .split('-').first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList();

  final a = parts(candidate);
  final b = parts(current);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final left = i < a.length ? a[i] : 0;
    final right = i < b.length ? b[i] : 0;
    if (left != right) return left > right;
  }
  return false;
}
