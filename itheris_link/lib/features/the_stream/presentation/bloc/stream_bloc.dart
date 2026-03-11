// ============================================================================
// STREAM BLOC - Business Logic for The Stream
// ============================================================================

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/services/websocket_service.dart';
import '../../../../core/services/service_locator.dart';

// -------------------------------------------------------------------------
// Events
// -------------------------------------------------------------------------

abstract class StreamEvent extends Equatable {
  const StreamEvent();
  
  @override
  List<Object?> get props => [];
}

class InitializeStream extends StreamEvent {}

class SendMessage extends StreamEvent {
  final String content;
  
  const SendMessage(this.content);
  
  @override
  List<Object?> get props => [content];
}

class ThoughtEventReceived extends StreamEvent {
  final ThoughtEvent event;
  
  const ThoughtEventReceived(this.event);
  
  @override
  List<Object?> get props => [event];
}

class ClearStream extends StreamEvent {}

// -------------------------------------------------------------------------
// States
// -------------------------------------------------------------------------

abstract class StreamState extends Equatable {
  const StreamState();
  
  @override
  List<Object?> get props => [];
}

class StreamInitial extends StreamState {}

class StreamLoading extends StreamState {}

class StreamActive extends StreamState {
  final List<ChatMessage> messages;
  final List<ThoughtEvent> activeThoughts;
  
  const StreamActive({
    this.messages = const [],
    this.activeThoughts = const [],
  });
  
  StreamActive copyWith({
    List<ChatMessage>? messages,
    List<ThoughtEvent>? activeThoughts,
  }) {
    return StreamActive(
      messages: messages ?? this.messages,
      activeThoughts: activeThoughts ?? this.activeThoughts,
    );
  }
  
  @override
  List<Object?> get props => [messages, activeThoughts];
}

class StreamError extends StreamState {
  final String message;
  
  const StreamError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// -------------------------------------------------------------------------
// Chat Message Model
// -------------------------------------------------------------------------

class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final MessageStatus status;
  
  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.sending,
  });
  
  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? timestamp,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }
}

enum MessageStatus {
  sending,
  sent,
  complete,
  error,
}

// -------------------------------------------------------------------------
// BLoC
// -------------------------------------------------------------------------

class StreamBloc extends Bloc<StreamEvent, StreamState> {
  final WebSocketService webSocketService;
  StreamSubscription? _thoughtEventsSubscription;
  
  StreamBloc({
    required this.webSocketService,
  }) : super(StreamInitial()) {
    on<InitializeStream>(_onInitialize);
    on<SendMessage>(_onSendMessage);
    on<ThoughtEventReceived>(_onThoughtEventReceived);
    on<ClearStream>(_onClearStream);
  }
  
  Future<void> _onInitialize(
    InitializeStream event,
    Emitter<StreamState> emit,
  ) async {
    emit(StreamLoading());
    
    try {
      // Initialize WebSocket service
      await webSocketService.initialize();
      
      // Subscribe to thought events
      _thoughtEventsSubscription = webSocketService.thoughtEvents.listen(
        (events) {
          // Filter active (incomplete) thoughts
          final activeThoughts = events.where((e) => !e.isComplete).toList();
          
          if (state is StreamActive) {
            // Update state with new thoughts
            final currentState = state as StreamActive;
            emit(currentState.copyWith(activeThoughts: activeThoughts));
          }
        },
      );
      
      emit(const StreamActive());
    } catch (e) {
      emit(StreamError(e.toString()));
    }
  }
  
  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<StreamState> emit,
  ) async {
    if (state is! StreamActive) return;
    
    final currentState = state as StreamActive;
    
    // Add user message
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: event.content,
      isUser: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
    );
    
    final updatedMessages = [...currentState.messages, userMessage];
    
    // Add placeholder for kernel response
    final kernelMessage = ChatMessage(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      content: '',
      isUser: false,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    
    emit(currentState.copyWith(
      messages: [...updatedMessages, kernelMessage],
    ));
    
    // Send thought to kernel
    await webSocketService.sendThought(event.content);
  }
  
  void _onThoughtEventReceived(
    ThoughtEventReceived event,
    Emitter<StreamState> emit,
  ) {
    if (state is! StreamActive) return;
    
    final currentState = state as StreamActive;
    
    // Update active thoughts
    final activeThoughts = List<ThoughtEvent>.from(currentState.activeThoughts);
    final existingIndex = activeThoughts.indexWhere((t) => t.id == event.event.id);
    
    if (existingIndex >= 0) {
      activeThoughts[existingIndex] = event.event;
    } else {
      activeThoughts.add(event.event);
    }
    
    // If thought is complete, update the last kernel message
    if (event.event.isComplete) {
      final messages = List<ChatMessage>.from(currentState.messages);
      if (messages.isNotEmpty && !messages.last.isUser) {
        messages[messages.length - 1] = messages.last.copyWith(
          content: event.event.content,
          status: MessageStatus.complete,
        );
      }
      
      // Remove from active thoughts
      activeThoughts.removeWhere((t) => t.id == event.event.id);
      
      emit(currentState.copyWith(
        messages: messages,
        activeThoughts: activeThoughts,
      ));
    } else {
      emit(currentState.copyWith(activeThoughts: activeThoughts));
    }
  }
  
  void _onClearStream(
    ClearStream event,
    Emitter<StreamState> emit,
  ) {
    emit(const StreamActive());
  }
  
  @override
  Future<void> close() {
    _thoughtEventsSubscription?.cancel();
    return super.close();
  }
}
