import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class TradingPanel extends StatefulWidget {
  const TradingPanel({super.key});

  @override
  State<TradingPanel> createState() => _TradingPanelState();
}

class _TradingPanelState extends State<TradingPanel> {
  final String _selectedPair = 'BTC/USDT';
  bool _isBuy = true;
  final TextEditingController _priceController = TextEditingController(text: '86402.15');
  final TextEditingController _amountController = TextEditingController();
  final double _sliderValue = 0.0; // ignore: unused_field
  
  // 模拟盘口数据
  final Random _rng = Random();
  List<_OrderRow> _asks = [];
  List<_OrderRow> _bids = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _generateMockData();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _updateMockData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _priceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _generateMockData() {
    double midPrice = 86402.15;
    _asks = List.generate(7, (i) => _OrderRow(
      price: midPrice + (7 - i) * 2.1,
      amount: _rng.nextDouble() * 2,
    )).reversed.toList();
    
    _bids = List.generate(7, (i) => _OrderRow(
      price: midPrice - (i + 1) * 2.1,
      amount: _rng.nextDouble() * 2,
    ));
  }

  void _updateMockData() {
    if (!mounted) return;
    setState(() {
      for (var ask in _asks) {
        if (_rng.nextBool()) ask.amount = _rng.nextDouble() * 3;
      }
      for (var bid in _bids) {
        if (_rng.nextBool()) bid.amount = _rng.nextDouble() * 3;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部交易对选择
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedPair,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '-3.57%',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
              const Spacer(),
              const Icon(Icons.candlestick_chart_outlined, size: 20, color: Colors.grey),
              const SizedBox(width: 12),
              const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2. 左侧交易表单
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    // 买入/卖出 切换
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isBuy = true),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isBuy ? const Color(0xFF00B07C) : Colors.grey.shade100,
                                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
                              ),
                              child: Text(
                                'Buy',
                                style: TextStyle(
                                  color: _isBuy ? Colors.white : Colors.black54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isBuy = false),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_isBuy ? const Color(0xFFF6465D) : Colors.grey.shade100,
                                borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                              ),
                              child: Text(
                                'Sell',
                                style: TextStyle(
                                  color: !_isBuy ? Colors.white : Colors.black54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Limit 下拉
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Limit', style: TextStyle(fontSize: 13)),
                          Icon(Icons.arrow_drop_down, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 价格输入
                    _buildInputBox('-', _priceController, '+', 'Price'),
                    const SizedBox(height: 12),
                    // 数量输入
                    _buildInputBox('', _amountController, 'BTC', 'Amount'),
                    const SizedBox(height: 12),
                    // 滑动条模拟
                    Row(
                      children: List.generate(5, (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: index == 0 ? Container(
                            decoration: BoxDecoration(
                              color: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ) : null,
                        ),
                      )),
                    ),
                    const SizedBox(height: 12),
                    // Total
                    _buildInputBox('', TextEditingController(), 'USDT', 'Total'),
                    const SizedBox(height: 12),
                    // 按钮
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${_isBuy ? 'Buy' : 'Sell'} Order Placed Successfully!'),
                              backgroundColor: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          elevation: 0,
                        ),
                        child: Text('${_isBuy ? 'Buy' : 'Sell'} BTC'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 3. 右侧盘口
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Price\n(USDT)', style: TextStyle(color: Colors.grey, fontSize: 10)),
                        Text('Amount\n(BTC)', style: TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.right),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Asks (Red)
                    ..._asks.map((row) => _buildOrderBookRow(row, const Color(0xFFF6465D))),
                    // Mid Price
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '86,402.15',
                            style: TextStyle(color: Color(0xFFF6465D), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '≈ HK\$671,939.03',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    // Bids (Green)
                    ..._bids.map((row) => _buildOrderBookRow(row, const Color(0xFF00B07C))),
                    
                    const SizedBox(height: 8),
                    // 底部比例条 (K字效果的一部分，展示买卖盘比例)
                    Row(
                      children: [
                        Expanded(flex: 6, child: Container(height: 4, color: const Color(0xFF00B07C))),
                        const SizedBox(width: 2),
                        Expanded(flex: 4, child: Container(height: 4, color: const Color(0xFFF6465D))),
                      ],
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('60%', style: TextStyle(color: Color(0xFF00B07C), fontSize: 10)),
                        Text('40%', style: TextStyle(color: Color(0xFFF6465D), fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputBox(String left, TextEditingController controller, String right, String hint) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          if (left.isNotEmpty) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(left, style: const TextStyle(fontSize: 20, color: Colors.grey)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(right, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderBookRow(_OrderRow row, Color color) {
    double maxAmount = 5.0; // 模拟最大深度用于背景条
    double widthFactor = (row.amount / maxAmount).clamp(0.05, 1.0);
    
    return Container(
      height: 20,
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Stack(
        children: [
          // 背景条
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Container(
                color: color.withOpacity(0.15),
              ),
            ),
          ),
          // 文字
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                row.price.toStringAsFixed(2),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                row.amount.toStringAsFixed(6),
                style: const TextStyle(color: Colors.black87, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderRow {
  double price;
  double amount;
  _OrderRow({required this.price, required this.amount});
}

