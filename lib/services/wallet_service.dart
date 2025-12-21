import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:reown_appkit/reown_appkit.dart';
import 'package:web3dart/web3dart.dart';
import 'package:convert/convert.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletService extends ChangeNotifier {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  ReownAppKitModal? _appKitModal;
  
  static const String _projectId = '1d9024e332c1f6c37d6d4ca165b07104';

  bool get isConnected => _appKitModal?.isConnected ?? false;
  bool get isConnecting => _appKitModal == null;
  
  String? get address {
    if (!isConnected || _appKitModal?.session == null) return null;
    // 兼容多种方式获取地址
    try {
      // 尝试从 session 中直接获取 (如果 SDK 版本支持)
      return (_appKitModal!.session as dynamic).address;
    } catch (_) {
      try {
        // 尝试从 namespaces 中获取
        final namespaces = _appKitModal!.session!.namespaces;
        if (namespaces != null && namespaces.containsKey('eip155')) {
          final accounts = namespaces['eip155']!.accounts;
          if (accounts.isNotEmpty) {
            return accounts.first.split(':').last;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String? get networkName => _appKitModal?.selectedChain?.name;
  int? get chainId => int.tryParse(_appKitModal?.selectedChain?.chainId ?? '');
  String? get connectionError => null;

  final List<String> debugLogs = [];

  ReownAppKitModal? get appKitModal => _appKitModal;

  bool _isDisposed = false;

  void _addLog(String msg) {
    if (_isDisposed) {
      debugPrint('[WALLET_LOG_DISPOSED] $msg');
      return;
    }
    final time = DateTime.now().toString().split('.').first.split(' ').last;
    final log = '[$time] $msg';
    debugLogs.add(log);
    if (debugLogs.length > 50) debugLogs.removeAt(0);
    debugPrint('[WALLET_LOG] $log');
    try {
      notifyListeners();
    } catch (e) {
      debugPrint('Error notifying listeners: $e');
    }
  }

  Future<void> init(BuildContext context) async {
    if (_appKitModal != null) return;

    _addLog('🚀 初始化 Reown AppKit...');

    _appKitModal = ReownAppKitModal(
      context: context,
      projectId: _projectId,
      metadata: const PairingMetadata(
        name: 'RiverBit',
        description: 'RiverBit Decentralized Exchange',
        url: 'https://riverbit.io',
        icons: ['https://riverbit.io/logo.png'],
        redirect: Redirect(
          native: 'riverbit://app',
          universal: 'https://riverbit.io',
        ),
      ),
      // 使用 optionalNamespaces 来定义支持的链和方法
      optionalNamespaces: {
        'eip155': RequiredNamespace(
          chains: ['eip155:1', 'eip155:56', 'eip155:137'], // ETH, BSC, Polygon
          methods: [
            'eth_sendTransaction',
            'personal_sign',
            'eth_signTypedData',
          ],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
      featuredWalletIds: {
        '971e689d0a5be527bac7963d4c458d9a0921431f928a0d0d500c1e6b911ef3661', // OKX Wallet
        'f2436c67184f4d050659f0ade8361f2238491c6e1847f9f30325f69085805561', // Binance Web3 Wallet
      },
    );

    await _appKitModal!.init();

    _appKitModal!.addListener(_onModalStateChanged);
    _addLog('✅ Reown AppKit 初始化完成');
    notifyListeners();
  }

  void _onModalStateChanged() {
    _addLog('🔄 模态框状态变更: isConnected=$isConnected');
    // 💡 修正方法名：从 closeModalView 改为 closeModal
    if (isConnected && (_appKitModal?.isOpen ?? false)) {
      _addLog('✅ 检测到连接成功，正在自动关闭等待模态框...');
      _appKitModal?.closeModal();
    }
    notifyListeners();
  }

  Future<void> connect(BuildContext context) async {
    if (_appKitModal == null) {
      await init(context);
    }
    _addLog('📱 唤起钱包连接模态框...');
    _appKitModal!.openModalView();
  }

  Future<void> disconnect() async {
    if (_appKitModal != null) {
      _addLog('🔌 正在断开连接...');
      await _appKitModal!.disconnect();
      _addLog('✅ 已断开连接');
    }
  }

  Future<List<Map<String, String>>> getTokenBalances() async {
    final addr = address;
    if (!isConnected || _appKitModal?.selectedChain == null || addr == null) return [];
    
    try {
      final rpcUrl = _appKitModal!.selectedChain!.rpcUrl;
      final client = Web3Client(rpcUrl, http.Client());
      final ownAddress = EthereumAddress.fromHex(addr);
      
      final balance = await client.getBalance(ownAddress);
      final value = balance.getValueInUnit(EtherUnit.ether).toStringAsFixed(4);
      final symbol = _appKitModal!.selectedChain!.currency;
      
      await client.dispose();
      return [{'symbol': symbol, 'balance': value}];
    } catch (e) {
      _addLog('❌ 获取余额失败: $e');
      return [];
    }
  }

  // 辅助方法：强制唤起钱包
  Future<void> _triggerWalletJump() async {
    try {
      _addLog('📲 正在尝试手动唤起钱包...');
      
      // 1. 尝试使用 SDK 推荐方式
      _appKitModal?.launchConnectedWallet();
      
      // 2. 检查是否有 Peer Metadata 中的原生协议
      final redirect = _appKitModal?.session?.peer?.metadata.redirect;
      if (redirect?.native != null) {
        final uri = Uri.parse(redirect!.native!);
        _addLog('🔗 尝试使用原生协议跳转: $uri');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _addLog('⚠️ 唤起钱包尝试结束: $e');
    }
  }

  // 签名消息
  Future<String?> personalSign(String message) async {
    final addr = address;
    if (!isConnected || _appKitModal == null || addr == null) {
      _addLog('❌ 无法签名: 钱包未连接');
      return null;
    }
    
    final session = _appKitModal!.session;
    if (session == null || session.topic == null) {
      _addLog('❌ 无法签名: 会话无效');
      return null;
    }

    try {
      _addLog('✍️ 发起签名请求...');
      final hexMsg = '0x${hex.encode(utf8.encode(message))}';
      _addLog('📝 签名内容: $message ($hexMsg)');

      // 1. 发起请求（注意：这里不立即 await，为了能紧接着触发跳转）
      final requestFuture = _appKitModal!.request(
        topic: session.topic!,
        chainId: _appKitModal!.selectedChain!.chainId,
        request: SessionRequestParams(
          method: 'personal_sign',
          params: [hexMsg, addr],
        ),
      );

      // 2. 立即触发跳转逻辑（包裹在 try-catch 中防止崩溃）
      await _triggerWalletJump();

      // 3. 等待签名结果
      _addLog('⏳ 等待钱包响应 (请在钱包中完成操作)...');
      final result = await requestFuture;
      
      _addLog('✅ 签名成功');
      return result.toString();
    } catch (e) {
      _addLog('❌ 签名失败 (详细信息): $e');
      // 如果报错包含 CanNotLaunchUrl，说明自动跳转失败了，但不代表请求没发出去
      if (e.toString().contains('CanNotLaunchUrl')) {
        _addLog('💡 提示: 无法自动唤起钱包，请手动切换到钱包进行确认。');
      }
      return null;
    }
  }

  // 发送交易
  Future<String?> sendTransaction({
    required String to,
    required String valueInWei,
  }) async {
    final addr = address;
    if (!isConnected || _appKitModal == null || addr == null) return null;
    try {
      _addLog('💸 发起转账请求...');
      final requestFuture = _appKitModal!.request(
        topic: _appKitModal!.session!.topic!,
        chainId: _appKitModal!.selectedChain!.chainId,
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [
            {
              'from': addr,
              'to': to,
              'value': '0x${BigInt.parse(valueInWei).toRadixString(16)}',
            },
          ],
        ),
      );

      // 触发跳转
      await _triggerWalletJump();

      final result = await requestFuture;
      _addLog('✅ 交易已发送: $result');
      return result.toString();
    } catch (e) {
      _addLog('❌ 交易失败: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _appKitModal?.removeListener(_onModalStateChanged);
    super.dispose();
  }
}
