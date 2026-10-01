import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:presentation_displays/secondary_display.dart'
    show SecondaryDisplay;

class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  List<dynamic> _cartItems = [];
  double _totalAmount = 0.0;
  int _moneyDigits = 2;
  String _welcome = 'Welcome to our store';
  String _cartTitle = 'My Cart';
  String _emptyCart = 'Cart is empty';
  String _totalLabel = 'Total';

  void _handleData(dynamic data) {
    if (data != null) {
      try {
        final map = jsonDecode(data.toString());
        if (mounted) {
          setState(() {
            _cartItems = map['cart'] ?? [];
            _moneyDigits = (map['moneyDigits'] as int? ?? 2).clamp(0, 2);
            _totalAmount = (map['total'] ?? 0.0).toDouble();
            _welcome = map['welcome'] as String? ?? 'Welcome to our store';
            _cartTitle = map['cartTitle'] as String? ?? 'My Cart';
            _emptyCart = map['emptyCart'] as String? ?? 'Cart is empty';
            _totalLabel = map['totalLabel'] as String? ?? 'Total';
          });
        }
      } catch (e) {
        debugPrint('Customer display data error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecondaryDisplay(
      callback: _handleData,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Row(
          children: [
            // 左侧：轮播图或店铺展示（占大半部分）
            Expanded(
              flex: 13,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fastfood,
                          size: 120,
                          color: const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _welcome,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 右侧：客户购物车（不可操作）
            Expanded(
              flex: 9,
              child: Container(
                margin: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            color: Color(0xFF0284C7),
                            size: 36,
                          ),
                          SizedBox(width: 12),
                          Text(
                            _cartTitle,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFE2E8F0),
                    ),
                    Expanded(
                      child: _cartItems.isEmpty
                          ? Center(
                              child: Text(
                                _emptyCart,
                                style: TextStyle(
                                  fontSize: 24,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _cartItems.length,
                              separatorBuilder: (_, _) => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                  color: Color(0xFFCBD5E1),
                                  thickness: 1.5,
                                ),
                              ),
                              itemBuilder: (_, i) {
                                final item = _cartItems[i];
                                final isByWeight = item['isByWeight'] == true;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['name'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            RichText(
                                              text: TextSpan(
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  color: Color(0xFF64748B),
                                                ),
                                                children: [
                                                  TextSpan(
                                                    text: isByWeight
                                                        ? '${item['weight'].toStringAsFixed((item['weightDigits'] as int? ?? 3).clamp(0, 3))} kg'
                                                        : 'x ${item['weight'].toStringAsFixed(0)}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF0284C7),
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 24,
                                                    ),
                                                  ),
                                                  const TextSpan(text: '  ×  '),
                                                  TextSpan(
                                                    text:
                                                        '${item['price'].toStringAsFixed((item['moneyDigits'] as int? ?? 2).clamp(0, 2))} ฿',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${(item['subtotal'] ?? 0.0).toStringAsFixed((item['moneyDigits'] as int? ?? 2).clamp(0, 2))} ฿',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0284C7),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _totalLabel,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${_totalAmount.toStringAsFixed(_moneyDigits)} ฿',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
