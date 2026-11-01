import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_session.dart';

class ServerHostFields extends StatefulWidget {
  const ServerHostFields({
    super.key,
    required this.controller,
    this.enabled = true,
  });
  final TextEditingController controller;
  final bool enabled;
  @override
  State<ServerHostFields> createState() => _ServerHostFieldsState();
}

class _ServerHostFieldsState extends State<ServerHostFields> {
  late bool _ip =
      widget.controller.text.isEmpty ||
      RegExp(r'^[\d.]+$').hasMatch(widget.controller.text);
  late final _parts = List.generate(4, (i) {
    final parts = widget.controller.text.split('.');
    return TextEditingController(
      text: _ip && parts.length == 4 ? parts[i] : '',
    );
  });
  final _focus = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    for (final controller in _parts) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('IP address')),
          ButtonSegment(value: false, label: Text('Hostname')),
        ],
        selected: {_ip},
        onSelectionChanged: widget.enabled
            ? (v) => setState(() {
                _ip = v.single;
                widget.controller.text = _ip
                    ? _parts.map((c) => c.text).join('.')
                    : '';
              })
            : null,
      ),
      const SizedBox(height: 16),
      if (_ip)
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text('.'),
                ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('server-ip-$i'),
                  controller: _parts[i],
                  focusNode: _focus[i],
                  enabled: widget.enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    hintText: ['192', '168', '31', '239'][i],
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) > 255
                      ? '0–255'
                      : null,
                  onChanged: (v) {
                    widget.controller.text = _parts
                        .map((c) => int.tryParse(c.text)?.toString() ?? '')
                        .join('.');
                    if (v.length == 3 && i < 3) _focus[i + 1].requestFocus();
                  },
                ),
              ),
            ],
          ],
        )
      else
        TextFormField(
          key: const ValueKey('server-hostname'),
          controller: widget.controller,
          enabled: widget.enabled,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server hostname',
            hintText: 'lovin.local',
          ),
          validator: serverHostError,
        ),
    ],
  );
}
