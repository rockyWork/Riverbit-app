import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class OrderBookTradeTabs extends StatefulWidget {
  final String symbol;

  const OrderBookTradeTabs({
    super.key,
    required this.symbol,
  });

  @override
  State<OrderBookTradeTabs> createState() => _OrderBookTradeTabsState();
}

class _OrderBookTradeTabsState extends State<OrderBookTradeTabs> {
  final _rng = Random();
  Timer? _timer;

  double _mid = 65000.0;
  List<_OrderBookRow> _asks = const [];
  List<_OrderBookRow> _bids = const [];
  List<_TradeRow> _trades = const [];

  @override
  void initState() {
    super.initState();
    _resetForSymbol();
    _tick(); // 先生成一次
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant OrderBookTradeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _resetForSymbol();
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetForSymbol() {
    // 用不同的 symbol 给一个不同的起始价格，让切换更“像真的”
    final seed = widget.symbol.hashCode.abs() % 10000;
    _mid = 1000 + seed.toDouble() * 10;
    _asks = const [];
    _bids = const [];
    _trades = const [];
  }

  void _tick() {
    // 随机游走 mid price
    final drift = (_rng.nextDouble() - 0.5) * (_mid * 0.0012);
    _mid = max(0.01, _mid + drift);

    // 生成盘口（10档）
    final spread = max(0.01, _mid * 0.0004);
    final step = max(0.01, _mid * 0.0003);
    final asks = <_OrderBookRow>[];
    final bids = <_OrderBookRow>[];

    double askTotal = 0;
    double bidTotal = 0;

    for (int i = 0; i < 10; i++) {
      final askPrice = _mid + spread + step * i;
      final askAmt = 0.01 + _rng.nextDouble() * 2.5;
      askTotal += askAmt;
      asks.add(_OrderBookRow(price: askPrice, amount: askAmt, total: askTotal));

      final bidPrice = max(0.01, _mid - spread - step * i);
      final bidAmt = 0.01 + _rng.nextDouble() * 2.5;
      bidTotal += bidAmt;
      bids.add(_OrderBookRow(price: bidPrice, amount: bidAmt, total: bidTotal));
    }

    // 生成成交（每 tick 追加 1-2 条）
    final trades = List<_TradeRow>.from(_trades);
    final newCount = 1 + _rng.nextInt(2);
    for (int i = 0; i < newCount; i++) {
      final isBuy = _rng.nextBool();
      final price = _mid + (isBuy ? 1 : -1) * _rng.nextDouble() * spread;
      final qty = 0.001 + _rng.nextDouble() * 0.8;
      trades.insert(
        0,
        _TradeRow(
          isBuy: isBuy,
          price: max(0.01, price),
          quantity: qty,
          time: DateTime.now(),
        ),
      );
    }
    if (trades.length > 40) {
      trades.removeRange(40, trades.length);
    }

    if (!mounted) return;
    setState(() {
      _asks = asks;
      _bids = bids;
      _trades = trades;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF0B1220);
    final panel = const Color(0xFF111A2E);

    return Container(
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: const Color(0xFF4C7DFF),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Order Book'),
                  Tab(text: 'Trade'),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: panel,
                child: TabBarView(
                  children: [
                    _OrderBookView(asks: _asks, bids: _bids, symbol: widget.symbol),
                    _TradesView(trades: _trades),
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

class _OrderBookView extends StatelessWidget {
  final List<_OrderBookRow> asks;
  final List<_OrderBookRow> bids;
  final String symbol;

  const _OrderBookView({
    required this.asks,
    required this.bids,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final headerStyle = text.bodySmall?.copyWith(color: Colors.white70, fontSize: 11);
    final cellStyle = text.bodyMedium?.copyWith(color: Colors.white, fontSize: 12);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Price', style: headerStyle)),
              Expanded(child: Text('Amount', style: headerStyle)),
              Expanded(child: Text('Total', style: headerStyle)),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0x221FFFFFF)),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OrderList(
                  rows: asks.reversed.toList(growable: false),
                  priceColor: const Color(0xFFFF5C5C),
                  cellStyle: cellStyle,
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: Color(0x221FFFFFF)),
              Expanded(
                child: _OrderList(
                  rows: bids,
                  priceColor: const Color(0xFF3DDB87),
                  cellStyle: cellStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<_OrderBookRow> rows;
  final Color priceColor;
  final TextStyle? cellStyle;

  const _OrderList({
    required this.rows,
    required this.priceColor,
    required this.cellStyle,
  });

  @override
  Widget build(BuildContext context) {
    final maxTotal = rows.isEmpty ? 1.0 : rows.last.total;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final r = rows[index];
        final pct = (maxTotal <= 0) ? 0.0 : (r.total / maxTotal).clamp(0.0, 1.0);

        return SizedBox(
          height: 22,
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct,
                  child: Container(
                    color: priceColor.withOpacity(0.12),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fmtPrice(r.price),
                      style: (cellStyle ?? const TextStyle()).copyWith(color: priceColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtQty(r.amount),
                      style: cellStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtQty(r.total),
                      style: cellStyle?.copyWith(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TradesView extends StatelessWidget {
  final List<_TradeRow> trades;

  const _TradesView({required this.trades});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final headerStyle = text.bodySmall?.copyWith(color: Colors.white70, fontSize: 11);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Price', style: headerStyle)),
              Expanded(child: Text('Qty', style: headerStyle)),
              Expanded(child: Text('Time', style: headerStyle)),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0x221FFFFFF)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: trades.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final t = trades[index];
              final color = t.isBuy ? const Color(0xFF3DDB87) : const Color(0xFFFF5C5C);
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      _fmtPrice(t.price),
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtQty(t.quantity),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtTime(t.time),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

String _fmtPrice(double v) {
  if (v >= 1000) return v.toStringAsFixed(2);
  if (v >= 1) return v.toStringAsFixed(4);
  return v.toStringAsFixed(6);
}

String _fmtQty(double v) {
  if (v >= 1000) return v.toStringAsFixed(0);
  if (v >= 1) return v.toStringAsFixed(3);
  return v.toStringAsFixed(5);
}

String _fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class _OrderBookRow {
  final double price;
  final double amount;
  final double total;

  const _OrderBookRow({
    required this.price,
    required this.amount,
    required this.total,
  });
}

class _TradeRow {
  final bool isBuy;
  final double price;
  final double quantity;
  final DateTime time;

  const _TradeRow({
    required this.isBuy,
    required this.price,
    required this.quantity,
    required this.time,
  });
}



