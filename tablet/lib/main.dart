import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';

import 'app_loading.dart';
import 'dashboard_screen.dart';
import 'replab_api.dart';

void main() {
  runApp(const GymManagementApp());
}

class GymManagementApp extends StatefulWidget {
  const GymManagementApp({super.key, this.home, this.api});

  final Widget? home;
  final RepLabApi? api;

  @override
  State<GymManagementApp> createState() => _GymManagementAppState();
}

class _GymManagementAppState extends State<GymManagementApp> {
  late final _api = widget.api ?? RepLabApi();
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _api.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_api.signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_api.signedIn) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
  }

  @override
  void dispose() {
    _api.removeListener(_sessionChanged);
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym Management',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF286455),
          surface: const Color(0xFFF7F8F5),
        ),
        useMaterial3: true,
      ),
      home:
          widget.home ??
          (_api.signedIn
              ? DashboardScreen(api: _api)
              : SplashScreen(api: _api)),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.api});
  final RepLabApi? api;

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
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController(
    text: const String.fromEnvironment('API_BASE_URL'),
  );
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    if (_server.text.isEmpty && kIsWeb) _server.text = 'https://localhost:8001';
    if (widget.api?.baseUrl.isNotEmpty == true) {
      _server.text = widget.api!.baseUrl;
    }
    _dumbbellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _dumbbellScale = Tween<double>(begin: 3, end: 1).animate(
      CurvedAnimation(parent: _dumbbellController, curve: Curves.easeOutCubic),
    );
    _dumbbellController.forward();
  }

  @override
  void dispose() {
    _dumbbellController.dispose();
    _email.dispose();
    _password.clear();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithDeviceSecurity() async {
    if (_isAuthenticating) return;
    if (!_form.currentState!.validate()) return;

    setState(() {
      _isAuthenticating = true;
      _authenticationMessage = null;
    });

    try {
      final authenticated =
          kIsWeb ||
          await _localAuthentication.authenticate(
            localizedReason: 'Unlock RepLab Fitness',
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          );
      if (!mounted) return;
      if (authenticated) {
        if (widget.api == null) {
          setState(() => _authenticationMessage = 'Server login is required.');
          return;
        }
        await widget.api!.login(_server.text, _email.text, _password.text);
        if (mounted) {
          _password.clear();
        }
        return;
      }
      setState(() {
        _authenticationMessage = 'Authentication was not completed.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _authenticationMessage = error.message);
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
          LocalAuthExceptionCode.biometricLockout => 'Authentication is temporarily locked. Unlock the tablet and try again.',
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
          Image.asset('assets/images/Splash.png', fit: BoxFit.cover),
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
          SafeArea(
            child: Center(
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
                            child: Form(
                              key: _form,
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
                                    kIsWeb
                                        ? 'Sign in with your gym administrator account.'
                                        : 'Sign in with your gym admin account and unlock using the tablet PIN or biometrics.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    key: const ValueKey('login-server'),
                                    controller: _server,
                                    enabled: !_isAuthenticating,
                                    autocorrect: false,
                                    keyboardType: TextInputType.url,
                                    decoration: const InputDecoration(
                                      labelText: 'Gym server address',
                                      hintText: 'https://192.168.1.50:8443',
                                    ),
                                    validator: apiAddressError,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const ValueKey('login-email'),
                                    controller: _email,
                                    enabled: !_isAuthenticating,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Admin email',
                                    ),
                                    validator: (v) =>
                                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                            .hasMatch((v ?? '').trim())
                                        ? null
                                        : 'Enter your admin email',
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const ValueKey('login-password'),
                                    controller: _password,
                                    enabled: !_isAuthenticating,
                                    obscureText: !_showPassword,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      suffixIcon: IconButton(
                                        tooltip: _showPassword
                                            ? 'Hide password'
                                            : 'Show password',
                                        onPressed: () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
                                        icon: Icon(
                                          _showPassword
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                        ),
                                      ),
                                    ),
                                    validator: (v) => (v ?? '').isEmpty
                                        ? 'Enter your password'
                                        : null,
                                    onFieldSubmitted: (_) =>
                                        _authenticateWithDeviceSecurity(),
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
                                          ? const DumbbellLoader(
                                              size: 22,
                                              label: 'Signing in to RepLab Fitness',
                                            )
                                          : const Text('Login'),
                                    ),
                                  ),
                                  if (_authenticationMessage != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      _authenticationMessage!,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                  if (_authenticationMessage == null &&
                                      widget.api?.sessionMessage != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      widget.api!.sessionMessage!,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Use the first admin created on the server. No default login is provided. Trust the server certificate before signing in.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
