// ============================================================================
// ITHERIS LINK - Main Entry Point
// The Neural Interface Client for Itheris AI Kernel
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/services/service_locator.dart';
import 'core/services/kernel_connector.dart';
import 'core/services/websocket_service.dart';
import 'core/services/notification_service.dart';
import 'core/theme/itheris_theme.dart';

import 'features/the_stream/presentation/pages/stream_page.dart';
import 'features/the_stream/presentation/bloc/stream_bloc.dart';

import 'features/authority_center/presentation/pages/authority_center_page.dart';
import 'features/authority_center/presentation/bloc/authorization_bloc.dart';

import 'features/kill_switch/presentation/bloc/kill_switch_bloc.dart';
import 'features/settings/presentation/pages/settings_page.dart';

import 'core/models/kernel_message.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0E21),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  // Initialize services
  await _initializeServices();
  
  runApp(const ItherisLinkApp());
}

/// Initialize all core services before app starts
Future<void> _initializeServices() async {
  final serviceLocator = ServiceLocator.instance;
  
  // Register services
  await serviceLocator.registerLazySingleton<KernelConnector>(
    () => KernelConnector(
      serverUrl: 'wss://kernel.itheris.ai/v1/stream',
      sovereignKey: 'placeholder_key',
    ),
  );
  
  serviceLocator.registerLazySingleton<WebSocketService>(
    () => WebSocketService(
      kernelConnector: serviceLocator<KernelConnector>(),
    ),
  );
  
  serviceLocator.registerLazySingleton<NotificationService>(
    () => NotificationService(),
  );
}

/// Root Application Widget
class ItherisLinkApp extends StatelessWidget {
  const ItherisLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Kernel connection state
        BlocProvider<KernelConnectionBloc>(
          create: (_) => KernelConnectionBloc(
            kernelConnector: ServiceLocator.instance<KernelConnector>(),
          )..add(ConnectToKernel()),
        ),
        
        // Stream/Chat state
        BlocProvider<StreamBloc>(
          create: (_) => StreamBloc(
            webSocketService: ServiceLocator.instance<WebSocketService>(),
          ),
        ),
        
        // Authorization requests state
        BlocProvider<AuthorizationBloc>(
          create: (_) => AuthorizationBloc(
            webSocketService: ServiceLocator.instance<WebSocketService>(),
          ),
        ),
        
        // Kill switch state
        BlocProvider<KillSwitchBloc>(
          create: (_) => KillSwitchBloc(
            kernelConnector: ServiceLocator.instance<KernelConnector>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Itheris Link',
        debugShowCheckedModeBanner: false,
        theme: ItherisTheme.darkTheme,
        home: const NeuralLinkHome(),
        routes: {
          '/stream': (context) => const StreamPage(),
          '/authority': (context) => const AuthorityCenterPage(),
          '/settings': (context) => const SettingsPage(),
        },
        onGenerateRoute: (settings) {
          // Handle deep links from notifications
          if (settings.name?.startsWith('/auth-request:') ?? false) {
            final requestId = settings.name!.split(':').last;
            return MaterialPageRoute(
              builder: (_) => AuthorityCenterPage(initialRequestId: requestId),
            );
          }
          return null;
        },
      ),
    );
  }
}

/// Main Home Screen with Navigation
class NeuralLinkHome extends StatefulWidget {
  const NeuralLinkHome({super.key});

  @override
  State<NeuralLinkHome> createState() => _NeuralLinkHomeState();
}

class _NeuralLinkHomeState extends State<NeuralLinkHome> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late final AnimationController _connectionPulseController;
  late final Animation<double> _connectionPulseAnimation;

  final List<Widget> _pages = [
    const StreamPage(),
    const AuthorityCenterPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _connectionPulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _connectionPulseAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _connectionPulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _connectionPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: const KillSwitchFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildBottomNav() {
    return BlocBuilder<KernelConnectionBloc, KernelConnectionState>(
      builder: (context, state) {
        final isConnected = state is KernelConnected;
        final connectionColor = isConnected 
            ? Colors.green 
            : (state is KernelConnecting ? Colors.orange : Colors.red);

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0E21),
            border: Border(
              top: BorderSide(
                color: connectionColor.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    icon: Icons.psychology,
                    label: 'The Stream',
                    index: 0,
                  ),
                  _buildNavItem(
                    icon: Icons.gavel,
                    label: 'Authority',
                    index: 1,
                    badge: context.watch<AuthorizationBloc>().state.pendingCount,
                  ),
                  _buildNavItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    index: 2,
                  ),
                  // Connection indicator
                  AnimatedBuilder(
                    animation: _connectionPulseAnimation,
                    builder: (context, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: connectionColor.withOpacity(
                                  _connectionPulseAnimation.value,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: connectionColor.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getConnectionText(state),
                              style: TextStyle(
                                color: connectionColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    int badge = 0,
  }) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected 
                      ? const Color(0xFF00D4FF) 
                      : Colors.grey,
                  size: 24,
                ),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badge > 9 ? '9+' : badge.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00D4FF) : Colors.grey,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConnectionText(KernelConnectionState state) {
    if (state is KernelConnected) return 'ONLINE';
    if (state is KernelConnecting) return 'CONNECTING';
    if (state is KernelReconnecting) return 'RECONNECTING';
    return 'OFFLINE';
  }
}

// ============================================================================
// KILL SWITCH FAB - Emergency Halt Button
// ============================================================================

class KillSwitchFAB extends StatelessWidget {
  const KillSwitchFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KillSwitchBloc, KillSwitchState>(
      builder: (context, state) {
        final isEngaged = state is KillSwitchEngaged;
        
        return GestureDetector(
          onLongPress: () => _triggerEmergencyHalt(context),
          onDoubleTap: () => _triggerEmergencyHalt(context),
          child: FloatingActionButton(
            heroTag: 'kill_switch',
            backgroundColor: isEngaged 
                ? Colors.red.shade900 
                : const Color(0xFFFF0000),
            onPressed: () => _showConfirmation(context),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isEngaged 
                    ? Icons.power_off 
                    : Icons.emergency,
                key: ValueKey(isEngaged),
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'EMERGENCY HALT',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'This will send an immediate emergency_halt! signal to the Kernel.\n\n'
          'All cognitive processes will be suspended.\n\n'
          'Press again to confirm.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _triggerEmergencyHalt(context);
            },
            child: const Text('HALT'),
          ),
        ],
      ),
    );
  }

  void _triggerEmergencyHalt(BuildContext context) {
    context.read<KillSwitchBloc>().add(TriggerEmergencyHalt());
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.power_off, color: Colors.white),
            const SizedBox(width: 12),
            const Text(
              'EMERGENCY HALT SIGNAL SENT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade900,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ============================================================================
// MODELS
// ============================================================================

/// Kernel message types for WebSocket communication
enum KernelMessageType {
  thoughtEvent,
  authorizationRequest,
  heartbeat,
  emergencyHalt,
  command,
  reflection,
}

/// Extension for JSON serialization
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

/// Kernel connection states
abstract class KernelConnectionState extends Equatable {
  const KernelConnectionState();
  
  @override
  List<Object?> get props => [];
}

class KernelInitial extends KernelConnectionState {}

class KernelConnecting extends KernelConnectionState {}

class KernelConnected extends KernelConnectionState {
  final String sessionId;
  final DateTime connectedAt;
  
  const KernelConnected({
    required this.sessionId,
    required this.connectedAt,
  });
  
  @override
  List<Object?> get props => [sessionId, connectedAt];
}

class KernelReconnecting extends KernelConnectionState {
  final int attempt;
  final int maxAttempts;
  
  const KernelReconnecting({
    required this.attempt,
    required this.maxAttempts,
  });
  
  @override
  List<Object?> get props => [attempt, maxAttempts];
}

class KernelDisconnected extends KernelConnectionState {
  final String? reason;
  
  const KernelDisconnected({this.reason});
  
  @override
  List<Object?> get props => [reason];
}

class KernelError extends KernelConnectionState {
  final String message;
  
  const KernelError(this.message);
  
  @override
  List<Object?> get props => [message];
}

// ============================================================================
// BLOCs (Business Logic Components)
// ============================================================================

/// BLoC for managing kernel connection
class KernelConnectionBloc extends Bloc<KernelConnectionEvent, KernelConnectionState> {
  final KernelConnector kernelConnector;
  
  KernelConnectionBloc({
    required this.kernelConnector,
  }) : super(KernelInitial()) {
    on<ConnectToKernel>(_onConnect);
    on<DisconnectFromKernel>(_onDisconnect);
    on<KernelConnectionLost>(_onConnectionLost);
    on<KernelConnectionRestored>(_onConnectionRestored);
  }
  
  Future<void> _onConnect(
    ConnectToKernel event,
    Emitter<KernelConnectionState> emit,
  ) async {
    emit(KernelConnecting());
    
    try {
      final result = await kernelConnector.connect();
      
      if (result.isSuccess) {
        emit(KernelConnected(
          sessionId: result.sessionId!,
          connectedAt: DateTime.now(),
        ));
      } else {
        emit(KernelError(result.error ?? 'Connection failed'));
      }
    } catch (e) {
      emit(KernelError(e.toString()));
    }
  }
  
  Future<void> _onDisconnect(
    DisconnectFromKernel event,
    Emitter<KernelConnectionState> emit,
  ) async {
    await kernelConnector.disconnect();
    emit(const KernelDisconnected());
  }
  
  void _onConnectionLost(
    KernelConnectionLost event,
    Emitter<KernelConnectionState> emit,
  ) {
    emit(KernelReconnecting(
      attempt: event.attempt,
      maxAttempts: event.maxAttempts,
    ));
  }
  
  void _onConnectionRestored(
    KernelConnectionRestored event,
    Emitter<KernelConnectionState> emit,
  ) {
    emit(KernelConnected(
      sessionId: event.sessionId,
      connectedAt: event.connectedAt,
    ));
  }
}

// Events
abstract class KernelConnectionEvent extends Equatable {
  const KernelConnectionEvent();
  
  @override
  List<Object?> get props => [];
}

class ConnectToKernel extends KernelConnectionEvent {}

class DisconnectFromKernel extends KernelConnectionEvent {}

class KernelConnectionLost extends KernelConnectionEvent {
  final int attempt;
  final int maxAttempts;
  
  const KernelConnectionLost({
    required this.attempt,
    required this.maxAttempts,
  });
  
  @override
  List<Object?> get props => [attempt, maxAttempts];
}

class KernelConnectionRestored extends KernelConnectionEvent {
  final String sessionId;
  final DateTime connectedAt;
  
  const KernelConnectionRestored({
    required this.sessionId,
    required this.connectedAt,
  });
  
  @override
  List<Object?> get props => [sessionId, connectedAt];
}
