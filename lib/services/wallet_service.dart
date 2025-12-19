import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

class WalletService extends ChangeNotifier {
  static const String _projectId = '1d9024e332c1f6c37d6d4ca165b07104';
  static const String _relayUrl = 'wss://relay.walletconnect.com';
  
  Web3App? _wc;
  SessionData? _session;
  Web3Client? _web3Client;
  Timer? _pollingTimer;
  String? _pendingPairingTopic; // 跟踪待处理的配对

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

  WalletService() {
    _initClient();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    final log = '[$time] $msg';
    debugLogs.add(log);
    if (debugLogs.length > 30) debugLogs.removeAt(0);
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
          name: 'RiverBit DEX',
          description: 'RiverBit Decentralized Exchange',
          url: 'https://riverbit.com',
          icons: ['https://riverbit.com/favicon.ico'],
          redirect: Redirect(native: 'riverbit://'),
        ),
      );

      // 设置事件监听器
      _setupEventListeners();

      // 尝试恢复已有会话
      await _restoreExistingSessions();
      
      _addLog('✅ Web3App 初始化完成');
    } catch (e, stackTrace) {
      _addLog('❌ 初始化失败: $e');
      _addLog('堆栈: ${stackTrace.toString().split('\n').first}');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _setupEventListeners() {
    if (_wc == null) return;

    // 会话连接事件
    _wc!.onSessionConnect.subscribe((SessionConnect? args) {
      _addLog('🎯 收到 SessionConnect 事件');
      if (args != null) {
        _stopPolling();
        _handleSession(args.session);
      }
    });

    // 会话更新事件
    _wc!.onSessionUpdate.subscribe((SessionUpdate? args) {
      _addLog('🔄 收到 SessionUpdate 事件');
      if (args != null && _session?.topic == args.topic) {
        _refreshSessionData();
      }
    });

    // 会话删除事件
    _wc!.onSessionDelete.subscribe((SessionDelete? args) {
      _addLog('🗑️ 收到 SessionDelete 事件');
      _disconnectInternal();
    });

    // Relay 连接状态
    _wc!.core.relayClient.onRelayClientConnect.subscribe((_) {
      _addLog('🌐 Relay 已连接');
    });

    _wc!.core.relayClient.onRelayClientError.subscribe((args) {
      _addLog('🌐 Relay 错误: ${args?.error}');
    });
  }

  Future<void> _restoreExistingSessions() async {
    if (_wc == null) return;
    
    final sessions = _wc!.sessions.getAll();
    final pairings = _wc!.pairings.getAll();
    
    _addLog('📊 恢复检查: ${sessions.length} 个会话, ${pairings.length} 个配对');
    
    for (var session in sessions) {
      final expiry = session.expiry;
      // expiry 是秒级时间戳
      if (expiry != null && DateTime.fromMillisecondsSinceEpoch(expiry * 1000).isBefore(DateTime.now())) {
        continue;
      }
      
      final eip155 = session.namespaces['eip155'];
      if (eip155 != null && eip155.accounts.isNotEmpty) {
        _addLog('✅ 恢复有效会话');
        _handleSession(session);
        return;
      }
    }
  }

  Future<bool> connect() async {
    await _initClient();
    if (_wc == null) return false;

    try {
      _isConnecting = true;
      _connectionError = null;
      debugLogs.clear();
      _addLog('🚀 开始连接流程...');
      notifyListeners();

      if (!_wc!.core.relayClient.isConnected) {
        _addLog('⏳ 等待 Relay 连接...');
        await Future.delayed(const Duration(seconds: 1));
      }

      await _cleanupOldConnections();

      _addLog('📡 请求连接...');
      
      final connectResp = await _wc!.connect(
        requiredNamespaces: {
          'eip155': RequiredNamespace(
            chains: ['eip155:1', 'eip155:56', 'eip155:137'],
            methods: ['eth_sendTransaction', 'personal_sign', 'eth_signTypedData_v4'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      final uri = connectResp.uri;
      if (uri == null) {
        _addLog('❌ 无法生成连接 URI');
        _isConnecting = false;
        return false;
      }

      _pendingPairingTopic = connectResp.pairingTopic;
      _addLog('🔗 URI 生成成功');

      final launched = await _launchWalletApp(uri.toString());
      if (!launched) {
        _addLog('❌ 无法唤起钱包');
        _isConnecting = false;
        _connectionError = '无法唤起 MetaMask';
        notifyListeners();
        return false;
      }

      _addLog('⏳ 等待钱包授权...');
      _startPolling();
      
      try {
        final session = await connectResp.session.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException('Future timeout'),
        );
        _stopPolling();
        _handleSession(session);
        return true;
      } on TimeoutException {
        _addLog('切换到轮询检查模式');
        return true;
      }
    } catch (e) {
      _addLog('❌ 连接出错: $e');
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _launchWalletApp(String uri) async {
    final encodedUri = Uri.encodeComponent(uri);
    final metamaskUrl = Uri.parse('metamask://wc?uri=$encodedUri');
    
    try {
      if (await canLaunchUrl(metamaskUrl)) {
        return await launchUrl(metamaskUrl, mode: LaunchMode.externalApplication);
      }
      final universalUrl = Uri.parse('https://metamask.app.link/wc?uri=$encodedUri');
      return await launchUrl(universalUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      _addLog('唤起失败: $e');
      return false;
    }
  }

  Future<void> _cleanupOldConnections() async {
    if (_wc == null) return;
    try {
      final pairings = _wc!.pairings.getAll();
      for (var pairing in pairings) {
        await _wc!.core.pairing.disconnect(topic: pairing.topic);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _stopPolling();
    int pollCount = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      pollCount++;
      if (!_isConnecting || isConnected || pollCount > 30) {
        timer.cancel();
        if (pollCount > 30) {
          _isConnecting = false;
          _connectionError = '连接超时';
          notifyListeners();
        }
        return;
      }
      _addLog('🔄 轮询检查 ($pollCount/30)...');
      _checkActiveConnections();
    });
  }

  void _checkActiveConnections() {
    if (_wc == null) return;
    final sessions = _wc!.sessions.getAll();
    if (sessions.isNotEmpty) {
      for (var session in sessions) {
        final eip155 = session.namespaces['eip155'];
        if (eip155 != null && eip155.accounts.isNotEmpty) {
          _addLog('✅ 轮询发现有效会话');
          _stopPolling();
          _handleSession(session);
          break;
        }
      }
    }
  }

  void _stopPolling() {
    _pendingPairingTopic = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _handleSession(SessionData session) {
    _session = session;
    final eip155 = session.namespaces['eip155'];
    if (eip155 != null && eip155.accounts.isNotEmpty) {
      final account = eip155.accounts.first;
      final parts = account.split(':');
      if (parts.length >= 3) {
        _chainId = int.tryParse(parts[1]);
        _address = parts[2];
        _addLog('✅ 地址: ${_address?.substring(0, 10)}...');
      }
    }

    _isConnecting = false;
    _updateNetworkName();
    _initializeWeb3Client();
    _addLog('🎉 连接成功！');
    notifyListeners();
  }

  void _refreshSessionData() {
    final sessions = _wc?.sessions.getAll();
    if (sessions != null && sessions.isNotEmpty) {
      _handleSession(sessions.first);
    }
  }

  void _updateNetworkName() {
    switch (_chainId) {
      case 1: _networkName = 'Ethereum Mainnet'; break;
      case 56: _networkName = 'BSC Mainnet'; break;
      case 137: _networkName = 'Polygon Mainnet'; break;
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
    _addLog('🔄 检查状态');
    await _initClient();
    await _restoreExistingSessions();
  }

  Future<List<Map<String, String>>> getTokenBalances() async {
    if (_address == null || _web3Client == null) return [];
    try {
      final bal = await _web3Client!.getBalance(EthereumAddress.fromHex(_address!));
      final val = bal.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      String symbol = (_chainId == 56) ? 'BNB' : (_chainId == 137 ? 'MATIC' : 'ETH');
      return [{'symbol': symbol, 'balance': val}];
    } catch (e) {
      _addLog('❌ 余额失败: $e');
      return [];
    }
  }

  Future<void> disconnect() async {
    _addLog('🔌 断开连接');
    await _disconnectInternal();
  }

  Future<void> _disconnectInternal() async {
    _stopPolling();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _web3Client?.dispose();
    super.dispose();
  }
}
