import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletService extends ChangeNotifier {
  WalletConnect? _connector;
  SessionStatus? _session;
  Web3Client? _web3Client;
  bool _isConnecting = false;
  String? _address;
  int? _chainId;
  String? _networkName;
  String? _connectionError;
  Timer? _connectionTimeout;
  Timer? _connectionCheckTimer;
  bool _isSigning = false;
  bool _isAuthorized = false;

  bool get isConnected => _session != null && _connector?.connected == true;
  bool get isConnecting => _isConnecting;
  bool get isSigning => _isSigning;
  bool get isAuthorized => _isAuthorized;
  String? get address => _address;
  int? get chainId => _chainId;
  String? get networkName => _networkName;
  String? get connectionError => _connectionError;

  WalletService() {
    _initializeConnector();
    _loadSavedSession();
  }

  void _initializeConnector() {
    _connector = WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      clientMeta: PeerMeta(
        name: 'RiverBit DEX',
        description: 'RiverBit Decentralized Exchange',
        url: 'https://riverbit.com',
        icons: ['https://riverbit.com/icon.png'],
      ),
    );
    
    // 检查是否有已存在的会话
    _checkExistingSession();

    _connector?.on('connect', (session) async {
      debugPrint('=== WalletConnect connect event triggered ===');
      debugPrint('Session type: ${session.runtimeType}');
      debugPrint('Session data: $session');
      
      _connectionTimeout?.cancel();
      _connectionTimeout = null;
      _connectionError = null;
      
      try {
        _session = session as SessionStatus;
        debugPrint('SessionStatus cast successful');
        debugPrint('Session accounts: ${_session?.accounts}');
        debugPrint('Session chainId: ${_session?.chainId}');
        
        _address = _session?.accounts[0];
        _chainId = _session?.chainId;
        debugPrint('Address extracted: $_address');
        debugPrint('ChainId extracted: $_chainId');
        
        if (_address == null || _address!.isEmpty) {
          debugPrint('ERROR: Address is null or empty!');
          _isConnecting = false;
          _connectionError = '无法获取钱包地址';
          notifyListeners();
          return;
        }
        
        _updateNetworkName();
        debugPrint('Network name: $_networkName');
        
        _initializeWeb3Client();
        debugPrint('Web3Client initialized');
        
        // 停止连接检查定时器
        _connectionCheckTimer?.cancel();
        _connectionCheckTimer = null;
        
        // 先更新连接状态，停止转圈
        _isConnecting = false;
        _isAuthorized = true; // 连接成功即视为已授权
        debugPrint('Connection state updated: isConnecting = false, isAuthorized = true');
        
        // 保存会话信息
        await _saveSession();
        
        // 立即通知UI更新，显示钱包信息
        notifyListeners();
        
        // 异步获取账户信息（不阻塞UI更新）
        debugPrint('Starting to fetch account info...');
        _fetchAccountInfo().then((_) {
          debugPrint('Account info fetch completed');
        }).catchError((e) {
          debugPrint('Error fetching account info: $e');
        });
        
        // 可选：请求签名（不阻塞主流程）
        _requestSignature().then((authorized) {
          if (authorized) {
            debugPrint('Signature authorization successful');
          } else {
            debugPrint('Signature authorization skipped or failed (non-blocking)');
          }
        }).catchError((e) {
          debugPrint('Signature request error (non-blocking): $e');
        });
        
      } catch (e, stackTrace) {
        debugPrint('Error in connect handler: $e');
        debugPrint('Stack trace: $stackTrace');
        _isConnecting = false;
        _isAuthorized = false;
        _connectionError = '连接处理错误: $e';
        notifyListeners();
      }
    });

    _connector?.on('session_update', (payload) async {
      if (payload is SessionStatus) {
        debugPrint('Wallet session updated');
        _session = payload;
        _address = _session?.accounts[0];
        _chainId = _session?.chainId;
        _updateNetworkName();
        
        // 会话更新时重新获取账户信息
        if (_web3Client == null) {
          _initializeWeb3Client();
        }
        await _fetchAccountInfo();
        
        notifyListeners();
      }
    });

    _connector?.on('disconnect', (session) {
      debugPrint('Wallet disconnected');
      _connectionTimeout?.cancel();
      _connectionTimeout = null;
      _session = null;
      _address = null;
      _chainId = null;
      _networkName = null;
      _connectionError = null;
      _isAuthorized = false;
      _isSigning = false;
      _web3Client?.dispose();
      _web3Client = null;
      _isConnecting = false;
      notifyListeners();
    });
  }

  void _checkExistingSession() {
    // 检查 WalletConnect 是否有已存在的会话
    if (_connector?.connected == true) {
      try {
        final session = _connector!.session;
        debugPrint('Found existing wallet session, restoring...');
        debugPrint('Session: $session');
        
        // 尝试从会话中恢复信息
        _tryRestoreFromSession(session);
      } catch (e) {
        debugPrint('Error checking existing session: $e');
      }
    }
  }

  void _tryRestoreFromSession(dynamic session) {
    try {
      debugPrint('Attempting to restore session: ${session.runtimeType}');
      
      // 尝试从会话对象中提取信息
      // 由于 walletconnect_dart 的类型限制，我们需要手动检查
      if (session is SessionStatus) {
        _session = session;
        _address = session.accounts.isNotEmpty ? session.accounts[0] : null;
        _chainId = session.chainId;
        
        if (_address != null && _address!.isNotEmpty) {
          debugPrint('Restored session with address: $_address');
          _updateNetworkName();
          _initializeWeb3Client();
          _isAuthorized = true;
          _isConnecting = false;
          _fetchAccountInfo();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error restoring session: $e');
    }
  }

  void _startConnectionCheck() {
    _connectionCheckTimer?.cancel();
    int checkCount = 0;
    const maxChecks = 30; // 最多检查30次（60秒）
    
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      checkCount++;
      debugPrint('Connection check #$checkCount');
      
      if (_connector?.connected == true) {
        debugPrint('WalletConnect is connected!');
        final session = _connector!.session;
        debugPrint('Session found: $session');
        _tryRestoreFromSession(session);
        timer.cancel();
        _connectionCheckTimer = null;
        return;
      }
      
      if (checkCount >= maxChecks) {
        debugPrint('Connection check timeout after ${maxChecks * 2} seconds');
        timer.cancel();
        _connectionCheckTimer = null;
        if (_isConnecting) {
          _isConnecting = false;
          _connectionError = '连接超时，请重试';
          notifyListeners();
        }
      }
    });
  }

  Future<void> _saveConnectionUri(String uri) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('walletconnect_uri', uri);
      await prefs.setInt('walletconnect_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving connection URI: $e');
    }
  }

  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAddress = prefs.getString('wallet_address');
      final savedChainId = prefs.getInt('wallet_chain_id');
      
      if (savedAddress != null && savedAddress.isNotEmpty && savedChainId != null) {
        debugPrint('Loading saved session: address=$savedAddress, chainId=$savedChainId');
        _address = savedAddress;
        _chainId = savedChainId;
        _updateNetworkName();
        _initializeWeb3Client();
        _isAuthorized = true;
        _isConnecting = false;
        notifyListeners();
        // 异步获取账户信息
        _fetchAccountInfo();
      }
    } catch (e) {
      debugPrint('Error loading saved session: $e');
    }
  }

  Future<void> _saveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_address != null && _chainId != null) {
        await prefs.setString('wallet_address', _address!);
        await prefs.setInt('wallet_chain_id', _chainId!);
        debugPrint('Session saved: address=$_address, chainId=$_chainId');
      }
    } catch (e) {
      debugPrint('Error saving session: $e');
    }
  }

  Future<void> _clearSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('wallet_address');
      await prefs.remove('wallet_chain_id');
      await prefs.remove('walletconnect_uri');
      await prefs.remove('walletconnect_timestamp');
    } catch (e) {
      debugPrint('Error clearing saved session: $e');
    }
  }

  // 手动检查连接状态（供外部调用，例如应用回到前台时）
  Future<void> checkConnectionStatus() async {
    debugPrint('=== Manual connection status check ===');
    debugPrint('_connector?.connected: ${_connector?.connected}');
    debugPrint('_isConnecting: $_isConnecting');
    debugPrint('_address: $_address');
    
    if (_connector?.connected == true) {
      final session = _connector!.session;
      debugPrint('Found active session, restoring...');
      _tryRestoreFromSession(session);
    } else if (_isConnecting) {
      // 如果正在连接但超时，停止连接状态
      debugPrint('Connection in progress but connector not connected, checking timeout...');
    }
  }

  Future<bool> _requestSignature() async {
    if (_connector == null || _address == null) {
      debugPrint('Cannot request signature: connector or address is null');
      return false;
    }

    try {
      _isSigning = true;
      notifyListeners();

      // 创建签名消息
      final message = 'RiverBit DEX 请求连接您的钱包\n\n'
          '地址: $_address\n'
          '时间: ${DateTime.now().toIso8601String()}\n\n'
          '点击确认以授权应用访问您的钱包信息。';

      debugPrint('Requesting signature for message: $message');

      // 将消息转换为 hex 格式
      final messageHex = '0x${message.codeUnits.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
      debugPrint('Message hex: $messageHex');

      // 使用 WalletConnect 请求签名
      // walletconnect_dart 使用 sendCustomRequest 方法
      dynamic result;
      try {
        result = await _connector!.sendCustomRequest(
          method: 'personal_sign',
          params: [messageHex, _address],
        );
        debugPrint('Signature result type: ${result.runtimeType}');
        debugPrint('Signature result: $result');
      } catch (e) {
        debugPrint('sendCustomRequest error: $e');
        // 如果 sendCustomRequest 不存在，尝试使用其他方法
        // 某些版本的 walletconnect_dart 可能使用不同的 API
        debugPrint('Trying alternative signature method...');
        // 对于 walletconnect_dart 0.0.7，可能需要直接使用 connector 的方法
        // 如果签名失败，我们仍然允许连接（连接本身已经通过用户确认）
        _isSigning = false;
        debugPrint('Signature request not available, allowing connection without signature');
        return true;
      }

      _isSigning = false;
      
      if (result != null && result is String && result.isNotEmpty) {
        debugPrint('Signature received successfully: ${result.substring(0, 20)}...');
        return true;
      } else {
        debugPrint('Signature request failed or cancelled');
        // 即使签名失败，如果连接已建立，仍然允许使用
        return true;
      }
    } catch (e, stackTrace) {
      debugPrint('Error requesting signature: $e');
      debugPrint('Stack trace: $stackTrace');
      _isSigning = false;
      // 如果签名失败，仍然允许连接（某些钱包可能不支持签名或用户取消）
      debugPrint('Allowing connection without signature verification');
      return true;
    }
  }

  Future<void> _fetchAccountInfo() async {
    debugPrint('=== _fetchAccountInfo called ===');
    debugPrint('isConnected: $isConnected');
    debugPrint('isAuthorized: $_isAuthorized');
    debugPrint('_address: $_address');
    debugPrint('_chainId: $_chainId');
    
    if (_address == null || _address!.isEmpty) {
      debugPrint('Cannot fetch account info: address is null or empty');
      return;
    }
    
    debugPrint('Fetching account information for: $_address');
    try {
      // 这里可以添加更多账户信息获取逻辑
      // 目前通过 notifyListeners() 触发 UI 更新，UI 会自动调用 getTokenBalances()
      notifyListeners();
      debugPrint('Account info fetch completed, listeners notified');
    } catch (e) {
      debugPrint('Error fetching account info: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  void _updateNetworkName() {
    if (_chainId == null) {
      _networkName = null;
      return;
    }

    switch (_chainId) {
      case 1:
        _networkName = 'Ethereum Mainnet';
        break;
      case 5:
        _networkName = 'Goerli Testnet';
        break;
      case 137:
        _networkName = 'Polygon';
        break;
      case 56:
        _networkName = 'BSC';
        break;
      default:
        _networkName = 'Unknown Network';
    }
  }

  void _initializeWeb3Client() {
    if (_chainId == null) return;

    String rpcUrl;
    switch (_chainId) {
      case 1:
        rpcUrl = 'https://eth.llamarpc.com';
        break;
      case 5:
        rpcUrl = 'https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161';
        break;
      case 137:
        rpcUrl = 'https://polygon-rpc.com';
        break;
      case 56:
        rpcUrl = 'https://bsc-dataseed.binance.org';
        break;
      default:
        rpcUrl = 'https://eth.llamarpc.com';
    }

    _web3Client = Web3Client(rpcUrl, http.Client());
  }

  Future<bool> connect() async {
    if (_connector == null) {
      _initializeConnector();
    }

    // 检查是否已经连接且有有效会话
    if (_connector?.connected == true && _session != null && _address != null) {
      debugPrint('Wallet already connected with address: $_address');
      _isConnecting = false;
      _isAuthorized = true;
      _initializeWeb3Client();
      _fetchAccountInfo();
      notifyListeners();
      return true;
    }

    try {
      _isConnecting = true;
      _connectionError = null;
      notifyListeners();

      // 设置连接超时（60秒）
      _connectionTimeout = Timer(const Duration(seconds: 60), () {
        if (_isConnecting) {
          _isConnecting = false;
          _connectionError = '连接超时，请重试';
          debugPrint('Wallet connection timeout');
          notifyListeners();
        }
      });

      debugPrint('Creating wallet connection session...');
      await _connector!.createSession(
        chainId: 1,
        onDisplayUri: (uri) async {
          debugPrint('WalletConnect URI generated: $uri');
          // 保存 URI 以便后续检查
          await _saveConnectionUri(uri);
          // 在移动端，尝试打开 MetaMask 应用或显示二维码
          await _handleWalletConnectUri(uri);
        },
      );

      debugPrint('Session created, waiting for user approval...');
      // 注意：createSession 返回后，实际连接需要等待用户在钱包中确认
      // 真正的连接成功会通过 'connect' 事件触发
      
      // 启动轮询检查连接状态（每2秒检查一次）
      _startConnectionCheck();
      
      return true;
    } catch (e) {
      _connectionTimeout?.cancel();
      _connectionTimeout = null;
      _isConnecting = false;
      _connectionError = '连接失败: ${e.toString()}';
      notifyListeners();
      debugPrint('Wallet connection error: $e');
      return false;
    }
  }

  Future<void> _handleWalletConnectUri(String uri) async {
    debugPrint('Attempting to launch wallet with URI: $uri');
    
    try {
      // 方法1: 使用 Android Intent 直接启动 MetaMask 应用（Android 专用）
      try {
        const platform = MethodChannel('com.riverbit.flutter_demo/wallet');
        final result = await platform.invokeMethod('launchMetaMask', {'uri': uri});
        if (result == true) {
          debugPrint('Successfully launched MetaMask via Android Intent');
          return;
        }
      } catch (e) {
        debugPrint('Android Intent method not available or failed: $e');
      }

      // 方法2: 优先使用 metamask:// 协议直接打开 MetaMask 应用
      final metamaskDeepLink = 'metamask://wc?uri=${Uri.encodeComponent(uri)}';
      debugPrint('Trying metamask:// protocol: $metamaskDeepLink');
      try {
        final metamaskUri = Uri.parse(metamaskDeepLink);
        // 直接尝试启动，不检查 canLaunchUrl（因为可能返回 false 但实际可以启动）
        await launchUrl(
          metamaskUri,
          mode: LaunchMode.externalApplication,
        );
        debugPrint('Successfully launched MetaMask with metamask:// protocol');
        return;
      } catch (e) {
        debugPrint('Failed to launch with metamask://: $e');
      }

      // 方法3: 使用 walletconnect:// 协议
      final walletConnectUri = uri.replaceFirst('wc:', 'walletconnect:');
      debugPrint('Trying walletconnect:// protocol: $walletConnectUri');
      try {
        final wcUri = Uri.parse(walletConnectUri);
        await launchUrl(
          wcUri,
          mode: LaunchMode.externalApplication,
        );
        debugPrint('Successfully launched with walletconnect:// protocol');
        return;
      } catch (e) {
        debugPrint('Failed to launch with walletconnect://: $e');
      }

      // 方法4: 使用 MetaMask 的 HTTPS 深度链接
      final metamaskHttpsUri = 'https://metamask.app/wc?uri=${Uri.encodeComponent(uri)}';
      debugPrint('Trying https://metamask.app/ protocol: $metamaskHttpsUri');
      try {
        final httpsUri = Uri.parse(metamaskHttpsUri);
        await launchUrl(
          httpsUri,
          mode: LaunchMode.externalApplication,
        );
        debugPrint('Successfully launched with https://metamask.app/');
        return;
      } catch (e) {
        debugPrint('Failed to launch with https://: $e');
      }

      debugPrint('All launch methods failed for URI: $uri');
    } catch (e) {
      debugPrint('Error launching wallet: $e');
    }
  }

  Future<void> disconnect() async {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
    
    if (_connector?.connected == true) {
      await _connector?.killSession();
    }
    _session = null;
    _address = null;
    _chainId = null;
    _networkName = null;
    _isAuthorized = false;
    _isSigning = false;
    _web3Client?.dispose();
    _web3Client = null;
    await _clearSavedSession();
    notifyListeners();
  }

  Future<EtherAmount> getBalance() async {
    debugPrint('=== getBalance called ===');
    debugPrint('_web3Client: ${_web3Client != null}');
    debugPrint('_address: $_address');
    
    if (_web3Client == null || _address == null) {
      debugPrint('Cannot get balance: web3Client or address is null');
      return EtherAmount.zero();
    }

    try {
      debugPrint('Converting address to EthereumAddress: $_address');
      final address = EthereumAddress.fromHex(_address!);
      debugPrint('EthereumAddress created: $address');
      
      debugPrint('Calling _web3Client.getBalance...');
      final balance = await _web3Client!.getBalance(address);
      debugPrint('Balance received: $balance');
      
      return balance;
    } catch (e, stackTrace) {
      debugPrint('Error getting balance: $e');
      debugPrint('Stack trace: $stackTrace');
      return EtherAmount.zero();
    }
  }

  Future<List<Map<String, dynamic>>> getTokenBalances() async {
    debugPrint('=== getTokenBalances called ===');
    debugPrint('_address: $_address');
    debugPrint('_web3Client: ${_web3Client != null ? "initialized" : "null"}');
    
    // 这里可以添加 ERC-20 代币余额查询逻辑
    // 目前返回 ETH 余额
    if (_address == null) {
      debugPrint('Address is null, returning empty list');
      return [];
    }

    if (_web3Client == null) {
      debugPrint('Web3Client is null, cannot get balance');
      return [];
    }

    try {
      debugPrint('Getting balance for address: $_address');
      final balance = await getBalance();
      debugPrint('Balance received: $balance');
      
      final ethBalance = balance.getValueInUnit(EtherUnit.ether);
      debugPrint('ETH balance: $ethBalance');
      
      final result = [
        {
          'symbol': 'ETH',
          'balance': ethBalance.toStringAsFixed(4),
          'address': _address,
        }
      ];
      
      debugPrint('Returning token balances: $result');
      return result;
    } catch (e, stackTrace) {
      debugPrint('Error getting token balances: $e');
      debugPrint('Stack trace: $stackTrace');
      return [];
    }
  }

  @override
  void dispose() {
    _connectionTimeout?.cancel();
    _connectionCheckTimer?.cancel();
    _web3Client?.dispose();
    _connector?.killSession();
    super.dispose();
  }
}

