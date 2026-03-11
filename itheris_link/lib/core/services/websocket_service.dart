// ============================================================================
// WEBSOCKET SERVICE - Real-time Thought Events Stream
// Listens for "Thought Events" from the Kernel's ReflectionEngine
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:rxdart/rxdart.dart';

import 'kernel_connector.dart';
import '../models/kernel_message.dart';

/// Stream of incoming kernel messages
class KernelMessageStream {
  final BehaviorSubject<KernelMessage> _subject = BehaviorSubject<KernelMessage>();
  
  Stream<KernelMessage> get stream => _subject.stream;
  
  void add(KernelMessage message) {
    _subject.add(message);
  }
  
  void dispose() {
    _subject.close();
  }
}

/// WebSocket service for real-time communication with the Kernel
/// Handles thought events, reflections, and authorization requests
class WebSocketService {
  final KernelConnector kernelConnector;
  
  // Streams
  final KernelMessageStream _messageStream = KernelMessageStream();
  final BehaviorSubject<List<ThoughtEvent>> _thoughtEventsSubject = 
      BehaviorSubject<List<ThoughtEvent>>.seeded([]);
  final BehaviorSubject<List<AuthorizationRequest>> _authRequestsSubject = 
      BehaviorSubject<List<AuthorizationRequest>>.seeded([]);
  final BehaviorSubject<List<Reflection>> _reflectionsSubject = 
      BehaviorSubject<List<Reflection>>.seeded([]);
  
  // Stream controllers for outgoing messages
  final StreamController<KernelMessage> _outgoingController = 
      StreamController<KernelMessage>.broadcast();
  
  Timer? _reconnectTimer;
  bool _isInitialized = false;
  
  // -------------------------------------------------------------------------
  // Public Streams
  // -------------------------------------------------------------------------
  
  /// Stream of all kernel messages
  Stream<KernelMessage> get messages => _messageStream.stream;
  
  /// Stream of thought events (typewriter effect)
  Stream<List<ThoughtEvent>> get thoughtEvents => _thoughtEventsSubject.stream;
  
  /// Stream of authorization requests
  Stream<List<AuthorizationRequest>> get authorizationRequests => 
      _authRequestsSubject.stream;
  
  /// Stream of reflections
  Stream<List<Reflection>> get reflections => _reflectionsSubject.stream;
  
  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  
  WebSocketService({
    required this.kernelConnector,
  });
  
  // -------------------------------------------------------------------------
  // Public Methods
  // -------------------------------------------------------------------------
  
  /// Initialize the WebSocket service and connect to the Kernel
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Set up message callback
    kernelConnector.setMessageCallback(_handleKernelMessage);
    kernelConnector.setStatusCallback(_handleConnectionStatus);
    
    // Connect to kernel
    await kernelConnector.connect();
    
    _isInitialized = true;
  }
  
  /// Send a thought/query to the Kernel
  Future<bool> sendThought(String content) async {
    final message = KernelMessage(
      type: KernelMessageType.command,
      sessionId: kernelConnector.sessionId ?? '',
      timestamp: DateTime.now(),
      payload: {
        'action': 'process_thought',
        'content': content,
      },
    );
    
    return kernelConnector.sendCommand(message.payload);
  }
  
  /// Send authorization response
  Future<bool> sendAuthorizationResponse({
    required String requestId,
    required bool authorized,
    String? reason,
  }) async {
    final message = KernelMessage(
      type: KernelMessageType.command,
      sessionId: kernelConnector.sessionId ?? '',
      timestamp: DateTime.now(),
      payload: {
        'action': 'authorization_response',
        'request_id': requestId,
        'authorized': authorized,
        'reason': reason,
      },
    );
    
    return kernelConnector.sendCommand(message.payload);
  }
  
  /// Send a command to the Kernel
  Future<bool> sendCommand(Map<String, dynamic> command) async {
    return kernelConnector.sendCommand(command);
  }
  
  /// Get current thought events
  List<ThoughtEvent> get currentThoughtEvents => _thoughtEventsSubject.value;
  
  /// Get current authorization requests
  List<AuthorizationRequest> get currentAuthRequests => 
      _authRequestsSubject.value;
  
  /// Clear all thought events
  void clearThoughtEvents() {
    _thoughtEventsSubject.add([]);
  }
  
  /// Dispose the service
  void dispose() {
    _messageStream.dispose();
    _thoughtEventsSubject.close();
    _authRequestsSubject.close();
    _reflectionsSubject.close();
    _outgoingController.close();
    _reconnectTimer?.cancel();
  }
  
  // -------------------------------------------------------------------------
  // Private Handlers
  // -------------------------------------------------------------------------
  
  void _handleKernelMessage(KernelMessage message) {
    // Add to main stream
    _messageStream.add(message);
    
    // Process based on type
    switch (message.type) {
      case KernelMessageType.thoughtEvent:
        _handleThoughtEvent(message);
        break;
        
      case KernelMessageType.authorizationRequest:
        _handleAuthorizationRequest(message);
        break;
        
      case KernelMessageType.reflection:
        _handleReflection(message);
        break;
        
      case KernelMessageType.command:
        // Handle command responses
        break;
        
      default:
        break;
    }
  }
  
  void _handleConnectionStatus(ConnectionStatus status) {
    if (status == ConnectionStatus.authenticated) {
      _isInitialized = true;
    } else if (status == ConnectionStatus.disconnected) {
      _isInitialized = false;
    }
  }
  
  void _handleThoughtEvent(KernelMessage message) {
    final payload = message.payload;
    final event = ThoughtEvent(
      id: payload['id'] as String? ?? '',
      content: payload['content'] as String? ?? '',
      type: _parseThoughtType(payload['thought_type'] as String?),
      progress: (payload['progress'] as num?)?.toDouble() ?? 0.0,
      timestamp: message.timestamp,
      isComplete: payload['is_complete'] as bool? ?? false,
    );
    
    // Update thought events list
    final currentEvents = List<ThoughtEvent>.from(_thoughtEventsSubject.value);
    
    // Check if this is an update to existing event
    final existingIndex = currentEvents.indexWhere((e) => e.id == event.id);
    if (existingIndex >= 0) {
      currentEvents[existingIndex] = event;
    } else {
      currentEvents.add(event);
    }
    
    _thoughtEventsSubject.add(currentEvents);
  }
  
  void _handleAuthorizationRequest(KernelMessage message) {
    final payload = message.payload;
    final request = AuthorizationRequest(
      id: payload['id'] as String? ?? '',
      title: payload['title'] as String? ?? 'Authorization Request',
      description: payload['description'] as String? ?? '',
      riskAssessment: (payload['risk_assessment'] as num?)?.toDouble() ?? 0.0,
      requestedAction: payload['requested_action'] as String? ?? '',
      timestamp: message.timestamp,
      requiresAuthorization: true,
    );
    
    // Update authorization requests list
    final currentRequests = List<AuthorizationRequest>.from(
      _authRequestsSubject.value,
    );
    currentRequests.insert(0, request);
    _authRequestsSubject.add(currentRequests);
  }
  
  void _handleReflection(KernelMessage message) {
    final payload = message.payload;
    final reflection = Reflection(
      id: payload['id'] as String? ?? '',
      content: payload['content'] as String? ?? '',
      type: _parseReflectionType(payload['reflection_type'] as String?),
      confidence: (payload['confidence'] as num?)?.toDouble() ?? 0.0,
      timestamp: message.timestamp,
    );
    
    // Update reflections list
    final currentReflections = List<Reflection>.from(_reflectionsSubject.value);
    currentReflections.insert(0, reflection);
    _reflectionsSubject.add(currentReflections);
  }
  
  ThoughtType _parseThoughtType(String? type) {
    switch (type) {
      case 'reasoning':
        return ThoughtType.reasoning;
      case 'analysis':
        return ThoughtType.analysis;
      case 'planning':
        return ThoughtType.planning;
      case 'reflection':
        return ThoughtType.reflection;
      case 'decision':
        return ThoughtType.decision;
      default:
        return ThoughtType.reasoning;
    }
  }
  
  ReflectionType _parseReflectionType(String? type) {
    switch (type) {
      case 'self':
        return ReflectionType.self;
      case 'context':
        return ReflectionType.context;
      case 'learning':
        return ReflectionType.learning;
      default:
        return ReflectionType.self;
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Type of thought event
enum ThoughtType {
  reasoning,
  analysis,
  planning,
  reflection,
  decision,
}

/// Thought event from the Kernel's ReflectionEngine
class ThoughtEvent {
  final String id;
  final String content;
  final ThoughtType type;
  final double progress;
  final DateTime timestamp;
  final bool isComplete;
  
  const ThoughtEvent({
    required this.id,
    required this.content,
    required this.type,
    required this.progress,
    required this.timestamp,
    required this.isComplete,
  });
  
  ThoughtEvent copyWith({
    String? id,
    String? content,
    ThoughtType? type,
    double? progress,
    DateTime? timestamp,
    bool? isComplete,
  }) {
    return ThoughtEvent(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      progress: progress ?? this.progress,
      timestamp: timestamp ?? this.timestamp,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

/// Authorization request from the Kernel
class AuthorizationRequest {
  final String id;
  final String title;
  final String description;
  final double riskAssessment;
  final String requestedAction;
  final DateTime timestamp;
  final bool requiresAuthorization;
  final bool? isAuthorized;
  
  const AuthorizationRequest({
    required this.id,
    required this.title,
    required this.description,
    required this.riskAssessment,
    required this.requestedAction,
    required this.timestamp,
    required this.requiresAuthorization,
    this.isAuthorized,
  });
  
  AuthorizationRequest copyWith({
    String? id,
    String? title,
    String? description,
    double? riskAssessment,
    String? requestedAction,
    DateTime? timestamp,
    bool? requiresAuthorization,
    bool? isAuthorized,
  }) {
    return AuthorizationRequest(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      riskAssessment: riskAssessment ?? this.riskAssessment,
      requestedAction: requestedAction ?? this.requestedAction,
      timestamp: timestamp ?? this.timestamp,
      requiresAuthorization: requiresAuthorization ?? this.requiresAuthorization,
      isAuthorized: isAuthorized ?? this.isAuthorized,
    );
  }
  
  bool get isHighRisk => riskAssessment > 0.5;
}

/// Type of reflection
enum ReflectionType {
  self,
  context,
  learning,
}

/// Reflection from the Kernel's metacognition
class Reflection {
  final String id;
  final String content;
  final ReflectionType type;
  final double confidence;
  final DateTime timestamp;
  
  const Reflection({
    required this.id,
    required this.content,
    required this.type,
    required this.confidence,
    required this.timestamp,
  });
}
