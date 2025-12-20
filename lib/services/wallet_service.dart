import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

class WalletService extends ChangeNotifier with WidgetsBindingObserver {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal() {
    _initClient();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _addLog('📱 App 回到前台，触发状态检查...');
      checkConnectionStatus();
    }
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

  // 重置连接状态，防止逻辑死锁
  void _resetConnectingState() {
    _isConnecting = false;
    _stopPolling();
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
          description: 'RiverBit Decentralized Exchange',
          url: 'riverbit://app', // 改为协议头，防止钱包在内部打开网页
          icons: ['https://riverbit.io/logo.png'],
          redirect: Redirect(
            native: 'riverbit://app', // 增加 host
            universal: 'https://riverbit.io',
          ),
        ),
      );

      // 监听连接
      _wc!.onSessionConnect.subscribe((SessionConnect? args) {
        if (args != null) {
          _addLog('🎯 [事件] 收到授权: ${args.session.topic.substring(0, 8)}');
          _handleSession(args.session);
        }
      });

      // 监听断开
      _wc!.onSessionDelete.subscribe((SessionDelete? args) {
        _addLog('🔌 钱包端已断开会话');
        _clearLocalState();
      });

      // 监听信令状态
      _wc!.core.relayClient.onRelayClientConnect.subscribe((_) {
        _addLog('🌐 信令链路已连接');
      });
      
      _wc!.core.relayClient.onRelayClientDisconnect.subscribe((_) {
        _addLog('⚠️ 信令链路已断开');
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
        final session = sessions.first;
        // 检查会话是否过期
        final expiry = session.expiry;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (expiry < now) {
          _addLog('🗑️ 清理过期会话');
          await disconnect();
          return;
        }

        if (_session?.topic != session.topic || _address == null) {
          _addLog('✅ 同步活动会话: ${session.topic.substring(0, 8)}');
          _handleSession(session);
        }
      }
    } catch (e) {
      _addLog('⚠️ 刷新会话异常: $e');
    }
  }

  Future<bool> connect({String? walletScheme}) async {
    await _initClient();
    if (_wc == null) return false;

    try {
      _isConnecting = true;
      _connectionError = null;
      _addLog('🚀 发起新连接 (全兼容增强版)...');
      notifyListeners();

      // 1. 强制清理残留：确保没有旧的 Pairing 干扰 OKX
      final pairings = _wc!.pairings.getAll();
      if (pairings.isNotEmpty) {
        _addLog('🧹 预清理 ${pairings.length} 个残留配对...');
        for (var p in pairings) {
          try { await _wc!.core.pairing.disconnect(topic: p.topic); } catch (_) {}
        }
      }

      // 2. 确保信令连通：增加等待和重试逻辑
      if (!_wc!.core.relayClient.isConnected) {
        _addLog('⏳ 正在建立信令链路...');
        await _wc!.core.relayClient.connect();
        int retry = 0;
        while (!_wc!.core.relayClient.isConnected && retry < 5) {
          await Future.delayed(const Duration(milliseconds: 500));
          retry++;
        }
      }
      
      // 给 Relay 准备的时间
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. Namespace 兼容性配置 (OKX 最佳实践)
      final connectResp = await _wc!.connect(
        optionalNamespaces: {
          'eip155': RequiredNamespace(
            chains: ['eip155:1', 'eip155:56', 'eip155:137', 'eip155:66', 'eip155:42161'],
            methods: [
              'eth_sendTransaction',
              'personal_sign',
              'eth_signTypedData',
              'eth_signTypedData_v4',
              'wallet_switchEthereumChain',
              'wallet_addEthereumChain',
            ],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      final uri = connectResp.uri;
      if (uri == null) return false;

      final encodedUri = Uri.encodeComponent(uri.toString());
      _addLog('📱 唤起钱包授权...');
      
      bool launched = false;
      try {
        if (walletScheme == 'okx') {
          // OKX 专用深度链接格式
          final okxUri = 'okx://wc?uri=$encodedUri';
          launched = await launchUrl(Uri.parse(okxUri), mode: LaunchMode.externalNonBrowserApplication);
        } else if (walletScheme == 'metamask') {
          launched = await launchUrl(Uri.parse('metamask://wc?uri=$encodedUri'), mode: LaunchMode.externalNonBrowserApplication);
        }
      } catch (e) {
        _addLog('⚠️ 唤起特定钱包失败: $e');
      }

      if (!launched) {
        _addLog('🌐 使用通用方式唤起...');
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!launched) {
        _addLog('❌ 无法打开任何钱包应用');
        _resetConnectingState();
        return false;
      }

      _startPolling();

      // 4. 等待授权结果，带更长超时和状态二次确认
      try {
        final session = await connectResp.session.future.timeout(const Duration(seconds: 90));
        _addLog('🎉 收到会话授权成功');
        _handleSession(session);
        return true;
      } catch (e) {
        // 如果 Future 超时，但后台可能已经通过 onSessionConnect 拿到结果了
        if (isConnected) {
          _addLog('✅ 后台已完成连接');
          return true;
        }
        _addLog('⏳ 授权等待超时，请手动切回 App 或重试');
        _resetConnectingState();
        return false;
      }
    } catch (e) {
      _addLog('❌ 连接初始化异常: $e');
      _resetConnectingState();
      return false;
    }
  }

  void _handleSession(SessionData session) {
    if (session.namespaces.isEmpty) {
      _addLog('⚠️ 收到空 Namespaces 会话');
      return;
    }
    
    // 如果 Topic 发生变化，强制更新
    bool isNewTopic = _session?.topic != session.topic;
    _session = session;

    String? foundAddress;
    int? foundChainId;

    // 🏆 深度账户解析：支持多 Namespace 遍历 (兼容更多链)
    for (var key in session.namespaces.keys) {
      final ns = session.namespaces[key]!;
      if (ns.accounts.isNotEmpty) {
        final account = ns.accounts.first; // 取第一个账户
        final parts = account.split(':');
        if (parts.length >= 3) {
          foundChainId = int.tryParse(parts[1]);
          foundAddress = parts[2];
          _addLog('📍 解析到账户: ${foundAddress.substring(0, 6)}... (Chain: $foundChainId)');
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
      
      if (isNewTopic) {
        _addLog('🎊 账户连接成功: ${_address!.substring(0, 10)}...');
      }
    } else {
      _addLog('❌ 会话中未找到有效地址');
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
      case 66: _networkName = 'OKC'; break;
      case 42161: _networkName = 'Arbitrum'; break;
      default: _networkName = 'Chain $_chainId';
    }
  }

  void _initializeWeb3Client() {
    if (_chainId == null || _address == null) return;
    
    // 使用更高可用的 RPC 节点
    String rpc = 'https://eth.llamarpc.com';
    switch (_chainId) {
      case 56: rpc = 'https://binance.llamarpc.com'; break;
      case 137: rpc = 'https://polygon.llamarpc.com'; break;
      case 66: rpc = 'https://exchainrpc.okex.org'; break;
      case 42161: rpc = 'https://arbitrum.llamarpc.com'; break;
    }
    
    _addLog('🌐 初始化 Web3Client: $rpc');
    _web3Client = Web3Client(rpc, http.Client());
  }

  Future<void> checkConnectionStatus() async {
    if (_wc == null) {
      await _initClient();
    }
    
    _addLog('🔄 强制同步状态...');

    // 1. 确保 Relay 连通
    if (!_wc!.core.relayClient.isConnected) {
      _addLog('⏳ 重新连接信令服务...');
      await _wc!.core.relayClient.connect();
      await Future.delayed(const Duration(seconds: 1));
    }
    
    // 2. 刷新会话
    await _refreshActiveSession();
    
    // 3. 如果还是没连上，尝试从持久化层捞
    if (!isConnected) {
      final sessions = _wc!.sessions.getAll();
      if (sessions.isNotEmpty) {
        _addLog('♻️ 从持久化层恢复会话');
        _handleSession(sessions.first);
      }
    }
    
    notifyListeners();
  }

  Future<List<Map<String, String>>> getTokenBalances() async {
    if (_address == null || _web3Client == null) return [];
    try {
      final bal = await _web3Client!.getBalance(EthereumAddress.fromHex(_address!));
      final val = bal.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      String symbol = 'ETH';
      if (_chainId == 56) symbol = 'BNB';
      if (_chainId == 137) symbol = 'MATIC';
      if (_chainId == 66) symbol = 'OKT';
      return [{'symbol': symbol, 'balance': val}];
    } catch (e) {
      _addLog('❌ 获取余额失败: $e');
      return [];
    }
  }

  Future<void> disconnect() async {
    _addLog('🔌 正在彻底断开连接...');
    
    // 1. 断开所有活动会话
    if (_wc != null) {
      try {
        final sessions = _wc!.sessions.getAll();
        for (var s in sessions) {
          _addLog('🔌 断开会话: ${s.topic.substring(0, 8)}');
          await _wc!.disconnectSession(
            topic: s.topic,
            reason: Errors.getSdkError(Errors.USER_DISCONNECTED),
          );
        }
      } catch (e) {
        _addLog('⚠️ 断开会话时异常: $e');
      }
    }
    
    // 2. 清理所有配对 (Pairings) - 这是防止连接死锁的关键
    if (_wc != null) {
      try {
        final pairings = _wc!.pairings.getAll();
        _addLog('🧹 清理 ${pairings.length} 个配对记录...');
        for (var p in pairings) {
          try {
            await _wc!.core.pairing.disconnect(topic: p.topic);
          } catch (_) {}
        }
      } catch (e) {
        _addLog('⚠️ 清理配对时异常: $e');
      }
    }

    // 3. 彻底重置 Web3App 状态 (可选，若仍有问题可开启)
    // _wc = null; 

    _clearLocalState();
    _addLog('✅ 已安全退出并重置状态');
  }

  void _clearLocalState() {
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
