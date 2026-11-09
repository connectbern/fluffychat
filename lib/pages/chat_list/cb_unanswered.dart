// Connect-Bern: "Reply?" (formerly "Not answered") chat-list filter.
//
// A chat is "not answered" when the newest message from someone else has no
// later answer from our side. Our side = the logged-in account, the other
// Connect-Bern account, and the WhatsApp puppets of our own phone numbers
// (messages typed on the phone arrive under those ghosts, phone- or LID-form).
//
// Not an answer: the WhatsApp-Business automatic greeting and our automatic
// voice/video transcript posts. An answer: any other message from us
// (emoji-only included) or a reaction from us.
//
// Kept in one file so upstream merges only touch chat_list.dart lightly.

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// Result of evaluating a chat.
enum CbAnswerState { unanswered, answered, noInbound }

/// A minimal, SDK-independent view of a timeline event (keeps the rule
/// unit-testable without a client).
class CbEv {
  final String type;
  final String sender;
  final String? msgtype;
  final String? body;
  final String? relType;
  final bool redacted;

  const CbEv({
    required this.type,
    required this.sender,
    this.msgtype,
    this.body,
    this.relType,
    this.redacted = false,
  });

  factory CbEv.fromEvent(Event e) => CbEv(
    type: e.type,
    sender: e.senderId,
    msgtype: e.content.tryGet<String>('msgtype'),
    body: e.content.tryGet<String>('body'),
    relType: e.relationshipType,
    redacted: e.redacted,
  );
}

abstract class CbUnanswered {
  /// Chip label: the user's own text from Settings → Chat, else [fallback]
  /// (the translated default, "Reply?").
  static String label(String fallback) {
    final custom = AppSettings.cbReplyTabLabel.value.trim();
    return custom.isEmpty ? fallback : custom;
  }

  /// Account-data type holding the saved results, so another device or a
  /// fresh browser opens the tab instantly too.
  static const String cacheType = 'website.chagai.reply_cache';

  /// Short, stable fingerprint of "room X with last event Y" (two 32-bit
  /// FNV-1a hashes, base36). Same result on web and native; the event and
  /// room ids themselves are never stored.
  static String fingerprint(String roomId, String lastEventId) {
    final s = '$roomId|$lastEventId';
    var a = 0x811c9dc5, b = 0x050c5d1f;
    for (final c in s.codeUnits) {
      a = _fnvStep(a ^ c);
      b = _fnvStep(b ^ (c + 0x9e));
    }
    return a.toRadixString(36) + b.toRadixString(36).padLeft(7, '0');
  }

  // h * 16777619 mod 2^32 via shifts (exact in JavaScript as well).
  static int _fnvStep(int h) =>
      (h + (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) &
      0xFFFFFFFF;

  /// Saved results: fingerprint -> is unanswered.
  static String encodeCache(Map<String, bool> verdicts) => jsonEncode({
    'v': 1,
    'u': [for (final e in verdicts.entries) if (e.value) e.key].join(','),
    'n': [for (final e in verdicts.entries) if (!e.value) e.key].join(','),
  });

  static Map<String, bool> decodeCache(Object? raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is! Map || m['v'] != 1) return {};
      Iterable<String> ids(Object? v) =>
          v is String && v.isNotEmpty ? v.split(',') : const [];
      return {
        for (final id in ids(m['n'])) id: false,
        for (final id in ids(m['u'])) id: true,
      };
    } catch (_) {
      return {};
    }
  }

  /// Senders that are always "our side", besides the logged-in user.
  static const Set<String> ownSenders = {
    '@stayinginbern:chagai.website',
    '@me:chagai.website',
    // Staying-in-Bern phone (+41 78 316 67 27): phone form + LID form.
    '@whatsapp_41783166727:chagai.website',
    '@whatsapp_lid-11828927193105:chagai.website',
    // Chagai's own phone (+41 76 652 44 56): phone form + LID form.
    '@whatsapp_41766524456:chagai.website',
    '@whatsapp_lid-212334660300826:chagai.website',
  };

  /// Starts of the WhatsApp-Business automatic greetings (all versions seen).
  static const List<String> autoReplyPrefixes = [
    'welcome to connect bern',
    'willkommen bei connect bern',
    'thank you for contacting staying in bern',
    'thank you for contacting connect bern',
    "hello! we're so excited that you found",
    'hello! we’re so excited that you found',
  ];

  static final RegExp _transcriptFooter = RegExp(
    r'^(?:\*\s+)?(?:— ?🎤 .+|— ?🎬 .+|🎤 transcript|🎤 auto-transcribed.*'
    r'|🎬 auto-transcribed.*|- trascrizione.*)\s*$',
  );

  static final RegExp _bridgeBot = RegExp(r'^@[a-z0-9_]*bot:');

  static const Set<String> _messageTypes = {
    EventTypes.Message,
    EventTypes.Encrypted,
    EventTypes.Sticker,
    EventTypes.CallInvite,
  };

  static bool isOwnSender(String sender, String? myUserId) =>
      sender == myUserId || ownSenders.contains(sender);

  static bool isBot(String sender) => _bridgeBot.hasMatch(sender);

  static bool isAutoReply(String? body) {
    if (body == null) return false;
    final b = body.trimLeft().toLowerCase();
    return autoReplyPrefixes.any(b.startsWith);
  }

  static bool isTranscriptPost(String? body) =>
      body != null &&
      body.split('\n').any((l) => _transcriptFooter.hasMatch(l.trim()));

  /// Evaluates events given NEWEST FIRST. Returns null when the list holds
  /// nothing decisive (caller may fetch more history or give up).
  static CbAnswerState? evaluate(Iterable<CbEv> newestFirst, String? myUserId) {
    for (final e in newestFirst) {
      if (e.redacted || e.relType == RelationshipTypes.edit) continue;
      if (e.type == EventTypes.RoomCreate) return CbAnswerState.noInbound;
      if (isOwnSender(e.sender, myUserId)) {
        if (e.type == EventTypes.Reaction) return CbAnswerState.answered;
        if (!_messageTypes.contains(e.type)) continue;
        if (isAutoReply(e.body) || isTranscriptPost(e.body)) continue;
        return CbAnswerState.answered;
      }
      if (isBot(e.sender)) continue;
      if (_messageTypes.contains(e.type)) return CbAnswerState.unanswered;
    }
    return null;
  }

  /// Chats the filter looks at at all (same large-group rule as Unread).
  /// [isDirect] is passed in because Room.isDirectChat is slow for groups.
  static bool isCandidate(Room room, {required bool isDirect}) =>
      room.membership == Membership.join &&
      !room.isSpace &&
      (isDirect || (room.summary.mJoinedMemberCount ?? 0) <= 5);
}

/// Lazily classifies rooms for the "Not answered" filter. Never blocks the UI.
///
/// - Instantly: a room whose last message is a real answer from us is hidden.
/// - Then, newest chats first, a few at a time: the room's recent events from
///   the local sync store are checked (milliseconds, no network) - this also
///   sees reactions, which the chat list's "last message" ignores. Only when
///   those are not enough (e.g. just our automatic greeting) one short history
///   fetch is made. Results are cached per last event and the list fills in as
///   they arrive.
///
/// Saved results: every verdict that needed a closer look is remembered as a
/// fingerprint of (room, last event) - in this browser (instant on reload)
/// and in Matrix account data (instant on another device). A room only gets
/// checked again when a new event arrives in it.
class CbUnansweredTracker {
  final Client client;
  final void Function() onChanged;

  CbUnansweredTracker(this.client, this.onChanged) {
    _loadSaved();
  }

  /// Fingerprint -> unanswered, from the last session / other devices.
  Map<String, bool> _saved = {};
  String? _lastLocal;
  String? _lastRemote;
  Timer? _saveLocal;
  Timer? _saveRemote;

  String get _localKey => 'cb.reply_cache.${client.userID}';

  static const int _historyLimit = 30;
  static const int _localLimit = 15;
  static const int _parallel = 4;

  /// A check that takes longer than this is given up for now (a lost
  /// request on a mobile connection used to stall the whole queue forever).
  static const Duration _checkTimeout = Duration(seconds: 15);

  /// Pause after each room so the (single-threaded) web UI stays smooth even
  /// on accounts with thousands of chats.
  static const Duration _breather = Duration(milliseconds: 25);

  final Map<String, _Verdict> _cache = {};
  Set<String>? _dmRoomIds;
  final List<String> _queue = [];
  final Set<String> _queued = {};
  int _running = 0;
  bool _active = false;
  bool _disposed = false;
  StreamSubscription<Event>? _sub;
  Timer? _notify;

  bool get isBusy => _running > 0 || _queue.isNotEmpty;

  /// Chats still waiting to be checked.
  int get pending => _running + _queue.length;

  /// Chats whose check failed or timed out this session (see [retryFailed]).
  int get failed => _cache.values.where((v) => v.failed).length;

  /// Checks the failed chats again.
  void retryFailed() {
    _cache.removeWhere((_, v) => v.failed);
    onChanged();
  }

  void start() {
    if (_active) return;
    _active = true;
    _dmRoomIds = null; // m.direct may have changed since last time
    _loadSaved(); // another device may have saved newer results
    _sub = client.onTimelineEvent.stream.listen(_onTimelineEvent);
    _pump();
  }

  /// Leaving the tab: the chats already queued keep being checked in the
  /// background, so the tab is ready next time; nothing new is queued.
  void stop() {
    if (_active) _flush();
    _active = false;
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    _disposed = true;
    _queue.clear();
    _queued.clear();
    _notify?.cancel();
    _saveLocal?.cancel();
    _saveRemote?.cancel();
  }

  void _loadSaved() {
    final remote = client.accountData[CbUnanswered.cacheType]?.content;
    String? local;
    try {
      local = AppSettings.store.getString(_localKey);
    } catch (_) {}
    _lastLocal = local;
    _saved = {
      ...CbUnanswered.decodeCache(remote?['data']),
      ...CbUnanswered.decodeCache(local),
    };
  }

  String _snapshot() => CbUnanswered.encodeCache({
    for (final e in _cache.entries)
      if (e.value.saved)
        CbUnanswered.fingerprint(e.key, e.value.lastEventId):
            e.value.state == CbAnswerState.unanswered,
  });

  void _scheduleSave() {
    _saveLocal ??= Timer(const Duration(seconds: 3), () {
      _saveLocal = null;
      _writeLocal(_snapshot());
    });
    // Account data syncs to every device, so upload rarely.
    _saveRemote ??= Timer(const Duration(minutes: 3), () {
      _saveRemote = null;
      _writeRemote(_snapshot());
    });
  }

  void _flush() {
    if (_saveLocal == null && _saveRemote == null) return;
    _saveLocal?.cancel();
    _saveRemote?.cancel();
    _saveLocal = _saveRemote = null;
    final snap = _snapshot();
    _writeLocal(snap);
    _writeRemote(snap);
  }

  void _writeLocal(String snap) {
    if (snap == _lastLocal) return;
    _lastLocal = snap;
    try {
      AppSettings.store.setString(_localKey, snap);
    } catch (_) {}
  }

  void _writeRemote(String snap) {
    final userId = client.userID;
    if (userId == null || snap == _lastRemote) return;
    if (client.accountData[CbUnanswered.cacheType]?.content['data'] == snap) {
      _lastRemote = snap;
      return;
    }
    _lastRemote = snap;
    client
        .setAccountData(userId, CbUnanswered.cacheType, {'data': snap})
        .catchError((e) {
          _lastRemote = null;
          Logs().w('Could not save the Reply? results', e);
        });
  }

  void _onTimelineEvent(Event e) {
    // A reaction or message from us settles the chat right away.
    if (CbUnanswered.isOwnSender(e.senderId, client.userID) &&
        e.type == EventTypes.Reaction) {
      final key = e.room.lastEvent?.eventId;
      if (key != null) {
        _cache[e.room.id] = _Verdict(key, CbAnswerState.answered, saved: true);
        _changed();
      }
    }
  }

  /// The filter predicate. Never blocks: unknown rooms get queued.
  /// Called for every chat on every list rebuild, so the cached path must be
  /// cheap: one map lookup.
  bool isUnanswered(Room room) {
    final last = room.lastEvent;
    if (last == null) return false;
    final cached = _cache[room.id];
    if (cached != null && cached.lastEventId == last.eventId) {
      return cached.state == CbAnswerState.unanswered;
    }
    final dms = _dmRoomIds ??= {
      for (final ids in client.directChats.values) ...ids,
    };
    if (!CbUnanswered.isCandidate(room, isDirect: dms.contains(room.id))) {
      _cache[room.id] = _Verdict(last.eventId, CbAnswerState.noInbound);
      return false;
    }
    final quick = CbUnanswered.evaluate([CbEv.fromEvent(last)], client.userID);
    if (quick == CbAnswerState.answered) {
      _cache[room.id] = _Verdict(last.eventId, quick!);
      return false;
    }
    // Known from an earlier session or another device?
    final saved = _saved[CbUnanswered.fingerprint(room.id, last.eventId)];
    if (saved != null) {
      _cache[room.id] = _Verdict(
        last.eventId,
        saved ? CbAnswerState.unanswered : CbAnswerState.answered,
        saved: true,
      );
      return saved;
    }
    // Their message last (we may have reacted) or our automatic post last
    // (look further back): decide in the background, show once known.
    _enqueue(room.id);
    return false;
  }

  void _enqueue(String roomId) {
    if (!_active || _queued.contains(roomId)) return;
    _queued.add(roomId);
    _queue.add(roomId);
    scheduleMicrotask(_pump);
  }

  void _pump() {
    while (!_disposed && _running < _parallel && _queue.isNotEmpty) {
      final roomId = _queue.removeAt(0);
      _running++;
      _check(roomId)
          .timeout(_checkTimeout, onTimeout: () => _giveUp(roomId))
          .then((_) => Future.delayed(_breather))
          .whenComplete(() {
        _running--;
        _queued.remove(roomId);
        _changed();
        _pump();
      });
    }
  }

  Future<void> _check(String roomId) async {
    final room = client.getRoomById(roomId);
    final last = room?.lastEvent;
    if (room == null || last == null) return;
    try {
      // 1) Events we already have locally from sync (contiguous newest part).
      final local = await client.database.getEventList(
        room,
        limit: _localLimit,
      );
      final localState = CbUnanswered.evaluate(
        local.map(CbEv.fromEvent),
        client.userID,
      );
      if (localState != null) {
        _cache[roomId] = _Verdict(last.eventId, localState, saved: true);
        return;
      }
      // 2) Not enough locally: one short history fetch from the server.
      final filter = StateFilter(
        types: [
          EventTypes.Message,
          EventTypes.Encrypted,
          EventTypes.Sticker,
          EventTypes.CallInvite,
          EventTypes.Reaction,
          EventTypes.RoomCreate,
        ],
        lazyLoadMembers: true,
      );
      final resp = await client.getRoomEvents(
        roomId,
        Direction.b,
        limit: _historyLimit,
        filter: jsonEncode(filter.toJson()),
      );
      final events = <CbEv>[];
      for (final m in resp.chunk) {
        var ev = Event.fromMatrixEvent(m, room);
        if (ev.type == EventTypes.Encrypted &&
            CbUnanswered.isOwnSender(ev.senderId, client.userID)) {
          // Only our own encrypted posts need their text (auto greeting?).
          try {
            ev = await client.encryption?.decryptRoomEvent(ev) ?? ev;
          } catch (_) {}
        }
        events.add(CbEv.fromEvent(ev));
      }
      final state =
          CbUnanswered.evaluate(events, client.userID) ??
          CbAnswerState.noInbound;
      _cache[roomId] = _Verdict(last.eventId, state, saved: true);
    } catch (e, s) {
      Logs().w('Not-answered check failed for $roomId', e, s);
      // Don't retry on every list refresh: forbidden = never (saved),
      // anything else = via "Retry" or next session.
      if (e is MatrixException && e.error == MatrixError.M_FORBIDDEN) {
        _cache[roomId] = _Verdict(
          last.eventId,
          CbAnswerState.noInbound,
          saved: true,
        );
      } else {
        _giveUp(roomId);
      }
    }
  }

  void _giveUp(String roomId) {
    final last = client.getRoomById(roomId)?.lastEvent;
    if (last == null) return;
    final known = _cache[roomId];
    if (known != null && known.lastEventId == last.eventId) return;
    _cache[roomId] = _Verdict(
      last.eventId,
      CbAnswerState.noInbound,
      failed: true,
    );
  }

  void _changed() {
    _scheduleSave();
    if (_notify?.isActive ?? false) return;
    _notify = Timer(const Duration(milliseconds: 1000), () {
      if (_active) onChanged();
    });
  }
}

class _Verdict {
  final String lastEventId;
  final CbAnswerState state;

  /// Needed a closer look -> worth remembering across sessions.
  final bool saved;

  /// Check failed or timed out; hidden for now, can be retried.
  final bool failed;
  const _Verdict(
    this.lastEventId,
    this.state, {
    this.saved = false,
    this.failed = false,
  });
}
