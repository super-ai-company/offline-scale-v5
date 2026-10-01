import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cart_item.dart';

typedef FeieTransport =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, String> fields);

class FeieConfig {
  final String user;
  final String sn;
  final String region;
  final String ukey;
  const FeieConfig({
    required this.user,
    required this.sn,
    required this.region,
    required this.ukey,
  });

  static const hosts = {
    'cn': 'api.feieyun.cn',
    'jp': 'api.jp.feieyun.com',
    'de': 'api.de.feieyun.com',
  };
  bool get valid =>
      user.trim().isNotEmpty &&
      RegExp(r'^\d{9}$').hasMatch(sn) &&
      ukey.trim().isNotEmpty &&
      hosts.containsKey(region);

  static const _secrets = MethodChannel('cashier/secrets');
  static Future<FeieConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _secrets.invokeMethod<String>('readFeieKey') ?? '';
    return FeieConfig(
      user: prefs.getString('feie_user') ?? '',
      sn: prefs.getString('feie_sn') ?? '',
      region: prefs.getString('feie_region') ?? 'jp',
      ukey: key,
    );
  }

  Future<void> save() async {
    if (!valid) throw const FormatException('Invalid Feie configuration');
    // Persist the secret first; never put UKEY in ordinary preferences.
    await _secrets.invokeMethod('writeFeieKey', ukey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('feie_user', user.trim());
    await prefs.setString('feie_sn', sn);
    await prefs.setString('feie_region', region);
  }
}

enum CloudPrintState { accepted, rejected, uncertain, blocked }

class CloudPrintResult {
  final CloudPrintState state;
  final String? orderId;
  const CloudPrintResult(this.state, [this.orderId]);
}

/// A single-device cloud adapter. No automatic print retries: Feie has no
/// documented idempotency key, so a lost reply may still mean a printed ticket.
class FeieService {
  static bool _submitting = false;
  final FeieConfig config;
  final FeieTransport transport;
  final DateTime Function() now;
  FeieService(this.config, {FeieTransport? transport, DateTime Function()? now})
    : transport = transport ?? _post,
      now = now ?? DateTime.now;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, String> fields,
  ) async {
    if (!config.valid) {
      throw const FormatException('Invalid Feie configuration');
    }
    final stamp = (now().millisecondsSinceEpoch ~/ 1000).toString();
    final signature = sha1
        .convert(
          utf8.encode('${config.user.trim()}${config.ukey.trim()}$stamp'),
        )
        .toString();
    return transport(
      Uri.https(
        FeieConfig.hosts[config.region]!,
        '/Api/Open/${name.substring(5)}',
      ),
      {
        'user': config.user.trim(),
        'stime': stamp,
        'sig': signature,
        'apiname': name,
        ...fields,
      },
    );
  }

  Future<int> printerStatus() async {
    final response = await _call('Open_queryPrinterStatus', {'sn': config.sn});
    if (response['ret'] != 0) {
      throw const FormatException('Printer status unavailable');
    }
    final status = response['data'];
    if (status is int && status >= 0 && status <= 2) return status;
    // The Asia Pacific API documents a string, not an integer status.
    final normalized = status.toString().toLowerCase().replaceAll(
      RegExp(r'[\s，,。.!]'),
      '',
    );
    if (const [
      '在线工作状态正常',
      '在线工作正常',
      'theonlineworkingconditionisnormal',
      'onlineandworkingnormally',
    ].contains(normalized)) {
      return 1;
    }
    if (const ['离线', 'offline'].contains(normalized)) return 0;
    if (const [
      '在线工作状态异常',
      '在线工作异常',
      'theonlineworkingconditionisabnormal',
      'onlinetheworkingstatusisabnormal',
    ].contains(normalized)) {
      return 2;
    }
    throw const FormatException('Unknown printer status');
  }

  Future<bool> orderPrinted(String id) async {
    final response = await _call('Open_queryOrderState', {'orderid': id});
    if (response['ret'] != 0 || response['data'] is! bool) {
      throw const FormatException('Order status unavailable');
    }
    return response['data'] as bool;
  }

  static String plain(String text) =>
      text.replaceAll(RegExp(r'[<>\x00-\x1F\x7F]'), ' ').replaceAll('&', '＆');

  static String receipt({
    required String shopName,
    required List<CartItem> items,
    required double total,
    required String totalLabel,
    required DateTime date,
    String language = 'en',
  }) {
    final out = StringBuffer('<CB>${plain(shopName)}</CB><BR>');
    out.write('${date.toIso8601String().substring(0, 16)}<BR>');
    out.write('--------------------------------<BR>');
    for (final item in items) {
      out.write('${plain(item.menuItem.nameFor(language))}<BR>');
      out.write(
        '${item.weightLabel} x ${item.menuItem.price.toStringAsFixed(item.moneyDigits)}',
      );
      out.write(
        ' = ${item.subtotal.toStringAsFixed(item.moneyDigits)} THB<BR>',
      );
    }
    out.write('--------------------------------<BR>');
    out.write(
      '<B>${plain(totalLabel)}: ${total.toStringAsFixed(items.isEmpty ? 2 : items.map((e) => e.moneyDigits).reduce((a, b) => a > b ? a : b))} THB</B><BR><BR>',
    );
    return out.toString();
  }

  Future<CloudPrintResult> print(String content) async {
    if (!config.valid || utf8.encode(content).length > 5000) {
      return const CloudPrintResult(CloudPrintState.rejected);
    }
    if (_submitting) return const CloudPrintResult(CloudPrintState.blocked);
    _submitting = true;
    try {
      return await _submit(content);
    } finally {
      _submitting = false;
    }
  }

  Future<CloudPrintResult> _submit(String content) async {
    if (utf8.encode(content).length > 5000) {
      return const CloudPrintResult(CloudPrintState.rejected);
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('feie_uncertain') == true) {
      return const CloudPrintResult(CloudPrintState.blocked);
    }
    // Durable intent before the side effect. A process death or lost response
    // leaves the guard set across restarts. No receipt/credentials in this log.
    if (!await prefs.setBool('feie_uncertain', true)) {
      return const CloudPrintResult(CloudPrintState.rejected);
    }
    try {
      final response = await _call('Open_printMsg', {
        'sn': config.sn,
        'content': content,
        'times': '1',
      });
      if (response['ret'] is int && response['ret'] != 0) {
        await prefs.setBool('feie_uncertain', false);
        return const CloudPrintResult(CloudPrintState.rejected);
      }
      final id = response['data'];
      if (response['ret'] == 0 && id is String && id.isNotEmpty) {
        await prefs.setString('feie_last_order', id);
        await prefs.setString('feie_last_region', config.region);
        await prefs.setString('feie_last_user', config.user.trim());
        await prefs.setBool('feie_uncertain', false);
        return CloudPrintResult(CloudPrintState.accepted, id);
      }
      return const CloudPrintResult(CloudPrintState.uncertain);
    } catch (_) {
      return const CloudPrintResult(CloudPrintState.uncertain);
    }
  }

  static Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, String> fields,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(
          fields.entries
              .map(
                (e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
        );
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException('Cloud HTTP failure');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const FormatException('Cloud response too large');
          }
        }
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}
