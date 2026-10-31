import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  runApp(const GymManagementApp());
}

class GymManagementApp extends StatelessWidget {
  const GymManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF286455),
          surface: const Color(0xFFF7F8F5),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  late final AnimationController _dumbbellController;
  late final Animation<double> _dumbbellScale;
  bool _isAuthenticating = false;
  String? _authenticationMessage;

  @override
  void initState() {
    super.initState();
    _dumbbellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _dumbbellScale = Tween<double>(begin: 3, end: 1).animate(
      CurvedAnimation(
        parent: _dumbbellController,
        curve: Curves.easeOutCubic,
      ),
    );
    _dumbbellController.forward();
  }

  @override
  void dispose() {
    _dumbbellController.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithDeviceSecurity() async {
    if (kIsWeb) {
      setState(() {
        _authenticationMessage =
            'Device authentication is available on the Android tablet.';
      });
      return;
    }
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _authenticationMessage = null;
    });

    try {
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: 'Unlock RepLab Fitness',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!mounted) return;
      setState(() {
        _authenticationMessage = authenticated
            ? 'Device verified. Staff authorization is not connected yet.'
            : 'Authentication was not completed.';
      });
    } on LocalAuthException catch (exception) {
      if (!mounted) return;
      setState(() {
        _authenticationMessage = switch (exception.code) {
          LocalAuthExceptionCode.noCredentialsSet =>
            'Set a tablet PIN or enroll biometrics in Android Settings.',
          LocalAuthExceptionCode.noBiometricsEnrolled =>
            'No biometrics are enrolled. Use the tablet PIN if available.',
          LocalAuthExceptionCode.userCanceled => 'Authentication canceled.',
          LocalAuthExceptionCode.temporaryLockout ||
          LocalAuthExceptionCode.biometricLockout =>
            'Authentication is temporarily locked. Unlock the tablet and try again.',
          _ => 'Device authentication could not be completed. Try again.',
        };
      });
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/Splash.png',
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            key: ValueKey('splash-gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(33, 0, 1, 0.88),
                  Color.fromRGBO(0, 0, 0, 0.88),
                ],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        key: const ValueKey('dumbbell-scale'),
                        scale: _dumbbellScale,
                        child: SvgPicture.asset(
                          'assets/icons/dumbell.svg',
                          width: 109,
                          height: 109,
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _dumbbellScale,
                        builder: (context, child) => SizedBox(
                          height: 20 + 44 * (_dumbbellScale.value - 1),
                        ),
                      ),
                      const Text(
                        'RepLab Fitness',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Management & Attendance System',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 32),
                      DecoratedBox(
                        key: const ValueKey('login-panel'),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 44,
                                color: Color(0xFF286455),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Use your tablet PIN or biometrics to continue.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: FilledButton(
                                  onPressed: _isAuthenticating
                                      ? null
                                      : _authenticateWithDeviceSecurity,
                                  child: _isAuthenticating
                                      ? const SizedBox.square(
                                          dimension: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Login'),
                                ),
                              ),
                              if (_authenticationMessage != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _authenticationMessage!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
