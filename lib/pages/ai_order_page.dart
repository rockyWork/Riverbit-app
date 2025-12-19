import 'dart:async';
import 'package:flutter/material.dart';
import '../components/custom_app_bar.dart';

/// GenUI 渲染引擎：将指令映射为高性能原生组件
class GenUIRenderer extends StatelessWidget {
  final Map<String, dynamic> payload;
  final Function(Map<String, dynamic>)? onAction;

  const GenUIRenderer({super.key, required this.payload, this.onAction});

  @override
  Widget build(BuildContext context) {
    final String componentType = payload['type'] ?? 'unknown';
    final Map<String, dynamic> data = payload['data'] ?? {};

    switch (componentType) {
      case 'AgentOrderForm':
        return _AgentOrderFormWidget(data: data, onAction: onAction);
      case 'OrderSuccessCard':
        return _OrderSuccessCardWidget(data: data);
      default:
        return const SizedBox.shrink();
    }
  }
}

class AiOrderPage extends StatefulWidget {
  const AiOrderPage({super.key});

  @override
  State<AiOrderPage> createState() => _AiOrderPageState();
}

class _AiOrderPageState extends State<AiOrderPage> with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  
  final List<Map<String, dynamic>> _messages = [
    {
      'role': 'ai',
      'content': '你好！我是 RiverBit AI 助手。长按麦克风说出您的交易策略，说完后再松开。',
    },
  ];

  bool _isAiThinking = false;
  bool _isRecording = false;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- 优化后的语音交互逻辑 ---

  void _onVoiceStart(LongPressStartDetails details) {
    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
    });
    // 可以在这里加入震动反馈 HapticFeedback.mediumImpact();
  }

  void _onVoiceEnd(LongPressEndDetails details) {
    if (!_isRecording) return;
    
    final duration = DateTime.now().difference(_recordingStartTime!);
    setState(() => _isRecording = false);

    // 如果按住时间太短（小于500ms），认为是误触
    if (duration.inMilliseconds < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('说话时间太短'), duration: Duration(milliseconds: 1000)),
      );
      return;
    }

    // 模拟语音转文字逻辑
    _addLog('正在识别语音...');
    Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _chatController.text = '帮我用 20 倍杠杆做多 BTC';
      _handleSendMessage();
    });
  }

  void _addLog(String msg) {
    debugPrint('[VOICE_LOG] $msg');
  }

  void _handleSendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _chatController.clear();
      _isAiThinking = true;
    });
    _scrollToBottom();

    Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _isAiThinking = false;
        
        Map<String, dynamic> genUiInstruction = {
          'type': 'AgentOrderForm',
          'data': {
            'symbol': text.contains('ETH') ? 'ETH/USDT' : 'BTC/USDT',
            'side': (text.contains('空') || text.contains('卖') || text.contains('Short')) ? 'Short' : 'Long',
            'leverage': text.contains('50') ? 50.0 : 20.0,
            'amount': '0.15',
          }
        };

        _messages.add({
          'role': 'ai',
          'content': '我已根据您的语音指令生成了下单 Agent，请审阅。',
          'gen_ui': genUiInstruction,
        });
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'AI 下单 Agent', centerTitle: true, showCloseButton: true),
      backgroundColor: const Color(0xFFF0F2F5),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_isAiThinking ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) return _buildAiThinking();
                    return _buildMessageItem(_messages[index]);
                  },
                ),
              ),
              _buildInputBar(),
            ],
          ),
          // 录音状态全屏覆盖提示（类似微信）
          if (_isRecording) _buildRecordingOverlay(),
        ],
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.2).animate(_pulseController),
                child: const Icon(Icons.mic, color: Colors.white, size: 64),
              ),
              const SizedBox(height: 16),
              const Text('正在聆听...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('松开手指 结束录音', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    bool isAi = msg['role'] == 'ai';
    return Column(
      crossAxisAlignment: isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAi ? Colors.white : Colors.blue.shade600,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
          ),
          child: Text(msg['content'], style: TextStyle(color: isAi ? Colors.black87 : Colors.white)),
        ),
        if (msg['gen_ui'] != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: GenUIRenderer(
              payload: msg['gen_ui'],
              onAction: (actionData) {
                setState(() {
                  _messages.add({
                    'role': 'ai',
                    'content': 'Agent 订单执行成功！',
                    'gen_ui': {'type': 'OrderSuccessCard', 'data': actionData}
                  });
                });
                _scrollToBottom();
              },
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(
        children: [
          // 优化后的长按按钮
          GestureDetector(
            onLongPressStart: _onVoiceStart,
            onLongPressEnd: _onVoiceEnd,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _isRecording ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 10 * _pulseController.value,
                        spreadRadius: 5 * _pulseController.value,
                      )
                    ] : [],
                  ),
                  child: CircleAvatar(
                    backgroundColor: _isRecording ? Colors.red.shade400 : Colors.blue.shade50,
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.white : Colors.blue,
                    ),
                  ),
                );
              }
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(24)),
              child: TextField(
                controller: _chatController,
                decoration: const InputDecoration(
                  hintText: '按住说话或直接输入...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSendMessage(),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.send, color: Colors.blue), onPressed: _handleSendMessage),
        ],
      ),
    );
  }

  Widget _buildAiThinking() {
    return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)));
  }
}

/// 核心组件：可交互的 Agent 下单面板
class _AgentOrderFormWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Function(Map<String, dynamic>)? onAction;

  const _AgentOrderFormWidget({required this.data, this.onAction});

  @override
  State<_AgentOrderFormWidget> createState() => _AgentOrderFormWidgetState();
}

class _AgentOrderFormWidgetState extends State<_AgentOrderFormWidget> {
  late String selectedSymbol;
  late String selectedSide;
  late double leverage;
  late TextEditingController amountController;

  final List<String> symbols = ['BTC/USDT', 'ETH/USDT', 'SOL/USDT', 'BNB/USDT'];

  @override
  void initState() {
    super.initState();
    selectedSymbol = widget.data['symbol'] ?? 'BTC/USDT';
    selectedSide = widget.data['side'] ?? 'Long';
    leverage = (widget.data['leverage'] as num?)?.toDouble() ?? 20.0;
    amountController = TextEditingController(text: widget.data['amount']?.toString() ?? '0.1');
  }

  @override
  Widget build(BuildContext context) {
    bool isLong = selectedSide == 'Long';
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue, size: 16),
              SizedBox(width: 8),
              Text('AI 提取的下单 Agent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          
          _buildFormRow('交易对', DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedSymbol,
              dropdownColor: const Color(0xFF111A2E),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              items: symbols.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => selectedSymbol = v!),
            ),
          )),

          _buildFormRow('方向', Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSideBtn('Long', isLong),
              const SizedBox(width: 8),
              _buildSideBtn('Short', !isLong),
            ],
          )),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('杠杆倍数', style: TextStyle(color: Colors.white60, fontSize: 13)),
              Text('${leverage.toInt()}x', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: leverage,
            min: 1,
            max: 100,
            activeColor: Colors.blue,
            inactiveColor: Colors.white12,
            onChanged: (v) => setState(() => leverage = v),
          ),

          _buildFormRow('数量 (BTC)', SizedBox(
            width: 80,
            child: TextField(
              controller: amountController,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              keyboardType: TextInputType.number,
            ),
          )),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => widget.onAction?.call({
                'symbol': selectedSymbol,
                'side': selectedSide,
                'leverage': leverage.toInt(),
                'amount': amountController.text,
              }),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('确认并创建 Agent', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSideBtn(String label, bool active) {
    Color activeColor = label == 'Long' ? Colors.green : Colors.red;
    return GestureDetector(
      onTap: () => setState(() => selectedSide = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFormRow(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          trailing,
        ],
      ),
    );
  }
}

class _OrderSuccessCardWidget extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OrderSuccessCardWidget({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 40),
          const SizedBox(height: 12),
          const Text('下单成功', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
          const SizedBox(height: 8),
          Text('Agent 已执行: ${data['symbol']} ${data['side']} (${data['leverage']}x)', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}
