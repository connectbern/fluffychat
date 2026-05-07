import 'dart:async';

import 'package:matrix/matrix.dart';

/// Connect-Bern: automatically join every room we are invited to.
///
/// If the invite carries `is_direct: true`, also register the room in the
/// `m.direct` account data so it appears in the DM list. Failed joins are
/// retried whenever the next sync delivers a room update.
class CbAutoAcceptInvites {
  CbAutoAcceptInvites(this.client) {
    _sub = client.onSync.stream.listen((_) => _processInvites());
    // Also run once immediately for invites already in cache.
    _processInvites();
  }

  final Client client;
  StreamSubscription<SyncUpdate>? _sub;
  final Set<String> _inFlight = <String>{};

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _processInvites() async {
    final invitedRooms = client.rooms
        .where((r) => r.membership == Membership.invite)
        .toList();
    for (final room in invitedRooms) {
      if (_inFlight.contains(room.id)) continue;
      _inFlight.add(room.id);
      // ignore: unawaited_futures
      _join(room).whenComplete(() => _inFlight.remove(room.id));
    }
  }

  Future<void> _join(Room room) async {
    try {
      final wasDirect = _isDirectInvite(room);
      final senderId = _inviteSender(room);
      await client.joinRoom(room.id);
      if (wasDirect && senderId != null) {
        try {
          final joined = client.getRoomById(room.id) ?? room;
          await joined.addToDirectChat(senderId);
        } catch (e, s) {
          Logs().w('[Connect-Bern] Failed to mark DM ${room.id}', e, s);
        }
      }
      Logs().i('[Connect-Bern] Auto-accepted invite to ${room.id}');
    } catch (e, s) {
      Logs().w(
          '[Connect-Bern] Auto-accept failed for ${room.id}; '
          'will retry on next sync.',
          e,
          s);
    }
  }

  bool _isDirectInvite(Room room) {
    for (final ev in room.states[EventTypes.RoomMember]?.values ??
        const <StrippedStateEvent>[]) {
      if (ev.stateKey == client.userID && ev.content['is_direct'] == true) {
        return true;
      }
    }
    return false;
  }

  String? _inviteSender(Room room) {
    for (final ev in room.states[EventTypes.RoomMember]?.values ??
        const <StrippedStateEvent>[]) {
      if (ev.stateKey == client.userID) {
        return ev.senderId;
      }
    }
    return null;
  }
}
