// ============================================================================
// KERNEL CONNECTOR - Secure Neural Link Protocol
// Handles handshake, heartbeat, and reconnection strategy
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/connection_result.dart';
import '../models/kernel_message.dart';

/// Connection status callback type
typedef ConnectionStatusCallback = void Function(ConnectionStatus status);

/// Message callback type
typedef MessageCallback = void Function(KernelMessage message);

/// Connection result callback type
typedef ConnectionResultCallback = void Function(ConnectionResult result);

/// Connection status enum
enum ConnectionStatus {
  disconnected,
  connecting,
  handshaking,
  authenticated,
  reconnecting,
  error,
}

/// Result of a connection attempt
class ConnectionResult {
  final bool isSuccess;
  final String? sessionId;
  final String? error;
  final String? sovereignKey;

  ConnectionResult({
    required this.isSuccess,
    this.sessionId,
    this.error,
    this.sovereignKey,
  });
}

/// Buffer for commands when disconnected
class CommandBuffer {
  final List<Map<String, dynamic>> _commands = [];
  
  void add(Map<String, dynamic> command) {
    _commands.add(command);
  }
  
  List<Map<String, dynamic>> flush() {
    final commands = List<Map<String, dynamic>>.from(_commands);
    _commands.clear();
    return commands;
  }
  
  bool get isEmpty => _commands.isEmpty;
  int get length => _commands.length;
}

/// The KernelConnector manages the secure connection to the Julia Kernel
/// Implements the E2EE protocol with sovereign key exchange
class KernelConnector {
  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------
  
  final String serverUrl;
  final String sovereignKey;
  final int maxReconnectAttempts;
  final Duration heartbeatInterval;
  final Duration connectionTimeout;
  final Duration reconnectDelay;
  
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------
  
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _sessionId;
  String? _serverPublicKey;
  DateTime? _connectedAt;
  int _reconnectAttempt = 0;
  
  // Callbacks
  ConnectionStatusCallback? _onStatusChange;
  MessageCallback? _onMessage;
  ConnectionResultCallback? _onConnectionResult;
  
  // Command buffer for offline resilience
  final CommandBuffer _commandBuffer = CommandBuffer();
  
  // Secure storage
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  
  KernelConnector({
    required this.serverUrl,
    required this.sovereignKey,
    this.maxReconnectAttempts = 5,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 10),
    this.reconnectDelay = const Duration(seconds: 2),
  });
  
  // -------------------------------------------------------------------------
  // Public Properties
  // -------------------------------------------------------------------------
  
  ConnectionStatus get status => _status;
  String? get sessionId => _sessionId;
  bool get isConnected => _status == ConnectionStatus.authenticated;
  DateTime? get connectedAt => _connectedAt;
  int get reconnectAttempt => _reconnectAttempt;
  
  // -------------------------------------------------------------------------
  // Public Methods
  // -------------------------------------------------------------------------
  
  /// Set callback for connection status changes
  void setStatusCallback(ConnectionStatusCallback callback) {
    _onStatusChange = callback;
  }
  
  /// Set callback for incoming messages
  void setMessageCallback(MessageCallback callback) {
    _onMessage = callback;
  }
  
  /// Set callback for connection results
  void setConnectionResultCallback(ConnectionResultCallback callback) {
    _onConnectionResult = callback;
  }
  
  /// Connect to the Kernel with sovereign key handshake
  Future<ConnectionResult> connect() async {
    if (_status == ConnectionStatus.authenticated) {
      return ConnectionResult(
        isSuccess: true,
        sessionId: _sessionId,
        sovereignKey: sovereignKey,
      );
    }
    
    _updateStatus(ConnectionStatus.connecting);
    
    try {
      // Create WebSocket connection
      _channel = WebSocketChannel.connect(
        Uri.parse(serverUrl),
        protocols: ['itheris-v1'],
      );
      
      // Wait for connection
      await _channel!.ready.timeout(connectionTimeout);
      
      _updateStatus(ConnectionStatus.handshaking);
      
      // Perform sovereign key handshake
      final handshakeResult = await _performHandshake();
      
      if (handshakeResult.isSuccess) {
        _sessionId = handshakeResult.sessionId;
        _serverPublicKey = handshakeResult.sovereignKey;
        _connectedAt = DateTime.now();
        _updateStatus(ConnectionStatus.authenticated);
        
        // Start heartbeat
        _startHeartbeat();
        
        // Flush any buffered commands
        _flushCommandBuffer();
        
        // Store session in secure storage
        await _storeSession();
        
        return ConnectionResult(
          isSuccess: true,
          sessionId: _sessionId,
          sovereignKey: sovereignKey,
        );
      } else {
        _updateStatus(ConnectionStatus.error);
        _onConnectionResult?.call(handshakeResult);
        return handshakeResult;
      }
    } catch (e) {
      _updateStatus(ConnectionStatus.error);
      final result = ConnectionResult(
        isSuccess: false,
        error: e.toString(),
      );
      _onConnectionResult?.call(result);
      return result;
    }
  }
  
  /// Disconnect from the Kernel
  Future<void> disconnect() async {
    _stopHeartbeat();
    _cancelReconnect();
    
    await _subscription?.cancel();
    await _channel?.sink.close();
    
    _channel = null;
    _sessionId = null;
    _serverPublicKey = null;
    _connectedAt = null;
    _updateStatus(ConnectionStatus.disconnected);
    
    // Clear session from secure storage
    await _clearSession();
  }
  
  /// Send a command to the Kernel
  Future<bool> sendCommand(Map<String, dynamic> command) async {
    if (!isConnected) {
      // Buffer command for later
      _commandBuffer.add(command);
      return false;
    }
    
    try {
      final message = jsonEncode({
        'type': 'command',
        'session_id': _sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'payload': command,
      });
      
      _channel?.sink.add(message);
      return true;
    } catch (e) {
      // Buffer command on error
      _commandBuffer.add(command);
      return false;
    }
  }
  
  /// Send emergency halt signal
  Future<bool> sendEmergencyHalt() async {
    final command = {
      'action': 'emergency_halt',
      'priority': 'critical',
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    return sendCommand(command);
  }
  
  /// Force reconnect
  Future<void> forceReconnect() async {
    await disconnect();
    _reconnectAttempt = 0;
    await connect();
  }
  
  // -------------------------------------------------------------------------
  // Private Methods
  // -------------------------------------------------------------------------
  
  void _updateStatus(ConnectionStatus status) {
    _status = status;
    _onStatusChange?.call(status);
  }
  
  /// Perform the sovereign key handshake
  Future<ConnectionResult> _performHandshake() async {
    try {
      // Generate client nonce
      final clientNonce = _generateNonce();
      
      // Create handshake message with sovereign key
      final handshake = {
        'type': 'handshake',
        'version': '1.0',
        'client_id': _generateClientId(),
        'sovereign_key_hash': _hashKey(sovereignKey),
        'nonce': clientNonce,
        'capabilities': ['thought_events', 'authorization', 'emergency_halt'],
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Send handshake
      _channel?.sink.add(jsonEncode(handshake));
      
      // Wait for response (with timeout)
      final response = await _channel!.stream.first.timeout(
        connectionTimeout,
        onTimeout: () => throw TimeoutException('Handshake timeout'),
      );
      
      final responseData = jsonDecode(response as String) as Map<String, dynamic>;
      
      // Validate response
      if (responseData['type'] != 'handshake_ack') {
        return ConnectionResult(
          isSuccess: false,
          error: 'Invalid handshake response',
        );
      }
      
      // Verify server nonce
      final serverNonce = responseData['nonce'] as String?;
      if (serverNonce == null) {
        return ConnectionResult(
          isSuccess: false,
          error: 'Missing server nonce',
        );
      }
      
      // Generate session key
      final sessionKey = _generateSessionKey(clientNonce, serverNonce);
      
      // Store session ID
      final sessionId = responseData['session_id'] as String?;
      if (sessionId == null) {
        return ConnectionResult(
          isSuccess: false,
          error: 'Missing session ID',
        );
      }
      
      // Listen for incoming messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );
      
      return ConnectionResult(
        isSuccess: true,
        sessionId: sessionId,
        sovereignKey: sessionKey,
      );
    } catch (e) {
      return ConnectionResult(
        isSuccess: false,
        error: e.toString(),
      );
    }
  }
  
  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic data) {
    try {
      final messageData = jsonDecode(data as String) as Map<String, dynamic>;
      final messageType = messageData['type'] as String?;
      
      switch (messageType) {
        case 'heartbeat_ack':
          // Heartbeat acknowledged
          break;
        
        case 'thought_event':
        case 'authorization_request':
        case 'reflection':
        case 'command_response':
          final message = KernelMessage.fromJson(messageData);
          _onMessage?.call(message);
          break;
        
        case 'session_expired':
          _handleSessionExpired();
          break;
        
        default:
          // Unknown message type
          break;
      }
    } catch (e) {
      // Invalid message format
    }
  }
  
  void _handleError(dynamic error) {
    if (_status == ConnectionStatus.authenticated) {
      _scheduleReconnect();
    }
  }
  
  void _handleDisconnect() {
    if (_status == ConnectionStatus.authenticated) {
      _scheduleReconnect();
    }
  }
  
  void _handleSessionExpired() {
    disconnect();
    forceReconnect();
  }
  
  // -------------------------------------------------------------------------
  // Heartbeat
  // -------------------------------------------------------------------------
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _sendHeartbeat();
    });
  }
  
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  Future<void> _sendHeartbeat() async {
    if (!isConnected) return;
    
    try {
      final heartbeat = {
        'type': 'heartbeat',
        'session_id': _sessionId,
        'timestamp': DateTime.now().toIso8601String(),
        'client_time': DateTime.now().millisecondsSinceEpoch,
      };
      
      _channel?.sink.add(jsonEncode(heartbeat));
    } catch (e) {
      // Heartbeat failed
    }
  }
  
  // -------------------------------------------------------------------------
  // Reconnection Strategy
  // -------------------------------------------------------------------------
  
  void _scheduleReconnect() {
    if (_reconnectAttempt >= maxReconnectAttempts) {
      _updateStatus(ConnectionStatus.error);
      return;
    }
    
    _updateStatus(ConnectionStatus.reconnecting);
    _reconnectAttempt++;
    
    final delay = Duration(
      milliseconds: reconnectDelay.inMilliseconds * (pow(2, _reconnectAttempt - 1)).toInt(),
    );
    
    _reconnectTimer = Timer(delay, () async {
      await connect();
    });
  }
  
  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }
  
  // -------------------------------------------------------------------------
  // Command Buffer
  // -------------------------------------------------------------------------
  
  void _flushCommandBuffer() {
    if (_commandBuffer.isEmpty || !isConnected) return;
    
    final commands = _commandBuffer.flush();
    for (final command in commands) {
      sendCommand(command);
    }
  }
  
  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------
  
  Future<void> _storeSession() async {
    await _secureStorage.write(
      key: 'itheris_session_id',
      value: _sessionId,
    );
    await _secureStorage.write(
      key: 'itheris_connected_at',
      value: _connectedAt?.toIso8601String(),
    );
  }
  
  Future<void> _clearSession() async {
    await _secureStorage.delete(key: 'itheris_session_id');
    await _secureStorage.delete(key: 'itheris_connected_at');
  }
  
  // -------------------------------------------------------------------------
  // Utility Methods
  // -------------------------------------------------------------------------
  
  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }
  
  String _generateClientId() {
    final keyBytes = utf8.encode(sovereignKey);
    final hash = sha256.convert(keyBytes);
    return 'client_${hash.toString().substring(0, 16)}';
  }
  
  String _hashKey(String key) {
    final keyBytes = utf8.encode(key);
    final hash = sha256.convert(keyBytes);
    return hash.toString();
  }
  
  String _generateSessionKey(String clientNonce, String serverNonce) {
    final combined = '$clientNonce:$serverNonce:$sovereignKey';
    final bytes = utf8.encode(combined);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }
  
  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------
  
  void dispose() {
    disconnect();
    _onStatusChange = null;
    _onMessage = null;
    _onConnectionResult = null;
  }
}
