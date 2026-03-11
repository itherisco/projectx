// ============================================================================
// NOTIFICATION SERVICE - Push Notifications & Risk Alerts
// Handles notifications for authorization requests and high-risk events
// ============================================================================

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/kernel_message.dart';

/// Notification service for handling push notifications
class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  bool _isInitialized = false;
  final StreamController<NotificationResponse> _notificationResponseController =
      StreamController<NotificationResponse>.broadcast();
  
  // -------------------------------------------------------------------------
  // Public Stream
  // -------------------------------------------------------------------------
  
  Stream<NotificationResponse> get onNotificationTap =>
      _notificationResponseController.stream;
  
  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------
  
  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    
    _isInitialized = true;
  }
  
  /// Request notification permissions
  Future<bool> requestPermissions() async {
    // Request Android notification permission
    final android = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    
    // Request iOS notification permission
    final ios = await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    
    return android ?? ios ?? false;
  }
  
  // -------------------------------------------------------------------------
  // Notification Methods
  // -------------------------------------------------------------------------
  
  /// Show authorization request notification
  Future<void> showAuthorizationRequestNotification({
    required String id,
    required String title,
    required String body,
    required double riskAssessment,
  }) async {
    // Only show notification for high-risk requests
    if (riskAssessment <= 0.5) return;
    
    final androidDetails = AndroidNotificationDetails(
      'authorization_requests',
      'Authorization Requests',
      channelDescription: 'Notifications for authorization requests',
      importance: Importance.high,
      priority: Priority.high,
      color: _getRiskColor(riskAssessment),
      category: AndroidNotificationCategory.alarm,
      styleInformation: BigTextStyleInformation(body),
      actions: [
        const AndroidNotificationAction(
          'authorize',
          'AUTHORIZE',
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'deny',
          'DENY',
          showsUserInterface: true,
        ),
      ],
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      id.hashCode,
      title,
      body,
      details,
      payload: 'auth_request:$id',
    );
  }
  
  /// Show emergency halt notification
  Future<void> showEmergencyHaltNotification() async {
    final androidDetails = AndroidNotificationDetails(
      'emergency_alerts',
      'Emergency Alerts',
      channelDescription: 'Critical emergency notifications',
      importance: Importance.max,
      priority: Priority.max,
      color: const Color(0xFFFF0000),
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      0,
      '🛑 EMERGENCY HALT',
      'Emergency halt signal sent to Kernel',
      details,
    );
  }
  
  /// Show thought event notification
  Future<void> showThoughtEventNotification({
    required String id,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'thought_events',
      'Thought Events',
      channelDescription: 'Real-time thought events from the Kernel',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: const Color(0xFF00D4FF),
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      id.hashCode,
      title,
      body,
      details,
      payload: 'thought_event:$id',
    );
  }
  
  /// Show connection status notification
  Future<void> showConnectionNotification({
    required bool isConnected,
    String? sessionId,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'connection_status',
      'Connection Status',
      channelDescription: 'Kernel connection status updates',
      importance: Importance.low,
      priority: Priority.low,
      color: isConnected ? const Color(0xFF00FF88) : const Color(0xFFFF4444),
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      999,
      isConnected ? '🟢 Connected' : '🔴 Disconnected',
      isConnected 
          ? 'Session: ${sessionId?.substring(0, 8) ?? "N/A"}...'
          : 'Attempting to reconnect...',
      details,
    );
  }
  
  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }
  
  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
  
  // -------------------------------------------------------------------------
  // Private Methods
  // -------------------------------------------------------------------------
  
  void _handleNotificationResponse(NotificationResponse response) {
    _notificationResponseController.add(response);
  }
  
  Color _getRiskColor(double risk) {
    if (risk > 0.8) return const Color(0xFFFF0000);
    if (risk > 0.6) return const Color(0xFFFF6600);
    return const Color(0xFFFFAA00);
  }
  
  /// Dispose the service
  void dispose() {
    _notificationResponseController.close();
  }
}

/// Notification response model
class NotificationResponse {
  final String? payload;
  final String? actionId;
  
  NotificationResponse({
    this.payload,
    this.actionId,
  });
}

// Import for Color
import 'dart:ui';
