import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'providers/safety_provider.dart';
import 'widgets/safety_map.dart';
import 'models/safety.dart';

void main() {
  runApp(const SafetyPulseApp());
}

class SafetyPulseApp extends StatelessWidget {
  const SafetyPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => SafetyProvider(),
      child: MaterialApp(
        title: 'Safety Pulse',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _locationRequested = false;
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _requestLocationAndInitialize();
  }

  Future<void> _requestLocationAndInitialize() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // First check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showSnackBar('Please enable location services');
          _initializeWithDefaultLocation();
        }
        return;
      }

      // Check if location permission is already granted
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Request permission
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Get current location with timeout (10 seconds)
        Position position =
            await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 10),
            ).timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                // If timeout, try last known position
                throw TimeoutException('Location request timed out');
              },
            );

        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
          // Set user location and initialize reports for that area
          context.read<SafetyProvider>().setUserLocation(
            MapLocation(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
          );
        }
      } else {
        // Permission denied, use default location
        if (mounted) {
          _showSnackBar('Location permission denied');
          _initializeWithDefaultLocation();
        }
      }
    } on TimeoutException catch (e) {
      // Timeout, try getting last known position
      if (mounted) {
        try {
          Position? lastPosition = await Geolocator.getLastKnownPosition();
          if (lastPosition != null) {
            setState(() {
              _isLoadingLocation = false;
            });
            context.read<SafetyProvider>().setUserLocation(
              MapLocation(
                latitude: lastPosition.latitude,
                longitude: lastPosition.longitude,
              ),
            );
            return;
          }
        } catch (_) {}
        _showSnackBar('Location request timed out');
        _initializeWithDefaultLocation();
      }
    } catch (e) {
      // If getting location fails, use default location
      if (mounted) {
        _showSnackBar('Could not get location: ${e.toString()}');
        _initializeWithDefaultLocation();
      }
    }
  }

  void _initializeWithDefaultLocation() {
    setState(() {
      _isLoadingLocation = false;
    });
    context.read<SafetyProvider>().setUserLocation(
      const MapLocation(latitude: 40.7484, longitude: -73.9857),
    );
  }

  void _onMapTap(double lat, double lng) {
    _showReportDialog(lat, lng);
  }

  void _showReportDialog(double lat, double lng) {
    showDialog(
      context: context,
      builder: (context) => ReportDialog(lat: lat, lng: lng),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Pulse'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Get My Location',
            onPressed: () => _requestLocationAndInitialize(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () => context.read<SafetyProvider>().refreshReports(),
          ),
        ],
      ),
      body: Consumer<SafetyProvider>(
        builder: (context, provider, child) {
          // Show error message if any
          if (provider.errorMessage != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showSnackBar(provider.errorMessage!);
              provider.clearError();
            });
          }

          return Stack(
            children: [
              SafetyMap(
                reports: provider.reports,
                onMapTap: _onMapTap,
                center: provider.userLocation != null
                    ? LatLng(
                        provider.userLocation!.latitude,
                        provider.userLocation!.longitude,
                      )
                    : null,
              ),
              // Loading indicator for location/data fetching
              if (provider.isLoading || _isLoadingLocation)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isLoadingLocation
                              ? 'Getting your location...'
                              : 'Loading safety data...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              // Debug location indicator
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Location:',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        provider.userLocation != null
                            ? '${provider.userLocation!.latitude.toStringAsFixed(6)}, ${provider.userLocation!.longitude.toStringAsFixed(6)}'
                            : 'Getting location...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (provider.reports.isEmpty &&
                          !provider.isLoading &&
                          !_isLoadingLocation)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'No reports in this area. Be the first to report!',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Use current location if available, otherwise default
          final provider = context.read<SafetyProvider>();
          final lat = provider.userLocation?.latitude ?? 40.7484;
          final lng = provider.userLocation?.longitude ?? -73.9857;
          _showReportDialog(lat, lng);
        },
        tooltip: 'Add Safety Report',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ReportDialog extends StatefulWidget {
  final double lat;
  final double lng;

  const ReportDialog({super.key, required this.lat, required this.lng});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  SafetyLevel _selectedLevel = SafetyLevel.safe;
  String _selectedCategory = 'Felt unsafe here';
  final TextEditingController _descriptionController = TextEditingController();

  void _submitReport() {
    final report = SafetyReport(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: widget.lat,
      longitude: widget.lng,
      level: _selectedLevel,
      category: _selectedCategory,
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      timestamp: DateTime.now(),
      opacity: 1.0,
    );

    context.read<SafetyProvider>().addReport(report);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Safety Report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<SafetyLevel>(
              initialValue: _selectedLevel,
              decoration: const InputDecoration(labelText: 'Safety Level'),
              items: SafetyLevel.values.map((level) {
                return DropdownMenuItem(
                  value: level,
                  child: Text(level.name.toUpperCase()),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedLevel = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: reportCategories.map((category) {
                return DropdownMenuItem(
                  value: category['label'] as String,
                  child: Text(category['label'] as String),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submitReport, child: const Text('Submit')),
      ],
    );
  }
}
