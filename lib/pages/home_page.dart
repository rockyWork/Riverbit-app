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
    'https://via.placeholder.com/800x400/4A90E2/FFFFFF?text=Blockchain+News+1',
    'https://via.placeholder.com/800x400/7B68EE/FFFFFF?text=Crypto+Market+2',
    'https://via.placeholder.com/800x400/50C878/FFFFFF?text=DeFi+Trends+3',
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
    if (widget.walletService.isConnected) {
      setState(() {
        _isLoadingBalances = true;
      });
      widget.walletService.getTokenBalances().then((balances) {
        if (mounted) {
          setState(() {
            _tokenBalances = balances.map((b) => {
              'symbol': b['symbol'] as String,
              'balance': b['balance'] as String,
            }).toList();
            _isLoadingBalances = false;
          });
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _isLoadingBalances = false;
          });
        }
      });
    } else {
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
          else
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  '请连接钱包以查看余额',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
