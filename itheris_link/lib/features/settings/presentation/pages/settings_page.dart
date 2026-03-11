// ============================================================================
// SETTINGS PAGE - App Configuration
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/itheris_theme.dart';
import '../../../../main.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: ItherisTheme.surfaceColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.settings,
                size: 16,
                color: ItherisTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            const Text('SETTINGS'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Section
          _buildSectionHeader('CONNECTION'),
          _buildConnectionCard(),
          
          const SizedBox(height: 24),
          
          // Security Section
          _buildSectionHeader('SECURITY'),
          _buildSecurityCard(),
          
          const SizedBox(height: 24),
          
          // Notifications Section
          _buildSectionHeader('NOTIFICATIONS'),
          _buildNotificationCard(),
          
          const SizedBox(height: 24),
          
          // About Section
          _buildSectionHeader('ABOUT'),
          _buildAboutCard(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: ItherisTheme.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return BlocBuilder<KernelConnectionBloc, KernelConnectionState>(
      builder: (context, state) {
        return Container(
          decoration: BoxDecoration(
            color: ItherisTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getConnectionColor(state).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.wifi,
                    color: _getConnectionColor(state),
                  ),
                ),
                title: const Text(
                  'Kernel Connection',
                  style: TextStyle(color: ItherisTheme.textPrimary),
                ),
                subtitle: Text(
                  _getConnectionStatus(state),
                  style: TextStyle(
                    color: _getConnectionColor(state),
                    fontSize: 12,
                  ),
                ),
                trailing: _buildConnectionIndicator(state),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ItherisTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.link,
                    color: ItherisTheme.textSecondary,
                  ),
                ),
                title: const Text(
                  'Server URL',
                  style: TextStyle(color: ItherisTheme.textPrimary),
                ),
                subtitle: const Text(
                  'wss://kernel.itheris.ai/v1/stream',
                  style: TextStyle(
                    color: ItherisTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<KernelConnectionBloc>().add(
                            ConnectToKernel(),
                          );
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('RECONNECT'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<KernelConnectionBloc>().add(
                            DisconnectFromKernel(),
                          );
                        },
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('DISCONNECT'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ItherisTheme.errorColor,
                          side: const BorderSide(color: ItherisTheme.errorColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSecurityCard() {
    return Container(
      decoration: BoxDecoration(
        color: ItherisTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ItherisTheme.successColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock,
                color: ItherisTheme.successColor,
              ),
            ),
            title: const Text(
              'End-to-End Encryption',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'All communications are encrypted',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            value: true,
            onChanged: null, // Read-only
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ItherisTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.key,
                color: ItherisTheme.primaryColor,
              ),
            ),
            title: const Text(
              'Sovereign Key',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'Key exchange completed',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            value: true,
            onChanged: null, // Read-only
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    return Container(
      decoration: BoxDecoration(
        color: ItherisTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ItherisTheme.warningColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning,
                color: ItherisTheme.warningColor,
              ),
            ),
            title: const Text(
              'High Risk Alerts',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'Notify for risk_assessment > 0.5',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            value: true,
            onChanged: (value) {
              // Toggle notifications
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ItherisTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.psychology,
                color: ItherisTheme.primaryColor,
              ),
            ),
            title: const Text(
              'Thought Events',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'Show real-time thought notifications',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            value: false,
            onChanged: (value) {
              // Toggle notifications
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      decoration: BoxDecoration(
        color: ItherisTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: ItherisTheme.primaryGradient,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.neural_link,
                color: Colors.white,
              ),
            ),
            title: const Text(
              'Itheris Link',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'Version 1.0.0',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.code,
              color: ItherisTheme.textSecondary,
            ),
            title: const Text(
              'Built with Flutter',
              style: TextStyle(color: ItherisTheme.textPrimary),
            ),
            subtitle: const Text(
              'The Neural Interface Client',
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

  Widget _buildConnectionIndicator(KernelConnectionState state) {
    Color color = _getConnectionColor(state);
    
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Color _getConnectionColor(KernelConnectionState state) {
    if (state is KernelConnected) return ItherisTheme.successColor;
    if (state is KernelConnecting || state is KernelReconnecting) 
      return ItherisTheme.warningColor;
    return ItherisTheme.errorColor;
  }

  String _getConnectionStatus(KernelConnectionState state) {
    if (state is KernelConnected) {
      return 'Connected • Session: ${state.sessionId.substring(0, 8)}...';
    }
    if (state is KernelConnecting) return 'Connecting...';
    if (state is KernelReconnecting) return 'Reconnecting (${state.attempt}/${state.maxAttempts})...';
    if (state is KernelError) return 'Error: ${state.message}';
    return 'Disconnected';
  }
}
