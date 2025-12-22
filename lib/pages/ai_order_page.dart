import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:genui_a2ui/genui_a2ui.dart';
import '../components/custom_app_bar.dart';

class AiOrderPage extends StatefulWidget {
  const AiOrderPage({super.key});

  @override
  State<AiOrderPage> createState() => _AiOrderPageState();
}

class _AiOrderPageState extends State<AiOrderPage> with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  late AnimationController _pulseController;
  
  // 1. 定义 A2UI 内容生成器
  late final A2uiContentGenerator _contentGenerator;
  // 2. 定义 GenUI 会话
  late final GenUiConversation _conversation;

  bool _isRecording = false;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // 初始化 A2UI 生成器
    _contentGenerator = A2uiContentGenerator(
      serverUrl: Uri.parse('wss://api.riverbit.ai/v1/a2a'), 
    );

    // 初始化目录 (Catalog)
    final catalog = Catalog([]);

    // 初始化 A2uiMessageProcessor
    final a2uiMessageProcessor = A2uiMessageProcessor(catalogs: [catalog]);

    // 初始化会话
    _conversation = GenUiConversation(
      contentGenerator: _contentGenerator,
      a2uiMessageProcessor: a2uiMessageProcessor,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _chatController.dispose();
    _conversation.dispose(); // 记得销毁会话
    super.dispose();
  }

  void _onVoiceStart(LongPressStartDetails details) {
    setState(() {
      _isRecording = true;
      _recordingStartTime = DateTime.now();
    });
  }

  void _onVoiceEnd(LongPressEndDetails details) {
    if (!_isRecording) return;
    
    final duration = DateTime.now().difference(_recordingStartTime!);
    setState(() => _isRecording = false);

    if (duration.inMilliseconds < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('说话时间太短'), duration: Duration(milliseconds: 1000)),
      );
      return;
    }

    _chatController.text = '帮我用 20 倍杠杆做多 BTC';
    _handleSendMessage();
  }

  void _handleSendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    // 3. 发送请求 (使用 UserMessage.text)
    _conversation.sendRequest(UserMessage.text(text));
    _chatController.clear();
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
                child: ValueListenableBuilder<List<ChatMessage>>(
                  valueListenable: _conversation.conversation,
                  builder: (context, messages, _) {
                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        if (message is UserMessage) {
                          return _buildUserMessage(message);
                        } else if (message is AiTextMessage) {
                          return _buildAiTextMessage(message);
                        } else if (message is AiUiMessage) {
                          return _buildAiUiMessage(message);
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  },
                ),
              ),
              _buildInputBar(),
            ],
          ),
          if (_isRecording) _buildRecordingOverlay(),
        ],
      ),
    );
  }

  Widget _buildUserMessage(UserMessage message) {
    return _buildChatBubble(message.text, isAi: false);
  }

  Widget _buildAiTextMessage(AiTextMessage message) {
    return _buildChatBubble(message.text, isAi: true);
  }

  Widget _buildAiUiMessage(AiUiMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: GenUiSurface(
        host: _conversation.host,
        surfaceId: message.surfaceId,
      ),
    );
  }

  Widget _buildChatBubble(String text, {required bool isAi}) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : Colors.blue.shade600,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
        ),
        child: Text(text, style: TextStyle(color: isAi ? Colors.black87 : Colors.white)),
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

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(
        children: [
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
}
