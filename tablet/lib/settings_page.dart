import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_loading.dart';
import 'device_session.dart';
import 'replab_api.dart';
import 'server_host_fields.dart';
import 'settings_preview.dart';
import 'warning_ribbon.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.preview,
    this.api,
    this.device,
    this.padding = EdgeInsets.zero,
  });
  final SettingsPreview preview;
  final RepLabApi? api;
  final DeviceSession? device;
  final EdgeInsets padding;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = false;
  bool _signingOut = false;
  final _scroll = ScrollController();
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.api != null) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api!.settings();
      if (!mounted) return;
      setState(() {
        widget.preview
          ..gymName = data['gym_name'] as String
          ..phone = data['phone'] as String
          ..address = data['address'] as String;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _dialog(String kind) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SettingsForm(
        kind: kind,
        data: widget.preview,
        api: widget.api,
        device: widget.device,
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved.')));
  }

  Future<void> _biometrics(bool value) async {
    try {
      if (!await LocalAuthentication().authenticate(
        localizedReason: value
            ? 'Enable biometric unlock'
            : 'Disable biometric unlock',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      )) {
        return;
      }
      final device = widget.device!;
      await device.save(
        host: device.host,
        token: device.token,
        biometrics: value,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometrics are unavailable or verification was canceled. The setting was not changed.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      final device = widget.device;
      if (device != null) {
        await device.save(
          host: device.host,
          token: null,
          biometrics: device.biometrics,
        );
      }
      await widget.api!.logout();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not clear the saved session. Retry signing out.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = widget.api != null || widget.preview.enabled;
    final panels = [
      _SettingsPanel(
        title: 'Server authentication',
        icon: Icons.lock_outline_rounded,
        children: [
          const Text(
            'One server administrator. Password-only authentication; no username or email is required.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('settings-change-password'),
            onPressed: () => _dialog('password'),
            icon: const Icon(Icons.password_rounded),
            label: const Text('Change password'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Changing the server password revokes remembered sessions on every device.',
          ),
          if (widget.api != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('settings-logout'),
              onPressed: _signingOut ? null : _logout,
              icon: _signingOut
                  ? const DumbbellLoader(size: 20)
                  : const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
      _SettingsPanel(
        title: 'Gym details',
        icon: Icons.storefront_outlined,
        children: [
          _SettingValue(
            label: 'Gym name',
            value: available ? widget.preview.gymName : 'Not configured',
          ),
          _SettingValue(label: 'Contact phone', value: widget.preview.phone),
          _SettingValue(label: 'Address', value: widget.preview.address),
          const _SettingValue(
            label: 'Gym time zone',
            value: 'Asia/Kolkata · IST (UTC+05:30)',
          ),
          OutlinedButton.icon(
            key: const ValueKey('settings-edit-preferences'),
            onPressed: widget.api != null && (_loading || _error != null)
                ? null
                : () => _dialog('gym'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit settings'),
          ),
        ],
      ),
      const _SettingsPanel(
        title: 'Attendance terminal',
        icon: Icons.face_retouching_natural_rounded,
        children: [
          _SettingValue(
            label: 'eSSL AiFace-Mars',
            value: 'Integration not connected',
          ),
          _SettingValue(label: 'Last event received', value: 'Unavailable'),
          Text(
            'Terminal events are received by the gym server. Enrollment remains on the terminal; this app does not store face templates.',
          ),
        ],
      ),
      const _SettingsPanel(
        title: 'Backups & data',
        icon: Icons.backup_outlined,
        children: [
          _SettingValue(label: 'Latest server backup', value: 'Unavailable'),
          _SettingValue(label: 'Backup destination', value: 'Not configured'),
          Text(
            'Backups and restore checks are managed natively on the server. Backup status and actions are not exposed by the API.',
          ),
        ],
      ),
    ];
    final page = Column(
      key: const ValueKey('settings-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settings',
          key: const ValueKey('settings-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: DumbbellLoader(label: 'Loading settings')),
        Expanded(
          child: SingleChildScrollView(
            key: const PageStorageKey('settings-scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) >=
                        900
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - 20 * (columns - 1)) / columns;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Manage gym preferences and device connection.'),
                    const SizedBox(height: 24),
                    if (widget.api == null || _error != null) ...[
                      WarningRibbon(
                        key: const ValueKey('settings-notice'),
                        message:
                            _error ??
                            (widget.preview.enabled
                                ? 'Preview only · No server configuration or passwords are changed.'
                                : 'Backend not connected. Server settings are unavailable.'),
                      ),
                      if (_error != null)
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry settings'),
                        ),
                      const SizedBox(height: 24),
                    ],
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        for (final panel in panels)
                          SizedBox(width: width, child: panel),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: ExpansionTile(
                        // Store expansion separately from the page's scroll offset.
                        key: const PageStorageKey(
                          'settings-advanced-expansion',
                        ),
                        title: const Text(
                          'Advanced settings',
                          key: ValueKey('settings-advanced'),
                        ),
                        leading: const Icon(Icons.tune_rounded),
                        childrenPadding: const EdgeInsets.all(20),
                        children: [
                          _SettingValue(
                            label: 'Server hostname / IP',
                            value: widget.device?.host ?? '',
                          ),
                          const Text(
                            'The server port is fixed in the app. HTTPS verification cannot be disabled. A different IP/hostname must be included in the server certificate.',
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            key: const ValueKey('settings-change-server'),
                            onPressed: () => _dialog('server'),
                            icon: const Icon(Icons.dns_outlined),
                            label: const Text('Change server'),
                          ),
                          if (!kIsWeb)
                            SwitchListTile(
                              key: const ValueKey('settings-biometrics'),
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Biometric unlock'),
                              subtitle: const Text(
                                'Verify fingerprint or face when opening this app.',
                              ),
                              value: widget.device?.biometrics ?? false,
                              onChanged:
                                  widget.api != null && widget.device != null
                                  ? _biometrics
                                  : null,
                            ),
                          const Text(
                            'The device remembers a revocable session key, never the server password. Sign out to forget it.',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
    return DumbbellRefresh(
      key: const ValueKey('settings-refresh'),
      padding: widget.padding,
      scrollController: _scroll,
      onRefresh: widget.api != null
          ? _load
          : () => refreshLocalView(
              context,
              preview: widget.preview.enabled,
              rebuild: () => setState(() {}),
            ),
      child: page,
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDDDDDD)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    ),
  );
}

class _SettingValue extends StatelessWidget {
  const _SettingValue({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value.isEmpty ? 'Not configured' : value),
      ],
    ),
  );
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({
    required this.kind,
    required this.data,
    this.api,
    this.device,
  });
  final String kind;
  final SettingsPreview data;
  final RepLabApi? api;
  final DeviceSession? device;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late final _gym = TextEditingController(text: widget.data.gymName);
  late final _phone = TextEditingController(text: widget.data.phone);
  late final _address = TextEditingController(text: widget.data.address);
  late final _host = TextEditingController(text: widget.device?.host ?? '');
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false, _uncertain = false, _show = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [
      _gym,
      _phone,
      _address,
      _host,
      _current,
      _password,
      _confirm,
    ]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _uncertain || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.kind == 'server') {
        final error = serverHostError(_host.text);
        if (error != null) throw ApiException(error);
        final candidate = widget.api!.newConnection();
        try {
          // Never forward the old server's session key to a different server.
          await candidate.login(
            serverUrl(_host.text.trim()),
            _password.text,
            notify: false,
          );
          await widget.device!.save(
            host: _host.text.trim(),
            token: candidate.sessionKey,
            biometrics: widget.device!.biometrics,
          );
          widget.api!.adoptSession(candidate);
        } finally {
          candidate.dispose();
        }
      } else if (widget.kind == 'password') {
        if (widget.api != null) {
          await widget.api!.changePassword(_current.text, _password.text);
        }
      } else {
        if (widget.api != null) {
          final data = await widget.api!.saveSettings(
            _gym.text,
            _phone.text,
            _address.text,
          );
          widget.data
            ..gymName = data['gym_name'] as String
            ..phone = data['phone'] as String
            ..address = data['address'] as String;
        } else {
          widget.data
            ..gymName = _gym.text.trim()
            ..phone = _phone.text.trim()
            ..address = _address.text.trim();
        }
      }
      _current.clear();
      _password.clear();
      _confirm.clear();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _uncertain = error.uncertain;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save device settings. The previous connection is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  TextFormField _secret(
    String key,
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    obscureText: !_show,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(labelText: label),
    validator: validator,
  );
  @override
  Widget build(BuildContext context) {
    final server = widget.kind == 'server',
        password = widget.kind == 'password';
    final enabled = server
        ? widget.api != null && widget.device != null
        : widget.api != null || widget.data.enabled;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        key: const ValueKey('settings-dialog'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  server
                      ? 'Change server'
                      : password
                      ? 'Change password'
                      : 'Gym details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('settings-form-scroll'),
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (server) ...[
                          const Text(
                            'Verify the password of the new server before saving. The previous device connection is kept if verification fails.',
                          ),
                          const SizedBox(height: 20),
                          ServerHostFields(
                            controller: _host,
                            enabled: !_saving,
                          ),
                          const SizedBox(height: 20),
                          _secret(
                            'settings-server-password',
                            _password,
                            'Server password',
                            (v) => (v ?? '').isEmpty
                                ? 'Enter the server password'
                                : null,
                          ),
                        ] else if (password) ...[
                          const Text(
                            'Changing the password revokes every remembered device session. No tablet PIN is changed.',
                          ),
                          const SizedBox(height: 20),
                          _secret(
                            'settings-current-password',
                            _current,
                            'Current password',
                            (v) => (v ?? '').isEmpty
                                ? 'Enter the current password'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          _secret(
                            'settings-new-password',
                            _password,
                            'New password',
                            (v) =>
                                (v ?? '').runes.length < 15 ||
                                    v!.runes.length > 128 ||
                                    v.trim().isEmpty
                                ? 'Use 15–128 characters'
                                : v == _current.text
                                ? 'Choose a different password'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          _secret(
                            'settings-confirm-password',
                            _confirm,
                            'Confirm password',
                            (v) => v != _password.text || (v ?? '').isEmpty
                                ? 'Passwords do not match'
                                : null,
                          ),
                        ] else ...[
                          TextFormField(
                            key: const ValueKey('settings-gym-name'),
                            controller: _gym,
                            maxLength: 100,
                            decoration: const InputDecoration(
                              labelText: 'Gym name *',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Enter the gym name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('settings-gym-phone'),
                            controller: _phone,
                            maxLength: 24,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone (optional)',
                            ),
                            validator: (v) =>
                                (v ?? '').isEmpty ||
                                    (RegExp(r'^\+?[\d ()-]+$').hasMatch(v!) &&
                                        v
                                                .replaceAll(RegExp(r'\D'), '')
                                                .length >=
                                            7 &&
                                        v
                                                .replaceAll(RegExp(r'\D'), '')
                                                .length <=
                                            15)
                                ? null
                                : 'Enter a valid phone number',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const ValueKey('settings-gym-address'),
                            controller: _address,
                            maxLength: 500,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Address (optional)',
                            ),
                          ),
                        ],
                        if (server || password)
                          CheckboxListTile(
                            key: const ValueKey('settings-show-passwords'),
                            contentPadding: EdgeInsets.zero,
                            value: _show,
                            onChanged: (v) =>
                                setState(() => _show = v ?? false),
                            title: const Text('Show passwords'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 12,
                  children: [
                    TextButton(
                      key: const ValueKey('settings-dialog-cancel'),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      key: const ValueKey('settings-dialog-save'),
                      onPressed: _saving || _uncertain || !enabled
                          ? null
                          : _save,
                      child: _saving
                          ? const DumbbellLoader(size: 22)
                          : const Text('Save settings'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
