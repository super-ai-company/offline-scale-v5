import 'package:flutter/services.dart';
import '../models/cart_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'feie_service.dart';

/// 封装 Android 侧 PrintChannel，负责打印收据。
class PrintService {
  static final PrintService _instance = PrintService._();
  factory PrintService() => _instance;
  PrintService._();

  static const _method = MethodChannel('cashier/print');

  bool _connected = false;
  bool get isConnected => _connected;
  String resultKey = 'print_fail';

  /// 连接内置或 USB 打印机
  Future<bool> connect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('printer_backend') == 'feie') {
        _connected =
            await FeieService(await FeieConfig.load()).printerStatus() == 1;
        return _connected;
      }
      final result = await _method.invokeMethod<bool>('openPort');
      _connected = result ?? false;
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
      if (prefs.getString('printer_backend') == 'feie') {
        final service = FeieService(await FeieConfig.load());
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
      // 如果未连接，先尝试连接
      if (!_connected) {
        final ok = await connect();
        if (!ok) return false;
      }

      final result = await _method.invokeMethod<bool>('printTicket', {
        'shopName': shopName,
        'items': items.map((e) => e.toPrintMap(language)).toList(),
        'total': total,
        'language': language,
        'totalLabel': totalLabel,
      });
      if (result != true) _connected = false;
      if (result == true) resultKey = 'print_success';
      return result == true;
    } catch (_) {
      _connected = false;
      return false;
    }
  }
}
