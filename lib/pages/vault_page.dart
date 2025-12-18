import 'package:flutter/material.dart';
import '../components/orderbook_trade_tabs.dart';

class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. OrderBook 与 Trade 切换区域
          const SizedBox(
            height: 300, // 给定一个固定高度
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: OrderBookTradeTabs(symbol: 'BTC/USDT'),
            ),
          ),
          
          // 2. 原有的内容区域（如果有的话）
          const Expanded(
            child: Center(
              child: Text('Vault Page Content'),
            ),
          ),
        ],
      ),
    );
  }
}

