import 'dart:io';

import 'package:flutter/services.dart';

class GeoAssetService {
  static const MethodChannel _channel =
      MethodChannel('aurum_proxy/vpn_permission');

  static const Map<String, int> _minimumBytes = {
    'geoip.dat': 100 * 1024,
    'geosite.dat': 100 * 1024,
    'geoip-cn.srs': 4 * 1024,
    'geosite-geolocation-cn.srs': 4 * 1024,
    'geosite-geolocation-!cn.srs': 4 * 1024,
  };

  static const Map<String, List<String>> _sources = {
    'geoip.dat': [
      'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat',
      'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat',
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    ],
    'geosite.dat': [
      'https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat',
      'https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat',
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
    ],
    'geoip-cn.srs': [
      'https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs',
      'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
    ],
    'geosite-geolocation-cn.srs': [
      'https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-geolocation-cn.srs',
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
    ],
    'geosite-geolocation-!cn.srs': [
      'https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-geolocation-!cn.srs',
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-!cn.srs',
    ],
  };

  Future<String> get filesDir async {
    return await _channel.invokeMethod<String>('filesDir') ?? '';
  }

  Future<String> bootstrap() async {
    final dir = await filesDir;
    if (dir.isEmpty) return '';
    final target = Directory(dir);
    await target.create(recursive: true);

    // 1.2.6 deliberately refreshes the bundled rule set once. Android keeps
    // getExternalFilesDir across APK upgrades, so older/corrupt Geo files can
    // otherwise survive indefinitely and make Smart mode appear ineffective.
    final bundleMarker = File('$dir/.aurum_geo_bundle_1_2_6');
    final forceBundledRefresh = !await bundleMarker.exists();
    var bundledRefreshComplete = true;

    for (final name in _sources.keys) {
      final file = File('$dir/$name');
      final minimum = _minimumBytes[name] ?? 1024;
      final validExisting =
          await file.exists() && await file.length() >= minimum;
      if (!forceBundledRefresh && validExisting) continue;
      try {
        final data = await rootBundle.load('assets/geo/$name');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.length < minimum) {
          bundledRefreshComplete = false;
          continue;
        }
        final temp = File('$dir/$name.bundle');
        await temp.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
      } catch (_) {
        bundledRefreshComplete = false;
        // Settings can download a fresh copy when bundled assets are absent.
      }
    }

    if (forceBundledRefresh &&
        bundledRefreshComplete &&
        await hasSmartRuleAssets()) {
      await bundleMarker.writeAsString(
        'AurumProxy 1.2.6 bundled Geo rules',
        flush: true,
      );
    }
    return dir;
  }

  Future<DateTime> updateAll() async {
    final dir = await filesDir;
    if (dir.isEmpty) throw StateError('无法获取 Geo 数据目录');
    final target = Directory(dir);
    await target.create(recursive: true);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    client.idleTimeout = const Duration(seconds: 12);
    try {
      for (final entry in _sources.entries) {
        await _downloadWithFallback(
          client,
          entry.key,
          entry.value,
          File('$dir/${entry.key}'),
        );
      }
    } finally {
      client.close(force: true);
    }

    if (!await hasSmartRuleAssets()) {
      throw StateError('Geo 数据下载完成但完整性检查失败');
    }
    return DateTime.now();
  }

  Future<void> _downloadWithFallback(
    HttpClient client,
    String name,
    List<String> urls,
    File target,
  ) async {
    Object? lastError;
    for (final url in urls) {
      try {
        await _download(client, url, target);
        final minimum = _minimumBytes[name] ?? 1024;
        if (await target.exists() && await target.length() >= minimum) return;
        throw FileSystemException('$name 文件过小或不完整', target.path);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('$name 更新失败：$lastError');
  }

  Future<void> _download(HttpClient client, String url, File target) async {
    var current = Uri.parse(url);
    for (var redirects = 0; redirects < 8; redirects++) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'AurumProxy/1.2.6');
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      final response = await request.close();

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw HttpException('重定向缺少 Location', uri: current);
        }
        current = current.resolve(location);
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(
          'HTTP ${response.statusCode}: $current',
          uri: current,
        );
      }

      final temp = File('${target.path}.download');
      if (await temp.exists()) await temp.delete();
      final sink = temp.openWrite();
      try {
        await response.pipe(sink);
      } catch (_) {
        await sink.close();
        rethrow;
      }
      final name = target.uri.pathSegments.last;
      final minimum = _minimumBytes[name] ?? 1024;
      if (!await temp.exists() || await temp.length() < minimum) {
        if (await temp.exists()) await temp.delete();
        throw FileSystemException('下载文件为空或不完整', target.path);
      }

      final backup = File('${target.path}.bak');
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) {
        await target.rename(backup.path);
      }
      try {
        await temp.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } catch (e) {
        if (await target.exists()) await target.delete();
        if (await backup.exists()) await backup.rename(target.path);
        rethrow;
      }
      return;
    }
    throw HttpException('重定向次数过多', uri: current);
  }

  Future<bool> hasSmartRuleAssets() async {
    final dir = await filesDir;
    if (dir.isEmpty) return false;
    for (final name in _sources.keys) {
      final f = File('$dir/$name');
      final minimum = _minimumBytes[name] ?? 1024;
      if (!await f.exists() || await f.length() < minimum) return false;
    }
    return true;
  }
}
