import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/safety_provider.dart';
import '../providers/auth_provider.dart';
import '../models/safety.dart';
import '../widgets/report_card.dart';

/// Report List Screen
///
/// Displays recent reports for a specific pulse location.
/// User can view reports and vote on them to verify community safety.
class ReportListScreen extends StatefulWidget {
  final double pulseLat;
  final double pulseLng;
  final int radius;

  const ReportListScreen({
    super.key,
    required this.pulseLat,
    required this.pulseLng,
    this.radius = 500,
  });

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<PulseReport> _reports = [];
  static const String _baseUrl = 'http://192.168.29.220:8000';

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in to view reports';
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('$_baseUrl/api/v1/reports/by-pulse').replace(
        queryParameters: {
          'lat': widget.pulseLat.toString(),
          'lng': widget.pulseLng.toString(),
          'radius': widget.radius.toString(),
          'time_window_hours': '2',
        },
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> reportsJson = data['reports'] ?? [];

        final reports = reportsJson
            .map((r) => PulseReport.fromJson(r))
            .toList();

        if (mounted) {
          setState(() {
            _reports = reports;
            _isLoading = false;
          });
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to fetch reports');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Recent Reports'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchReports,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Loading reports...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(
                'Unable to load reports',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return const EmptyReportsState();
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          return ReportCard(
            reportId: report.reportId,
            createdAt: report.createdAt,
            feelingLevel: report.feelingLevel,
            reason: report.reason,
            description: report.description,
            hasUserVoted: report.hasUserVoted,
            isUserReport: report.isUserReport,
            userVote: report.userVote,
            onVoted: _fetchReports, // Refresh list after voting
            onDeleted: _fetchReports, // Refresh list after deletion
          );
        },
      ),
    );
  }
}

/// Pulse Report model for the by-pulse endpoint
class PulseReport {
  final String reportId;
  final DateTime createdAt;
  final String feelingLevel;
  final String reason;
  final String? description;
  final bool hasUserVoted;
  final bool isUserReport;
  final bool? userVote;

  PulseReport({
    required this.reportId,
    required this.createdAt,
    required this.feelingLevel,
    required this.reason,
    this.description,
    required this.hasUserVoted,
    required this.isUserReport,
    this.userVote,
  });

  factory PulseReport.fromJson(Map<String, dynamic> json) {
    return PulseReport(
      reportId: json['report_id'] as String,
      createdAt:
          DateTime.tryParse(json['created_at'] as String ?? '') ??
          DateTime.now(),
      feelingLevel: json['feeling_level'] as String,
      reason: json['reason'] as String,
      description: json['description'] as String?,
      hasUserVoted: json['has_user_voted'] as bool,
      isUserReport: json['is_user_report'] as bool,
      userVote: json['user_vote'] as bool?,
    );
  }
}
