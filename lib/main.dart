import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/market_page.dart';
import 'pages/vault_page.dart';
import 'pages/profile_page.dart';
import 'services/wallet_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiverBit DEX',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainNavigationPage(),
    );
  }
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late WalletService _walletService;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _walletService = WalletService();
    _walletService.addListener(_onWalletStateChanged);
    // 初始化页面列表，避免每次重建时创建新实例
    _pages = [
      HomePage(
        walletService: _walletService,
      ),
      const MarketPage(),
      const VaultPage(),
      const ProfilePage(),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _walletService.removeListener(_onWalletStateChanged);
    _walletService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 当应用从后台回到前台时，检查连接状态
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed, checking wallet connection status...');
      _walletService.checkConnectionStatus();
    }
  }

  void _onWalletStateChanged() {
    setState(() {});
  }

  final List<String> _titles = const [
    'Home',
    'Market',
    'Vault',
    'Profile',
  ];

  Future<void> _toggleWalletConnection() async {
    if (_walletService.isConnected) {
      await _walletService.disconnect();
    } else {
      // 弹出钱包选择器
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择钱包连接',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'OKX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                title: const Text('OKX Wallet'),
                subtitle: const Text('推荐使用 OKX 钱包'),
                onTap: () {
                  Navigator.pop(context);
                  _walletService.connect(walletScheme: 'okx');
                },
              ),
              ListTile(
                leading: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/3/36/MetaMask_Alpha_Color.svg/512px-MetaMask_Alpha_Color.svg.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.wallet, size: 40),
                ),
                title: const Text('MetaMask'),
                onTap: () {
                  Navigator.pop(context);
                  _walletService.connect(walletScheme: 'metamask');
                },
              ),
              ListTile(
                leading: const Icon(Icons.apps, size: 40, color: Colors.blue),
                title: const Text('其他钱包'),
                subtitle: const Text('使用系统默认选择器'),
                onTap: () {
                  Navigator.pop(context);
                  _walletService.connect();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: _currentIndex == 0
            ? [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ElevatedButton(
                    onPressed: _toggleWalletConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: _walletService.isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _walletService.isConnected ? '断开连接' : '连接钱包',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ]
            : null,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Market',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Vault',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
