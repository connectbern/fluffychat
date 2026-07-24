// Connect-Bern: WhatsApp bridge glue for the "Message a phone number" feature.
//
// Dart port of Chagai's proven Cinny implementation
// (src/app/features/wa-start-chat/waBridge.ts). It talks to the mautrix-whatsapp
// bridge bot: send `!wa pm <e164>` into the bridge management room, then resolve
// the outcome (new DM room / existing DM room / not-on-WhatsApp / error /
// timeout) — never an unhandled crash.
//
// ─────────────────────────────────────────────────────────────────────────────
// Bridge configuration — VERIFIED against Chagai's server.
// ─────────────────────────────────────────────────────────────────────────────
//  - The bridge bot is `@whatsappbot:chagai.website` (joined to each user's
//    management room).
//  - `!wa pm <e164>` is the correct command (confirmed from real management-room
//    history — `!wa pn` returns "Unknown command"; `!wa pm +<number>` works).
//  - The command is issued **as whoever is logged in** to this FluffyChat
//    instance, into that account's WhatsApp bridge **management room**. The
//    connect-bern-chat deployment logs in as `@stayinginbern:chagai.website`,
//    whose management room is `!DXORRePztlYSpKZzwZ:chagai.website` (members:
//    @stayinginbern + @whatsappbot — verified read-only in the Synapse DB,
//    2026-07-24). So we DEFAULT the management room to that id, but keep it
//    configurable and FALL BACK to auto-discovery if the fixed room isn't
//    joined (e.g. when a different account logs in).
//
// Everything the feature needs to be re-pointed is isolated to this file.

import 'dart:async';

import 'package:matrix/matrix.dart';

/// Static, verified configuration for the WhatsApp bridge.
///
/// This is the single place to re-point the feature if the server topology ever
/// changes. Marked as clearly-labelled constants per the task spec.
class WaBridgeConfig {
  /// Fixed room id of the bridge-bot **management room** to send `!wa pm` into.
  /// This is the primary target. If the logged-in user is NOT joined to it, we
  /// fall back to discovering the management room by the bot's presence.
  ///
  /// VERIFIED (read-only DB check, 2026-07-24): @stayinginbern's WhatsApp
  /// management room on chagai.website — the account connect-bern-chat uses.
  static const String managementRoomId = '!DXORRePztlYSpKZzwZ:chagai.website';

  /// Localpart of the bridge bot (no @, no :server). Used for discovery + reply
  /// matching. The bot's server is derived from the logged-in user's server.
  static const String bridgeBotLocalpart = 'whatsappbot';

  /// Command template; `{number}` → E.164 with leading +.
  static const String pmCommandTemplate = '!wa pm {number}';

  /// Max wait for a result (new DM, or the bot's reply) before giving up.
  /// 45s: give the bridge time to resolve the number + create/invite the portal,
  /// OR to reply "already have a chat" / "not on WhatsApp".
  static const Duration newRoomTimeout = Duration(seconds: 45);
}

/// Resolve the bridge-bot user id for the current client/session.
String resolveBridgeBotUserId(Client client) {
  final myUserId = client.userID ?? '';
  final idx = myUserId.indexOf(':');
  final server = idx >= 0 ? myUserId.substring(idx + 1) : 'chagai.website';
  return '@${WaBridgeConfig.bridgeBotLocalpart}:$server';
}

/// Build the `!wa pm <number>` command body from an E.164 string.
String buildPmCommand(String e164) =>
    WaBridgeConfig.pmCommandTemplate.replaceFirst('{number}', e164);

/// Count of joined members in a room (from the room summary, cheap + reliable).
int _joinedMemberCount(Room room) {
  final n = room.summary.mJoinedMemberCount;
  if (n != null) return n;
  // Fallback to the local participant list if the summary count is missing.
  return room.getParticipants([Membership.join]).length;
}

/// Find the management/DM room with the WhatsApp bridge bot. This is the room
/// where `!wa` commands are issued. We PREFER the configured fixed room id (if
/// we are joined to it); otherwise we discover it: a JOINED room that contains
/// the bot as a member and is small (a DM/management room, not a big portal).
///
/// If several candidates exist we prefer:
///   1) a 2-member room (just me + bot),
///   2) then the smallest room,
///   3) then the most recently active.
Room? findBridgeBotRoom(Client client) {
  // 1) Fixed, verified management room — use it if we're actually joined.
  final fixed = client.getRoomById(WaBridgeConfig.managementRoomId);
  if (fixed != null && fixed.membership == Membership.join) return fixed;

  // 2) Fall back to discovery (different logged-in account, or room not synced).
  final botUserId = resolveBridgeBotUserId(client);
  final myUserId = client.userID ?? '';

  final candidates = client.rooms.where((room) {
    if (room.membership != Membership.join) return false;
    final participants = room.getParticipants([Membership.join]);
    final hasBot = participants.any((u) => u.id == botUserId);
    if (!hasBot) return false;
    final hasMe = participants.any((u) => u.id == myUserId);
    // Bot must be present, I must be present, and it must be small
    // (management/DM), not a group portal.
    return hasMe && _joinedMemberCount(room) <= 3;
  }).toList();

  candidates.sort((a, b) {
    final aTwo = _joinedMemberCount(a) == 2 ? 0 : 1;
    final bTwo = _joinedMemberCount(b) == 2 ? 0 : 1;
    if (aTwo != bTwo) return aTwo - bTwo;
    final sizeDiff = _joinedMemberCount(a) - _joinedMemberCount(b);
    if (sizeDiff != 0) return sizeDiff;
    final aTs = a.latestEventReceivedTime.millisecondsSinceEpoch;
    final bTs = b.latestEventReceivedTime.millisecondsSinceEpoch;
    return bTs - aTs;
  });

  return candidates.isNotEmpty ? candidates.first : null;
}

/// Snapshot of the room ids the client currently knows (joined or invited).
Set<String> knownRoomIds(Client client) {
  final set = <String>{};
  for (final room in client.rooms) {
    if (room.membership == Membership.join ||
        room.membership == Membership.invite) {
      set.add(room.id);
    }
  }
  return set;
}

/// Heuristic: does this room look like the WhatsApp DM the bridge just created
/// for our `!wa pm` command? A freshly-bridged WhatsApp DM:
///   - we are joined OR invited,
///   - it is a small (<= 2 real user) room,
///   - it is NOT the bridge management room itself,
///   - (best signal) the bridge bot is present, since mautrix invites via the
///     bot.
/// The caller also filters by "not previously known", so this only needs to
/// distinguish a new portal from unrelated new rooms.
bool looksLikeNewWaDm(Client client, Room room, String? botRoomId) {
  if (room.id == botRoomId) return false;
  final membership = room.membership;
  if (membership != Membership.join && membership != Membership.invite) {
    return false;
  }

  final botUserId = resolveBridgeBotUserId(client);
  final myUserId = client.userID ?? '';

  // Members excluding me and the bot → the actual WhatsApp contact(s).
  final others = room
      .getParticipants([Membership.join, Membership.invite])
      .where((u) => u.id != myUserId && u.id != botUserId)
      .toList();

  // A DM portal has exactly one "other" party (the contact). Allow 0 too,
  // because right at creation the contact ghost may not have synced yet.
  return others.length <= 1;
}

/// Parse a matrix.to room link out of the bridge bot's reply. mautrix formats
/// the "you already have a direct chat" reply with a link like
///   https://matrix.to/#/!roomid:server   (plain body) OR
///   https://matrix.to/#/%21roomid%3Aserver   (url-encoded, in formatted_body)
/// Returns the `!roomid:server` or `!roomid` string, or null.
String? parseRoomIdFromMatrixTo(String text) {
  if (text.isEmpty) return null;
  // Match both encoded (%21) and plain (!) forms of the room-id sigil.
  final m = RegExp(
    r'matrix\.to/#/(%21|!)([^/\s"<]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  var rest = Uri.decodeComponent(m.group(2)!);
  // rest is the localpart(+:server) after the '!'. Strip any trailing junk.
  rest = rest.replaceFirst(RegExp(r'[)>"' "'" r'].*$'), '');
  return '!$rest';
}

/// What the bridge bot's reply to `!wa pm` told us.
enum BotReplyKind { existing, notOnWhatsApp, error, other }

class BotReply {
  final BotReplyKind kind;

  /// For `existing`: the room id to open.
  final String? roomId;

  /// For `error` / `notOnWhatsApp` / `other`: the raw body text.
  final String body;

  const BotReply(this.kind, {this.roomId, this.body = ''});
}

/// Classify a bridge-bot message body/formatted_body posted in the management
/// room in response to our command.
BotReply classifyBotReply(String body, [String? formattedBody]) {
  final text = '$body\n${formattedBody ?? ''}';
  final lower = text.toLowerCase();

  if (lower.contains('already have a direct chat') ||
      lower.contains('already have a chat')) {
    final roomId = parseRoomIdFromMatrixTo(text);
    if (roomId != null) {
      return BotReply(BotReplyKind.existing, roomId: roomId);
    }
    // We know a chat exists but couldn't parse the link — treat as a soft error.
    return BotReply(
      BotReplyKind.error,
      body: body.isNotEmpty ? body : 'You already have a chat with this number.',
    );
  }
  if (lower.contains('is not on whatsapp') ||
      lower.contains('not on whatsapp') ||
      lower.contains('failed to resolve identifier')) {
    return BotReply(BotReplyKind.notOnWhatsApp, body: body);
  }
  if (lower.contains('unknown command') ||
      lower.contains('usage:') ||
      lower.contains('error') ||
      lower.contains('failed')) {
    return BotReply(BotReplyKind.error, body: body);
  }
  return BotReply(BotReplyKind.other, body: body);
}

/// The resolved outcome of a `!wa pm` command.
enum WaitOutcomeKind { room, notOnWhatsApp, error, timeout }

class WaitOutcome {
  final WaitOutcomeKind kind;

  /// For `room`: the room id to open (new OR existing).
  final String? roomId;

  /// For `notOnWhatsApp` / `error`: a user-friendly message.
  final String message;

  const WaitOutcome(this.kind, {this.roomId, this.message = ''});
}

/// Wait for the bridge to respond to our `!wa pm` command. Resolves as soon as
/// ANY of these happens:
///   - a NEW WhatsApp DM room appears (→ open it),
///   - the bot replies "you already have a direct chat …" (→ open that room),
///   - the bot replies "… is not on WhatsApp" (→ friendly message),
///   - any other bot error notice (→ surface it),
///   - or the timeout elapses (→ timeout).
///
/// This mirrors the Cinny fix for the old bug where the flow only handled "new
/// room created" and otherwise hung for the full timeout and threw a scary error
/// even though the bot had already answered (the common "already have a chat"
/// case).
Future<WaitOutcome> waitForWaResult(
  Client client, {
  required Set<String> preexisting,
  required String? botRoomId,
  required DateTime sinceTs,
  Duration? timeout,
}) {
  final effectiveTimeout = timeout ?? WaBridgeConfig.newRoomTimeout;
  final botUserId = resolveBridgeBotUserId(client);
  final completer = Completer<WaitOutcome>();
  final subscriptions = <StreamSubscription>[];
  Timer? timer;

  void finish(WaitOutcome outcome) {
    if (completer.isCompleted) return;
    timer?.cancel();
    for (final sub in subscriptions) {
      sub.cancel();
    }
    completer.complete(outcome);
  }

  // (a) A brand-new WhatsApp DM room shows up (surfaced via sync updates).
  void considerRoom(Room room) {
    if (completer.isCompleted) return;
    if (preexisting.contains(room.id)) return;
    if (looksLikeNewWaDm(client, room, botRoomId)) {
      finish(WaitOutcome(WaitOutcomeKind.room, roomId: room.id));
    }
  }

  // (b) The bot posts a reply in the management room.
  void considerEvent(Event event) {
    if (completer.isCompleted) return;
    if (botRoomId != null && event.room.id != botRoomId) return;
    if (event.type != EventTypes.Message) return;
    if (event.senderId != botUserId) return;
    // Ignore replies from before we issued the command (1s slack for clock skew).
    if (event.originServerTs.millisecondsSinceEpoch <
        sinceTs.millisecondsSinceEpoch - 1000) {
      return;
    }

    final content = event.content;
    final body = content['body'] is String ? content['body'] as String : '';
    final formatted = content['formatted_body'] is String
        ? content['formatted_body'] as String
        : null;
    final reply = classifyBotReply(body, formatted);

    switch (reply.kind) {
      case BotReplyKind.existing:
        finish(WaitOutcome(WaitOutcomeKind.room, roomId: reply.roomId));
        break;
      case BotReplyKind.notOnWhatsApp:
        finish(
          const WaitOutcome(
            WaitOutcomeKind.notOnWhatsApp,
            message:
                "That number isn't on WhatsApp, so no chat could be started.",
          ),
        );
        break;
      case BotReplyKind.error:
        finish(WaitOutcome(WaitOutcomeKind.error, message: reply.body));
        break;
      case BotReplyKind.other:
        // ignore (e.g. state/keepalive notices); keep waiting.
        break;
    }
  }

  // Listen for new/changed rooms via sync, and for bot messages in the timeline.
  subscriptions.add(
    client.onSync.stream.listen((_) {
      for (final room in client.rooms) {
        considerRoom(room);
      }
    }),
  );
  subscriptions.add(client.onTimelineEvent.stream.listen(considerEvent));

  timer = Timer(effectiveTimeout, () {
    finish(const WaitOutcome(WaitOutcomeKind.timeout));
  });

  // Immediate sweep — the room may already be present.
  for (final room in client.rooms) {
    considerRoom(room);
  }

  return completer.future;
}

/// Error carrying a user-friendly message (dialog shows `.message` verbatim).
class StartWhatsAppChatException implements Exception {
  final String message;
  const StartWhatsAppChatException(this.message);
  @override
  String toString() => message;
}

/// Full client-side flow:
///   1. find the bridge-bot management room (fixed id, else discovery),
///   2. send `!wa pm <e164>` into it (literal text — command parsing OFF),
///   3. wait for the outcome: a new DM room, an existing DM room, "not on
///      WhatsApp", another error, or a timeout,
///   4. auto-join the room if we were only invited,
///   5. return its room id — or throw a `StartWhatsAppChatException` with a
///      friendly, user-readable message (never an unhandled crash).
///
/// Performs NO navigation — the caller navigates so it can use the app router.
Future<String> startWhatsAppChat(Client client, String e164) async {
  final botRoom = findBridgeBotRoom(client);
  if (botRoom == null) {
    throw const StartWhatsAppChatException(
      'Could not find the WhatsApp bridge chat. Make sure you are logged in and '
      'the WhatsApp bridge is connected, then try again.',
    );
  }

  final preexisting = knownRoomIds(client);
  final command = buildPmCommand(e164);
  final sinceTs = DateTime.now();

  try {
    // parseCommands:false so `!wa pm …` is sent to the bridge as literal text
    // and NOT intercepted by the client's own command parser. parseMarkdown is
    // also off to keep the body byte-exact.
    await botRoom.sendTextEvent(
      command,
      parseCommands: false,
      parseMarkdown: false,
    );
  } catch (_) {
    throw const StartWhatsAppChatException(
      'Could not send the WhatsApp chat request to the bridge. Please try again '
      'in a moment.',
    );
  }

  final outcome = await waitForWaResult(
    client,
    preexisting: preexisting,
    botRoomId: botRoom.id,
    sinceTs: sinceTs,
  );

  switch (outcome.kind) {
    case WaitOutcomeKind.notOnWhatsApp:
      throw StartWhatsAppChatException(outcome.message);
    case WaitOutcomeKind.error:
      throw StartWhatsAppChatException(outcome.message);
    case WaitOutcomeKind.timeout:
      throw const StartWhatsAppChatException(
        'The WhatsApp bridge did not respond in time. The chat may still appear '
        'in your list shortly — please check in a moment.',
      );
    case WaitOutcomeKind.room:
      break;
  }

  final newRoomId = outcome.roomId!;

  // If the bridge invited us rather than auto-joining, join now so we can open
  // it. Non-fatal if it fails — the room view handles the "accept invite" state.
  final newRoom = client.getRoomById(newRoomId);
  if (newRoom != null && newRoom.membership == Membership.invite) {
    try {
      await newRoom.join();
    } catch (_) {
      // ignore
    }
  }

  return newRoomId;
}
