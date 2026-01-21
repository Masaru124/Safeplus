import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety.dart';

/// Enhanced Report Form with slider for severity and reason buttons
class EnhancedReportForm extends StatefulWidget {
  final Function(String category, int severity, String? description) onSubmit;
  final VoidCallback onCancel;
  final LatLng? location;

  const EnhancedReportForm({
    super.key,
    required this.onSubmit,
    required this.onCancel,
    this.location,
  });

  @override
  State<EnhancedReportForm> createState() => _EnhancedReportFormState();
}

class _EnhancedReportFormState extends State<EnhancedReportForm> {
  String _selectedCategory = 'felt-unsafe';
  int _severity = 3; // 1-5 scale
  final TextEditingController _descriptionController = TextEditingController();

  // Focus node for description field
  final FocusNode _descriptionFocus = FocusNode();

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategoryInfo = reportCategories.firstWhere(
      (cat) => cat['id'] == _selectedCategory,
    );
    final safetyLevel = selectedCategoryInfo['level'] as SafetyLevel;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    _getCategoryIcon(_selectedCategory),
                    color: Color(safetyColors[safetyLevel]!['main']!),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Report Safety Concern',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // "How unsafe did it feel?" slider
              _buildSeveritySlider(),
              const SizedBox(height: 20),

              // Category buttons
              _buildCategoryButtons(),
              const SizedBox(height: 20),

              // Selected category info
              _buildCategoryInfo(selectedCategoryInfo),
              const SizedBox(height: 16),

              // Optional description
              _buildDescriptionField(),
              const SizedBox(height: 24),

              // Submit button
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeveritySlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'How unsafe did it feel?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _getSeverityColor(_severity).withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getSeverityColor(_severity),
                  width: 1,
                ),
              ),
              child: Text(
                _getSeverityLabel(_severity),
                style: TextStyle(
                  color: _getSeverityColor(_severity),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 14,
              elevation: 4,
            ),
            activeTrackColor: _getSeverityColor(_severity),
            inactiveTrackColor: Colors.grey[300],
            thumbColor: _getSeverityColor(_severity),
            overlayColor: _getSeverityColor(_severity).withOpacity(0.2),
          ),
          child: Slider(
            value: _severity.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (value) {
              setState(() {
                _severity = value.toInt();
              });
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSeverityLabel('Safe', 1),
            _buildSeverityLabel('Mild', 2),
            _buildSeverityLabel('Concerning', 3),
            _buildSeverityLabel('Unsafe', 4),
            _buildSeverityLabel('Dangerous', 5),
          ],
        ),
      ],
    );
  }

  Widget _buildSeverityLabel(String label, int value) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: _severity == value ? _getSeverityColor(value) : Colors.grey[500],
        fontWeight: _severity == value ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Color _getSeverityColor(int severity) {
    switch (severity) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.yellow[700]!;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getSeverityLabel(int severity) {
    switch (severity) {
      case 1:
        return 'Safe';
      case 2:
        return 'Mild Concern';
      case 3:
        return 'Concerning';
      case 4:
        return 'Unsafe';
      case 5:
        return 'Dangerous';
      default:
        return '';
    }
  }

  Widget _buildCategoryButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What happened?',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: reportCategories.map((category) {
            final isSelected = _selectedCategory == category['id'];
            final level = category['level'] as SafetyLevel;
            final color = Color(safetyColors[level]!['main']!);

            return FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category['icon'] as String),
                  const SizedBox(width: 6),
                  Text(category['label'] as String),
                ],
              ),
              selectedColor: color.withOpacity(0.2),
              checkmarkColor: color,
              labelStyle: TextStyle(
                color: isSelected ? color : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? color : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = category['id'] as String;
                  });
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryInfo(Map<String, dynamic> categoryInfo) {
    final level = categoryInfo['level'] as SafetyLevel;
    final color = Color(safetyColors[level]!['main']!);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            level == SafetyLevel.unsafe
                ? Icons.warning
                : level == SafetyLevel.caution
                ? Icons.info
                : Icons.check_circle,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This will be reported as "${categoryInfo['label']}" with ${_getSeverityLabel(_severity).toLowerCase()} severity.',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Additional details',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Text(
              '(optional)',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: 'Briefly describe what happened...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final selectedCategoryInfo = reportCategories.firstWhere(
      (cat) => cat['id'] == _selectedCategory,
    );
    final safetyLevel = selectedCategoryInfo['level'] as SafetyLevel;
    final color = Color(safetyColors[safetyLevel]!['main']!);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'Submit Report',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _submitReport() {
    final description = _descriptionController.text.trim();
    widget.onSubmit(
      _selectedCategory,
      _severity,
      description.isEmpty ? null : description,
    );
  }

  IconData _getCategoryIcon(String categoryId) {
    switch (categoryId) {
      case 'followed':
        return Icons.visibility;
      case 'suspicious-activity':
        return Icons.warning;
      case 'harassment':
        return Icons.block;
      case 'poor-lighting':
        return Icons.lightbulb;
      case 'safe-area':
        return Icons.check_circle;
      default:
        return Icons.warning;
    }
  }
}

/// Quick report buttons for easy reporting on the map
class QuickReportButtons extends StatelessWidget {
  final Function(String category, int severity) onReport;
  final LatLng location;

  const QuickReportButtons({
    super.key,
    required this.onReport,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickButton(
            'Followed',
            Icons.visibility,
            Colors.red,
            'followed',
            5,
          ),
          const SizedBox(width: 8),
          _buildQuickButton(
            'Harassment',
            Icons.block,
            Colors.deepOrange,
            'harassment',
            5,
          ),
          const SizedBox(width: 8),
          _buildQuickButton(
            'Suspicious',
            Icons.warning,
            Colors.orange,
            'suspicious-activity',
            4,
          ),
          const SizedBox(width: 8),
          _buildQuickButton(
            'Unsafe',
            Icons.info,
            Colors.yellow[700]!,
            'felt-unsafe',
            3,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickButton(
    String label,
    IconData icon,
    Color color,
    String category,
    int severity,
  ) {
    return InkWell(
      onTap: () => onReport(category, severity),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
