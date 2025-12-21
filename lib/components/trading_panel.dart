import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class TradingPanel extends StatefulWidget {
  const TradingPanel({super.key});

  @override
  State<TradingPanel> createState() => _TradingPanelState();
}

class _TradingPanelState extends State<TradingPanel> {
  String _selectedPair = 'BTC/USDT';
  final List<String> _pairs = ['BTC/USDT', 'ETH/USDT'];
  bool _isBuy = true;
  final TextEditingController _priceController = TextEditingController(text: '86402.15');
  final TextEditingController _amountController = TextEditingController();
  double _sliderValue = 0.0;
  
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
    final String baseAsset = _selectedPair.split('/').first;

    // 💡 计算买卖盘比例
    double totalAskVol = _asks.fold(0, (sum, item) => sum + item.amount);
    double totalBidVol = _bids.fold(0, (sum, item) => sum + item.amount);
    double totalVol = totalAskVol + totalBidVol;
    int bidPercent = totalVol > 0 ? ((totalBidVol / totalVol) * 100).round() : 50;
    int askPercent = 100 - bidPercent;
    
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
          // 1. 顶部交易对选择 - 改为真正的下拉框
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPair,
                    icon: const Icon(Icons.arrow_drop_down),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedPair = newValue;
                        });
                      }
                    },
                    items: _pairs.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const Spacer(),
              // 💡 重新加回图标
              const Icon(Icons.candlestick_chart_outlined, size: 20, color: Colors.grey),
              const SizedBox(width: 12),
              const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                height: 38,
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
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isBuy = false),
                              child: Container(
                                height: 38,
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
                                    fontSize: 16,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Limit', style: TextStyle(fontSize: 14, color: Colors.black87)),
                            Icon(Icons.arrow_drop_down, size: 20, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 价格输入 - 带有动态边框
                      _buildPriceInput(),
                      const SizedBox(height: 12),
                      // 数量输入
                      _buildInputBox('', _amountController, baseAsset, 'Amount'),
                      const SizedBox(height: 12),
                      // 动态滑杆 0-100%
                      _buildSlider(),
                      const SizedBox(height: 12),
                      // Total
                      _buildInputBox('', TextEditingController(), 'USDT', 'Total'),
                      const Spacer(),
                      const SizedBox(height: 12),
                      // 按钮 - 文本跟随交易对变化
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${_isBuy ? 'Buy' : 'Sell'} $baseAsset Order Placed Successfully!'),
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
                          child: Text(
                            '${_isBuy ? 'Buy' : 'Sell'} $baseAsset',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Price\n(USDT)', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          Text('Amount\n($baseAsset)', style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.right),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Asks (Red)
                      ..._asks.map((row) => _buildOrderBookRow(row, const Color(0xFFF6465D))),
                      // Mid Price
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Column(
                          children: [
                            const Text(
                              '86,402.15',
                              style: TextStyle(color: Color(0xFFF6465D), fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '≈ HK\$671,939.03',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      // Bids (Green)
                      ..._bids.map((row) => _buildOrderBookRow(row, const Color(0xFF00B07C))),
                      
                      const Spacer(),
                      const SizedBox(height: 8),
                      // 底部比例条
                      Row(
                        children: [
                          Expanded(flex: bidPercent, child: Container(height: 4, color: const Color(0xFF00B07C))),
                          const SizedBox(width: 2),
                          Expanded(flex: askPercent, child: Container(height: 4, color: const Color(0xFFF6465D))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$bidPercent%', style: const TextStyle(color: Color(0xFF00B07C), fontSize: 11)),
                          Text('$askPercent%', style: const TextStyle(color: Color(0xFFF6465D), fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceInput() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D), width: 1.5),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              double val = double.tryParse(_priceController.text) ?? 0;
              // 💡 点击减少整数位 (减 1)
              _priceController.text = (val - 1).toStringAsFixed(2);
            },
            icon: const Icon(Icons.remove, size: 18, color: Colors.grey),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: TextField(
              controller: _priceController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          IconButton(
            onPressed: () {
              double val = double.tryParse(_priceController.text) ?? 0;
              // 💡 点击增加整数位 (加 1)
              _priceController.text = (val + 1).toStringAsFixed(2);
            },
            icon: const Icon(Icons.add, size: 18, color: Colors.grey),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D),
            inactiveTrackColor: Colors.grey.shade200,
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 2),
            overlayColor: (_isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D)).withOpacity(0.1),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
            activeTickMarkColor: _isBuy ? const Color(0xFF00B07C) : const Color(0xFFF6465D),
            inactiveTickMarkColor: Colors.grey.shade300,
          ),
          child: Slider(
            value: _sliderValue,
            min: 0,
            max: 1,
            divisions: 4,
            onChanged: (val) {
              setState(() {
                _sliderValue = val;
                _amountController.text = (val * 1.5).toStringAsFixed(4);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInputBox(String left, TextEditingController controller, String right, String hint) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Text(hint, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(right, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500)),
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
