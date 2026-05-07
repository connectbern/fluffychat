import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/utils/cb_signature.dart';

/// Connect-Bern: Settings → Signature page.
///
/// Lets users set, edit or clear the device-local signing name used by the
/// composer chip and the 24h auto-insert.
class SettingsSignaturePage extends StatefulWidget {
  const SettingsSignaturePage({super.key});

  @override
  State<SettingsSignaturePage> createState() => _SettingsSignaturePageState();
}

class _SettingsSignaturePageState extends State<SettingsSignaturePage> {
  late final TextEditingController _ctrl =
      TextEditingController(text: CbSignature.name ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await CbSignature.set(_ctrl.text);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signing name saved')),
    );
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    await CbSignature.set(null);
    if (!mounted) return;
    _ctrl.clear();
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signing name cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms/settings')),
        ),
        title: const Text('Signature'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pick the name appended to your messages on this device. '
            'Tap the chip in the composer to insert or remove it. '
            'It auto-inserts on first room load if no message has been sent '
            'there in the last 24 hours.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ctrl,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Signing name',
              hintText: 'e.g. Chagai',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_outlined),
                onPressed: _saving ? null : _save,
                label: const Text('Save'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _clear,
                label: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
