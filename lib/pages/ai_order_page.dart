import 'package:flutter/material.dart';
import '../components/custom_app_bar.dart';

class AiOrderPage extends StatelessWidget {
  const AiOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'AI 下单',
        centerTitle: true,
        showBackButton: true,
        showCloseButton: true, // 预留的 X 图标
      ),
      backgroundColor: const Color(0xFFF5F7F9),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_outlined, size: 80, color: Colors.blue.shade700),
            const SizedBox(height: 16),
            const Text(
              'AI 智能下单系统',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '正在开发中，敬请期待...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

