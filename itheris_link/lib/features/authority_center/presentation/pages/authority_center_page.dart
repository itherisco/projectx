// ============================================================================
// AUTHORITY CENTER - Authorization Requests with Swipe Actions
// Swipe Right to Authorize, Swipe Left to Deny
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/itheris_theme.dart';
import '../../../../core/services/websocket_service.dart';
import '../bloc/authorization_bloc.dart';

// -------------------------------------------------------------------------
// Authority Center Page
// -------------------------------------------------------------------------

class AuthorityCenterPage extends StatefulWidget {
  final String? initialRequestId;
  
  const AuthorityCenterPage({
    super.key,
    this.initialRequestId,
  });

  @override
  State<AuthorityCenterPage> createState() => _AuthorityCenterPageState();
}

class _AuthorityCenterPageState extends State<AuthorityCenterPage> {
  final CardSwiperController _swiperController = CardSwiperController();
  
  @override
  void initState() {
    super.initState();
    // Initialize authorization
    context.read<AuthorizationBloc>().add(InitializeAuthorization());
  }

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

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
                color: ItherisTheme.warningColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.gavel,
                size: 16,
                color: ItherisTheme.warningColor,
              ),
            ),
            const SizedBox(width: 12),
            const Text('AUTHORITY CENTER'),
          ],
        ),
      ),
      body: BlocBuilder<AuthorizationBloc, AuthorizationState>(
        builder: (context, state) {
          if (state is AuthorizationLoading) {
            return const Center(
              child: CircularProgressIndicator(
                color: ItherisTheme.warningColor,
              ),
            );
          }
          
          if (state is AuthorizationError) {
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
                  ),
                ],
              ),
            );
          }
          
          if (state is AuthorizationActive) {
            if (state.pendingRequests.isEmpty) {
              return _buildEmptyState();
            }
            
            return _buildAuthorizationCards(state.pendingRequests);
          }
          
          return _buildEmptyState();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ItherisTheme.surfaceColor,
              border: Border.all(
                color: ItherisTheme.successColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.verified_user,
              size: 48,
              color: ItherisTheme.successColor,
            ),
          ).animate().scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1, 1),
            duration: 500.ms,
            curve: Curves.elasticOut,
          ),
          const SizedBox(height: 32),
          const Text(
            'ALL CLEAR',
            style: TextStyle(
              color: ItherisTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No pending authorization requests',
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.swipe,
                  size: 16,
                  color: ItherisTheme.textTertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Swipe right to authorize, left to deny',
                  style: TextStyle(
                    color: ItherisTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorizationCards(List<AuthorizationRequest> requests) {
    return Column(
      children: [
        // Header with pending count
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ItherisTheme.warningColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.pending_actions,
                      size: 16,
                      color: ItherisTheme.warningColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${requests.length} PENDING',
                      style: const TextStyle(
                        color: ItherisTheme.warningColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Swipe instructions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSwipeHint(
                icon: Icons.close,
                label: 'DENY',
                color: ItherisTheme.errorColor,
                alignment: Alignment.centerLeft,
              ),
              _buildSwipeHint(
                icon: Icons.check,
                label: 'AUTHORIZE',
                color: ItherisTheme.successColor,
                alignment: Alignment.centerRight,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Swipeable cards
        Expanded(
          child: CardSwiper(
            controller: _swiperController,
            cardsCount: requests.length,
            numberOfCardsDisplayed: requests.length.clamp(1, 3),
            backCardOffset: const Offset(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            onSwipe: (previousIndex, currentIndex, direction) {
              final request = requests[previousIndex];
              
              if (direction == CardSwiperDirection.right) {
                // Authorize
                context.read<AuthorizationBloc>().add(
                  AuthorizeRequest(requestId: request.id),
                );
                _showFeedbackSnackbar(true);
              } else if (direction == CardSwiperDirection.left) {
                // Deny
                context.read<AuthorizationBloc>().add(
                  DenyRequest(requestId: request.id),
                );
                _showFeedbackSnackbar(false);
              }
              
              return true;
            },
            cardBuilder: (context, index, horizontalOffsetPercentage, verticalOffsetPercentage) {
              final request = requests[index];
              return _AuthorizationCard(request: request);
            },
          ),
        ),
        
        // Action buttons
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _swiperController.swipe(CardSwiperDirection.left);
                },
                icon: const Icon(Icons.close),
                label: const Text('DENY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ItherisTheme.errorColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _swiperController.swipe(CardSwiperDirection.right);
                },
                icon: const Icon(Icons.check),
                label: const Text('AUTHORIZE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ItherisTheme.successColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeHint({
    required IconData icon,
    required String label,
    required Color color,
    required Alignment alignment,
  }) {
    return Row(
      children: [
        if (alignment == Alignment.centerRight) ...[
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        if (alignment == Alignment.centerLeft) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ],
    );
  }

  void _showFeedbackSnackbar(bool authorized) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              authorized ? Icons.check_circle : Icons.cancel,
              color: authorized ? ItherisTheme.successColor : ItherisTheme.errorColor,
            ),
            const SizedBox(width: 12),
            Text(
              authorized ? 'AUTHORIZED' : 'DENIED',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: authorized ? ItherisTheme.successColor : ItherisTheme.errorColor,
              ),
            ),
          ],
        ),
        backgroundColor: ItherisTheme.surfaceColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Authorization Card Widget
// -------------------------------------------------------------------------

class _AuthorizationCard extends StatelessWidget {
  final AuthorizationRequest request;
  
  const _AuthorizationCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ItherisTheme.cardColor,
            ItherisTheme.surfaceColor,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _getRiskColor().withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: _getRiskColor().withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with risk indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getRiskColor().withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.security,
                    color: _getRiskColor(),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AUTHORIZATION REQUEST',
                        style: TextStyle(
                          color: ItherisTheme.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.title,
                        style: const TextStyle(
                          color: ItherisTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Risk assessment gauge
            _buildRiskGauge(),
            
            const SizedBox(height: 24),
            
            // Description
            const Text(
              'DESCRIPTION',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  request.description,
                  style: const TextStyle(
                    color: ItherisTheme.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ItherisTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bolt,
                    color: ItherisTheme.primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.requestedAction,
                      style: const TextStyle(
                        color: ItherisTheme.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.access_time,
                  size: 12,
                  color: ItherisTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(request.timestamp),
                  style: TextStyle(
                    color: ItherisTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskGauge() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RISK ASSESSMENT',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getRiskColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(request.riskAssessment * 100).toInt()}%',
                style: TextStyle(
                  color: _getRiskColor(),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: request.riskAssessment,
            backgroundColor: ItherisTheme.surfaceColor,
            valueColor: AlwaysStoppedAnimation(_getRiskColor()),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LOW',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 8,
              ),
            ),
            Text(
              'MEDIUM',
              style: TextStyle(
                color: ItherisTheme.textTertiary,
                fontSize: 8,
              ),
            ),
            Text(
              'HIGH',
              style: TextStyle(
                color: ItherisTheme.errorColor,
                fontSize: 8,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getRiskColor() {
    if (request.riskAssessment > 0.8) return ItherisTheme.errorColor;
    if (request.riskAssessment > 0.6) return Colors.orange;
    if (request.riskAssessment > 0.4) return ItherisTheme.warningColor;
    return ItherisTheme.successColor;
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
