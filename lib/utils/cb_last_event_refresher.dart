import 'dart:async';

import 'package:matrix/matrix.dart';

/// Connect-Bern: heals chat-list previews stuck on "Loading… Please wait.".
///
/// When a sync delivers a *limited* timeline for a room (e.g. a bridge wrote
/// many state events into thousands of rooms at once), the SDK drops the
/// room's last event, shows a `refreshingLastEvent` placeholder and fires one
/// `/messages` request per room - all at the same time. With thousands of
/// rooms most of those requests hit the SDK's 30 s timeout, the error is
/// swallowed, and the placeholder is stored and kept until the room sees new
/// activity. This retries the refresh a few rooms at a time with a cool-down
/// per room: rooms shown in the chat list first, then (once per client) every
/// other stuck room in the background, so they stop floating to the top.
class CbLastEventRefresher {
  static const int _maxParallel = 4;
  static const Duration _coolDown = Duration(minutes: 2);
  static const Duration _timeout = Duration(seconds: 30);

  static final List<Room> _queue = [];
  static final Set<String> _pending = {};
  static final Map<String, DateTime> _lastTry = {};
  static final Map<String, DateTime> _lastSweep = {};
  static int _running = 0;

  static bool isStuck(Room room) =>
      room.membership == Membership.join &&
      room.lastEvent?.type == EventTypes.refreshingLastEvent;

  /// Safe to call from `build()`: only schedules work.
  static void request(Room room) {
    if (!isStuck(room)) return;
    final last = _lastTry[room.id];
    if (last != null && DateTime.now().difference(last) < _coolDown) return;
    if (_pending.add(room.id)) {
      _queue.insert(0, room);
    } else if (_queue.remove(room)) {
      // Shown on screen now: move it to the front.
      _queue.insert(0, room);
    }
    final now = DateTime.now();
    final lastSweep = _lastSweep[room.client.clientName];
    if (lastSweep == null || now.difference(lastSweep) > _coolDown) {
      _lastSweep[room.client.clientName] = now;
      for (final other in room.client.rooms) {
        if (isStuck(other) && _pending.add(other.id)) _queue.add(other);
      }
    }
    scheduleMicrotask(_pump);
  }

  static void _pump() {
    while (_running < _maxParallel && _queue.isNotEmpty) {
      final room = _queue.removeAt(0);
      if (!isStuck(room)) {
        _pending.remove(room.id);
        continue;
      }
      _running++;
      _lastTry[room.id] = DateTime.now();
      _refresh(room).whenComplete(() {
        _running--;
        _pending.remove(room.id);
        _pump();
      });
    }
  }

  static Future<void> _refresh(Room room) async {
    try {
      final event = await room.refreshLastEvent(timeout: _timeout);
      if (event == null && room.lastEvent == null) {
        // Nothing to preview (no visible message). The SDK cleared the
        // placeholder in memory only; store that and rebuild the list.
        await room.client.database.transaction(
          () => room.client.handleSync(
            SyncUpdate(
              nextBatch: '',
              rooms: RoomsUpdate(
                join: {
                  room.id: JoinedRoomUpdate(
                    timeline: TimelineUpdate(limited: false),
                  ),
                },
              ),
            ),
          ),
        );
      }
    } catch (e, s) {
      Logs().w('Could not refresh last event of ${room.id}', e, s);
    }
  }
}
