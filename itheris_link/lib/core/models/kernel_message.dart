// ============================================================================
// KERNEL MESSAGE - Core message model for Kernel communication
// ============================================================================

import 'package:equatable/equatable.dart';

/// Type of kernel message
enum KernelMessageType {
  thoughtEvent,
  authorizationRequest,
  heartbeat,
  emergencyHalt,
  command,
  reflection,
}

/// Kernel message model for WebSocket communication
class KernelMessage extends Equatable {
  final KernelMessageType type;
  final String sessionId;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  
  const KernelMessage({
    required this.type,
    required this.sessionId,
    required this.timestamp,
    required this.payload,
  });
  
  /// Create from JSON
  factory KernelMessage.fromJson(Map<String, dynamic> json) {
    return KernelMessage(
      type: KernelMessageTypeExtension.fromString(json['type'] as String),
      sessionId: json['session_id'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? 
          DateTime.now(),
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }
  
  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'session_id': sessionId,
      'timestamp': timestamp.toIso8601String(),
      'payload': payload,
    };
  }
  
  @override
  List<Object?> get props => [type, sessionId, timestamp, payload];
}

/// Extension for KernelMessageType
extension KernelMessageTypeExtension on KernelMessageType {
  String get value {
    switch (this) {
      case KernelMessageType.thoughtEvent:
        return 'thought_event';
      case KernelMessageType.authorizationRequest:
        return 'authorization_request';
      case KernelMessageType.heartbeat:
        return 'heartbeat';
      case KernelMessageType.emergencyHalt:
        return 'emergency_halt';
      case KernelMessageType.command:
        return 'command';
      case KernelMessageType.reflection:
        return 'reflection';
    }
  }
  
  static KernelMessageType fromString(String value) {
    switch (value) {
      case 'thought_event':
        return KernelMessageType.thoughtEvent;
      case 'authorization_request':
        return KernelMessageType.authorizationRequest;
      case 'heartbeat':
        return KernelMessageType.heartbeat;
      case 'emergency_halt':
        return KernelMessageType.emergencyHalt;
      case 'command':
        return KernelMessageType.command;
      case 'reflection':
        return KernelMessageType.reflection;
      default:
        return KernelMessageType.command;
    }
  }
}
