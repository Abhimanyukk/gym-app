import 'package:flutter/material.dart';

import 'app_loading.dart';
import 'member_enrollment.dart';
import 'replab_api.dart';
import 'settings_preview.dart';
import 'warning_ribbon.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({
    super.key,
    required this.preview,
    required this.onClose,
    this.api,
    this.padding = EdgeInsets.zero,
  });
  final SettingsPreview preview;
  final VoidCallback onClose;
  final RepLabApi? api;
  final EdgeInsets padding;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  final _scroll = ScrollController();
  final _ratesForm = GlobalKey<FormState>();
  final _training = TextEditingController();
  final _insurance = TextEditingController();
  EnrollmentOptions? _catalog;
  List<EnrollmentPlan> _draft = [];
  bool _loading = false, _saving = false, _dirty = false;
  bool _showArchived = false, _needsReload = false;
  String? _error;
  bool get _busy => _loading || _saving;
  bool get _editable =>
      !_busy &&
      !_needsReload &&
      _catalog != null &&
      (widget.api != null || widget.preview.enabled);

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _load();
    } else if (widget.preview.enabled) {
      _replace(widget.preview.plans);
    }
  }

  void _replace(EnrollmentOptions catalog) {
    _catalog = catalog;
    _draft = List.of(catalog.plans);
    _training.text = priceInput(catalog.trainingMonthly);
    _insurance.text = priceInput(catalog.insuranceMonthly);
    _dirty = false;
    _needsReload = false;
    _error = null;
  }

  Future<bool> _discard(String action) async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard your draft?'),
            content: Text(
              _needsReload
                  ? 'A previous save may already have applied. Reload the server values to check. Your local draft will be replaced.'
                  : 'Your plan changes have not been saved. $action will discard this draft.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                key: const ValueKey('plans-discard'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _close() async {
    if (_busy || !await _discard('Back to Settings') || !mounted) return;
    widget.onClose();
  }

  Future<void> _load() async {
    if (_busy || !await _discard('Reload') || !mounted) return;
    if (widget.api == null) {
      if (widget.preview.enabled) {
        setState(() => _replace(widget.preview.plans));
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.api!.plans();
      if (catalog.revision == null) {
        throw const ApiException(
          'The server returned an invalid plan catalogue.',
        );
      }
      if (mounted) setState(() => _replace(catalog));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the plan catalogue. Reload to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() => setState(() {
    _dirty = true;
    _error = null;
  });

  Future<void> _edit([EnrollmentPlan? plan]) async {
    if (!_editable) return;
    final saved = await showDialog<EnrollmentPlan>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanForm(
        plan: plan,
        names: [
          for (final existing in _draft)
            if (existing.code != plan?.code) existing.name.toLowerCase(),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final index = _draft.indexWhere((p) => p.code == saved.code);
      if (index < 0) {
        _draft.add(saved);
      } else {
        _draft[index] = saved;
      }
      if (!saved.active) _showArchived = true;
      _dirty = true;
      _error = null;
    });
  }

  void _archive(EnrollmentPlan plan) {
    final index = _draft.indexWhere((p) => p.code == plan.code);
    setState(() {
      _draft[index] = EnrollmentPlan.fromJson({
        ...plan.toJson(),
        'active': !plan.active,
      });
      _showArchived = true;
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_editable || !_dirty || !_ratesForm.currentState!.validate()) return;
    final fields = {
      'revision': _catalog!.revision,
      'plans': [for (final plan in _draft) plan.toJson()],
      'training_monthly_paise': parseRupees(_training.text)!,
      'insurance_monthly_paise': parseRupees(_insurance.text)!,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = widget.api != null
          ? await widget.api!.savePlans(fields)
          : EnrollmentOptions.fromJson({
              ...fields,
              'revision': _catalog!.revision! + 1,
              'upi_id': _catalog!.upiId,
              'payee_name': _catalog!.payeeName,
            });
      if (saved.revision == null) {
        throw const FormatException('Missing revision');
      }
      if (!mounted) return;
      if (widget.api == null) widget.preview.plans = saved;
      setState(() => _replace(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.api != null
                ? 'Plans saved. Existing memberships and receipts are unchanged.'
                : 'Preview catalogue updated. No server plans were changed.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _needsReload =
              error.uncertain || error.code == 'plan_catalog_changed';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The save result could not be read. Reload server values before editing again.';
          _needsReload = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _training.dispose();
    _insurance.dispose();
    super.dispose();
  }

  Widget _panel(List<Widget> children) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFDDDDDD)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _planCard(EnrollmentPlan plan) => _panel([
    Row(
      children: [
        Icon(
          Icons.fitness_center_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            plan.name,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      plan.active
          ? 'Active · Available for new registrations'
          : 'Archived · Existing memberships are unchanged',
      style: TextStyle(
        color: plan.active ? const Color(0xFF286455) : Colors.black54,
      ),
    ),
    if (plan.description.isNotEmpty) ...[
      const SizedBox(height: 12),
      Text(plan.description),
    ],
    const SizedBox(height: 16),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry
            in (plan.prices.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          Chip(
            label: Text(
              '${entry.key} ${entry.key == 1 ? 'month' : 'months'} · ${rupees(entry.value)}',
            ),
          ),
      ],
    ),
    const SizedBox(height: 16),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: ValueKey('plans-edit-${plan.code}'),
          onPressed: _editable ? () => _edit(plan) : null,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit plan'),
        ),
        TextButton.icon(
          key: ValueKey('plans-archive-${plan.code}'),
          onPressed: _editable ? () => _archive(plan) : null,
          icon: Icon(
            plan.active ? Icons.archive_outlined : Icons.unarchive_outlined,
          ),
          label: Text(plan.active ? 'Archive' : 'Reactivate'),
        ),
      ],
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _draft
        .where((plan) => _showArchived || plan.active)
        .toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: DumbbellRefresh(
        key: const ValueKey('plans-refresh'),
        padding: widget.padding,
        scrollController: _scroll,
        onRefresh: _load,
        child: Column(
          key: const ValueKey('plans-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('plans-back'),
                  tooltip: 'Back to Settings',
                  onPressed: _busy ? null : _close,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plans',
                    key: const ValueKey('plans-title'),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('plans-add'),
                  onPressed: _editable && _draft.length < 64
                      ? () => _edit()
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add plan'),
                ),
                FilledButton.icon(
                  key: const ValueKey('plans-save'),
                  onPressed: _editable && _dirty ? _save : null,
                  icon: _saving
                      ? const DumbbellLoader(size: 20)
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving' : 'Save changes'),
                ),
                TextButton.icon(
                  key: const ValueKey('plans-reload'),
                  onPressed:
                      !_busy && (widget.api != null || widget.preview.enabled)
                      ? _load
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reload'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey('plans-scroll'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Customize membership plans, duration prices and monthly add-ons.',
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(
                        child: DumbbellLoader(label: 'Loading plans'),
                      ),
                    if (widget.api == null || _error != null) ...[
                      WarningRibbon(
                        key: const ValueKey('plans-notice'),
                        message:
                            _error ??
                            (widget.preview.enabled
                                ? 'Preview only · Changes stay in this debug preview.'
                                : 'Backend not connected. Plan management is unavailable.'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_catalog != null) ...[
                      Text(
                        _dirty
                            ? 'Unsaved changes · Save to publish your catalogue.'
                            : 'Saved catalogue · Changes apply only to future registrations.',
                      ),
                      SwitchListTile(
                        key: const ValueKey('plans-show-archived'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show archived plans'),
                        value: _showArchived,
                        onChanged: (value) =>
                            setState(() => _showArchived = value),
                      ),
                      if (_draft.every((plan) => !plan.active)) ...[
                        const WarningRibbon(
                          message: 'No active plans. New members cannot register until a plan is added or reactivated.',
                        ),
                        const SizedBox(height: 16),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth /
                                      MediaQuery.textScalerOf(context)
                                          .scale(1) >=
                                  900
                              ? 2
                              : 1;
                          final width =
                              (constraints.maxWidth - 20 * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: 20,
                            runSpacing: 20,
                            children: [
                              for (final plan in visible)
                                SizedBox(
                                  key: ValueKey('plans-card-${plan.code}'),
                                  width: width,
                                  child: _planCard(plan),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      _panel([
                        Text(
                          'Monthly add-ons',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Members can choose add-on durations independently, up to their plan duration.',
                        ),
                        const SizedBox(height: 16),
                        Form(
                          key: _ratesForm,
                          child: Column(
                            children: [
                              for (final (key, label, controller) in [
                                (
                                  'plans-training-price',
                                  'Personal training / month',
                                  _training,
                                ),
                                (
                                  'plans-insurance-price',
                                  'Insurance / month',
                                  _insurance,
                                ),
                              ]) ...[
                                TextFormField(
                                  key: ValueKey(key),
                                  controller: controller,
                                  enabled: _editable,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: label,
                                    prefixText: '₹ ',
                                  ),
                                  onChanged: (_) => _changed(),
                                  validator: (value) =>
                                      parseRupees(value ?? '') == null
                                      ? 'Enter an amount from ₹0 to ₹1,00,00,000 with up to 2 decimals'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _PriceFields = ({
  int id,
  TextEditingController months,
  TextEditingController price,
});

class _PlanForm extends StatefulWidget {
  const _PlanForm({this.plan, this.names = const []});
  final EnrollmentPlan? plan;
  final List<String> names;
  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _description = TextEditingController(
    text: widget.plan?.description ?? '',
  );
  final _rows = <_PriceFields>[];
  int _nextId = 0;
  late bool _active = widget.plan?.active ?? true;
  late final _code = widget.plan?.code ?? enrollmentRequestId();

  @override
  void initState() {
    super.initState();
    for (final entry in (widget.plan?.prices ?? {1: 0}).entries) {
      _rows.add((
        id: _nextId++,
        months: TextEditingController(text: '${entry.key}'),
        price: TextEditingController(
          text: widget.plan == null ? '' : priceInput(entry.value),
        ),
      ));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final row in _rows) {
      row.months.dispose();
      row.price.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      EnrollmentPlan(
        code: _code,
        name: _name.text.trim(),
        description: _description.text.trim(),
        active: _active,
        prices: {
          for (final row in _rows)
            int.parse(row.months.text.trim()): parseRupees(row.price.text)!,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('plan-dialog'),
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.plan == null ? 'Add plan' : 'Edit plan',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('plan-name'),
                        controller: _name,
                        maxLength: 100,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Plan name *',
                        ),
                        validator: (value) {
                          final name = (value ?? '').trim();
                          if (name.isEmpty) return 'Enter a plan name';
                          if (widget.names.contains(name.toLowerCase())) {
                            return 'Another plan already uses this name';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        key: const ValueKey('plan-description'),
                        controller: _description,
                        maxLength: 300,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description / access included',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Available for new registrations'),
                        value: _active,
                        onChanged: (value) => setState(() => _active = value),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Set a full-payment price for each duration (1–120 months).',
                      ),
                      const SizedBox(height: 16),
                      for (final row in _rows) ...[
                        Row(
                          key: ValueKey('plan-price-row-${row.id}'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('plan-duration-${row.id}'),
                                controller: row.months,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Months *',
                                ),
                                validator: (value) {
                                  final months = int.tryParse(
                                    (value ?? '').trim(),
                                  );
                                  if (months == null ||
                                      months < 1 ||
                                      months > 120) {
                                    return 'Use 1–120 months';
                                  }
                                  if (_rows.any(
                                    (other) =>
                                        other.id != row.id &&
                                        int.tryParse(
                                              other.months.text.trim(),
                                            ) ==
                                            months,
                                  )) {
                                    return 'Duration already added';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                key: ValueKey('plan-price-${row.id}'),
                                controller: row.price,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Full price *',
                                  prefixText: '₹ ',
                                ),
                                validator: (value) {
                                  final amount = parseRupees(value ?? '');
                                  return amount == null || amount == 0
                                      ? 'Enter a positive price (up to 2 decimals)'
                                      : null;
                                },
                              ),
                            ),
                            IconButton(
                              key: ValueKey('plan-remove-duration-${row.id}'),
                              tooltip: 'Remove duration',
                              onPressed: _rows.length == 1
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      setState(() => _rows.remove(row));
                                      row.months.dispose();
                                      row.price.dispose();
                                    },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      TextButton.icon(
                        key: const ValueKey('plan-add-duration'),
                        onPressed: _rows.length >= 24
                            ? null
                            : () => setState(
                                () => _rows.add((
                                  id: _nextId++,
                                  months: TextEditingController(),
                                  price: TextEditingController(),
                                )),
                              ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add duration price'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Apply to your draft, then use Save changes on the Plans page to publish.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('plan-cancel'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('plan-apply'),
                  onPressed: _apply,
                  child: const Text('Apply to draft'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
