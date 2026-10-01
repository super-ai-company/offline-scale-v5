import 'package:flutter/services.dart';
import '../models/cart_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'feie_service.dart';

/// 封装 Android 侧 PrintChannel，负责打印收据。
class PrintService {
  static final PrintService _instance = PrintService._();
  factory PrintService() => _instance;
  PrintService._() : _cloudLoader = _defaultCloudLoader;
  PrintService.forTesting({required Future<FeieService> Function() cloudLoader})
    : _cloudLoader = cloudLoader;
  final Future<FeieService> Function() _cloudLoader;
  static Future<FeieService> _defaultCloudLoader() async =>
      FeieService(await FeieConfig.load());
  bool _localConnected = false;

  static const _method = MethodChannel('cashier/print');

  bool _connected = false;
  bool get isConnected => _connected;
  String resultKey = 'print_fail';

  /// 连接内置或 USB 打印机
  Future<bool> connect() async {
    try {
      _localConnected = await _method.invokeMethod<bool>('openPort') ?? false;
      _connected = _localConnected;
      if (_localConnected) return true;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('feie_enabled') == true) {
        _connected = await (await _cloudLoader()).printerStatus() == 1;
      }
      return _connected;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  /// 断开打印机
  Future<void> disconnect() async {
    try {
      await _method.invokeMethod('closePort');
    } on PlatformException {
      // 设备已断开时，仍要清理本地连接状态。
    }
    _connected = false;
    _localConnected = false;
  }

  /// 打印收据
  /// [shopName] 当前语言的店名，[items] 购物车，[total] 总金额
  Future<bool> printTicket({
    required String shopName,
    required List<CartItem> items,
    required double total,
    String language = 'en',
    String totalLabel = 'Total',
  }) async {
    resultKey = 'print_fail';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('local_print_uncertain') == true) {
        resultKey = 'print_local_uncertain';
        return false;
      }
      // A local connection attempt happens before any secret or network access.
      _localConnected = await _method.invokeMethod<bool>('openPort') ?? false;
      if (!_localConnected) {
        if (prefs.getBool('feie_enabled') != true) return false;
        final service = await _cloudLoader();
        if (prefs.getBool('feie_uncertain') == true) {
          resultKey = 'feie_uncertain';
          return false;
        }
        // Refuse offline / out-of-paper status before sending an order.
        if (await service.printerStatus() != 1) return false;
        final result = await service.print(
          FeieService.receipt(
            shopName: shopName,
            items: items,
            total: total,
            totalLabel: totalLabel,
            date: DateTime.now(),
            language: language,
          ),
        );
        resultKey = switch (result.state) {
          CloudPrintState.accepted => 'feie_accepted',
          CloudPrintState.uncertain ||
          CloudPrintState.blocked => 'feie_uncertain',
          CloudPrintState.rejected => 'print_fail',
        };
        return result.state == CloudPrintState.accepted;
      }

      await prefs.setBool('local_print_uncertain', true);
      final result = await _method.invokeMethod<bool>('printTicket', {
        'shopName': shopName,
        'items': items.map((e) => e.toPrintMap(language)).toList(),
        'total': total,
        'language': language,
        'totalLabel': totalLabel,
      });
      if (result != true) {
        _connected = false;
        _localConnected = false;
        resultKey = 'print_local_uncertain';
      }
      if (result == true) {
        await prefs.setBool('local_print_uncertain', false);
        resultKey = 'print_success';
      }
      return result == true;
    } catch (_) {
      _connected = false;
      resultKey = _localConnected ? 'print_local_uncertain' : 'print_fail';
      _localConnected = false;
      return false;
    }
  }
}
