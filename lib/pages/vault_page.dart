import 'package:flutter/material.dart';
import '../components/orderbook_trade_tabs.dart';
import '../components/trading_panel.dart';

class VaultPage extends StatelessWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. 新增的交易面板 (包含下拉、买卖表单、盘口)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TradingPanel(),
            ),

            const SizedBox(height: 16), // 模块间的间距

            // 2. 原有的 OrderBook 与 Trade 切换区域
            const SizedBox(
              height: 400, // 稍微调高一点高度以适应内容
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: OrderBookTradeTabs(symbol: 'BTC/USDT'),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

