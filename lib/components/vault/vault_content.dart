import 'package:flutter/material.dart';
import 'wallet_info.dart';
import 'token_balances.dart';

class VaultContentWidget extends StatelessWidget {
  final String networkName;
  final String chainId;
  final List<Map<String, String>> tokenBalances;
  final String? address;

  const VaultContentWidget({
    super.key,
    required this.networkName,
    required this.chainId,
    required this.tokenBalances,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WalletInfoWidget(
            networkName: networkName,
            chainId: chainId,
            address: address,
          ),
          const SizedBox(height: 16),
          TokenBalancesWidget(
            tokenBalances: tokenBalances,
          ),
        ],
      ),
    );
  }
}

