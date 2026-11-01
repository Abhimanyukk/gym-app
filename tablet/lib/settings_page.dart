import 'package:flutter/material.dart';

import 'settings_preview.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.preview});
  final SettingsPreview preview;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsPreview get data => widget.preview;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _account({required bool addAdmin}) async {
    final validated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountDialog(data: data, addAdmin: addAdmin),
    );
    if (validated != true || !mounted) return;
    setState(() {});
    _message(
      addAdmin
          ? 'Admin identity added to preview only. No login account was created.'
          : 'Preview validation passed. No password was verified or changed.',
    );
  }

  Future<void> _preferences() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PreferencesDialog(data: data),
    );
    if (saved != true || !mounted) return;
    setState(() {});
    _message(
      'Preferences saved to preview only. No server configuration changed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final readableWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final columns = readableWidth >= 900 ? 2 : 1;
        final width = (constraints.maxWidth - 20 * (columns - 1)) / columns;
        final panels = [
          _SettingsPanel(
            title: 'Password & device security',
            icon: Icons.lock_outline_rounded,
            children: [
              const Text(
                'Change your admin password. This is separate from the tablet PIN or biometrics.',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('settings-change-password'),
                  onPressed: () => _account(addAdmin: false),
                  icon: const Icon(Icons.password_rounded, size: 20),
                  label: const Text('Change password'),
                ),
              ),
              const SizedBox(height: 16),
              Text('Tablet unlock', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              const Text(
                'The Android app uses device security to unlock. Manage the tablet PIN and biometrics in Android Settings.',
              ),
              const SizedBox(height: 12),
              Text(
                'Admin authentication is not connected yet.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          _SettingsPanel(
            title: 'Gym details & connection',
            icon: Icons.storefront_outlined,
            children: [
              _SettingValue(
                label: 'Gym name',
                value: data.enabled ? data.gymName : 'Not configured',
              ),
              _SettingValue(
                label: 'Contact phone',
                value: data.enabled ? data.phone : '',
              ),
              _SettingValue(
                label: 'Address',
                value: data.enabled ? data.address : '',
              ),
              _SettingValue(
                label: 'API server address',
                value: data.enabled ? data.serverUrl : '',
              ),
              const _SettingValue(
                label: 'Gym time zone',
                value: 'Asia/Kolkata · IST (UTC+05:30)',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('settings-edit-preferences'),
                  onPressed: _preferences,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: const Text('Edit settings'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Backend not connected. A preview address does not connect the app.',
                style: theme.textTheme.bodySmall,
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
              _SettingValue(
                label: 'Latest server backup',
                value: 'Unavailable',
              ),
              _SettingValue(
                label: 'Backup destination',
                value: 'Not configured',
              ),
              Text(
                'Server backups and restore checks will be managed through the backend. No backup or restore action is performed in this preview.',
              ),
            ],
          ),
        ];
        return Column(
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
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey('settings-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Manage administrators and gym preferences.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.07,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        data.enabled
                            ? 'Preview only · Sample admins and preferences are temporary. Passwords are never stored or changed here.'
                            : 'Backend and staff authorization are not connected. Account changes and saving are unavailable.',
                        key: const ValueKey('settings-notice'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SettingsPanel(
                      title: 'Administrators',
                      icon: Icons.admin_panel_settings_outlined,
                      children: [
                        Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              data.enabled
                                  ? '${data.admins.length} of ${SettingsPreview.maxAdmins} admin slots used'
                                  : 'Admin records unavailable · Maximum 3 admins',
                              key: const ValueKey('settings-admin-count'),
                              style: theme.textTheme.bodyLarge,
                            ),
                            FilledButton.icon(
                              key: const ValueKey('settings-add-admin'),
                              onPressed: data.canAddAdmin
                                  ? () => _account(addAdmin: true)
                                  : null,
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 20,
                              ),
                              label: const Text('Add admin'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (data.enabled)
                          for (final admin in data.admins)
                            Padding(
                              key: ValueKey('settings-admin-${admin.email}'),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFE4F0ED),
                                    foregroundColor: theme.colorScheme.primary,
                                    child: const Icon(
                                      Icons.person_outline_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          admin.name,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          admin.email,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          admin == data.admins.first
                                              ? 'Sample admin · Preview identity'
                                              : 'Admin · Preview identity',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        if (data.enabled && !data.canAddAdmin)
                          Text(
                            'Maximum of 3 admins reached.',
                            key: const ValueKey('settings-admin-limit'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'The limit includes the initial admin. Real accounts and permissions must be managed by the server.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      children: [
                        for (final panel in panels)
                          SizedBox(width: width, child: panel),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
}

class _SettingValue extends StatelessWidget {
  const _SettingValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(value.isEmpty ? 'Not configured' : value),
      ],
    ),
  );
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.data, required this.addAdmin});
  final SettingsPreview data;
  final bool addAdmin;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPasswords = false;

  @override
  void dispose() {
    for (final controller in [_name, _email, _current, _password, _confirm]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!widget.data.enabled || !_form.currentState!.validate()) return;
    if (widget.addAdmin) {
      // Recheck the shared count and uniqueness at submission, not just the UI.
      final error = widget.data.addAdmin((
        name: _name.text,
        email: _email.text,
      ));
      if (error != null) {
        _form.currentState!.validate();
        return;
      }
    }
    _current.clear();
    _password.clear();
    _confirm.clear();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final add = widget.addAdmin;
    return _SettingsDialog(
      title: add ? 'Add admin' : 'Change password',
      action: add ? 'Add preview admin' : 'Validate preview',
      onSave: widget.data.enabled && (!add || widget.data.canAddAdmin)
          ? _submit
          : null,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.data.enabled
                  ? add
                        ? 'Preview only · Use test details. This adds an identity, not a working login account.'
                        : 'Preview validation only · The current password cannot be verified and no password will be changed. Use test passwords.'
                  : 'The backend and staff authorization are required. Saving is unavailable.',
            ),
            const SizedBox(height: 20),
            if (add) ...[
              TextFormField(
                key: const ValueKey('settings-admin-name'),
                controller: _name,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name *'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter the admin’s full name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('settings-admin-email'),
                controller: _email,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: widget.data.adminEmailError,
              ),
              const SizedBox(height: 12),
            ] else ...[
              TextFormField(
                key: const ValueKey('settings-current-password'),
                controller: _current,
                obscureText: !_showPasswords,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Current password *',
                ),
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Enter the current password' : null,
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              key: const ValueKey('settings-new-password'),
              controller: _password,
              obscureText: !_showPasswords,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: add ? 'Initial password *' : 'New password *',
                helperText: 'At least 15 characters; spaces are allowed.',
                helperMaxLines: 3,
              ),
              validator: (value) {
                if ((value ?? '').runes.length < 15 || value!.trim().isEmpty) {
                  return 'Use at least 15 characters';
                }
                if (!add && value == _current.text) {
                  return 'Choose a different password';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('settings-confirm-password'),
              controller: _confirm,
              obscureText: !_showPasswords,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Confirm password *',
              ),
              validator: (value) =>
                  value != _password.text || (value ?? '').isEmpty
                  ? 'Passwords do not match'
                  : null,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const ValueKey('settings-show-passwords'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _showPasswords,
              onChanged: (value) =>
                  setState(() => _showPasswords = value ?? false),
              title: const Text('Show passwords'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Passwords are discarded when this form closes. No tablet PIN is changed.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog({required this.data});
  final SettingsPreview data;

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  final _form = GlobalKey<FormState>();
  late final _gym = TextEditingController(text: widget.data.gymName);
  late final _phone = TextEditingController(text: widget.data.phone);
  late final _address = TextEditingController(text: widget.data.address);
  late final _server = TextEditingController(text: widget.data.serverUrl);

  @override
  void dispose() {
    for (final controller in [_gym, _phone, _address, _server]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SettingsDialog(
    title: 'Gym details & connection',
    action: 'Save preview settings',
    onSave: !widget.data.enabled
        ? null
        : () {
            if (!_form.currentState!.validate()) return;
            widget.data
              ..gymName = _gym.text.trim()
              ..phone = _phone.text.trim()
              ..address = _address.text.trim()
              ..serverUrl = _server.text.trim();
            Navigator.pop(context, true);
          },
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.data.enabled
                ? 'Preview preferences only · Changes reset on restart. This does not connect to a server or change the gym’s real configuration.'
                : 'Saving settings requires the backend and staff authorization.',
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('settings-gym-name'),
            controller: _gym,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Gym name *'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter the gym name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('settings-gym-phone'),
            controller: _phone,
            maxLength: 24,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ||
                    (RegExp(r'^\+?[\d ()-]+$').hasMatch(value!.trim()) &&
                        value.replaceAll(RegExp(r'\D'), '').length >= 7 &&
                        value.replaceAll(RegExp(r'\D'), '').length <= 15)
                ? null
                : 'Enter a valid phone number',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('settings-gym-address'),
            controller: _address,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('settings-server-url'),
            controller: _server,
            maxLength: 500,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API server address (optional)',
              hintText: 'https://gym-server.example',
              helperText: 'Use the gym server, not the attendance terminal. HTTP is not encrypted.',
              helperMaxLines: 4,
            ),
            validator: serverAddressError,
          ),
          const SizedBox(height: 20),
          const Text('Time zone: Asia/Kolkata · IST (UTC+05:30)'),
        ],
      ),
    ),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({
    required this.title,
    required this.action,
    required this.child,
    required this.onSave,
  });
  final String title;
  final String action;
  final Widget child;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => Dialog(
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
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('settings-form-scroll'),
              padding: const EdgeInsets.all(24),
              child: child,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 12,
              overflowSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('settings-dialog-cancel'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('settings-dialog-save'),
                  onPressed: onSave,
                  child: Text(action),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
