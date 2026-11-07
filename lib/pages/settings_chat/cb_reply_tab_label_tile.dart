// Connect-Bern: Settings → Chat → name of the "Reply?" chat-list tab.

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:flutter/material.dart';

class CbReplyTabLabelTile extends StatefulWidget {
  const CbReplyTabLabelTile({super.key});

  @override
  State<CbReplyTabLabelTile> createState() => _CbReplyTabLabelTileState();
}

class _CbReplyTabLabelTileState extends State<CbReplyTabLabelTile> {
  Future<void> _edit() async {
    final l10n = L10n.of(context);
    final input = await showTextInputDialog(
      context: context,
      title: l10n.replyTabName,
      hintText: l10n.notAnswered,
      message: l10n.replyTabNameHint,
      initialText: AppSettings.cbReplyTabLabel.value,
      maxLength: 24,
    );
    if (input == null) return;
    await AppSettings.cbReplyTabLabel.setItem(input.trim());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final custom = AppSettings.cbReplyTabLabel.value.trim();
    return ListTile(
      leading: const Icon(Icons.label_outline),
      title: Text(l10n.replyTabName),
      subtitle: Text(custom.isEmpty ? l10n.notAnswered : custom),
      trailing: const Icon(Icons.edit_outlined),
      onTap: _edit,
    );
  }
}
