import 'dart:async';
import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class WalletService extends ChangeNotifier {
  WalletConnect? _connector;
  SessionStatus? _session;
  Web3Client? _web3Client;
  bool _isConnecting = false;
  String? _address;
  int? _chainId;
  String? _networkName;

  bool get isConnected => _session != null && _connector?.connected == true;
  bool get isConnecting => _isConnecting;
  String? get address => _address;
  int? get chainId => _chainId;
  String? get networkName => _networkName;

  WalletService() {
    _initializeConnector();
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

    _connector?.on('connect', (session) {
      _session = session as SessionStatus;
      _address = _session?.accounts[0];
      _chainId = _session?.chainId;
      _updateNetworkName();
      _initializeWeb3Client();
      _isConnecting = false;
      notifyListeners();
    });

    _connector?.on('session_update', (payload) {
      if (payload is SessionStatus) {
        _session = payload;
        _address = _session?.accounts[0];
        _chainId = _session?.chainId;
        _updateNetworkName();
        notifyListeners();
      }
    });

    _connector?.on('disconnect', (session) {
      _session = null;
      _address = null;
      _chainId = null;
      _networkName = null;
      _web3Client?.dispose();
      _web3Client = null;
      _isConnecting = false;
      notifyListeners();
    });
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

    if (_connector?.connected == true) {
      return true;
    }

    try {
      _isConnecting = true;
      notifyListeners();

      final session = await _connector!.createSession(
        chainId: 1,
        onDisplayUri: (uri) async {
          // 在移动端，尝试打开 MetaMask 应用或显示二维码
          await _handleWalletConnectUri(uri);
        },
      );

      _session = session;
      _address = session.accounts[0];
      _chainId = session.chainId;
      _updateNetworkName();
      _initializeWeb3Client();

      _isConnecting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isConnecting = false;
      notifyListeners();
      debugPrint('Wallet connection error: $e');
      return false;
    }
  }

  Future<void> _handleWalletConnectUri(String uri) async {
    // 尝试使用 walletconnect:// 协议打开 MetaMask
    final walletConnectUri = uri.replaceFirst('wc:', 'walletconnect:');
    
    try {
      if (await canLaunchUrl(Uri.parse(walletConnectUri))) {
        await launchUrl(
          Uri.parse(walletConnectUri),
          mode: LaunchMode.externalApplication,
        );
      } else {
        // 如果无法打开，尝试使用 https://metamask.app/wc?uri= 格式
        final metamaskUri = 'https://metamask.app/wc?uri=${Uri.encodeComponent(uri)}';
        if (await canLaunchUrl(Uri.parse(metamaskUri))) {
          await launchUrl(
            Uri.parse(metamaskUri),
            mode: LaunchMode.externalApplication,
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching wallet: $e');
    }
  }

  Future<void> disconnect() async {
    if (_connector?.connected == true) {
      await _connector?.killSession();
    }
    _session = null;
    _address = null;
    _chainId = null;
    _networkName = null;
    _web3Client?.dispose();
    _web3Client = null;
    notifyListeners();
  }

  Future<EtherAmount> getBalance() async {
    if (_web3Client == null || _address == null) {
      return EtherAmount.zero();
    }

    try {
      final address = EthereumAddress.fromHex(_address!);
      final balance = await _web3Client!.getBalance(address);
      return balance;
    } catch (e) {
      debugPrint('Error getting balance: $e');
      return EtherAmount.zero();
    }
  }

  Future<List<Map<String, dynamic>>> getTokenBalances() async {
    // 这里可以添加 ERC-20 代币余额查询逻辑
    // 目前返回 ETH 余额
    if (_address == null) {
      return [];
    }

    try {
      final balance = await getBalance();
      final ethBalance = balance.getValueInUnit(EtherUnit.ether);
      
      return [
        {
          'symbol': 'ETH',
          'balance': ethBalance.toStringAsFixed(4),
          'address': _address,
        }
      ];
    } catch (e) {
      debugPrint('Error getting token balances: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _web3Client?.dispose();
    _connector?.killSession();
    super.dispose();
  }
}

