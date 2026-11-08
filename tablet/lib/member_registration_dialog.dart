import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'app_loading.dart';
import 'member_enrollment.dart';
import 'member_photo.dart';
import 'member_profile.dart';
import 'replab_api.dart';
import 'sample_attendance.dart';

class MemberRegistrationDialog extends StatefulWidget {
  const MemberRegistrationDialog({
    super.key,
    required this.members,
    required this.canSave,
    this.api,
    this.previewPlans,
    this.capturePhoto = captureMemberPhoto,
  });
  final List<MemberProfile> members;
  final bool canSave;
  final RepLabApi? api;
  final EnrollmentOptions? previewPlans;
  final Future<Uint8List?> Function(BuildContext) capturePhoto;
  @override
  State<MemberRegistrationDialog> createState() =>
      _MemberRegistrationDialogState();
}

class _MemberRegistrationDialogState extends State<MemberRegistrationDialog> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _emergency = TextEditingController();
  final _notes = TextEditingController();
  final _reference = TextEditingController();
  final _requestId = enrollmentRequestId();
  DateTime _joined = DateUtils.dateOnly(gymNow());
  DateTime _start = DateUtils.dateOnly(gymNow());
  int _step = 0, _months = 1, _training = 0, _insurance = 0;
  String? _planCode;
  String _method = 'cash';
  bool _confirmed = false, _saving = false, _capturing = false;
  bool _uncertain = false, _loadingOptions = false;
  String? _error, _optionsError;
  Uint8List? _photo;
  EnrollmentOptions? _options;
  Map<String, dynamic>? _submitted;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _loadOptions();
    } else if (widget.canSave) {
      final catalog =
          widget.previewPlans?.toJson() ?? EnrollmentOptions.previewData;
      catalog['plans'] = (catalog['plans'] as List)
          .where((plan) => (plan as Map)['active'] != false)
          .toList();
      _options = EnrollmentOptions.fromJson(catalog);
      if (_durations.isNotEmpty && !_durations.contains(_months)) {
        _months = _durations.first;
      }
    }
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _optionsError = null;
    });
    try {
      final options = await widget.api!.enrollmentOptions();
      if (mounted) {
        setState(() {
          _options = options;
          final selected = options.plans.where(
            (plan) => plan.code == _planCode,
          );
          if (selected.isEmpty) _planCode = null;
          final durations = _durations;
          if (durations.isNotEmpty && !durations.contains(_months)) {
            _months = durations.first;
          }
          if (_training > _months) _training = _months;
          if (_insurance > _months) _insurance = _months;
          _confirmed = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _optionsError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _optionsError = 'Could not load the plan catalogue.');
      }
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final controller in [
      _name,
      _phone,
      _email,
      _address,
      _emergency,
      _notes,
      _reference,
    ]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  EnrollmentPlan? get _plan => _planCode == null || _options == null
      ? null
      : _options!.plans.firstWhere((plan) => plan.code == _planCode);
  List<int> get _durations =>
      (_plan?.prices.keys.toList() ??
            _options?.plans
                .expand((plan) => plan.prices.keys)
                .toSet()
                .toList() ??
            [])
        ..sort();
  int get _base => _plan?.prices[_months] ?? 0;
  int get _total =>
      _base +
      _training * (_options?.trainingMonthly ?? 0) +
      _insurance * (_options?.insuranceMonthly ?? 0);
  bool get _busy => _saving || _capturing;

  String? _phoneError(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter a phone number';
    final digits = text.replaceAll(RegExp(r'\D'), '').length;
    if (!RegExp(r'^\+?[\d ()-]+$').hasMatch(text) ||
        digits < 7 ||
        digits > 15) {
      return 'Enter a valid phone number (7–15 digits)';
    }
    return null;
  }

  void _changeStep(int step) {
    setState(() {
      _step = step;
      _error = null;
      _confirmed = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() {
    if (_busy || _uncertain) return;
    if (_step == 0 && !_form.currentState!.validate()) return;
    if (_step == 1 && _photo == null) {
      setState(() => _error = 'Take a member photo to continue.');
      return;
    }
    if (_step == 2 && (_plan == null || !_plan!.prices.containsKey(_months))) {
      setState(() => _error = 'Select a plan to continue.');
      return;
    }
    _changeStep(_step + 1);
  }

  Future<void> _takePhoto() async {
    setState(() => _capturing = true);
    try {
      final photo = await widget.capturePhoto(context);
      if (mounted && photo != null) {
        setState(() {
          _photo = photo;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not access the camera. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Map<String, dynamic> _payload() => {
    'request_id': _requestId,
    'member': {
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'address': _address.text.trim(),
      'emergency_phone': _emergency.text.trim(),
      'notes': _notes.text.trim(),
      'joined': isoDate(_joined),
      'is_active': true,
    },
    'photo_base64': base64Encode(_photo!),
    'plan_code': _planCode,
    'months': _months,
    'starts_on': isoDate(_start),
    'training_months': _training,
    'insurance_months': _insurance,
    'payment_method': _method,
    'payment_reference': _reference.text.trim(),
    'payment_confirmed': true,
    if (_options!.revision != null) 'catalog_revision': _options!.revision,
  };

  Future<void> _save() async {
    if (_busy ||
        _uncertain ||
        !_confirmed ||
        _photo == null ||
        _plan == null ||
        !widget.canSave) {
      return;
    }
    if (widget.api == null) {
      final serial =
          widget.members.fold<int>(0, (highest, member) {
            final value =
                int.tryParse(member.number.replaceFirst('M-', '')) ?? 0;
            return highest > value ? highest : value;
          }) +
          1;
      Navigator.pop(
        context,
        MemberProfile(
          number: 'M-${serial.toString().padLeft(4, '0')}',
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          emergencyPhone: _emergency.text.trim(),
          notes: _notes.text.trim(),
          joined: _joined,
          photo: _photo,
          plan: _plan!.name,
          planStart: _start,
          planEnd: enrollmentEnd(_start, _months),
          enrollment: {
            'plan_name': _plan!.name,
            'months': _months,
            'training_months': _training,
            'insurance_months': _insurance,
            'base_paise': _base,
            'training_paise': _training * _options!.trainingMonthly,
            'insurance_paise': _insurance * _options!.insuranceMonthly,
            'total_paise': _total,
            'payment_method': _method,
            'payment_reference': _reference.text.trim(),
            'invoice_number': 'PREVIEW ONLY',
            'received_at': gymNow().toIso8601String(),
          },
        ),
      );
      return;
    }
    _submitted = _payload();
    await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api!.enrollMember(_submitted!);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _uncertain = error.uncertain;
          if (error.code == 'plan_catalog_changed' ||
              error.code == 'plan_unavailable') {
            _step = 2;
            _optionsError = error.message;
            _error = null;
            _options = null;
            _planCode = null;
            _confirmed = false;
            _submitted = null;
            if (_scroll.hasClients) _scroll.jumpTo(0);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The registration result could not be read. Check the registration before trying again.';
          _uncertain = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkRegistration() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.api!.findEnrollment(_requestId);
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'enrollment_not_found'
              ? 'Registration not found yet. Retry the same registration safely; do not collect payment again.'
              : error.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not check the registration. Retry the check or the same registration; do not collect payment again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _basicDetails() {
    final fields = [
      TextFormField(
        key: const ValueKey('member-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Full name *'),
        validator: (v) =>
            (v ?? '').trim().isEmpty ? 'Enter the member’s full name' : null,
      ),
      TextFormField(
        key: const ValueKey('member-phone'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        maxLength: 24,
        decoration: const InputDecoration(labelText: 'Phone *'),
        validator: _phoneError,
      ),
      TextFormField(
        key: const ValueKey('member-email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        maxLength: 254,
        decoration: const InputDecoration(labelText: 'Email (optional)'),
        validator: (v) =>
            (v ?? '').trim().isEmpty ||
                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
            ? null
            : 'Enter a valid email address',
      ),
      TextFormField(
        key: const ValueKey('member-emergency'),
        controller: _emergency,
        keyboardType: TextInputType.phone,
        maxLength: 24,
        decoration: const InputDecoration(labelText: 'Emergency phone *'),
        validator: _phoneError,
      ),
      TextFormField(
        key: const ValueKey('member-address'),
        controller: _address,
        maxLength: 500,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Address *'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the address' : null,
      ),
      TextFormField(
        key: const ValueKey('member-notes'),
        controller: _notes,
        maxLength: 2000,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Notes (optional)'),
      ),
    ];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in fields) ...[field, const SizedBox(height: 12)],
          OutlinedButton.icon(
            key: const ValueKey('member-joined'),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _joined,
                firstDate: DateTime(2000),
                lastDate: DateUtils.dateOnly(gymNow()),
              );
              if (date != null && mounted) setState(() => _joined = date);
            },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              'Joined on ${MaterialLocalizations.of(context).formatCompactDate(_joined)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Take a clear photo with the member’s permission. This is a profile photo, not face recognition enrollment.',
      ),
      const SizedBox(height: 20),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _photo == null
              ? Container(
                  width: 220,
                  height: 240,
                  color: const Color(0xFFE4F0ED),
                  child: const Icon(Icons.person_outline_rounded, size: 80),
                )
              : Image.memory(
                  _photo!,
                  key: const ValueKey('member-photo-preview'),
                  width: 220,
                  height: 240,
                  fit: BoxFit.cover,
                ),
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        key: const ValueKey('member-take-photo'),
        onPressed: _capturing ? null : _takePhoto,
        icon: const Icon(Icons.camera_alt_outlined),
        label: Text(_photo == null ? 'Take photo *' : 'Retake photo'),
      ),
    ],
  );

  Widget _addon(
    String key,
    String name,
    int monthly,
    int selected,
    ValueChanged<int> change,
  ) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: '$name · ${rupees(monthly)} / month',
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: ValueKey('member-$key-months'),
          value: selected,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: 0, child: Text('Not included')),
            for (var i = 1; i <= _months; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '$i ${i == 1 ? 'month' : 'months'} · ${rupees(i * monthly)}',
                ),
              ),
          ],
          onChanged: (value) => setState(() {
            change(value!);
            _confirmed = false;
          }),
        ),
      ),
    ),
  );

  Widget _planStep() {
    if (_options == null) {
      return Column(
        children: [
          if (_loadingOptions) const DumbbellLoader(label: 'Loading plans'),
          Text(
            _optionsError ??
                'A server connection is required to select a plan.',
          ),
          if (widget.api != null && !_loadingOptions)
            TextButton(
              onPressed: _loadOptions,
              child: const Text('Retry plans'),
            ),
        ],
      );
    }
    if (_options!.plans.isEmpty) {
      return Column(
        children: [
          const Text(
            'No active plans are available. Add or reactivate a plan in Settings → Manage plans.',
          ),
          if (widget.api != null)
            TextButton(
              onPressed: _loadOptions,
              child: const Text('Reload plans'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in _options!.plans) ...[
          Card(
            color: _planCode == plan.code
                ? const Color(0xFFE4F0ED)
                : Colors.white,
            child: ListTile(
              key: ValueKey('member-plan-${plan.code}'),
              selected: _planCode == plan.code,
              leading: Icon(
                _planCode == plan.code
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(plan.name),
              subtitle: Text(
                '${plan.description}\n${plan.prices.containsKey(_months) ? '${rupees(plan.prices[_months]!)} for $_months ${_months == 1 ? 'month' : 'months'}' : 'From ${rupees(plan.prices.values.reduce((a, b) => a < b ? a : b))} · Select a duration'}',
              ),
              isThreeLine: true,
              onTap: () => setState(() {
                _planCode = plan.code;
                if (!plan.prices.containsKey(_months)) {
                  _months = (plan.prices.keys.toList()..sort()).first;
                }
                if (_training > _months) _training = _months;
                if (_insurance > _months) _insurance = _months;
                _confirmed = false;
              }),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        KeyedSubtree(
          // Recreate the form state when plans offer different durations.
          key: ValueKey('member-duration-$_planCode-$_months'),
          child: DropdownButtonFormField<int>(
            key: const ValueKey('member-plan-months'),
            initialValue: _months,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Plan duration',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final months in _durations)
                DropdownMenuItem(
                  value: months,
                  child: Text(planDuration(months)),
                ),
            ],
            onChanged: (value) => setState(() {
              _months = value!;
              if (_training > _months) _training = _months;
              if (_insurance > _months) _insurance = _months;
              _confirmed = false;
            }),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('member-plan-start'),
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            'Starts ${MaterialLocalizations.of(context).formatCompactDate(_start)}',
          ),
          onPressed: () async {
            final today = DateUtils.dateOnly(gymNow());
            final value = await showDatePicker(
              context: context,
              initialDate: _start,
              firstDate: today,
              lastDate: today.add(const Duration(days: 366)),
            );
            if (value != null && mounted) setState(() => _start = value);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Valid through ${MaterialLocalizations.of(context).formatCompactDate(enrollmentEnd(_start, _months))} (inclusive)',
        ),
        _addon(
          'training',
          'Personal training',
          _options!.trainingMonthly,
          _training,
          (v) => _training = v,
        ),
        _addon(
          'insurance',
          'Insurance',
          _options!.insuranceMonthly,
          _insurance,
          (v) => _insurance = v,
        ),
        const SizedBox(height: 12),
        const Text(
          'Add-ons start with the plan. Choose their durations independently; they cannot exceed the plan duration.',
        ),
        if (_plan != null) ...[
          const SizedBox(height: 20),
          Text(
            'Total: ${rupees(_total)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ],
    );
  }

  Widget _paymentStep() {
    final theme = Theme.of(context);
    final preview = widget.api == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_name.text.trim(), style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text('${_plan!.name} · $_months ${_months == 1 ? 'month' : 'months'}'),
        Text('Plan: ${rupees(_base)}'),
        if (_training > 0)
          Text(
            'Personal training: $_training months · ${rupees(_training * _options!.trainingMonthly)}',
          ),
        if (_insurance > 0)
          Text(
            'Insurance: $_insurance months · ${rupees(_insurance * _options!.insuranceMonthly)}',
          ),
        const Divider(height: 32),
        Text(
          'Full payment: ${rupees(_total)}',
          key: const ValueKey('member-payment-total'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'cash',
              icon: Icon(Icons.payments_outlined),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: 'upi',
              icon: Icon(Icons.qr_code_rounded),
              label: Text('UPI'),
            ),
          ],
          selected: {_method},
          onSelectionChanged: _uncertain
              ? null
              : (value) => setState(() {
                  _method = value.single;
                  _confirmed = false;
                  _reference.clear();
                }),
        ),
        const SizedBox(height: 20),
        if (_method == 'upi') ...[
          Text(
            '${_options!.payeeName} · ${_options!.upiId}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (preview)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Preview only: payment QR disabled to prevent real transfers from test registrations.',
                textAlign: TextAlign.center,
              ),
            )
          else
            Center(
              child: Semantics(
                label:
                    'UPI payment QR for ${rupees(_total)} to ${_options!.payeeName}',
                child: QrImageView(
                  key: const ValueKey('member-upi-qr'),
                  data: upiPaymentUri(_options!, _total, _requestId),
                  size: 220,
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Ask the member to scan and pay the exact amount. Check the receiving account before confirming. Scanning the QR is not proof of payment.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('member-payment-reference'),
            controller: _reference,
            enabled: !_uncertain,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'UPI transaction reference (optional)',
            ),
          ),
        ] else
          Text(
            preview
                ? 'Preview only. Do not collect money for test registrations.'
                : 'Collect the full cash amount before confirming. No partial payments.',
          ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('member-payment-confirm'),
          contentPadding: EdgeInsets.zero,
          value: _confirmed,
          onChanged: _uncertain ? null : (v) => setState(() => _confirmed = v!),
          title: Text(
            preview
                ? 'Confirm simulated payment (preview only)'
                : 'I have verified receipt of ${rupees(_total)} in ${_method == 'cash' ? 'cash' : 'the receiving UPI account'}.',
          ),
          subtitle: const Text(
            'Recorded as staff confirmation, not automatic bank verification.',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = ['Basic details', 'Photo', 'Plan', 'Payment'];
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        key: const ValueKey('member-add-dialog'),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add member', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          Text(
                            '${i + 1}. ${steps[i]}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: i == _step
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == _step
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('member-form-scroll'),
                  controller: _scroll,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.api != null
                            ? 'Member, photo, plan and full-payment receipt are saved together at the final step.'
                            : widget.canSave
                            ? 'Preview only · Use test data. Nothing is saved to the server and no payment is processed.'
                            : 'Connect to the gym server to register members.',
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AbsorbPointer(
                        absorbing: _busy || _uncertain,
                        child: switch (_step) {
                          0 => _basicDetails(),
                          1 => _photoStep(),
                          2 => _planStep(),
                          _ => _paymentStep(),
                        },
                      ),
                      if (_uncertain) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Do not collect payment again or start another registration. Check the result, or retry this exact registration safely.',
                        ),
                        TextButton(
                          onPressed: _saving ? null : _checkRegistration,
                          child: const Text('Check registration'),
                        ),
                        OutlinedButton(
                          onPressed: _saving ? null : _submit,
                          child: const Text('Retry same registration'),
                        ),
                      ],
                    ],
                  ),
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
                      key: const ValueKey('member-add-cancel'),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    if (_step > 0)
                      TextButton(
                        key: const ValueKey('member-add-back'),
                        onPressed: _busy || _uncertain
                            ? null
                            : () => _changeStep(_step - 1),
                        child: const Text('Back'),
                      ),
                    FilledButton(
                      key: ValueKey(
                        _step == 3 ? 'member-add-save' : 'member-add-next',
                      ),
                      onPressed:
                          !widget.canSave ||
                              _busy ||
                              _uncertain ||
                              (_step == 2 && _options == null) ||
                              (_step == 3 && !_confirmed)
                          ? null
                          : _step == 3
                          ? _save
                          : _next,
                      child: _saving
                          ? const DumbbellLoader(size: 22)
                          : Text(_step == 3 ? 'Complete registration' : 'Next'),
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
