import 'package:flutter/material.dart';
import '../components/carousel.dart';
import '../components/vault/vault_content.dart';
import '../services/wallet_service.dart';

class HomePage extends StatefulWidget {
  final WalletService walletService;

  const HomePage({
    super.key,
    required this.walletService,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 区块链热点图片URL - 使用可靠的图片链接
  static const List<String> _carouselImages = [
    'https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=1200&auto=format&fit=crop', // 加密货币/区块链主题
    'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&auto=format&fit=crop', // 数字金融主题
    'https://images.unsplash.com/photo-1620321023374-d1a68fbc720d?w=1200&auto=format&fit=crop', // 科技金融主题
  ];

  List<Map<String, String>> _tokenBalances = [];
  bool _isLoadingBalances = false;

  @override
  void initState() {
    super.initState();
    widget.walletService.addListener(_loadBalances);
    if (widget.walletService.isConnected) {
      _loadBalances();
    }
  }

  @override
  void dispose() {
    widget.walletService.removeListener(_loadBalances);
    super.dispose();
  }

  void _loadBalances() {
    debugPrint('=== _loadBalances called ===');
    debugPrint('isConnected: ${widget.walletService.isConnected}');
    debugPrint('address: ${widget.walletService.address}');
    
    if (widget.walletService.isConnected) {
      debugPrint('Wallet is connected, loading balances...');
      setState(() {
        _isLoadingBalances = true;
      });
      widget.walletService.getTokenBalances().then((balances) {
        debugPrint('Token balances received: $balances');
        if (mounted) {
          setState(() {
            _tokenBalances = balances.map((b) => {
              'symbol': b['symbol'] as String,
              'balance': b['balance'] as String,
            }).toList();
            _isLoadingBalances = false;
          });
          debugPrint('Token balances updated in UI: $_tokenBalances');
        }
      }).catchError((error) {
        debugPrint('Error loading balances: $error');
        debugPrint('Stack trace: ${StackTrace.current}');
        if (mounted) {
          setState(() {
            _isLoadingBalances = false;
          });
        }
      });
    } else {
      debugPrint('Wallet is not connected, clearing balances');
      setState(() {
        _tokenBalances = [];
        _isLoadingBalances = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletService = widget.walletService;
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 轮播图
          CarouselWidget(
            imageUrls: _carouselImages,
            height: 200,
          ),
          const SizedBox(height: 20),
          // 钱包信息（仅在连接时显示）
          if (walletService.isConnected)
            VaultContentWidget(
              networkName: walletService.networkName ?? 'Unknown',
              chainId: walletService.chainId?.toString() ?? '0',
              tokenBalances: _isLoadingBalances
                  ? [{'symbol': 'Loading...', 'balance': '...'}]
                  : _tokenBalances,
              address: walletService.address,
            )
          else if (walletService.isConnecting || walletService.isSigning)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      walletService.isSigning ? '正在请求签名授权...' : '正在连接钱包...',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      walletService.isSigning 
                          ? '请在 MetaMask 中确认签名'
                          : '请在 MetaMask 中确认连接',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (walletService.connectionError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          walletService.connectionError!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '请连接钱包以查看余额',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点击右上角"连接钱包"按钮',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
