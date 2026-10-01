import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/weight_service.dart';
import '../l10n/locale_provider.dart';
import '../utils/top_toast.dart';
import '../services/feie_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pathCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _defaultPriceCtrl = TextEditingController();
  bool _printEnabled = true;
  bool _productCameraEnabled = false;
  final _feieUserCtrl = TextEditingController();
  final _feieSnCtrl = TextEditingController();
  final _feieKeyCtrl = TextEditingController();
  String _backend = 'usb';
  String _region = 'jp';
  bool _busy = false;
  String _printerMessage = '';

  FeieConfig get _feieConfig => FeieConfig(
    user: _feieUserCtrl.text.trim(),
    sn: _feieSnCtrl.text.trim(),
    region: _region,
    ukey: _feieKeyCtrl.text.trim(),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _pathCtrl.text = prefs.getString('serial_path') ?? '/dev/ttyS4';
    _rateCtrl.text = (prefs.getInt('serial_rate') ?? 9600).toString();
    final savedShopName = prefs.getString('shop_name');
    _shopCtrl.text = savedShopName == 'ร้านอาหาร' ? '' : savedShopName ?? '';
    _defaultPriceCtrl.text = (prefs.getDouble('default_weight_price') ?? 1)
        .toStringAsFixed(2);
    setState(() {
      _printEnabled = prefs.getBool('print_enabled') ?? true;
      _productCameraEnabled = prefs.getBool('product_camera_enabled') ?? false;
      _backend = prefs.getString('printer_backend') == 'feie' ? 'feie' : 'usb';
      _region = prefs.getString('feie_region') ?? 'jp';
      _feieUserCtrl.text = prefs.getString('feie_user') ?? '';
      _feieSnCtrl.text = prefs.getString('feie_sn') ?? '';
    });
    try {
      final config = await FeieConfig.load();
      if (mounted) _feieKeyCtrl.text = config.ukey;
    } catch (_) {
      if (mounted && _backend == 'feie') {
        setState(() => _printerMessage = 'feie_key_error');
      }
    }
  }

  Future<void> _save(LocaleProvider lp) async {
    if (_busy) return;
    final path = _pathCtrl.text.trim();
    final rate = int.tryParse(_rateCtrl.text.trim());
    final defaultPrice = double.tryParse(_defaultPriceCtrl.text.trim());
    if (path.isEmpty || rate == null || rate <= 0) {
      TopToast.show(
        context,
        lp.tr('invalid_serial_settings'),
        type: ToastType.error,
      );
      return;
    }
    if (defaultPrice == null || !defaultPrice.isFinite || defaultPrice <= 0) {
      TopToast.show(
        context,
        lp.tr('enter_positive_price'),
        type: ToastType.error,
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (_backend == 'feie') {
      if (!mounted) return;
      if (!_feieConfig.valid) {
        TopToast.show(context, lp.tr('feie_invalid'), type: ToastType.error);
        return;
      }
      try {
        await _feieConfig.save();
      } catch (_) {
        if (mounted) {
          TopToast.show(
            context,
            lp.tr('feie_key_error'),
            type: ToastType.error,
          );
        }
        return;
      }
    }
    await prefs.setString('printer_backend', _backend);
    await prefs.setString('serial_path', path);
    await prefs.setInt('serial_rate', rate);
    await prefs.setString('shop_name', _shopCtrl.text.trim());
    await prefs.setDouble('default_weight_price', defaultPrice);
    await prefs.setBool('print_enabled', _printEnabled);
    await prefs.setBool('product_camera_enabled', _productCameraEnabled);
    if (!mounted) return;
    TopToast.show(context, lp.tr('settings_saved'), type: ToastType.success);
  }

  Future<void> _cloudAction(String action) async {
    if (_busy) return;
    if (!_feieConfig.valid) {
      setState(() => _printerMessage = 'feie_invalid');
      return;
    }
    setState(() => _busy = true);
    var message = 'feie_network_error';
    try {
      final service = FeieService(_feieConfig);
      if (action == 'status') {
        message = switch (await service.printerStatus()) {
          1 => 'feie_online',
          0 => 'feie_offline',
          _ => 'feie_abnormal',
        };
      } else if (action == 'order') {
        final prefs = await SharedPreferences.getInstance();
        final id = prefs.getString('feie_last_order');
        if (id == null ||
            prefs.getString('feie_last_region') != _region ||
            prefs.getString('feie_last_user') != _feieUserCtrl.text.trim()) {
          message = 'feie_no_order';
        } else {
          message = await service.orderPrinted(id)
              ? 'feie_printed'
              : 'feie_queued';
        }
      } else {
        if (await service.printerStatus() != 1) {
          message = 'feie_offline';
        } else {
          final result = await service.print(
            '<CB>Offline Scale V5</CB><BR>'
            'Printer test / 打印测试<BR>1234567890<BR>'
            'THB 1.00<BR><BR>',
          );
          message = result.state == CloudPrintState.accepted
              ? 'feie_accepted'
              : result.state == CloudPrintState.rejected
              ? 'print_fail'
              : 'feie_uncertain';
        }
      }
    } catch (_) {
      /* Do not display cloud payloads or credentials. */
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _printerMessage = message;
      });
    }
  }

  Future<void> _resolveUncertain(LocaleProvider lp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lp.tr('feie_resolve')),
        content: Text(lp.tr('feie_resolve_hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(lp.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(lp.tr('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('feie_uncertain', false);
    if (mounted) setState(() => _printerMessage = 'feie_resolved');
  }

  Future<void> _testScale(LocaleProvider lp) async {
    final path = _pathCtrl.text.trim();
    final rate = int.tryParse(_rateCtrl.text.trim());
    if (path.isEmpty || rate == null || rate <= 0) {
      TopToast.show(
        context,
        lp.tr('invalid_serial_settings'),
        type: ToastType.error,
      );
      return;
    }
    final ok = await WeightService().open(path: path, rate: rate);
    if (!mounted) return;
    TopToast.show(
      context,
      ok ? lp.tr('serial_success', args: {'path': path}) : lp.tr('serial_fail'),
      type: ok ? ToastType.success : ToastType.error,
    );
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _rateCtrl.dispose();
    _shopCtrl.dispose();
    _defaultPriceCtrl.dispose();
    _feieUserCtrl.dispose();
    _feieSnCtrl.dispose();
    _feieKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LocaleProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          lp.tr('settings'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _Section(
                title: lp.tr('shop_info'),
                children: [
                  TextField(
                    controller: _shopCtrl,
                    decoration: InputDecoration(
                      labelText: lp.tr('shop_name'),
                      hintText: lp.tr('default_shop_name'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: lp.tr('default_price'),
                children: [
                  TextField(
                    controller: _defaultPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: lp.tr('price_kg'),
                      prefixText: '฿ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: lp.tr('printer_settings'),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(lp.tr('print_enabled')),
                    subtitle: Text(lp.tr('print_enabled_hint')),
                    value: _printEnabled,
                    onChanged: (value) => setState(() => _printEnabled = value),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _backend,
                    decoration: InputDecoration(
                      labelText: lp.tr('printer_backend'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'usb',
                        child: Text(lp.tr('printer_usb')),
                      ),
                      DropdownMenuItem(
                        value: 'feie',
                        child: Text(lp.tr('printer_feie')),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _backend = v!),
                  ),
                  if (_backend == 'feie') ...[
                    const SizedBox(height: 16),
                    Text(lp.tr('feie_hint')),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _region,
                      decoration: InputDecoration(
                        labelText: lp.tr('feie_region'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'jp',
                          child: Text('Asia Pacific / 亚太'),
                        ),
                        DropdownMenuItem(
                          value: 'cn',
                          child: Text('China / 中国'),
                        ),
                        DropdownMenuItem(
                          value: 'de',
                          child: Text('Europe / 欧洲'),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _region = v!),
                    ),
                    TextField(
                      controller: _feieUserCtrl,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: lp.tr('feie_user'),
                      ),
                    ),
                    TextField(
                      controller: _feieKeyCtrl,
                      enabled: !_busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: lp.tr('feie_ukey'),
                      ),
                    ),
                    TextField(
                      controller: _feieSnCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: lp.tr('feie_sn')),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _cloudAction('status'),
                          child: Text(lp.tr('feie_check')),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _cloudAction('test'),
                          child: Text(lp.tr('feie_test')),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _cloudAction('order'),
                          child: Text(lp.tr('feie_order')),
                        ),
                      ],
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_printerMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(lp.tr(_printerMessage)),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => _resolveUncertain(lp),
                      child: Text(lp.tr('feie_resolve')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: lp.tr('product_camera_settings'),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(lp.tr('product_camera_enabled')),
                    subtitle: Text(lp.tr('product_camera_hint')),
                    value: _productCameraEnabled,
                    onChanged: (value) =>
                        setState(() => _productCameraEnabled = value),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: lp.tr('serial_setting'),
                children: [
                  TextField(
                    controller: _pathCtrl,
                    decoration: InputDecoration(
                      labelText: lp.tr('serial_path'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rateCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: lp.tr('baud_rate'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cable_rounded, size: 24),
                    label: Text(
                      lp.tr('test_connection'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => _testScale(lp),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded, size: 24),
                label: Text(
                  lp.tr('save_settings'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _save(lp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
