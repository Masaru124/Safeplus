import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/safety_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/safety_utils.dart';

/// Pulse Report Card
///
/// Displays a single report with voting buttons.
/// Shows time since report, feeling level, reason, and optional description.
/// Voting is calm, civic, and anonymous.
class ReportCard extends StatefulWidget {
  final String reportId;
  final DateTime createdAt;
  final String feelingLevel;
  final String reason;
  final String? description;
  final bool hasUserVoted;
  final bool isUserReport;
  final bool? userVote;
  final VoidCallback? onVoted; // Callback when vote is cast
  final VoidCallback? onDeleted; // Callback when report is deleted

  const ReportCard({
    super.key,
    required this.reportId,
    required this.createdAt,
    required this.feelingLevel,
    required this.reason,
    this.description,
    required this.hasUserVoted,
    required this.isUserReport,
    this.userVote,
    this.onVoted,
    this.onDeleted,
  });

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  bool _isVoting = false;
  bool? _optimisticVote;
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final safetyProvider = context.watch<SafetyProvider>();
    final token = authProvider.token;

    // Determine card color based on feeling level
    final feelingColor = _getFeelingColor(widget.feelingLevel);
    final timeAgo = _formatTimeAgo(widget.createdAt);

    return Card(
      elevation: 2,
      color: Colors.white10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: feelingColor.withOpacity(0.3)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Time ago + Feeling level
            Row(
              children: [
                // Time ago
                Text(
                  timeAgo,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Spacer(),
                // Feeling level badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: feelingColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: feelingColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    widget.feelingLevel,
                    style: TextStyle(
                      color: feelingColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Reason
            Row(
              children: [
                Icon(
                  _getReasonIcon(widget.reason),
                  size: 18,
                  color: feelingColor,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.reason,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            // Description (if any)
            if (widget.description != null &&
                widget.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.description!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Voting section
            _buildVotingSection(token, safetyProvider),
            // Confirmation message
            if (widget.hasUserVoted && !widget.isUserReport) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Thanks for helping verify community safety.',
                  style: TextStyle(
                    color: Colors.green[300],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            // User's own report - show delete button
            if (widget.isUserReport) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'This is your report',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _isDeleting
                      ? null
                      : () => _handleDelete(context, token, safetyProvider),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                  label: Text(
                    _isDeleting ? 'Deleting...' : 'Delete',
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ),
            ],
            // Show hint for other reports
            if (!widget.isUserReport && !widget.hasUserVoted) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Vote to verify community safety',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVotingSection(String? token, SafetyProvider safetyProvider) {
    // Can't vote on own report
    if (widget.isUserReport) {
      return const SizedBox.shrink();
    }

    // Already voted
    if (widget.hasUserVoted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildVoteButton(
            icon: Icons.thumb_up,
            label: 'Accurate',
            isSelected: widget.userVote == true,
            color: Colors.green,
            isDisabled: true,
          ),
          const SizedBox(width: 16),
          _buildVoteButton(
            icon: Icons.thumb_down,
            label: 'Not accurate',
            isSelected: widget.userVote == false,
            color: Colors.red,
            isDisabled: true,
          ),
        ],
      );
    }

    // Not voted yet - show voting buttons
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isVoting
                ? null
                : () => _handleVote(true, token, safetyProvider),
            icon: const Icon(Icons.thumb_up_outlined, size: 18),
            label: const Text('This feels accurate'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              backgroundColor: Colors.green.withOpacity(0.1),
              side: BorderSide(color: Colors.green.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isVoting
                ? null
                : () => _handleVote(false, token, safetyProvider),
            icon: const Icon(Icons.thumb_down_outlined, size: 18),
            label: const Text('This seems false'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              backgroundColor: Colors.red.withOpacity(0.1),
              side: BorderSide(color: Colors.red.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required bool isDisabled,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? color : Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? color : Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? color : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleVote(
    bool isTrue,
    String? token,
    SafetyProvider safetyProvider,
  ) async {
    if (token == null) return;

    setState(() {
      _isVoting = true;
      _optimisticVote = isTrue;
    });

    try {
      // Call the API to vote
      safetyProvider.voteOnReport(
        signalId: widget.reportId,
        isTrue: isTrue,
        token: token,
      );

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Thanks for helping verify community safety.'),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );

        // Call the onVoted callback to refresh the list
        widget.onVoted?.call();
      }
    } catch (e) {
      // Rollback on failure
      setState(() {
        _isVoting = false;
        _optimisticVote = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to vote: ${e.toString()}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    String? token,
    SafetyProvider safetyProvider,
  ) async {
    if (token == null) return;

    // Show confirmation dialog
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
          'Are you sure you want to delete this report? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmDelete != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await safetyProvider.deleteReport(
        signalId: widget.reportId,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Call the onDeleted callback to refresh the list
        widget.onDeleted?.call();
      }
    } catch (e) {
      setState(() {
        _isDeleting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString()}'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  Color _getFeelingColor(String feelingLevel) {
    switch (feelingLevel) {
      case 'Very Unsafe':
        return const Color(0xFFDC2626);
      case 'Unsafe':
        return const Color(0xFFEF4444);
      case 'Moderate':
        return const Color(0xFFF97316);
      case 'Caution':
        return const Color(0xFFEAB308);
      case 'Calm':
        return const Color(0xFF22C55E);
      default:
        return Colors.grey;
    }
  }

  IconData _getReasonIcon(String reason) {
    switch (reason) {
      case 'Followed':
        return Icons.directions_walk;
      case 'Suspicious activity':
        return Icons.warning_amber;
      case 'Harassment':
        return Icons.report_problem;
      case 'Poor lighting':
        return Icons.light_mode;
      default:
        return Icons.info_outline;
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${difference.inDays ~/ 7} weeks ago';
  }
}

/// Empty state when no reports exist
class EmptyReportsState extends StatelessWidget {
  const EmptyReportsState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'No recent reports yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Reports in this area will appear here.\nTap on the map to share how a place felt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
