import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class AppUpdate {
  final String version, url, sha256;
  final int size;
  const AppUpdate(this.version, this.url, this.sha256, this.size);

  static AppUpdate? fromRelease(Map<String, dynamic> data, String current) {
    if (data['draft'] != false || data['prerelease'] != false) return null;
    final tag = data['tag_name'];
    if (tag is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw const FormatException('Invalid release');
    }
    final version = tag.substring(1);
    if (!_newer(version, current)) return null;
    final assets = data['assets'];
    if (assets is! List) throw const FormatException('Missing assets');
    final matches = assets.whereType<Map>().where(
      (a) => a['name'] == 'offline-scale-android-$tag.apk',
    );
    if (matches.length != 1) throw const FormatException('Missing APK');
    final asset = matches.single;
    final url = asset['browser_download_url'];
    final digest = asset['digest'];
    final size = asset['size'];
    if (url !=
            'https://github.com/super-ai-company/offline-scale-v5/releases/download/$tag/offline-scale-android-$tag.apk' ||
        digest is! String ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest) ||
        size is! int ||
        size <= 0 ||
        size > 250 * 1024 * 1024) {
      throw const FormatException('Invalid APK metadata');
    }
    return AppUpdate(version, url as String, digest.substring(7), size);
  }

  static bool _newer(String candidate, String installed) {
    final a = candidate.split('.').map(int.parse).toList();
    final raw = installed.split('+').first;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(raw)) {
      throw const FormatException('Invalid installed version');
    }
    final b = raw.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}

class UpdateService {
  static const channel = MethodChannel('cashier/update');
  static const api =
      'https://api.github.com/repos/super-ai-company/offline-scale-v5/releases/latest';
  Future<bool> isPlayDistribution() async =>
      await channel.invokeMethod<String>('distribution') == 'play';

  Future<bool> openStore() async =>
      await channel.invokeMethod<bool>('openStore') ?? false;

  Future<String> installedVersion() async =>
      (await channel.invokeMethod<String>('version'))!;

  Future<AppUpdate?> check(String current) async {
    if (await isPlayDistribution()) {
      throw UnsupportedError('Play updates are managed by the store');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(api))
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'OfflineScaleV5');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw const HttpException('Release unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Response too large');
        }
      }
      return AppUpdate.fromRelease(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        current,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> install(AppUpdate update) async {
    if (await isPlayDistribution()) {
      throw UnsupportedError('Play cannot install website APKs');
    }
    return await channel.invokeMethod<bool>('install', {
          'url': update.url,
          'sha256': update.sha256,
          'version': update.version,
          'size': update.size,
        }) ??
        false;
  }
}
