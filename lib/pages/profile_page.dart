import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:convert/convert.dart';
import '../services/river_address_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final RiverAddressService _riverService = RiverAddressService();
  RiverWallet? _wallet;
  bool _isLoading = false;

  // 写死的签名数据
  final String _hardcodedSignature = "0x52fc8a10a5a1dfd0304d16dfc0c7c391d4f55040f8e29bb21ecdb12a9c030972428343c53bb36bbc1866d684b2310dcb407eee3c97df1b5f3128a62d227aef4e1c";

  @override
  void initState() {
    super.initState();
    _generateWallet();
  }

  Future<void> _generateWallet() async {
    setState(() => _isLoading = true);
    try {
      final wallet = await _riverService.generateRiverWallet(_hardcodedSignature);
      setState(() => _wallet = wallet);
    } catch (e) {
      debugPrint('生成 River 钱包失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              )
            else if (_wallet != null)
              _buildWalletInfo()
            else
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('暂无钱包信息，请检查签名格式'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.orange.shade700],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 80, // 设置底座固定宽度
            height: 80, // 设置底座固定高度
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(8.0), // 在圆形内留出一点边距，更美观
                child: SvgPicture.asset(
                  'lib/aseat/images/logo-Riverbit.svg',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain, // 改为 contain，确保图标完整且不超出
                  placeholderBuilder: (context) => const Icon(Icons.person, size: 40, color: Colors.orange),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'RiverBit User',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text(
            'RiverChain Wallet',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'RiverChain 地址',
            _wallet!.riverAddress,
            Icons.account_balance_wallet,
          ),
          _buildInfoCard(
            '助记词 (24 Words)',
            _wallet!.mnemonic,
            Icons.vpn_key,
            isLongText: true,
          ),
          _buildInfoCard(
            '私钥 (Private Key)',
            hex.encode(_wallet!.privateKey),
            Icons.security,
            isSensitive: true,
          ),
          _buildInfoCard(
            '公钥 (Public Key)',
            hex.encode(_wallet!.publicKey),
            Icons.remove_red_eye,
            isSensitive: true,
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _generateWallet,
              icon: const Icon(Icons.refresh),
              label: const Text('重新生成'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, {bool isSensitive = false, bool isLongText = false}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                  onPressed: () => _copyToClipboard(value, title),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: isSensitive ? Colors.red.shade700 : Colors.black54,
                ),
                maxLines: isLongText ? 5 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
