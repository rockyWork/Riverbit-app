import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

/// WalletConnect v2 服务（使用提供的 projectId）
class WalletService extends ChangeNotifier {
  static const String _projectId = '1d9024e332c1f6c37d6d4ca165b07104';
  static const String _relayUrl = 'wss://relay.walletconnect.com';
  static const String _appName = 'RiverBit DEX';
  static const String _appUrl = 'https://riverbit.com';
  static const List<String> _chains = [
    'eip155:1', // Ethereum
    'eip155:5', // Goerli
    'eip155:56', // BSC
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

  /// 初始化 WalletConnect v2 客户端
  Future<void> _initClient() async {
    if (_wc != null || _isInitializing) return;
    _isInitializing = true;
    try {
      _wc = await Web3App.createInstance(
        projectId: _projectId,
        relayUrl: _relayUrl,
        metadata: const PairingMetadata(
          name: _appName,
          description: 'RiverBit Decentralized Exchange',
          url: _appUrl,
          icons: ['https://riverbit.com/icon.png'],
        ),
      );

      // 尝试恢复已有会话
      final sessions = _wc!.sessions.getAll();
      if (sessions.isNotEmpty) {
        _handleSession(sessions.first);
      }
    } catch (e) {
      debugPrint('Init WalletConnect v2 error: $e');
      _connectionError = '初始化失败: $e';
    } finally {
      _isInitializing = false;
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

    // 已有会话直接复用
    if (_session != null && _address != null) {
      _isConnecting = false;
      notifyListeners();
      return true;
    }

    try {
      _isConnecting = true;
      _connectionError = null;
      notifyListeners();

      final connectResp = await _wc!.connect(
        requiredNamespaces: {
          'eip155': RequiredNamespace(
            chains: _chains,
            methods: const [
              'personal_sign',
              'eth_sendTransaction',
              'eth_signTransaction',
              'eth_signTypedData',
            ],
            events: const ['accountsChanged', 'chainChanged'],
          ),
        },
      );

      // 唤起钱包
      final uri = connectResp.uri;
      if (uri != null) {
        debugPrint('WC URI: $uri');
        await _launchWallet(uri.toString());
      }

      // 等待用户在钱包中批准
      final session = await connectResp.session.future;
      _handleSession(session);
      return true;
    } catch (e) {
      debugPrint('Connect error: $e');
      _isConnecting = false;
      _connectionError = '连接失败: $e';
      notifyListeners();
      return false;
    }
  }

  void _handleSession(SessionData session) {
    _session = session;
    final accounts = session.namespaces['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) {
      _connectionError = '未获取到账户信息';
      _isConnecting = false;
      notifyListeners();
      return;
    }

    // 取第一个账户，格式 eip155:1:0xabc...
    final parts = accounts.first.split(':');
    if (parts.length < 3) {
      _connectionError = '账户格式异常';
      _isConnecting = false;
      notifyListeners();
      return;
    }

    _chainId = int.tryParse(parts[1]);
    _address = parts[2];
    _updateNetworkName();
    _initializeWeb3Client();

    _isConnecting = false;
    _connectionError = null;
    notifyListeners();

    _fetchAccountInfo();
    _requestSignature(); // 非阻塞，可选
  }

  Future<void> _launchWallet(String uri) async {
    final meta = Uri.parse('metamask://wc?uri=${Uri.encodeComponent(uri)}');
    final wc = Uri.parse(uri.replaceFirst('wc:', 'walletconnect:'));
    final https = Uri.parse('https://metamask.app/wc?uri=${Uri.encodeComponent(uri)}');

    if (await canLaunchUrl(meta)) {
      await launchUrl(meta, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(wc)) {
      await launchUrl(wc, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(https, mode: LaunchMode.externalApplication);
  }

  /// 应用回到前台时可调用，尝试恢复会话
  Future<void> checkConnectionStatus() async {
    await _initClient();
    if (_wc == null) return;
    final sessions = _wc!.sessions.getAll();
    if (sessions.isNotEmpty) {
      _handleSession(sessions.first);
    }
  }

  Future<bool> _requestSignature() async {
    if (_wc == null || _session == null || _address == null) return false;
    try {
      _isSigning = true;
      notifyListeners();

      final message = 'RiverBit DEX 请求连接您的钱包\\n\\n'
          '地址: $_address\\n'
          '时间: ${DateTime.now().toIso8601String()}\\n\\n'
          '点击确认以授权应用访问您的钱包信息。';
      final messageHex = '0x${message.codeUnits.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';

      final res = await _wc!.request(
        topic: _session!.topic,
        chainId: 'eip155:${_chainId ?? 1}',
        request: SessionRequestParams(
          method: 'personal_sign',
          params: [messageHex, _address],
        ),
      );

      debugPrint('Signature result: $res');
      _isSigning = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Signature error: $e');
      _isSigning = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _fetchAccountInfo() async {
    if (_address == null || _web3Client == null) return;
    notifyListeners(); // 触发 UI 更新（UI 会拉余额）
  }

  void _updateNetworkName() {
    switch (_chainId) {
      case 1:
        _networkName = 'Ethereum Mainnet';
        break;
      case 5:
        _networkName = 'Goerli Testnet';
        break;
      case 56:
        _networkName = 'BSC';
        break;
      case 137:
        _networkName = 'Polygon';
        break;
      default:
        _networkName = 'Unknown Network';
    }
  }

  void _initializeWeb3Client() {
    if (_chainId == null) return;
    String rpc;
    switch (_chainId) {
      case 1:
        rpc = 'https://eth.llamarpc.com';
        break;
      case 5:
        rpc = 'https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161';
        break;
      case 56:
        rpc = 'https://bsc-dataseed.binance.org';
        break;
      case 137:
        rpc = 'https://polygon-rpc.com';
        break;
      default:
        rpc = 'https://eth.llamarpc.com';
    }
    _web3Client = Web3Client(rpc, http.Client());
  }

  Future<List<Map<String, dynamic>>> getTokenBalances() async {
    if (_address == null || _web3Client == null) return [];
    try {
      final bal = await _web3Client!.getBalance(EthereumAddress.fromHex(_address!));
      final eth = bal.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      return [
        {'symbol': 'ETH', 'balance': eth, 'address': _address},
      ];
    } catch (e) {
      debugPrint('Balance error: $e');
      return [];
    }
  }

  Future<void> disconnect() async {
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
    // 断开所有会话，避免资源占用
    try {
      final sessions = _wc?.sessions.getAll();
      if (sessions != null) {
        for (final s in sessions) {
          _wc!.disconnectSession(
            topic: s.topic,
            reason: Errors.getSdkError(Errors.USER_DISCONNECTED),
          );
        }
      }
    } catch (_) {}
    super.dispose();
  }
}

