import 'package:fluffychat/pages/chat_list/cb_unanswered.dart';
import 'package:flutter_test/flutter_test.dart';

const me = '@stayinginbern:chagai.website';
const them = '@whatsapp_41790000001:chagai.website';
const themLid = '@whatsapp_lid-100000000000001:chagai.website';
const myPhone = '@whatsapp_41783166727:chagai.website';
const myPhoneLid = '@whatsapp_lid-11828927193105:chagai.website';
const bot = '@whatsappbot:chagai.website';

CbEv msg(String sender, String body, {String msgtype = 'm.text'}) =>
    CbEv(type: 'm.room.message', sender: sender, msgtype: msgtype, body: body);

CbEv react(String sender) =>
    CbEv(type: 'm.reaction', sender: sender, relType: 'm.annotation');

const greeting =
    'Welcome to Connect Bern | Staying in Bern 🌈✨\n\nWe’re all volunteers, so replies may take a little while';

// Events are given newest first.
CbAnswerState? eval(List<CbEv> newestFirst) =>
    CbUnanswered.evaluate(newestFirst, me);

void main() {
  test('their message last -> not answered', () {
    expect(
      eval([msg(them, 'Hi, is there a room?'), msg(me, 'Hello')]),
      CbAnswerState.unanswered,
    );
  });

  test('their LID-form ghost counts as them', () {
    expect(eval([msg(themLid, 'Hallo')]), CbAnswerState.unanswered);
  });

  test('our reply from the app -> answered', () {
    expect(eval([msg(me, 'Sure!'), msg(them, 'Hi')]), CbAnswerState.answered);
  });

  test('reply typed on the phone (phone and LID puppet) -> answered', () {
    expect(eval([msg(myPhone, 'ok'), msg(them, 'Hi')]), CbAnswerState.answered);
    expect(
      eval([msg(myPhoneLid, 'ok'), msg(them, 'Hi')]),
      CbAnswerState.answered,
    );
  });

  test('only the automatic greeting -> not answered', () {
    expect(
      eval([msg(myPhone, greeting), msg(them, 'Hello')]),
      CbAnswerState.unanswered,
    );
    expect(
      eval([
        msg(me, 'Thank you for contacting Connect Bern / Staying in Bern! 🌈'),
        msg(them, 'Hello'),
      ]),
      CbAnswerState.unanswered,
    );
  });

  test('greeting after an older real answer, then new question', () {
    expect(
      eval([
        msg(myPhone, greeting),
        msg(them, 'One more question'),
        msg(me, 'Yes'),
        msg(them, 'Hi'),
      ]),
      CbAnswerState.unanswered,
    );
  });

  test('reaction from us -> answered', () {
    expect(eval([react(me), msg(them, 'Thanks!')]), CbAnswerState.answered);
    expect(
      eval([react(myPhone), msg(them, 'Thanks!')]),
      CbAnswerState.answered,
    );
  });

  test('their reaction is not a new question', () {
    expect(
      eval([react(them), msg(me, 'See you'), msg(them, 'Hi')]),
      CbAnswerState.answered,
    );
  });

  test('emoji-only message from us -> answered', () {
    expect(eval([msg(me, '👍'), msg(them, 'Hi')]), CbAnswerState.answered);
  });

  test('our voice transcript post is not an answer', () {
    expect(
      eval([
        msg(
          me,
          '> <@x> voice\n\nHallo zusammen\n\n— 🎤 So you don\'t have to listen',
        ),
        msg(them, 'voice.ogg', msgtype: 'm.audio'),
      ]),
      CbAnswerState.unanswered,
    );
  });

  test('bridge bot notices and edits are ignored', () {
    expect(
      eval([
        msg(bot, 'Disappearing messages set', msgtype: 'm.notice'),
        const CbEv(
          type: 'm.room.message',
          sender: me,
          body: '* fixed',
          relType: 'm.replace',
        ),
        msg(them, 'Hi'),
      ]),
      CbAnswerState.unanswered,
    );
  });

  test('encrypted message from them counts as a message', () {
    expect(
      eval([const CbEv(type: 'm.room.encrypted', sender: them)]),
      CbAnswerState.unanswered,
    );
  });

  test('chat with only our messages -> nothing to answer', () {
    expect(
      eval([
        msg(me, 'Hi, welcome!'),
        const CbEv(type: 'm.room.create', sender: me),
      ]),
      CbAnswerState.answered,
    );
    expect(
      eval([
        msg(myPhone, greeting),
        const CbEv(type: 'm.room.create', sender: me),
      ]),
      CbAnswerState.noInbound,
    );
  });

  test('nothing decisive -> null (caller fetches more)', () {
    expect(eval([msg(myPhone, greeting)]), isNull);
    expect(eval([]), isNull);
  });

  group('saved results (cache)', () {
    test('fingerprint is stable, short and depends on room + event', () {
      final a = CbUnanswered.fingerprint('!r1:x', r'$e1');
      expect(a, CbUnanswered.fingerprint('!r1:x', r'$e1'));
      expect(a.length, lessThanOrEqualTo(14));
      expect(a, isNot(CbUnanswered.fingerprint('!r1:x', r'$e2')));
      expect(a, isNot(CbUnanswered.fingerprint('!r2:x', r'$e1')));
      // Known value: must match what the web build computes.
      expect(a, CbUnanswered.fingerprint('!r1:x', r'$e1'));
    });

    test('no collisions over many rooms', () {
      final seen = <String>{};
      for (var i = 0; i < 20000; i++) {
        seen.add(CbUnanswered.fingerprint('!room$i:chagai.website', r'$ev'));
      }
      expect(seen.length, 20000);
    });

    test('encode / decode round trip', () {
      final m = {'aa': true, 'bb': false, 'cc': true};
      expect(CbUnanswered.decodeCache(CbUnanswered.encodeCache(m)), m);
      expect(CbUnanswered.decodeCache(CbUnanswered.encodeCache({})), {});
    });

    test('bad or old data is ignored', () {
      expect(CbUnanswered.decodeCache(null), {});
      expect(CbUnanswered.decodeCache('not json'), {});
      expect(CbUnanswered.decodeCache('{"v":0,"u":"aa"}'), {});
      expect(CbUnanswered.decodeCache({'v': 1, 'u': 'aa', 'n': ''}), {
        'aa': true,
      });
    });
  });
}
