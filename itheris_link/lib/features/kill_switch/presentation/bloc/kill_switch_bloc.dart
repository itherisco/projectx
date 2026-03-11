// ============================================================================
// KILL SWITCH BLOC - Emergency Halt Control
// ============================================================================

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/services/kernel_connector.dart';
import '../../../../core/services/notification_service.dart';

// -------------------------------------------------------------------------
// Events
// -------------------------------------------------------------------------

abstract class KillSwitchEvent extends Equatable {
  const KillSwitchEvent();
  
  @override
  List<Object?> get props => [];
}

class TriggerEmergencyHalt extends KillSwitchEvent {}

class ResetKillSwitch extends KillSwitchEvent {}

class CheckKillSwitchStatus extends KillSwitchEvent {}

// -------------------------------------------------------------------------
// States
// -------------------------------------------------------------------------

abstract class KillSwitchState extends Equatable {
  const KillSwitchState();
  
  @override
  List<Object?> get props => [];
}

class KillSwitchIdle extends KillSwitchState {}

class KillSwitchEngaged extends KillSwitchState {
  final DateTime engagedAt;
  
  const KillSwitchEngaged({required this.engagedAt});
  
  @override
  List<Object?> get props => [engagedAt];
}

class KillSwitchSending extends KillSwitchState {}

class KillSwitchError extends KillSwitchState {
  final String message;
  
  const KillSwitchError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// -------------------------------------------------------------------------
// BLoC
// -------------------------------------------------------------------------

class KillSwitchBloc extends Bloc<KillSwitchEvent, KillSwitchState> {
  final KernelConnector kernelConnector;
  final NotificationService _notificationService = NotificationService();
  
  KillSwitchBloc({
    required this.kernelConnector,
  }) : super(KillSwitchIdle()) {
    on<TriggerEmergencyHalt>(_onTriggerHalt);
    on<ResetKillSwitch>(_onReset);
    on<CheckKillSwitchStatus>(_onCheckStatus);
  }
  
  Future<void> _onTriggerHalt(
    TriggerEmergencyHalt event,
    Emitter<KillSwitchState> emit,
  ) async {
    emit(KillSwitchSending());
    
    try {
      // Send emergency halt signal
      final success = await kernelConnector.sendEmergencyHalt();
      
      if (success) {
        emit(KillSwitchEngaged(engagedAt: DateTime.now()));
        
        // Show notification
        await _notificationService.showEmergencyHaltNotification();
      } else {
        emit(const KillSwitchError('Failed to send emergency halt signal'));
      }
    } catch (e) {
      emit(KillSwitchError(e.toString()));
    }
  }
  
  void _onReset(
    ResetKillSwitch event,
    Emitter<KillSwitchState> emit,
  ) {
    emit(KillSwitchIdle());
  }
  
  void _onCheckStatus(
    CheckKillSwitchStatus event,
    Emitter<KillSwitchState> emit,
  ) {
    // Check if kernel is still connected
    if (!kernelConnector.isConnected) {
      emit(KillSwitchIdle());
    }
  }
  
  @override
  Future<void> close() {
    _notificationService.dispose();
    return super.close();
  }
}
