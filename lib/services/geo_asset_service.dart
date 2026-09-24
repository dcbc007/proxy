import 'dart:io';

import 'package:flutter/services.dart';

class GeoAssetService {
  static const MethodChannel _channel =
      MethodChannel('aurum_proxy/vpn_permission');

  static const Map<String, String> _urls = {
    'geoip.dat':
        'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat',
    'geosite.dat':
        'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat',
    'geoip-cn.srs':
        'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs',
    'geosite-geolocation-cn.srs':
        'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs',
  };

  Future<String> get filesDir async {
    return await _channel.invokeMethod<String>('filesDir') ?? '';
  }

  Future<String> bootstrap() async {
    final dir = await filesDir;
    if (dir.isEmpty) return '';
    final target = Directory(dir);
    await target.create(recursive: true);

    for (final name in _urls.keys) {
      final file = File('$dir/$name');
      if (await file.exists() && await file.length() > 0) continue;
      try {
        final data = await rootBundle.load('assets/geo/$name');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } catch (_) {
        // Build/dev environments without bundled assets can still update them
        // from the Settings screen.
      }
    }
    return dir;
  }

  Future<DateTime> updateAll() async {
    final dir = await filesDir;
    if (dir.isEmpty) throw StateError('无法获取 Geo 数据目录');
    final target = Directory(dir);
    await target.create(recursive: true);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      for (final entry in _urls.entries) {
        await _download(client, entry.value, File('$dir/${entry.key}'));
      }
    } finally {
      client.close(force: true);
    }
    return DateTime.now();
  }

  Future<void> _download(HttpClient client, String url, File target) async {
    var current = Uri.parse(url);
    for (var redirects = 0; redirects < 6; redirects++) {
      final request = await client.getUrl(current);
      request.headers.set(HttpHeaders.userAgentHeader, 'AurumProxy/1.1');
      final response = await request.close();

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw HttpException('Geo 数据重定向缺少 Location', uri: current);
        }
        current = current.resolve(location);
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw HttpException(
          '下载失败 HTTP ${response.statusCode}: $current',
          uri: current,
        );
      }

      final temp = File('${target.path}.tmp');
      final sink = temp.openWrite();
      await response.pipe(sink);
      if (!await temp.exists() || await temp.length() == 0) {
        throw const FileSystemException('下载的 Geo 数据为空');
      }
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      return;
    }
    throw HttpException('Geo 数据重定向次数过多', uri: current);
  }

  Future<bool> hasSmartRuleAssets() async {
    final dir = await filesDir;
    if (dir.isEmpty) return false;
    for (final name in _urls.keys) {
      final f = File('$dir/$name');
      if (!await f.exists() || await f.length() == 0) return false;
    }
    return true;
  }
}
