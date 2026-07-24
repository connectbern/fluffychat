import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/pages/wa_start_chat/normalize_phone.dart';
import 'package:fluffychat/pages/wa_start_chat/wa_bridge.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/adaptive_dialogs/user_dialog.dart';

class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  const NewPrivateChat({super.key, required this.deeplink});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();

    final deeplink = widget.deeplink;
    if (deeplink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UrlLauncher(context, deeplink).openMatrixToUrl();
      });
    }
  }

  Future<void> searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    final result = await Matrix.of(
      context,
    ).client.searchUserDirectory(searchTerm);
    final profiles = result.results;

    if (searchTerm.isValidMatrixId &&
        searchTerm.sigil == '@' &&
        !profiles.any((profile) => profile.userId == searchTerm)) {
      profiles.add(Profile(userId: searchTerm));
    }

    return profiles;
  }

  void inviteAction() => FluffyShare.shareInviteLink(context);

  /// Connect-Bern: "Message a phone number" — start a WhatsApp chat from any
  /// phone number typed by the user. Normalizes the input to E.164, asks the
  /// mautrix-whatsapp bridge to open the DM (`!wa pm`), then navigates to it.
  /// All failure modes are handled gracefully (never an unhandled crash).
  Future<void> startWhatsAppByNumberAction() async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;

    final input = await showTextInputDialog(
      context: context,
      title: l10n.messageAPhoneNumber,
      message: l10n.messageAPhoneNumberHint,
      hintText: '+41 79 123 45 67',
      keyboardType: TextInputType.phone,
      okLabel: l10n.startChat,
      cancelLabel: l10n.cancel,
      autocorrect: false,
      validator: (value) {
        final normalized = normalizePhone(value);
        if (normalized.e164.isEmpty) {
          return l10n.enterAValidPhoneNumber;
        }
        return null;
      },
    );
    if (input == null) return;

    final normalized = normalizePhone(input);
    if (normalized.e164.isEmpty) return;

    if (!mounted) return;
    final router = GoRouter.of(context);
    final result = await showFutureLoadingDialog(
      context: context,
      // Primary candidate first (Switzerland for bare numbers, or the exact
      // international number the user typed).
      future: () => startWhatsAppChat(client, normalized.e164),
    );

    final roomId = result.result;
    if (roomId == null) {
      // The loading dialog already surfaced the friendly error message and the
      // user dismissed it. Nothing more to do.
      return;
    }
    router.go('/rooms/$roomId');
  }

  Future<void> openScannerAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (info.version.sdkInt < 21) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.unsupportedAndroidVersionLong)),
        );
        return;
      }
    }
    if (!mounted) return;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (_) => QrScannerModal(
        onScan: (link) => UrlLauncher(context, link).openMatrixToUrl(),
      ),
    );
  }

  Future<void> copyUserId() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    await Clipboard.setData(
      ClipboardData(text: Matrix.of(context).client.userID!),
    );
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  void openUserModal(Profile profile) =>
      UserDialog.show(context: context, profile: profile);

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
