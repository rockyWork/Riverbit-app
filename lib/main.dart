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
    
    // 延迟初始化以确保 BuildContext 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _walletService.init(context);
    });

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


  void _onWalletStateChanged() {
    if (mounted) {
      setState(() {});
    }
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
      await _walletService.connect(context);
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
