import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'providers/safety_provider.dart';
import 'providers/auth_provider.dart';
import 'widgets/safety_map.dart';
import 'models/safety.dart';
import 'models/user.dart';

void main() {
  runApp(const SafetyPulseApp());
}

class SafetyPulseApp extends StatelessWidget {
  const SafetyPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => SafetyProvider()),
      ],
      child: MaterialApp(
        title: 'Safety Pulse',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

/// Auth wrapper - shows login if not authenticated, home page if authenticated
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Initialize auth state on app start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoading) {
      // Loading screen while checking auth state
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading...'),
            ],
          ),
        ),
      );
    }

    if (authProvider.isAuthenticated) {
      // User is logged in, show the main app
      return const HomePage();
    }

    // User is not logged in, show login screen
    return const LoginScreen();
  }
}

/// Login screen with registration option
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    bool success;

    if (_isLogin) {
      success = await authProvider.login(
        _emailController.text,
        _passwordController.text,
      );
    } else {
      success = await authProvider.register(
        _emailController.text,
        _usernameController.text,
        _passwordController.text,
      );
    }

    setState(() {
      _isLoading = false;
    });

    if (success) {
      if (mounted) {
        // Get the token and initialize safety provider
        final token = authProvider.token!;
        context.read<SafetyProvider>().initializeReports(token: token);

        // Navigate to home
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } else {
      setState(() {
        _errorMessage = authProvider.error ?? 'An error occurred';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'Login' : 'Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Icon(Icons.security, size: 80, color: Colors.blue),
                const SizedBox(height: 16),
                Text(
                  _isLogin ? 'Welcome Back' : 'Create Account',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isLogin
                      ? 'Sign in to report and view safety data'
                      : 'Sign up to start using Safety Pulse',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                if (_errorMessage != null) const SizedBox(height: 16),
                if (!_isLogin)
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                if (!_isLogin) const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email is required';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isLogin ? 'Login' : 'Create Account'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _errorMessage = null;
                          });
                        },
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Login',
                  ),
                ),
              ],
            ),
          ),
        ),
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
  final bool _locationRequested = false;
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

    // Get auth token
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token == null) {
      // Not authenticated, go to login
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
      return;
    }

    try {
      // First check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showSnackBar('Please enable location services');
          _initializeWithDefaultLocation(token: token);
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
            token: token,
          );
        }
      } else {
        // Permission denied, use default location
        if (mounted) {
          _showSnackBar('Location permission denied');
          _initializeWithDefaultLocation(token: token);
        }
      }
    } on TimeoutException {
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
              token: token,
            );
            return;
          }
        } catch (_) {}
        _showSnackBar('Location request timed out');
        _initializeWithDefaultLocation(token: token);
      }
    } catch (e) {
      // If getting location fails, use default location
      if (mounted) {
        _showSnackBar('Could not get location: ${e.toString()}');
        _initializeWithDefaultLocation(token: token);
      }
    }
  }

  void _initializeWithDefaultLocation({required String token}) {
    setState(() {
      _isLoadingLocation = false;
    });
    context.read<SafetyProvider>().setUserLocation(
      const MapLocation(latitude: 40.7484, longitude: -73.9857),
      token: token,
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

  void _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final safetyProvider = context.watch<SafetyProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Pulse'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          // Show username if logged in
          if (authProvider.user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  '@${authProvider.user!.username}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Get My Location',
            onPressed: () => _requestLocationAndInitialize(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              final token = authProvider.token;
              if (token != null) {
                safetyProvider.refreshReports(token: token);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
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

          // Get token for API calls
          final token = authProvider.token;

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

    // Get auth token
    final authProvider = context.read<AuthProvider>();
    final token = authProvider.token;

    if (token != null) {
      context.read<SafetyProvider>().addReport(report, token: token);
    }

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
