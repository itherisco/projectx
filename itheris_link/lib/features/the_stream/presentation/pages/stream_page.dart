// ============================================================================
// THE STREAM - Chat Interface with Real-time Thought Events
// Implements typewriter effect for thoughts, bubble effect for final answers
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/itheris_theme.dart';
import '../bloc/stream_bloc.dart';
import '../../../../core/services/websocket_service.dart';

// -------------------------------------------------------------------------
// Stream Page
// -------------------------------------------------------------------------

class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    // Initialize the stream
    context.read<StreamBloc>().add(InitializeStream());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ItherisTheme.primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: ItherisTheme.primaryColor.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Text('THE STREAM'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              context.read<StreamBloc>().add(ClearStream());
            },
            tooltip: 'Clear Stream',
          ),
        ],
      ),
      body: Column(
        children: [
          // Active Thoughts Display
          _buildActiveThoughtsSection(),
          
          // Chat Messages
          Expanded(
            child: _buildMessagesList(),
          ),
          
          // Input Area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildActiveThoughtsSection() {
    return BlocBuilder<StreamBloc, StreamState>(
      builder: (context, state) {
        if (state is! StreamActive || state.activeThoughts.isEmpty) {
          return const SizedBox.shrink();
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: ItherisTheme.surfaceColor.withOpacity(0.5),
            border: Border(
              bottom: BorderSide(
                color: ItherisTheme.primaryColor.withOpacity(0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.psychology,
                    size: 16,
                    color: ItherisTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ACTIVE THOUGHTS',
                    style: TextStyle(
                      color: ItherisTheme.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...state.activeThoughts.map((thought) => 
                _TypewriterThoughtBubble(thought: thought)
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesList() {
    return BlocConsumer<StreamBloc, StreamState>(
      listener: (context, state) {
        if (state is StreamActive) {
          _scrollToBottom();
        }
      },
      builder: (context, state) {
        if (state is StreamLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: ItherisTheme.primaryColor,
            ),
          );
        }
        
        if (state is StreamError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: ItherisTheme.errorColor,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  state.message,
                  style: const TextStyle(color: ItherisTheme.errorColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    context.read<StreamBloc>().add(InitializeStream());
                  },
                  child: const Text('RETRY'),
                ),
              ],
            ),
          );
        }
        
        if (state is StreamActive) {
          if (state.messages.isEmpty) {
            return _buildEmptyState();
          }
          
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.messages.length,
            itemBuilder: (context, index) {
              final message = state.messages[index];
              return _MessageBubble(
                message: message,
                key: ValueKey(message.id),
              );
            },
          );
        }
        
        return _buildEmptyState();
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology,
            size: 64,
            color: ItherisTheme.primaryColor.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'THE STREAM',
            style: TextStyle(
              color: ItherisTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your mind to the Kernel',
            style: TextStyle(
              color: ItherisTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: ItherisTheme.surfaceColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Send a thought to begin...',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ItherisTheme.surfaceColor,
        border: Border(
          top: BorderSide(
            color: ItherisTheme.primaryColor.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Enter your thought...',
                  hintStyle: TextStyle(
                    color: ItherisTheme.textTertiary,
                  ),
                  filled: true,
                  fillColor: ItherisTheme.cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                style: const TextStyle(
                  color: ItherisTheme.textPrimary,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: ItherisTheme.primaryGradient,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: IconButton(
                onPressed: () => _sendMessage(_messageController.text),
                icon: const Icon(
                  Icons.send,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String content) {
    if (content.trim().isEmpty) return;
    
    context.read<StreamBloc>().add(SendMessage(content.trim()));
    _messageController.clear();
    _focusNode.requestFocus();
  }
}

// -------------------------------------------------------------------------
// Message Bubble Widget
// -------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  
  const _MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: 
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: message.isUser 
                    ? const LinearGradient(
                        colors: ItherisTheme.primaryGradient,
                      )
                    : null,
                color: message.isUser ? null : ItherisTheme.cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(message.isUser ? 20 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (message.isUser 
                        ? ItherisTheme.primaryColor 
                        : ItherisTheme.cardColor).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: message.isUser 
                          ? Colors.white 
                          : ItherisTheme.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          color: message.isUser 
                              ? Colors.white70 
                              : ItherisTheme.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                      if (!message.isUser) ...[
                        const SizedBox(width: 8),
                        _buildStatusIndicator(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ).animate(
            key: ValueKey(message.id),
          ).fadeIn(duration: 300.ms).slideX(
            begin: message.isUser ? 0.1 : -0.1,
            end: 0,
            duration: 300.ms,
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            _buildAvatar(isUser: true),
          ],
        ],
      ),
    );
  }
  
  Widget _buildAvatar({bool isUser = false}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUser 
            ? const LinearGradient(colors: ItherisTheme.primaryGradient)
            : null,
        color: isUser ? null : ItherisTheme.secondaryColor,
      ),
      child: Icon(
        isUser ? Icons.person : Icons.psychology,
        color: Colors.white,
        size: 16,
      ),
    );
  }
  
  Widget _buildStatusIndicator() {
    IconData icon;
    Color color;
    
    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        color = ItherisTheme.textTertiary;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        color = ItherisTheme.successColor;
        break;
      case MessageStatus.complete:
        icon = Icons.done_all;
        color = ItherisTheme.primaryColor;
        break;
      case MessageStatus.error:
        icon = Icons.error_outline;
        color = ItherisTheme.errorColor;
        break;
    }
    
    return Icon(icon, size: 14, color: color);
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

// -------------------------------------------------------------------------
// Typewriter Thought Bubble
// -------------------------------------------------------------------------

class _TypewriterThoughtBubble extends StatefulWidget {
  final ThoughtEvent thought;
  
  const _TypewriterThoughtBubble({required this.thought});

  @override
  State<_TypewriterThoughtBubble> createState() => _TypewriterThoughtBubbleState();
}

class _TypewriterThoughtBubbleState extends State<_TypewriterThoughtBubble> {
  String _displayedText = '';
  Timer? _typewriterTimer;
  
  @override
  void initState() {
    super.initState();
    _startTypewriter();
  }
  
  @override
  void didUpdateWidget(covariant _TypewriterThoughtBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thought.content != widget.thought.content) {
      _displayedText = '';
      _startTypewriter();
    }
  }
  
  void _startTypewriter() {
    _typewriterTimer?.cancel();
    final text = widget.thought.content;
    
    int index = 0;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (index < text.length) {
        setState(() {
          _displayedText = text.substring(0, index + 1);
        });
        index++;
      } else {
        timer.cancel();
      }
    });
  }
  
  @override
  void dispose() {
    _typewriterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ItherisTheme.cardColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getThoughtTypeColor().withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getThoughtTypeIcon(),
                size: 12,
                color: _getThoughtTypeColor(),
              ),
              const SizedBox(width: 6),
              Text(
                _getThoughtTypeLabel(),
                style: TextStyle(
                  color: _getThoughtTypeColor(),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Progress indicator
              SizedBox(
                width: 50,
                child: LinearProgressIndicator(
                  value: widget.thought.progress,
                  backgroundColor: ItherisTheme.surfaceColor,
                  valueColor: AlwaysStoppedAnimation(_getThoughtTypeColor()),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(widget.thought.progress * 100).toInt()}%',
                style: TextStyle(
                  color: _getThoughtTypeColor(),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Typewriter text
          Text(
            _displayedText,
            style: const TextStyle(
              color: ItherisTheme.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          // Blinking cursor
          if (!widget.thought.isComplete)
            Container(
              width: 6,
              height: 14,
              color: _getThoughtTypeColor(),
            ).animate(
              onPlay: (controller) => controller.repeat(),
            ).fadeOut(duration: 500.ms),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
  
  IconData _getThoughtTypeIcon() {
    switch (widget.thought.type) {
      case ThoughtType.reasoning:
        return Icons.account_tree;
      case ThoughtType.analysis:
        return Icons.analytics;
      case ThoughtType.planning:
        return Icons.event_note;
      case ThoughtType.reflection:
        return Icons.self_improvement;
      case ThoughtType.decision:
        return Icons.gavel;
    }
  }
  
  Color _getThoughtTypeColor() {
    switch (widget.thought.type) {
      case ThoughtType.reasoning:
        return ItherisTheme.primaryColor;
      case ThoughtType.analysis:
        return ItherisTheme.secondaryColor;
      case ThoughtType.planning:
        return ItherisTheme.accentColor;
      case ThoughtType.reflection:
        return Colors.orange;
      case ThoughtType.decision:
        return Colors.pink;
    }
  }
  
  String _getThoughtTypeLabel() {
    switch (widget.thought.type) {
      case ThoughtType.reasoning:
        return 'REASONING';
      case ThoughtType.analysis:
        return 'ANALYSIS';
      case ThoughtType.planning:
        return 'PLANNING';
      case ThoughtType.reflection:
        return 'REFLECTION';
      case ThoughtType.decision:
        return 'DECISION';
    }
  }
}
