import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

class WalletService extends ChangeNotifier {
  // --- 核心修复：单例模式，应对 Android Activity 重启 ---
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal() {
    _initClient();
  }

  static const String _projectId = '1d9024e332c1f6c37d6d4ca165b07104';
  static const String _relayUrl = 'wss://relay.walletconnect.com';
  
  Web3App? _wc;
  SessionData? _session;
  Web3Client? _web3Client;
  Timer? _pollingTimer;

  bool _isInitializing = false;
  bool _isConnecting = false;
  String? _address;
  int? _chainId;
  String? _networkName;
  String? _connectionError;
  
  final List<String> debugLogs = [];

  bool get isConnected => _session != null && _address != null;
  bool get isConnecting => _isConnecting;
  String? get address => _address;
  int? get chainId => _chainId;
  String? get networkName => _networkName;
  String? get connectionError => _connectionError;

  void _addLog(String msg) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    final log = '[$time] $msg';
    debugLogs.add(log);
    if (debugLogs.length > 50) debugLogs.removeAt(0);
    debugPrint('[WALLET_LOG] $log');
    notifyListeners();
  }

  Future<void> _initClient() async {
    if (_wc != null || _isInitializing) return;
    _isInitializing = true;
    try {
      _addLog('🚀 初始化 Web3App...');
      _wc = await Web3App.createInstance(
        projectId: _projectId,
        relayUrl: _relayUrl,
        metadata: const PairingMetadata(
          name: 'RiverBit',
          description: 'DEX',
          url: 'https://riverbit.com',
          icons: [],
          redirect: Redirect(native: 'riverbit://'),
        ),
      );

      _wc!.onSessionConnect.subscribe((SessionConnect? args) {
        _addLog('🎯 收到授权信号！');
        if (args != null) _handleSession(args.session);
      });

      _wc!.core.relayClient.onRelayClientConnect.subscribe((_) {
        _addLog('🌐 信令已连接');
        _refreshActiveSession();
      });

      await _refreshActiveSession();
    } catch (e) {
      _addLog('❌ 初始化失败: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _refreshActiveSession() async {
    if (_wc == null) return;
    try {
      final sessions = _wc!.sessions.getAll();
      if (sessions.isNotEmpty) {
        _addLog('✅ 恢复已存会话');
        _handleSession(sessions.first);
      }
    } catch (e) {
      _addLog('⚠️ 刷新会话异常: $e');
    }
  }

  Future<bool> connect() async {
    await _initClient();
    if (_wc == null) return false;

    try {
      _isConnecting = true;
      _connectionError = null;
      _addLog('🚀 准备新连接...');
      notifyListeners();

      // 【核心优化】不要在连接瞬间暴力清理所有 Pairing，这会杀掉当前的请求
      if (_wc!.pairings.getAll().length > 5) {
        _addLog('🧹 清理积压配对...');
        for (var p in _wc!.pairings.getAll().take(3)) {
          await _wc!.core.pairing.disconnect(topic: p.topic);
        }
      }

      if (!_wc!.core.relayClient.isConnected) {
        await _wc!.core.relayClient.connect();
        await Future.delayed(const Duration(seconds: 1));
      }

      // 【核心修复】使用可选命名空间，增加兼容性，防止小狐狸拒绝
      final connectResp = await _wc!.connect(
        optionalNamespaces: {
          'eip155': RequiredNamespace(
            chains: ['eip155:1', 'eip155:56', 'eip155:137'], 
            methods: ['eth_sendTransaction', 'personal_sign', 'eth_signTypedData_v4'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      final uri = connectResp.uri;
      if (uri == null) return false;

      _addLog('📱 唤起应用选择弹窗...');
      // 【UI 层面恢复】直接使用 uri (wc: 协议)，这会弹出系统选择菜单
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!success) {
        _addLog('⚠️ 系统跳转失败，尝试直接唤起小狐狸...');
        final encodedUri = Uri.encodeComponent(uri.toString());
        await launchUrl(Uri.parse('metamask://wc?uri=$encodedUri'), mode: LaunchMode.externalApplication);
      }

      _startPolling();

      try {
        final session = await connectResp.session.future.timeout(const Duration(minutes: 3));
        _handleSession(session);
      } catch (e) {
        if (_session != null) {
          _addLog('ℹ️ 授权已同步完成');
        } else {
          _addLog('⏰ 等待授权超时');
          _isConnecting = false;
          _stopPolling();
          notifyListeners();
          return false;
        }
      }
      
      return true;
    } catch (e) {
      _addLog('❌ 连接异常: $e');
      _isConnecting = false;
      _stopPolling();
      notifyListeners();
      return false;
    }
  }

  void _handleSession(SessionData session) {
    if (session.namespaces.isEmpty) return;
    _session = session;
    _addLog('📦 解析账户...');
    
    String? foundAddress;
    int? foundChainId;

    // 🏆 深度扫描解析所有可能的命名空间 Key
    for (var key in session.namespaces.keys) {
      final ns = session.namespaces[key];
      if (ns != null && ns.accounts.isNotEmpty) {
        final account = ns.accounts.first;
        final parts = account.split(':');
        if (parts.length >= 3) {
          foundChainId = int.tryParse(parts[1]);
          foundAddress = parts[2];
          _addLog('✅ 发现账户: ${foundAddress!.substring(0, 10)}...');
          break;
        }
      }
    }

    if (foundAddress != null) {
      _address = foundAddress;
      _chainId = foundChainId;
      _isConnecting = false;
      _stopPolling();
      _updateNetworkName();
      _initializeWeb3Client();
      notifyListeners();
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (isConnected) {
        timer.cancel();
        return;
      }
      _refreshActiveSession();
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _updateNetworkName() {
    switch (_chainId) {
      case 1: _networkName = 'Ethereum'; break;
      case 56: _networkName = 'BSC'; break;
      case 137: _networkName = 'Polygon'; break;
      default: _networkName = 'Chain $_chainId';
    }
  }

  void _initializeWeb3Client() {
    if (_chainId == null || _address == null) return;
    String rpc = 'https://eth.llamarpc.com';
    if (_chainId == 56) rpc = 'https://bsc-dataseed.binance.org';
    if (_chainId == 137) rpc = 'https://polygon-rpc.com';
    _web3Client = Web3Client(rpc, http.Client());
  }

  Future<void> checkConnectionStatus() async {
    _addLog('🔄 切回前台，深度同步...');
    await _initClient(); // 单例模式下这里只是获取引用
    if (_wc != null) {
      if (!_wc!.core.relayClient.isConnected) {
        await _wc!.core.relayClient.connect();
        await Future.delayed(const Duration(seconds: 2));
      }
      await _refreshActiveSession();
    }
  }

  Future<List<Map<String, String>>> getTokenBalances() async {
    if (_address == null || _web3Client == null) return [];
    try {
      final bal = await _web3Client!.getBalance(EthereumAddress.fromHex(_address!));
      final val = bal.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      String symbol = (_chainId == 56) ? 'BNB' : (_chainId == 137 ? 'MATIC' : 'ETH');
      return [{'symbol': symbol, 'balance': val}];
    } catch (e) {
      return [];
    }
  }

  Future<void> disconnect() async {
    _addLog('🔌 断开连接');
    if (_session != null && _wc != null) {
      try {
        await _wc!.disconnectSession(
          topic: _session!.topic,
          reason: Errors.getSdkError(Errors.USER_DISCONNECTED),
        );
      } catch (_) {}
    }
    _session = null;
    _address = null;
    _chainId = null;
    _isConnecting = false;
    _stopPolling();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _web3Client?.dispose();
    super.dispose();
  }
}
