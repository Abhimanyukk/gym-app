import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';

import 'app_loading.dart';
import 'dashboard_screen.dart';
import 'replab_api.dart';
import 'device_session.dart';
import 'server_host_fields.dart';

void main() {
  runApp(const GymManagementApp());
}

class GymManagementApp extends StatefulWidget {
  const GymManagementApp({super.key, this.home, this.api, this.device});

  final Widget? home;
  final RepLabApi? api;
  final DeviceSession? device;

  @override
  State<GymManagementApp> createState() => _GymManagementAppState();
}

class _GymManagementAppState extends State<GymManagementApp>
    with WidgetsBindingObserver {
  late final _api = widget.api ?? RepLabApi();
  late final _device = widget.device ?? DeviceSession();
  final _navigator = GlobalKey<NavigatorState>();
  bool _locking = false;
  bool _hadSession = false;

  @override
  void initState() {
    super.initState();
    _hadSession = _api.signedIn;
    _api.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _device.biometrics &&
        _api.signedIn &&
        _device.token != null &&
        _api.sessionKey == _device.token) {
      _locking = true;
      _api.clearSession();
      _locking = false;
    }
  }

  void _sessionChanged() {
    if (!mounted) return;
    final lostSession = _hadSession && !_api.signedIn;
    _hadSession = _api.signedIn;
    if (!_api.signedIn && !_locking && _device.token != null) {
      _device.token = null;
      _device
          .save(host: _device.host, token: null, biometrics: _device.biometrics)
          .catchError((Object error) {
            _api.sessionMessage =
                'Could not clear device storage. Retry signing out.';
          });
    }
    setState(() {});
    if (lostSession) {
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
    WidgetsBinding.instance.removeObserver(this);
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
              ? DashboardScreen(
                  key: ValueKey(_api.baseUrl),
                  api: _api,
                  device: _device,
                )
              : SplashScreen(api: _api, device: _device)),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.api, this.device});
  final RepLabApi? api;
  final DeviceSession? device;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  late final AnimationController _dumbbellController;
  late final Animation<double> _dumbbellScale;
  bool _isAuthenticating = false;
  bool _awaitingConsent = false;
  String? _authenticationMessage;
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _server = TextEditingController(
    text:
        Uri.tryParse(const String.fromEnvironment('API_BASE_URL'))?.host ?? '',
  );
  bool _showPassword = false;
  late final _device = widget.device ?? DeviceSession();
  bool _loadingSetup = true;
  bool _hostStep = true;
  bool _savedSession = false;
  bool _firstSetup = true;

  @override
  void initState() {
    super.initState();
    _dumbbellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _dumbbellScale = Tween<double>(begin: 3, end: 1).animate(
      CurvedAnimation(parent: _dumbbellController, curve: Curves.easeOutCubic),
    );
    _dumbbellController.forward();
    _loadSetup();
  }

  Future<void> _loadSetup() async {
    try {
      if (!_device.loaded) await _device.load();
      if (!mounted) return;
      setState(() {
        if (_device.configured) _server.text = _device.host;
        _hostStep = !_device.configured;
        _firstSetup = !_device.configured;
        _savedSession = _device.token != null;
        _loadingSetup = false;
      });
      if (_savedSession && widget.api != null) await _resume();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingSetup = false;
          _authenticationMessage = 'Device storage could not be read. Retry; do not reset server data.';
        });
      }
    }
  }

  Future<void> _resume() async {
    if (_isAuthenticating || _device.token == null || widget.api == null) {
      return;
    }
    setState(() {
      _isAuthenticating = true;
      _authenticationMessage = null;
    });
    try {
      if (_device.biometrics && !kIsWeb) {
        final unlocked = await _localAuthentication.authenticate(
          localizedReason: 'Unlock RepLab Fitness',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!unlocked) {
          throw const ApiException('Biometric verification was not completed.');
        }
      }
      if (!mounted) return;
      await widget.api!.resume(serverUrl(_device.host), _device.token!);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'unauthorized') {
        _device.token = null;
        await _device.save(
          host: _device.host,
          token: null,
          biometrics: _device.biometrics,
        );
        _savedSession = false;
      }
      if (mounted) setState(() => _authenticationMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _authenticationMessage = 'Unable to unlock or reconnect. Retry, or use the server password to recover.',
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthenticating = false);
    }
  }

  @override
  void dispose() {
    _dumbbellController.dispose();
    _password.clear();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isAuthenticating) return;
    if (!_form.currentState!.validate()) return;

    setState(() {
      _isAuthenticating = true;
      _authenticationMessage = null;
    });

    try {
      if (widget.api == null) {
        throw const ApiException('Server login is required.');
      }
      await widget.api!.login(
        serverUrl(_server.text.trim()),
        _password.text,
        notify: false,
      );
      _password.clear();
      if (!mounted) return;
      bool bio = _device.biometrics;
      if (!kIsWeb && (_firstSetup || _savedSession)) {
        setState(() => _awaitingConsent = true);
        final enable = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Enable biometrics?'),
            content: const Text(
              'Use fingerprint or face verification when opening RepLab. Without it, this device opens the dashboard automatically. The server password is not stored.',
            ),
            actions: [
              TextButton(
                key: const ValueKey('setup-skip-biometrics'),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                key: const ValueKey('setup-enable-biometrics'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enable biometrics'),
              ),
            ],
          ),
        );
        if (mounted) setState(() => _awaitingConsent = false);
        bio = enable == true;
        if (bio) {
          final verified = await _localAuthentication.authenticate(
            localizedReason: 'Enable biometric unlock for RepLab',
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          );
          if (!verified) {
            throw const ApiException(
              'Biometric verification was not completed. Retry or choose Not now.',
            );
          }
        }
      }
      await _device.save(
        host: _server.text.trim(),
        token: widget.api!.sessionKey,
        biometrics: bio,
      );
      if (mounted) widget.api!.publishSession();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _authenticationMessage = error.message);
    } on LocalAuthException catch (exception) {
      if (!mounted) return;
      setState(() {
        _authenticationMessage = switch (exception.code) {
          LocalAuthExceptionCode.noCredentialsSet ||
          LocalAuthExceptionCode.noBiometricsEnrolled =>
            'Enroll biometrics in Android Settings, or choose Not now.',
          LocalAuthExceptionCode.userCanceled => 'Authentication canceled.',
          LocalAuthExceptionCode.temporaryLockout ||
          LocalAuthExceptionCode.biometricLockout => 'Authentication is temporarily locked. Unlock the tablet and try again.',
          _ => 'Device authentication could not be completed. Try again.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _authenticationMessage = 'Could not save the device session. Retry; your server password is never saved.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _awaitingConsent = false;
        });
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
                                    _hostStep
                                        ? 'Connect your gym server'
                                        : _savedSession
                                        ? 'Welcome back to RepLab'
                                        : 'Enter the server password',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                  const SizedBox(height: 24),
                                  if (_loadingSetup)
                                    const DumbbellLoader(
                                      label: 'Reading device setup',
                                    )
                                  else if (_hostStep) ...[
                                    ServerHostFields(
                                      controller: _server,
                                      enabled: !_isAuthenticating,
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton(
                                      key: const ValueKey('setup-next'),
                                      onPressed: () {
                                        if (!_form.currentState!.validate()) {
                                          return;
                                        }
                                        final error = serverHostError(
                                          _server.text,
                                        );
                                        setState(() {
                                          _authenticationMessage = error;
                                          if (error == null) _hostStep = false;
                                        });
                                      },
                                      child: const Text('Next'),
                                    ),
                                  ] else ...[
                                    Text(
                                      'Server: ${_server.text}',
                                      key: const ValueKey('login-saved-server'),
                                    ),
                                    const SizedBox(height: 16),
                                    if (!_savedSession)
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
                                          labelText: 'Server password',
                                          suffixIcon: IconButton(
                                            tooltip: _showPassword
                                                ? 'Hide password'
                                                : 'Show password',
                                            onPressed: () => setState(
                                              () => _showPassword =
                                                  !_showPassword,
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
                                        onFieldSubmitted: (_) => _login(),
                                      ),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: FilledButton(
                                        onPressed: _isAuthenticating
                                            ? null
                                            : _savedSession
                                            ? _resume
                                            : _login,
                                        child:
                                            _isAuthenticating &&
                                                !_awaitingConsent
                                            ? const DumbbellLoader(
                                                size: 22,
                                                label: 'Signing in to RepLab Fitness',
                                              )
                                            : Text(
                                                _savedSession
                                                    ? 'Unlock & connect'
                                                    : 'Login',
                                              ),
                                      ),
                                    ),
                                    if (_savedSession)
                                      TextButton(
                                        key: const ValueKey(
                                          'login-use-password',
                                        ),
                                        onPressed: _isAuthenticating
                                            ? null
                                            : () => setState(() {
                                                _savedSession = false;
                                                _firstSetup = true;
                                                _authenticationMessage = null;
                                              }),
                                        child: const Text(
                                          'Recover using server password',
                                        ),
                                      ),
                                    TextButton(
                                      key: const ValueKey('login-advanced'),
                                      onPressed: _isAuthenticating
                                          ? null
                                          : () => setState(() {
                                              _savedSession = false;
                                              _hostStep = true;
                                              _firstSetup = true;
                                              _authenticationMessage = null;
                                            }),
                                      child: const Text(
                                        'Advanced connection settings',
                                      ),
                                    ),
                                  ],
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
                                    'One server administrator. Your password is never stored. HTTPS certificate verification stays enabled.',
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
