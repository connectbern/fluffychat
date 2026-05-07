import 'package:flutter/material.dart';

import 'package:fluffychat/utils/cb_signature.dart';
import 'chat.dart';

/// Connect-Bern: composer chip showing "Signing as [name]".
///
/// Tapping the chip toggles the signature line at the bottom of the
/// message input. The chip is hidden when no signing name is set.
class CbSigningChip extends StatefulWidget {
  final ChatController controller;

  const CbSigningChip(this.controller, {super.key});

  @override
  State<CbSigningChip> createState() => _CbSigningChipState();
}

class _CbSigningChipState extends State<CbSigningChip> {
  late VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) setState(() {});
    };
    CbSignature.notifier.addListener(_listener);
    widget.controller.sendController.addListener(_listener);
  }

  @override
  void dispose() {
    CbSignature.notifier.removeListener(_listener);
    widget.controller.sendController.removeListener(_listener);
    super.dispose();
  }

  void _toggle() {
    final c = widget.controller.sendController;
    final hasSig = CbSignature.textHasSignature(c.text);
    c.text = hasSig
        ? CbSignature.stripSignature(c.text)
        : CbSignature.appendSignature(c.text);
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  @override
  Widget build(BuildContext context) {
    if (!CbSignature.isSet) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hasSig = CbSignature.textHasSignature(
      widget.controller.sendController.text,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: Icon(
            hasSig ? Icons.check_circle : Icons.draw_outlined,
            size: 18,
          ),
          label: Text('Signing as ${CbSignature.name ?? ''}'),
          onPressed: _toggle,
          visualDensity: VisualDensity.compact,
          backgroundColor:
              hasSig ? theme.colorScheme.secondaryContainer : null,
        ),
      ),
    );
  }
}
