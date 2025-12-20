import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart' as bip32;
import 'package:bech32/bech32.dart';
import 'package:web3dart/crypto.dart';

class RiverWallet {
  final String mnemonic;
  final Uint8List privateKey;
  final Uint8List publicKey;
  final String riverAddress;
  final String ethSignature;

  RiverWallet({
    required this.mnemonic,
    required this.privateKey,
    required this.publicKey,
    required this.riverAddress,
    required this.ethSignature,
  });
}

class RiverAddressService {
  // 验证签名格式是否为 65 字节（130 个十六进制字符）
  bool validateSignature(String signature) {
    final cleanSignature = _stripHexPrefix(signature);
    return cleanSignature.length == 130;
  }

  String _stripHexPrefix(String hex) {
    return hex.startsWith('0x') ? hex.substring(2) : hex;
  }

  Uint8List _hexToUint8Array(String hexStr) {
    return Uint8List.fromList(hex.decode(_stripHexPrefix(hexStr)));
  }

  // 核心逻辑：从签名生成 River 钱包
  Future<RiverWallet> generateRiverWallet(String signature) async {
    if (!validateSignature(signature)) {
      throw Exception('Invalid signature format: must be 65 bytes');
    }

    final buffer = _hexToUint8Array(signature);
    if (buffer.length != 65) {
      throw Exception('Signature must be 65 bytes');
    }

    // 1. 取前 64 字节 (R, S 值)
    final rsValues = buffer.sublist(0, 64);

    // 2. 计算 Keccak-256 哈希作为熵 (Entropy)
    final entropy = keccak256(rsValues);

    // 3. 将熵转换为助记词 (BIP39 24词规范)
    final mnemonic = bip39.entropyToMnemonic(hex.encode(entropy));

    // 4. 从助记词派生地址
    return deriveFromMnemonic(mnemonic, ethSignature: signature);
  }

  // 从助记词派生钱包信息
  RiverWallet deriveFromMnemonic(String mnemonic, {String ethSignature = ""}) {
    // 生成 Seed
    final seed = bip39.mnemonicToSeed(mnemonic);
    
    // HD Key 派生
    final root = bip32.BIP32.fromSeed(seed);
    final derived = root.derivePath("m/44'/118'/0'/0/0");

    if (derived.privateKey == null) {
      throw Exception('Failed to derive private key');
    }

    // 5. 公钥转 Bech32 地址
    // 这里的逻辑参考 React：去掉压缩公钥首字节 (0x02/0x03) 并非标准以太坊做法，
    // 但根据 React 代码：pubKeyWithoutPrefix = publicKey.slice(1)
    // 实际上通常以太坊使用的是非压缩公钥（65字节，去掉0x04后剩余64字节进行哈希）
    // React 代码中使用的 hdKey.publicKey 默认可能是压缩的。
    
    final publicKey = derived.publicKey;
    final riverAddress = _publicKeyToRiverAddress(publicKey);

    return RiverWallet(
      mnemonic: mnemonic,
      privateKey: derived.privateKey!,
      publicKey: publicKey,
      riverAddress: riverAddress,
      ethSignature: ethSignature,
    );
  }

  String _publicKeyToRiverAddress(Uint8List publicKey) {
    // React 逻辑：const pubKeyWithoutPrefix = publicKey.slice(1);
    // const keccakHash = keccak_256(pubKeyWithoutPrefix);
    // return keccakHash.slice(-20);
    
    final pubKeyWithoutPrefix = publicKey.sublist(1);
    final hash = keccak256(pubKeyWithoutPrefix);
    final rawAddress = hash.sublist(hash.length - 20);

    // Bech32 编码
    return _toBech32('river', rawAddress);
  }

  String _toBech32(String prefix, Uint8List data) {
    // 将 8-bit 数据转换为 5-bit words
    final words = _convertBits(data, 8, 5, true);
    return bech32.encode(Bech32(prefix, words));
  }

  // 内部工具函数：位转换
  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << to) - 1;
    for (var v in data) {
      if (v < 0 || (v >> from) != 0) {
        throw Exception('Invalid value: $v');
      }
      acc = (acc << from) | v;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) {
        result.add((acc << (to - bits)) & maxv);
      }
    } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }
    return result;
  }
}

