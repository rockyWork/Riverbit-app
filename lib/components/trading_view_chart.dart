import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';

class TradingViewChart extends StatefulWidget {
  final String symbol;
  final double height;

  const TradingViewChart({
    super.key,
    required this.symbol,
    required this.height,
  });

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    print('DEBUG: Initializing TradingViewChart for ${widget.symbol}');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('DEBUG: WebView page started loading: $url');
          },
          onPageFinished: (String url) {
            print('DEBUG: WebView page finished loading: $url');
          },
          onWebResourceError: (WebResourceError error) {
            print('DEBUG: WebView resource error: ${error.description}, type: ${error.errorType}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChan',
        onMessageReceived: (JavaScriptMessage message) {
          print('DEBUG: JS Console: ${message.message}');
        },
      )
      ..loadHtmlString(_getHtml(widget.symbol));
  }

  @override
  void didUpdateWidget(TradingViewChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      print('DEBUG: Updating TradingViewChart to ${widget.symbol}');
      _controller.loadHtmlString(_getHtml(widget.symbol));
    }
  }

  String _getHtml(String symbol) {
    // 转换交易对格式，例如 BTC/USD -> BINANCE:BTCUSDT
    String tvSymbol = symbol.toUpperCase();
    if (tvSymbol.contains('/')) {
      String base = tvSymbol.split('/')[0];
      String quote = tvSymbol.split('/')[1];
      if (quote == 'USD') quote = 'USDT';
      tvSymbol = 'BINANCE:$base$quote';
    } else if (!tvSymbol.contains(':')) {
      tvSymbol = 'BINANCE:${tvSymbol}USDT';
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    body { margin: 0; padding: 0; height: 100vh; width: 100vw; overflow: hidden; background-color: #ffffff; }
    #tradingview_container { height: 100vh; width: 100vw; display: flex; justify-content: center; align-items: center; }
    .loading-text { font-family: sans-serif; color: #999; }
  </style>
</head>
<body>
  <div id="tradingview_container">
    <div class="loading-text">正在加载图表 ($tvSymbol)...</div>
  </div>
  <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
  <script type="text/javascript">
    function log(msg) {
      if (window.FlutterChan) {
        window.FlutterChan.postMessage(msg);
      } else {
        console.log(msg);
      }
    }

    log("Script loading started for symbol: $tvSymbol");

    window.onload = function() {
      log("Window onload triggered");
      if (typeof TradingView === 'undefined') {
        log("Error: TradingView script not loaded");
        document.getElementById('tradingview_container').innerHTML = '<div class="loading-text">无法加载 TradingView 脚本，请检查网络连接。</div>';
        return;
      }

      try {
        log("Initializing TradingView widget...");
        new TradingView.widget({
          "autosize": true,
          "symbol": "$tvSymbol",
          "interval": "D",
          "timezone": "Etc/UTC",
          "theme": "light",
          "style": "1",
          "locale": "zh_CN",
          "toolbar_bg": "#f1f3f6",
          "enable_publishing": false,
          "allow_symbol_change": false,
          "container_id": "tradingview_container",
          "hide_top_toolbar": true,
          "save_image": false,
          "backgroundColor": "rgba(255, 255, 255, 1)",
          "gridColor": "rgba(240, 243, 250, 0.06)",
        });
        log("TradingView widget initialized");
      } catch (e) {
        log("Error initializing TradingView: " + e.toString());
      }
    };
  </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: WebViewWidget(controller: _controller),
    );
  }
}

