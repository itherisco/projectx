// ============================================================================
// AUTHORIZATION BLOC - Business Logic for Authority Center
// ============================================================================

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/services/websocket_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/service_locator.dart';

// -------------------------------------------------------------------------
// Events
// -------------------------------------------------------------------------

abstract class AuthorizationEvent extends Equatable {
  const AuthorizationEvent();
  
  @override
  List<Object?> get props => [];
}

class InitializeAuthorization extends AuthorizationEvent {}

class AuthorizationRequestReceived extends AuthorizationEvent {
  final AuthorizationRequest request;
  
  const AuthorizationRequestReceived(this.request);
  
  @override
  List<Object?> get props => [request];
}

class AuthorizeRequest extends AuthorizationEvent {
  final String requestId;
  final String? reason;
  
  const AuthorizeRequest({required this.requestId, this.reason});
  
  @override
  List<Object?> get props => [requestId, reason];
}

class DenyRequest extends AuthorizationEvent {
  final String requestId;
  final String? reason;
  
  const DenyRequest({required this.requestId, this.reason});
  
  @override
  List<Object?> get props => [requestId, reason];
}

class DismissRequest extends AuthorizationEvent {
  final String requestId;
  
  const DismissRequest(this.requestId);
  
  @override
  List<Object?> get props => [requestId];
}

// -------------------------------------------------------------------------
// States
// -------------------------------------------------------------------------

abstract class AuthorizationState extends Equatable {
  const AuthorizationState();
  
  @override
  List<Object?> get props => [];
}

class AuthorizationInitial extends AuthorizationState {}

class AuthorizationLoading extends AuthorizationState {}

class AuthorizationActive extends AuthorizationState {
  final List<AuthorizationRequest> pendingRequests;
  final List<AuthorizationRequest> processedRequests;
  
  const AuthorizationActive({
    this.pendingRequests = const [],
    this.processedRequests = const [],
  });
  
  int get pendingCount => pendingRequests.length;
  
  AuthorizationActive copyWith({
    List<AuthorizationRequest>? pendingRequests,
    List<AuthorizationRequest>? processedRequests,
  }) {
    return AuthorizationActive(
      pendingRequests: pendingRequests ?? this.pendingRequests,
      processedRequests: processedRequests ?? this.processedRequests,
    );
  }
  
  @override
  List<Object?> get props => [pendingRequests, processedRequests];
}

class AuthorizationError extends AuthorizationState {
  final String message;
  
  const AuthorizationError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// -------------------------------------------------------------------------
// BLoC
// -------------------------------------------------------------------------

class AuthorizationBloc extends Bloc<AuthorizationEvent, AuthorizationState> {
  final WebSocketService webSocketService;
  final NotificationService _notificationService = NotificationService();
  StreamSubscription? _authRequestsSubscription;
  
  AuthorizationBloc({
    required this.webSocketService,
  }) : super(AuthorizationInitial()) {
    on<InitializeAuthorization>(_onInitialize);
    on<AuthorizationRequestReceived>(_onRequestReceived);
    on<AuthorizeRequest>(_onAuthorize);
    on<DenyRequest>(_onDeny);
    on<DismissRequest>(_onDismiss);
  }
  
  Future<void> _onInitialize(
    InitializeAuthorization event,
    Emitter<AuthorizationState> emit,
  ) async {
    emit(AuthorizationLoading());
    
    try {
      // Initialize notification service
      await _notificationService.initialize();
      
      // Subscribe to authorization requests
      _authRequestsSubscription = webSocketService.authorizationRequests.listen(
        (requests) {
          // Filter pending requests
          final pending = requests.where((r) => r.requiresAuthorization).toList();
          
          if (state is AuthorizationActive) {
            final currentState = state as AuthorizationActive;
            emit(currentState.copyWith(pendingRequests: pending));
            
            // Show notification for high-risk requests
            for (final request in pending) {
              if (request.isHighRisk) {
                _notificationService.showAuthorizationRequestNotification(
                  id: request.id,
                  title: request.title,
                  body: request.description,
                  riskAssessment: request.riskAssessment,
                );
              }
            }
          }
        },
      );
      
      emit(const AuthorizationActive());
    } catch (e) {
      emit(AuthorizationError(e.toString()));
    }
  }
  
  void _onRequestReceived(
    AuthorizationRequestReceived event,
    Emitter<AuthorizationState> emit,
  ) {
    if (state is! AuthorizationActive) return;
    
    final currentState = state as AuthorizationActive;
    final updatedPending = [event.request, ...currentState.pendingRequests];
    
    emit(currentState.copyWith(pendingRequests: updatedPending));
    
    // Show push notification for high-risk
    if (event.request.isHighRisk) {
      _notificationService.showAuthorizationRequestNotification(
        id: event.request.id,
        title: event.request.title,
        body: event.request.description,
        riskAssessment: event.request.riskAssessment,
      );
    }
  }
  
  Future<void> _onAuthorize(
    AuthorizeRequest event,
    Emitter<AuthorizationState> emit,
  ) async {
    if (state is! AuthorizationActive) return;
    
    final currentState = state as AuthorizationActive;
    
    // Send authorization to kernel
    await webSocketService.sendAuthorizationResponse(
      requestId: event.requestId,
      authorized: true,
      reason: event.reason,
    );
    
    // Update request status
    final updatedPending = currentState.pendingRequests
        .where((r) => r.id != event.requestId)
        .toList();
    
    final processedRequest = currentState.pendingRequests
        .firstWhere((r) => r.id == event.requestId)
        .copyWith(isAuthorized: true);
    
    final updatedProcessed = [processedRequest, ...currentState.processedRequests];
    
    emit(currentState.copyWith(
      pendingRequests: updatedPending,
      processedRequests: updatedProcessed,
    ));
  }
  
  Future<void> _onDeny(
    DenyRequest event,
    Emitter<AuthorizationState> emit,
  ) async {
    if (state is! AuthorizationActive) return;
    
    final currentState = state as AuthorizationActive;
    
    // Send denial to kernel
    await webSocketService.sendAuthorizationResponse(
      requestId: event.requestId,
      authorized: false,
      reason: event.reason,
    );
    
    // Update request status
    final updatedPending = currentState.pendingRequests
        .where((r) => r.id != event.requestId)
        .toList();
    
    final processedRequest = currentState.pendingRequests
        .firstWhere((r) => r.id == event.requestId)
        .copyWith(isAuthorized: false);
    
    final updatedProcessed = [processedRequest, ...currentState.processedRequests];
    
    emit(currentState.copyWith(
      pendingRequests: updatedPending,
      processedRequests: updatedProcessed,
    ));
  }
  
  void _onDismiss(
    DismissRequest event,
    Emitter<AuthorizationState> emit,
  ) {
    if (state is! AuthorizationActive) return;
    
    final currentState = state as AuthorizationActive;
    final updatedPending = currentState.pendingRequests
        .where((r) => r.id != event.requestId)
        .toList();
    
    emit(currentState.copyWith(pendingRequests: updatedPending));
  }
  
  @override
  Future<void> close() {
    _authRequestsSubscription?.cancel();
    _notificationService.dispose();
    return super.close();
  }
}
