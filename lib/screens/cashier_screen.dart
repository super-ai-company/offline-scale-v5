import 'dart:async';
import 'dart:convert';
import 'package:presentation_displays/displays_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/top_toast.dart';
import '../models/menu_item.dart';
import '../models/cart_item.dart';
import '../services/db_service.dart';
import '../services/weight_service.dart';
import '../services/print_service.dart';
import '../services/ai_recognition_service.dart';
import '../l10n/locale_provider.dart';
import 'menu_screen.dart';
import 'settings_screen.dart';
import 'ai_camera_screen.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final _db = DbService();
  final _weight = WeightService();
  final _print = PrintService();

  List<MenuItem> _menuItems = [];
  final List<CartItem> _cart = [];

  double _currentKg = 0.0;
  bool _weightStable = false;
  bool _weightValid = false;
  bool _weightIsZero = false;
  bool _weightIsTare = false;
  bool _scaleControlAvailable = false;
  bool _scaleConnected = false;
  StreamSubscription<WeightData>? _weightSub;
  Timer? _weightWatchdog;
  DateTime? _lastWeightAt;

  MenuItem? _selectedItem;
  final _priceCtrl = TextEditingController(text: '1.00');
  double _defaultPrice = 1;
  double _enteredPrice = 1;
  bool _keypadReplaceOnNext = true;
  bool _printerConnected = false;
  bool _printEnabled = true;
  bool _productCameraEnabled = false;
  bool _printing = false;
  int _fixedQty = 1;

  final DisplayManager _displayManager = DisplayManager();
  bool _hasSecondaryDisplay = false;
  LocaleProvider? _localeProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<LocaleProvider>(context);
    if (_localeProvider != provider) {
      _localeProvider?.removeListener(_syncCartToSecondaryDisplay);
      _localeProvider = provider;
      provider.addListener(_syncCartToSecondaryDisplay);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultPrice();
    _loadMenu();
    _loadPrintSetting();
    _loadProductCameraSetting();
    _connectScale();
    _weightWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastWeightAt != null &&
          DateTime.now().difference(_lastWeightAt!) > const Duration(seconds: 3)) {
        setState(() {
          _weightValid = false;
          _weightStable = false;
          _weightIsZero = false;
          _weightIsTare = false;
          _scaleControlAvailable = false;
          _currentKg = 0;
          _scaleConnected = false;
        });
        _lastWeightAt = null;
      }
    });
    _setupSecondaryDisplay();
  }

  Future<void> _setupSecondaryDisplay() async {
    try {
      final displays = await _displayManager.getDisplays();
      if (mounted && displays != null && displays.length > 1) {
        final secondaryDisplay = displays[1];
        await _displayManager.showSecondaryDisplay(
          displayId: secondaryDisplay.displayId!, 
          routerName: "presentation",
        );
        setState(() => _hasSecondaryDisplay = true);
        _syncCartToSecondaryDisplay();
      }
    } catch (e) {
      debugPrint('副屏初始化失败: $e');
    }
  }

  void _syncCartToSecondaryDisplay() {
    if (!_hasSecondaryDisplay || !mounted) return;
    final lp = _localeProvider;
    if (lp == null) return;
    
    final cartData = _cart.map((e) {
      return {
        'name': e.menuItem.nameFor(lp.localeStr),
        'price': e.menuItem.price,
        'weight': e.weight,
        'subtotal': e.subtotal,
        'isByWeight': e.menuItem.isByWeight,
      };
    }).toList();

    final payload = jsonEncode({
      'cart': cartData,
      'total': _total,
      'language': lp.localeStr,
      'welcome': lp.tr('customer_welcome'),
      'cartTitle': lp.tr('customer_cart_title'),
      'emptyCart': lp.tr('cart_empty'),
      'totalLabel': lp.tr('total'),
    });
    
    _displayManager.transferDataToPresentation(payload);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _localeProvider?.removeListener(_syncCartToSecondaryDisplay);
    _weightSub?.cancel();
    _weightWatchdog?.cancel();
    _weight.close();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    final items = await _db.getMenuItems();
    if (!mounted) return;
    final defaultItem = items.firstWhere(
      (item) => item.isQuickWeigh,
      orElse: () => MenuItem.quickWeigh,
    );
    final selected = _selectedItem;
    final next = selected == null || selected.isQuickWeigh
        ? defaultItem
        : items.firstWhere(
            (item) => item.id == selected.id,
            orElse: () => defaultItem,
          );
    setState(() {
      _menuItems = items;
      _selectedItem = next;
      _fixedQty = 1;
      _setPriceText(next.isQuickWeigh ? _defaultPrice : next.price);
      _keypadReplaceOnNext = true;
    });
  }

  Future<void> _loadDefaultPrice() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('default_weight_price') ?? 1;
    if (!mounted || !saved.isFinite || saved <= 0) return;
    setState(() {
      _defaultPrice = saved;
      if (_selectedItem == null || _selectedItem!.isQuickWeigh) {
        _setPriceText(saved);
        _keypadReplaceOnNext = true;
      }
    });
  }

  void _setPriceText(double price) {
    _enteredPrice = price;
    final text = price.toStringAsFixed(2);
    _priceCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _saveDefaultPrice(LocaleProvider lp) async {
    if (_enteredPrice <= 0) {
      _showSnack(lp.tr('enter_positive_price'), type: ToastType.error);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('default_weight_price', _enteredPrice);
    if (!mounted) return;
    setState(() => _defaultPrice = _enteredPrice);
    _showSnack(lp.tr('default_price_saved'), type: ToastType.success);
  }

  void _pressPriceKey(String key) {
    final current = _priceCtrl.text;
    String next;
    if (key == 'C') {
      next = '';
    } else if (key == '⌫') {
      next = current.isEmpty ? '' : current.substring(0, current.length - 1);
    } else if (_keypadReplaceOnNext) {
      next = key == '.' ? '0.' : key;
    } else if (current == '0' && key != '.') {
      next = key;
    } else {
      next = current + key;
    }
    if (!RegExp(r'^\d{0,7}(\.\d{0,2})?$').hasMatch(next)) return;
    setState(() {
      _keypadReplaceOnNext = false;
      _enteredPrice = double.tryParse(next) ?? 0;
      _priceCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });
  }

  Future<void> _loadPrintSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final enabled = prefs.getBool('print_enabled') ?? true;
    setState(() => _printEnabled = enabled);
    if (enabled) {
      _connectPrinter();
    } else {
      await _print.disconnect();
      if (!mounted) return;
      setState(() => _printerConnected = false);
    }
  }

  Future<void> _loadProductCameraSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _productCameraEnabled =
          prefs.getBool('product_camera_enabled') ?? false);
    }
  }

  Future<void> _connectScale() async {
    await _weightSub?.cancel();
    _weightSub = null;
    _lastWeightAt = null;
    if (mounted) {
      setState(() {
        _scaleConnected = false;
        _weightValid = false;
        _weightStable = false;
        _weightIsZero = false;
        _weightIsTare = false;
        _scaleControlAvailable = false;
        _currentKg = 0;
      });
    }
    final ok = await _weight.open();
    if (!mounted) return;
    setState(() => _scaleConnected = ok);
    if (ok) {
      _weightSub = _weight.weightStream.listen((data) {
        if (!mounted) return;
        _lastWeightAt = DateTime.now();
        setState(() {
          _scaleConnected = true;
          _currentKg = data.kg;
          _weightStable = data.stable;
          _weightValid = data.canSell;
          _weightIsZero = data.isZero;
          _weightIsTare = data.isTare;
          _scaleControlAvailable = data.valid && data.unit.toLowerCase() == 'kg';
        });
      }, onError: (_) {
        if (mounted) {
          setState(() {
            _scaleConnected = false;
            _weightValid = false;
            _weightStable = false;
            _weightIsZero = false;
            _weightIsTare = false;
            _scaleControlAvailable = false;
          });
        }
      });
    }
  }

  Future<void> _connectPrinter() async {
    if (!_printEnabled) return;
    final ok = await _print.connect();
    if (!mounted || !_printEnabled) return;
    setState(() => _printerConnected = ok);
  }

  Future<void> _sendScaleCommand(LocaleProvider lp, {required bool tare}) async {
    if (!_scaleConnected || !_weightStable) {
      _showSnack(lp.tr('wait_for_stable_scale'), type: ToastType.error);
      return;
    }
    bool sent;
    try {
      sent = tare ? await _weight.tare() : await _weight.zero();
    } on PlatformException {
      sent = false;
    }
    if (!mounted) return;
    _showSnack(
      lp.tr(sent ? 'scale_command_sent' : 'scale_command_failed'),
      type: sent ? ToastType.success : ToastType.error,
    );
  }

  void _selectMenuItem(MenuItem item) {
    setState(() {
      _selectedItem = item;
      _fixedQty = 1;
      _setPriceText(item.isQuickWeigh ? _defaultPrice : item.price);
      _keypadReplaceOnNext = true;
    });
  }

  Future<void> _recognizeProduct(LocaleProvider lp) async {
    final counts = await _db.visualSampleCounts();
    if (!mounted) return;
    if (!counts.keys.any((id) => _menuItems.any((item) => item.id == id && !item.isQuickWeigh))) {
      _showSnack(lp.tr('ai_no_samples'), type: ToastType.error);
      return;
    }
    final embedding = await Navigator.push<List<double>>(
      context,
      MaterialPageRoute(builder: (_) => const AiCameraScreen()),
    );
    if (embedding == null || !mounted) return;
    final matches = await AiRecognitionService().recognize(embedding, _menuItems);
    if (!mounted) return;
    if (matches.isEmpty) {
      _showSnack(lp.tr('ai_no_match'), type: ToastType.error);
      return;
    }
    final selected = await showDialog<MenuItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(lp.tr('ai_choose')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final match in matches)
                ListTile(
                  title: Text(match.item.nameFor(lp.localeStr)),
                  subtitle: Text('${lp.tr('ai_similarity')}: ${(match.similarity * 100).toStringAsFixed(0)}%'),
                  onTap: () => Navigator.pop(dialogContext, match.item),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(lp.tr('cancel')))],
      ),
    );
    if (selected != null && mounted) _selectMenuItem(selected);
  }

  void _addToCart(LocaleProvider lp) {
    if (_selectedItem == null || _printing) return;
    final item = _selectedItem!;
    if (_enteredPrice <= 0) {
      _showSnack(lp.tr('enter_positive_price'), type: ToastType.error);
      return;
    }

    double qty;
    if (item.isByWeight) {
      if (!_weightValid || !_scaleConnected || _currentKg <= 0) {
        _showSnack(lp.tr('pls_put_on_scale'), type: ToastType.error);
        return;
      }
      qty = _currentKg;
    } else {
      qty = _fixedQty.toDouble();
    }

    final subtotal = CartItem.saleSubtotal(
      byWeight: item.isByWeight,
      quantity: qty,
      price: _enteredPrice,
    );

    setState(() {
      _cart.add(CartItem(menuItem: item.copyWith(price: _enteredPrice), weight: qty, subtotal: subtotal));
    });
    _syncCartToSecondaryDisplay();
  }

  void _removeCartItem(int index) {
    if (_printing) return;
    setState(() => _cart.removeAt(index));
    _syncCartToSecondaryDisplay();
  }

  void _clearCart() {
    if (_printing) return;
    setState(() {
      _cart.clear();
      _keypadReplaceOnNext = true;
    });
    _syncCartToSecondaryDisplay();
  }

  double get _total => _cart.fold(0.0, (sum, e) => sum + e.subtotal);

  Future<void> _printReceipt(LocaleProvider lp) async {
    if (_printing) return;
    if (_cart.isEmpty) {
      _showSnack(lp.tr('cart_empty'));
      return;
    }
    if (!_printEnabled) {
      _clearCart();
      _showSnack(lp.tr('sale_complete'), type: ToastType.success);
      return;
    }
    setState(() => _printing = true);
    _showSnack(lp.tr('printing'));

    bool ok;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedShopName = prefs.getString('shop_name');
      final shopName = savedShopName == null ||
              savedShopName.trim().isEmpty ||
              savedShopName == 'ร้านอาหาร'
          ? lp.tr('default_shop_name')
          : savedShopName.trim();
      ok = await _print.printTicket(
        shopName: shopName,
        items: _cart,
        total: _total,
        language: lp.localeStr,
        totalLabel: lp.tr('total'),
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _printing = false;
      _printerConnected = ok;
    });
    _showSnack(
      lp.tr(_print.resultKey),
      type: ok ? ToastType.success : ToastType.error,
    );
    if (ok) _clearCart();
  }

  void _showSnack(String msg, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    TopToast.show(context, msg, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LocaleProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      appBar: _buildAppBar(lp),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Expanded(
              flex: 7,
              child: Row(children: [
                Expanded(flex: 3, child: _buildMenuPanel(lp)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _buildWeightSection(lp)),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: _buildKeypadPanel(lp)),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(flex: 3, child: _buildCartPanel(lp)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(LocaleProvider lp) {
    return AppBar(
      title: Text(lp.tr('app_title'), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A), // Slate 900
      actions: [
        _StatusChip(
          icon: Icons.scale_rounded,
          label: lp.tr('scale'),
          connected: _scaleConnected,
          onTap: _connectScale,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          icon: Icons.print_rounded,
          label: lp.tr('printer'),
          connected: _printerConnected,
          onTap: _printEnabled ? _connectPrinter : null,
        ),
        const SizedBox(width: 16),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: lp.localeStr,
              items: [
                DropdownMenuItem(value: 'en', child: Text(lp.tr('lang_en'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                DropdownMenuItem(value: 'th', child: Text(lp.tr('lang_th'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                DropdownMenuItem(value: 'zh', child: Text(lp.tr('lang_zh'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              ],
              onChanged: (v) {
                if (v != null) lp.setLocale(v);
              },
              icon: const Icon(Icons.language, size: 18, color: Color(0xFF64748B)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_productCameraEnabled)
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: lp.tr('ai_camera'),
            onPressed: () => _recognizeProduct(lp),
          ),
        IconButton(
          icon: const Icon(Icons.restaurant_menu_rounded),
          tooltip: lp.tr('menu_manage'),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const MenuScreen()));
            _loadMenu();
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: lp.tr('settings'),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            _loadPrintSetting();
            _loadProductCameraSetting();
            _loadDefaultPrice();
            _connectScale();
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMenuPanel(LocaleProvider lp) {
    final items = _menuItems.any((item) => item.isQuickWeigh)
        ? _menuItems
        : [MenuItem.quickWeigh, ..._menuItems];
    final visibleItems = items.map((item) => item.isQuickWeigh
        ? item.copyWith(price: _defaultPrice)
        : item).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(scrollbars: false),
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.15,
            ),
            itemCount: visibleItems.length,
            itemBuilder: (_, i) => _MenuCard(
              item: visibleItems[i],
              selected: _selectedItem?.id == visibleItems[i].id,
              onTap: () => _selectMenuItem(visibleItems[i]),
              lp: lp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel(LocaleProvider lp) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          Expanded(child: _buildCartList(lp)),
          _buildBottomBar(lp),
        ],
      ),
    );
  }

  Widget _buildKeypadPanel(LocaleProvider lp) {
    const keys = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '.', '0', '⌫'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(lp.tr('number_keypad'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A))),
          ),
          TextButton.icon(
            onPressed: () => _pressPriceKey('C'),
            icon: const Icon(Icons.backspace_outlined),
            label: Text(lp.tr('clear')),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final keyWidth = (constraints.maxWidth - 16) / 3;
            final keyHeight = (constraints.maxHeight - 24) / 4;
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: keyWidth / keyHeight,
              children: [
                for (final key in keys)
                  FilledButton.tonal(
                    onPressed: () => _pressPriceKey(key),
                    style: FilledButton.styleFrom(
                      backgroundColor: key == '⌫'
                          ? const Color(0xFFFFEDD5) : const Color(0xFFE0F2FE),
                      foregroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(key,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()])),
                  ),
              ],
            );
          }),
        ),
      ]),
    );
  }

  Widget _buildWeightSection(LocaleProvider lp) {
    final hasSelected = _selectedItem != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部始终显示当前称重状态 (Always show the live scale weight)
          _WeightDisplay(kg: _currentKg, valid: _scaleConnected && _weightValid, stable: _weightStable, lp: lp),
          if (_scaleControlAvailable) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _scaleConnected && _weightStable
                  ? () => _sendScaleCommand(lp, tare: true) : null,
              icon: const Icon(Icons.layers_clear_rounded),
              label: Text(lp.tr('tare')),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _scaleConnected && _weightStable
                  ? () => _sendScaleCommand(lp, tare: false) : null,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(lp.tr('zero')),
            )),
            if (_weightIsTare || _weightIsZero) ...[
              const SizedBox(width: 8),
              Text(lp.tr(_weightIsTare ? 'tare_active' : 'zero_active'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
            ],
          ]),
          ],
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          // 2. 根据左右选择情况显示操作状态
          if (hasSelected) ...[
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(12)),
                child: Icon(_selectedItem!.isByWeight ? Icons.scale_rounded : Icons.fastfood_rounded, size: 20, color: const Color(0xFF0284C7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedItem!.nameFor(lp.localeStr),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  readOnly: true,
                  showCursor: false,
                  enableInteractiveSelection: false,
                  decoration: InputDecoration(
                    labelText: lp.tr('unit_price'),
                    prefixText: '฿ ',
                    suffixText: _selectedItem!.isByWeight ? '/kg' : '/pc',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (_selectedItem!.isQuickWeigh)
                TextButton(
                  onPressed: () => _saveDefaultPrice(lp),
                  child: Text(lp.tr('save_default_price')),
                ),
            ]),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(lp.tr('calculated_price'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  '฿ ${CartItem.saleSubtotal(
                    byWeight: _selectedItem!.isByWeight,
                    quantity: _selectedItem!.isByWeight
                        ? (_weightValid && _scaleConnected ? _currentKg : 0)
                        : _fixedQty.toDouble(),
                    price: _enteredPrice,
                  ).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
                      color: Color(0xFF0284C7)),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (hasSelected && _selectedItem!.isByWeight) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 26),
                label: Text(lp.tr('add_to_cart'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981), // Emerald 500
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => _addToCart(lp),
              ),
            ),
          ],
          if (hasSelected && !_selectedItem!.isByWeight) ...[
            Row(children: [
              Text(lp.tr('qty'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
              const Spacer(),
              _QtyButton(icon: Icons.remove_rounded, onPressed: () => setState(() => _fixedQty = (_fixedQty - 1).clamp(1, 99))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('$_fixedQty', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              ),
              _QtyButton(icon: Icons.add_rounded, onPressed: () => setState(() => _fixedQty = (_fixedQty + 1).clamp(1, 99))),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 26),
                label: Text(lp.tr('add_to_cart'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => _addToCart(lp),
              ),
            )
          ],
          if (!hasSelected)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(lp.tr('pls_select_from_left'), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCartList(LocaleProvider lp) {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_basket_outlined, size: 60, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            Text(lp.tr('cart_empty'), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16, fontWeight: FontWeight.w500)),
          ]
        )
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _cart.length,
      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1.5, color: Color(0xFFF1F5F9)),
      itemBuilder: (_, i) {
        final item = _cart[i];
        final unit = item.menuItem.isByWeight ? lp.tr('unit_kg') : lp.tr('unit_pc');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.menuItem.nameFor(lp.localeStr), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF0F172A), height: 1.1)),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontSize: 18, color: const Color(0xFF64748B)),
                        children: [
                          TextSpan(text: item.weight.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0284C7), fontSize: 22)),
                          const TextSpan(text: ' '),
                          TextSpan(text: unit, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const TextSpan(text: ' × '),
                          TextSpan(text: '${item.menuItem.price.toStringAsFixed(2)} ฿', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '฿ ${item.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 28),
                onPressed: () => _removeCartItem(i),
                color: const Color(0xFFEF4444), // Red 500
                visualDensity: VisualDensity.standard,
                splashRadius: 28,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(LocaleProvider lp) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Row(
            children: [
              Text(lp.tr('total').toUpperCase(), style: const TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              Text(
                '฿ ${_total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Color(0xFF0284C7)), // Sky 600
              ),
            ],
          )),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_rounded, size: 24),
            label: Text(lp.tr('clear'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _cart.isEmpty ? null : _clearCart,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 300,
            child: FilledButton.icon(
              icon: const Icon(Icons.receipt_long_rounded, size: 28),
              label: Text(lp.tr(_printEnabled ? 'print_ticket' : 'finish_sale'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              onPressed: _cart.isEmpty || _printing ? null : () => _printReceipt(lp),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final MenuItem item;
  final bool selected;
  final VoidCallback onTap;
  final LocaleProvider lp;

  const _MenuCard({required this.item, required this.selected, required this.onTap, required this.lp});

  @override
  Widget build(BuildContext context) {
    final primaryName = item.nameFor(lp.localeStr);
    
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0284C7) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: selected
                ? [const BoxShadow(color: Color(0x330284C7), blurRadius: 10, offset: Offset(0, 4))]
                : [const BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: item.isByWeight 
                            ? [const Color(0xFF0EA5E9), const Color(0xFF38BDF8)]
                            : [const Color(0xFFF59E0B), const Color(0xFFFBBF24)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (item.isByWeight ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Icon(
                        item.isByWeight ? Icons.scale_rounded : Icons.fastfood_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      primaryName,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: selected ? Colors.white : const Color(0xFF0F172A), height: 1.1),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.isByWeight
                        ? '${item.price.toStringAsFixed(2)} ${lp.tr('price_kg')}'
                        : '${item.price.toStringAsFixed(2)} ${lp.tr('price_pc')}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : const Color(0xFF0284C7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightDisplay extends StatelessWidget {
  final double kg;
  final bool valid;
  final bool stable;
  final LocaleProvider lp;

  const _WeightDisplay({required this.kg, required this.valid, required this.stable, required this.lp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: valid ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9), // Green 100 or Slate 100
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: valid ? const Color(0xFF22C55E) : const Color(0xFFE2E8F0), width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.scale_rounded, color: valid ? const Color(0xFF16A34A) : const Color(0xFF94A3B8), size: 44),
          const SizedBox(width: 20),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${kg.toStringAsFixed(3)} kg',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: valid ? const Color(0xFF166534) : const Color(0xFF64748B),
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -1.0,
                ),
              ),
            ),
          ),
          if (valid && stable) ...[
            const SizedBox(width: 16),
            Container(width: 16, height: 16, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
          ]
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _QtyButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(icon, size: 32, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool connected;
  final VoidCallback? onTap;

  const _StatusChip({required this.icon, required this.label, required this.connected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: connected ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: connected ? const Color(0xFFB1F2C2) : const Color(0xFFFECACA), width: 1.5)
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
        ]),
      ),
    );
  }
}
