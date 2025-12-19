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
          name: 'RiverBit',
          description: 'DEX',
          url: 'https://riverbit.com',
          icons: [], // 留空防止崩溃
          redirect: Redirect(native: 'riverbit://'),
        ),
      );

      _wc!.onSessionConnect.subscribe((SessionConnect? args) {
        _addLog('🎯 收到授权成功信号！');
        if (args != null) _handleSession(args.session);
      });

      _wc!.core.relayClient.onRelayClientConnect.subscribe((_) {
        _addLog('🌐 信令已连接');
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
    final sessions = _wc!.sessions.getAll();
    if (sessions.isNotEmpty) {
      _addLog('✅ 自动恢复会话');
      _handleSession(sessions.first);
    }
  }

  Future<bool> connect() async {
    await _initClient();
    if (_wc == null) return false;

    try {
      _isConnecting = true;
      _connectionError = null;
      debugLogs.clear();
      _addLog('🚀 发起【防崩溃】连接请求...');
      notifyListeners();

      // 清理旧 Pairing
      for (var p in _wc!.pairings.getAll()) {
        await _wc!.core.pairing.disconnect(topic: p.topic);
      }

      if (!_wc!.core.relayClient.isConnected) {
        await _wc!.core.relayClient.connect();
        await Future.delayed(const Duration(seconds: 1));
      }

      // 【核心修复】使用极简配置，防止小狐狸 React Native 引擎崩溃
      final connectResp = await _wc!.connect(
        optionalNamespaces: {
          'eip155': RequiredNamespace(
            chains: ['eip155:1'], // 仅请求主网
            methods: ['personal_sign'], // 仅请求最基础的签名权限，规避崩溃
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      final uri = connectResp.uri;
      if (uri == null) {
        _addLog('❌ URI 生成失败');
        _isConnecting = false;
        return false;
      }

      _addLog('📱 跳转小狐狸...');
      final uriString = Uri.encodeComponent(uri.toString());
      await launchUrl(
        Uri.parse('metamask://wc?uri=$uriString'),
        mode: LaunchMode.externalApplication,
      );

      _startPolling();

      // 等待授权
      final session = await connectResp.session.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException('等待授权超时'),
      );
      
      _handleSession(session);
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
    _session = session;
    _addLog('📦 解析账户...');
    
    final eip155 = session.namespaces['eip155'];
    if (eip155 != null && eip155.accounts.isNotEmpty) {
      final account = eip155.accounts.first;
      final parts = account.split(':');
      if (parts.length >= 3) {
        _chainId = int.tryParse(parts[1]);
        _address = parts[2];
        _addLog('✅ 获取地址成功: ${_address?.substring(0, 10)}...');
      }
    }

    _isConnecting = false;
    _stopPolling();
    _updateNetworkName();
    _initializeWeb3Client();
    _addLog('🎉 连接成功');
    notifyListeners();
  }

  void _startPolling() {
    _stopPolling();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
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
    _addLog('🔄 应用切回前台，同步状态');
    await _initClient();
    if (_wc != null && !_wc!.core.relayClient.isConnected) {
      await _wc!.core.relayClient.connect();
    }
    await Future.delayed(const Duration(milliseconds: 1000));
    await _refreshActiveSession();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    _web3Client?.dispose();
    super.dispose();
  }
}
