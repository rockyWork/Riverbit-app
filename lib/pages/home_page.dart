import 'dart:async';
import 'package:flutter/material.dart';
import '../components/carousel.dart';
import '../components/vault/vault_content.dart';
import '../services/wallet_service.dart';
import 'ai_order_page.dart';

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
  bool _isSigning = false;
  String? _lastAddress; // 💡 记录上次成功抓取余额的地址
  Timer? _connectionTimer; // 💡 用于连接超时的定时器
  bool _showManualConnect = false; // 💡 是否显示手动连接提示

  @override
  void initState() {
    super.initState();
    widget.walletService.addListener(_handleWalletNotification);
    
    // 💡 如果进入页面时正在连接，启动 10 秒超时检测
    if (widget.walletService.isConnecting) {
      _startConnectionTimer();
    }
    
    if (widget.walletService.isConnected) {
      _loadBalances();
    }
  }

  @override
  void dispose() {
    _connectionTimer?.cancel();
    widget.walletService.removeListener(_handleWalletNotification);
    super.dispose();
  }

  // 💡 启动 10 秒连接超时定时器
  void _startConnectionTimer() {
    _connectionTimer?.cancel();
    setState(() {
      _showManualConnect = false;
    });
    
    _connectionTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && widget.walletService.isConnecting) {
        setState(() {
          _showManualConnect = true;
        });
        debugPrint('⏳ 连接钱包超时（10秒），提示手动连接');
      }
    });
  }

  // 💡 只有当地址真正变化，或者从断开变为连接时才执行余额刷新
  void _handleWalletNotification() {
    final isConnecting = widget.walletService.isConnecting;
    final isConnected = widget.walletService.isConnected;
    final currentAddress = widget.walletService.address;

    // 如果开始连接，启动定时器
    if (isConnecting && (_connectionTimer == null || !_connectionTimer!.isActive) && !_showManualConnect) {
      _startConnectionTimer();
    }
    
    // 如果连接成功或彻底断开，取消定时器并重置手动提示
    if (isConnected || (!isConnecting && !isConnected)) {
      _connectionTimer?.cancel();
      if (_showManualConnect) {
        setState(() {
          _showManualConnect = false;
        });
      }
    }

    if (currentAddress != _lastAddress && isConnected) {
      debugPrint('Detected address change: $_lastAddress -> $currentAddress');
      _loadBalances();
    } else if (mounted) {
      // 状态变更时刷新 UI
      setState(() {});
    }
  }

  void _loadBalances() {
    // 如果正在加载，则直接跳过，防止并发导致的死循环
    if (_isLoadingBalances) return;

    final currentAddress = widget.walletService.address;
    _lastAddress = currentAddress; 
    
    debugPrint('=== _loadBalances called ===');
    
    if (widget.walletService.isConnected && currentAddress != null) {
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
      if (mounted) {
        setState(() {
          _tokenBalances = [];
          _isLoadingBalances = false;
        });
      }
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
          
          // AI 下单按钮区域
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade400],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AiOrderPage()),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'AI 下单',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),
          // 钱包状态显示区域
          _buildWalletStatusSection(walletService),
        ],
      ),
    );
  }

  Widget _buildWalletStatusSection(WalletService walletService) {
    // 1. 已连接状态：显示账户信息和测试按钮
    if (walletService.isConnected) {
      return Column(
        children: [
          VaultContentWidget(
            networkName: walletService.networkName ?? 'Unknown',
            chainId: walletService.chainId?.toString() ?? '0',
            tokenBalances: _isLoadingBalances
                ? [{'symbol': 'Loading...', 'balance': '...'}]
                : _tokenBalances,
            address: walletService.address,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSigning ? null : () async {
                      setState(() => _isSigning = true);
                      try {
                        final msg = 'RiverBit Login - ${DateTime.now().millisecondsSinceEpoch}';
                        final sig = await walletService.personalSign(msg);
                        
                        // 💡 增加微小延迟，确保从钱包切回 App 后的 UI 状态已稳定
                        await Future.delayed(const Duration(milliseconds: 300));
                        
                        if (sig != null) {
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green),
                                    SizedBox(width: 8),
                                    Text('签名成功'),
                                  ],
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('消息内容:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text(msg),
                                    const SizedBox(height: 12),
                                    const Text('签名哈希:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    SelectableText(
                                      sig,
                                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('确定'),
                                  ),
                                ],
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('签名未完成或已被拒绝。'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isSigning = false);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: _isSigning 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        )
                      : const Icon(Icons.security),
                    label: Text(
                      _isSigning ? '正在唤起钱包...' : '测试钱包签名',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          // 示例：向自己发送 0 ETH 测试交易
                          final tx = await walletService.sendTransaction(
                            to: walletService.address!,
                            valueInWei: '0',
                          );
                          if (tx != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('交易已发送: ${tx.substring(0, 20)}...')),
                            );
                          }
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('测试交易'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => walletService.disconnect(),
                        icon: const Icon(Icons.logout),
                        label: const Text('断开连接'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 2. 正在连接状态（未超时）
    if (walletService.isConnecting && !_showManualConnect) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                '正在连接钱包...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              // 展示最后一条日志
              if (walletService.debugLogs.isNotEmpty)
                Text(
                  walletService.debugLogs.last,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      );
    }

    // 3. 未连接状态 或 连接超时：显示占位提示
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 16.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              _showManualConnect ? '连接似乎响应较慢' : '请连接钱包以查看余额',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Text(
              _showManualConnect ? '建议点击右上角按钮重新尝试连接' : '点击右上角"连接钱包"按钮',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            if (_showManualConnect) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() => _showManualConnect = false);
                  walletService.connect(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text('立即重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
