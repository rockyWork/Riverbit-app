import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

/// WalletConnect v2 服务
class WalletService extends ChangeNotifier {
  static const String _projectId = '1d9024e332c1f6c37d6d4ca165b07104';
  static const String _relayUrl = 'wss://relay.walletconnect.com';
  static const String _appName = 'RiverBit DEX';
  static const String _appUrl = 'https://riverbit.com';
  
  // 支持的链
  static const List<String> _chains = [
    'eip155:1',   // Ethereum
    'eip155:56',  // BSC
    'eip155:137', // Polygon
  ];

  Web3App? _wc;
  SessionData? _session;
  Web3Client? _web3Client;

  bool _isInitializing = false;
  bool _isConnecting = false;
  bool _isSigning = false;
  String? _address;
  int? _chainId;
  String? _networkName;
  String? _connectionError;

  bool get isConnected => _session != null;
  bool get isConnecting => _isConnecting;
  bool get isSigning => _isSigning;
  String? get address => _address;
  int? get chainId => _chainId;
  String? get networkName => _networkName;
  String? get connectionError => _connectionError;

  WalletService() {
    _initClient();
  }

  /// 初始化 WalletConnect v2 客户端并注册监听器
  Future<void> _initClient() async {
    if (_wc != null || _isInitializing) return;
    _isInitializing = true;
    try {
      debugPrint('DEBUG: Initializing WalletConnect Web3App...');
      _wc = await Web3App.createInstance(
        projectId: _projectId,
        relayUrl: _relayUrl,
        metadata: const PairingMetadata(
          name: _appName,
          description: 'RiverBit Decentralized Exchange',
          url: _appUrl,
          icons: ['https://riverbit.com/favicon.ico'],
          redirect: Redirect(
            native: 'riverbit://', // 尝试通过自定义协议返回
            universal: 'https://riverbit.com',
          ),
        ),
      );

      // 注册全局监听器
      _wc!.onSessionConnect.subscribe((SessionConnect? args) {
        debugPrint('DEBUG: Session connected event: ${args?.session.topic}');
        if (args != null) {
          _handleSession(args.session);
        }
      });

      _wc!.onSessionUpdate.subscribe((SessionUpdate? args) {
        debugPrint('DEBUG: Session updated event: ${args?.topic}');
        if (args != null && _session?.topic == args.topic) {
          _wc!.sessions.getAll().forEach((s) {
            if (s.topic == args.topic) _handleSession(s);
          });
        }
      });

      _wc!.onSessionDelete.subscribe((SessionDelete? args) {
        debugPrint('DEBUG: Session deleted event: ${args?.topic}');
        if (args != null && _session?.topic == args.topic) {
          disconnect();
        }
      });

      // 尝试恢复已有会话
      final sessions = _wc!.sessions.getAll();
      if (sessions.isNotEmpty) {
        debugPrint('DEBUG: Restoring existing session: ${sessions.first.topic}');
        _handleSession(sessions.first);
      }
    } catch (e) {
      debugPrint('DEBUG: Init WalletConnect error: $e');
      _connectionError = '初始化失败: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// 连接钱包
  Future<bool> connect() async {
    await _initClient();
    if (_wc == null) {
      _connectionError = 'WalletConnect 初始化失败';
      notifyListeners();
      return false;
    }

    if (isConnected) return true;

    try {
      _isConnecting = true;
      _connectionError = null;
      notifyListeners();

      debugPrint('DEBUG: Requesting connection...');
      
      // 使用 optionalNamespaces 而非 requiredNamespaces，以提高钱包兼容性
      final connectResp = await _wc!.connect(
        optionalNamespaces: {
          'eip155': RequiredNamespace(
            chains: _chains,
            methods: const [
              'personal_sign',
              'eth_sendTransaction',
              'eth_signTypedData_v4',
              'eth_accounts',
            ],
            events: const ['accountsChanged', 'chainChanged'],
          ),
        },
      );

      final uri = connectResp.uri;
      if (uri != null) {
        debugPrint('DEBUG: Launching wallet with URI: $uri');
        await _launchWallet(uri.toString());
      }

      // 等待会话批准，设置 2 分钟超时
      final session = await connectResp.session.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          debugPrint('DEBUG: Connection timeout');
          throw TimeoutException('Connection timed out');
        },
      );
      
      debugPrint('DEBUG: Session established: ${session.topic}');
      _handleSession(session);
      return true;
    } catch (e) {
      debugPrint('DEBUG: Connect error: $e');
      _isConnecting = false;
      _connectionError = e is TimeoutException ? '连接超时，请重试' : '连接失败: $e';
      notifyListeners();
      return false;
    }
  }

  void _handleSession(SessionData session) {
    debugPrint('DEBUG: Handling session data...');
    _session = session;
    
    // 遍历所有命名空间寻找账户
    String? account;
    for (final namespace in session.namespaces.values) {
      if (namespace.accounts.isNotEmpty) {
        account = namespace.accounts.first;
        break;
      }
    }

    if (account == null) {
      debugPrint('DEBUG: No accounts found in session');
      _connectionError = '未获取到账户信息';
      _isConnecting = false;
      notifyListeners();
      return;
    }

    // 解析格式 eip155:chainId:address
    final parts = account.split(':');
    if (parts.length >= 3) {
      _chainId = int.tryParse(parts[1]);
      _address = parts[2];
      debugPrint('DEBUG: Connected Address: $_address, ChainID: $_chainId');
    }

    _updateNetworkName();
    _initializeWeb3Client();

    _isConnecting = false;
    _connectionError = null;
    notifyListeners();
    
    // 连接成功后，异步拉取余额
    _fetchAccountInfo();
  }

  Future<void> _launchWallet(String uri) async {
    // 针对 MetaMask 的深度链接优化
    final metamaskUrl = Uri.parse('metamask://wc?uri=${Uri.encodeComponent(uri)}');
    final universalUrl = Uri.parse('https://metamask.app.link/wc?uri=${Uri.encodeComponent(uri)}');
    
    try {
      bool launched = false;
      if (await canLaunchUrl(metamaskUrl)) {
        debugPrint('DEBUG: Launching MetaMask via native scheme');
        launched = await launchUrl(
          metamaskUrl, 
          mode: LaunchMode.externalNonBrowserApplication
        );
      }
      
      if (!launched) {
        debugPrint('DEBUG: Launching via Universal Link');
        await launchUrl(
          universalUrl, 
          mode: LaunchMode.externalApplication
        );
      }
    } catch (e) {
      debugPrint('DEBUG: Launch wallet error: $e');
      // 最后退路：尝试原生的 wc: 协议
      final wcUrl = Uri.parse(uri);
      if (await canLaunchUrl(wcUrl)) {
        await launchUrl(wcUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> checkConnectionStatus() async {
    debugPrint('DEBUG: Checking connection status...');
    await _initClient();
  }

  void _updateNetworkName() {
    switch (_chainId) {
      case 1: _networkName = 'Ethereum Mainnet'; break;
      case 5: _networkName = 'Goerli Testnet'; break;
      case 56: _networkName = 'BSC Mainnet'; break;
      case 137: _networkName = 'Polygon Mainnet'; break;
      case 11155111: _networkName = 'Sepolia Testnet'; break;
      default: _networkName = 'Chain $_chainId';
    }
  }

  void _initializeWeb3Client() {
    if (_chainId == null) return;
    String rpc;
    switch (_chainId) {
      case 1: rpc = 'https://eth.llamarpc.com'; break;
      case 56: rpc = 'https://bsc-dataseed.binance.org'; break;
      case 137: rpc = 'https://polygon-rpc.com'; break;
      case 11155111: rpc = 'https://rpc.sepolia.org'; break;
      default: rpc = 'https://eth.llamarpc.com';
    }
    _web3Client = Web3Client(rpc, http.Client());
  }

  Future<void> _fetchAccountInfo() async {
    if (_address == null || _web3Client == null) return;
    debugPrint('DEBUG: Fetching account balance for $_address');
    notifyListeners();
  }

  Future<List<Map<String, String>>> getTokenBalances() async {
    if (_address == null || _web3Client == null) return [];
    try {
      final bal = await _web3Client!.getBalance(EthereumAddress.fromHex(_address!));
      final etherValue = bal.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      debugPrint('DEBUG: Balance fetched: $etherValue');
      
      String symbol = 'ETH';
      if (_chainId == 56) symbol = 'BNB';
      if (_chainId == 137) symbol = 'MATIC';

      return [
        {'symbol': symbol, 'balance': etherValue},
      ];
    } catch (e) {
      debugPrint('DEBUG: Fetch balance error: $e');
      return [];
    }
  }

  Future<void> disconnect() async {
    debugPrint('DEBUG: Disconnecting session...');
    if (_session != null && _wc != null) {
      try {
        await _wc!.disconnectSession(
          topic: _session!.topic,
          reason: Errors.getSdkError(Errors.USER_DISCONNECTED),
        );
      } catch (e) {
        debugPrint('DEBUG: Disconnect session error: $e');
      }
    }
    _session = null;
    _address = null;
    _chainId = null;
    _networkName = null;
    _connectionError = null;
    _isConnecting = false;
    _isSigning = false;
    _web3Client?.dispose();
    _web3Client = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _web3Client?.dispose();
    super.dispose();
  }
}
