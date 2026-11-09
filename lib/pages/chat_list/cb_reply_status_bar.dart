// Connect-Bern: status line under the chips while the "Reply?" tab works.
// Shows how many chats are still being checked (results already found are
// listed meanwhile), or how many could not be checked, with a retry.

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/cb_unanswered.dart';
import 'package:flutter/material.dart';

class CbReplyStatusBar extends StatelessWidget {
  final CbUnansweredTracker tracker;
  const CbReplyStatusBar(this.tracker, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.secondary,
    );
    if (tracker.isBusy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text(l10n.checkingChatsLeft(tracker.pending), style: style),
          ),
        ],
      );
    }
    final failed = tracker.failed;
    if (failed == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(l10n.chatsNotChecked(failed), style: style)),
          TextButton(
            onPressed: tracker.retryFailed,
            child: Text(l10n.tryAgain),
          ),
        ],
      ),
    );
  }
}
