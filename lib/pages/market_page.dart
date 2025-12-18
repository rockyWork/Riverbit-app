import 'package:flutter/material.dart';
import '../components/trading_view_chart.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  String _selectedSymbol = 'BTC/USD';

  final List<String> _popularPairs = [
    'BTC/USD',
    'ETH/USD',
    'BNB/USD',
    'SOL/USD',
    'ADA/USD',
    'XRP/USD',
    'DOGE/USD',
    'DOT/USD',
  ];

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final chartHeight = screenHeight / 3;

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. K线图区域
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TradingViewChart(
                  symbol: _selectedSymbol,
                  height: chartHeight,
                ),
              ),
            ),
          ),

          // 2. 热门交易对标题
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '热门交易对',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // 3. 交易对列表
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _popularPairs.length,
              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
              itemBuilder: (context, index) {
                final pair = _popularPairs[index];
                final isSelected = pair == _selectedSymbol;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSymbol = pair;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.shade700 : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          pair,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.blue.shade700 : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Icon(
                            Icons.bar_chart,
                            color: Colors.blue.shade700,
                            size: 20,
                          )
                        else
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

