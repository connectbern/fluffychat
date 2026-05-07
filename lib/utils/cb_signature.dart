import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connect-Bern: storage + helpers for the per-device signing name.
///
/// The signing name persists across refreshes via [SharedPreferences] under
/// the key [storageKey]. UI listens to [notifier] to refresh on change.
class CbSignature {
  static const storageKey = 'cbern_signing_name';

  static String? _name;
  static SharedPreferences? _prefs;

  /// Notifies listeners (e.g. composer chip) when the name changes.
  static final notifier = _CbSignatureNotifier();

  static String? get name => _name;
  static bool get isSet => (_name ?? '').trim().isNotEmpty;

  /// Must be called once during app bootstrap (after SharedPreferences ready).
  static Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    final stored = prefs.getString(storageKey);
    _name = (stored == null || stored.trim().isEmpty) ? null : stored.trim();
  }

  static Future<void> set(String? newName) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final cleaned = newName?.trim();
    if (cleaned == null || cleaned.isEmpty) {
      await prefs.remove(storageKey);
      _name = null;
    } else {
      await prefs.setString(storageKey, cleaned);
      _name = cleaned;
    }
    notifier.bump();
  }

  /// The line that gets inserted at the bottom of the composer.
  static String? get signatureLine => isSet ? '\n$_name' : null;

  /// True if [text] ends with the current signature line.
  static bool textHasSignature(String text) {
    final line = signatureLine;
    if (line == null) return false;
    return text.endsWith(line);
  }

  /// Returns [text] with the trailing signature line removed (if present).
  /// Used both when saving drafts and when toggling the chip off.
  static String stripSignature(String text) {
    final line = signatureLine;
    if (line == null) return text;
    if (text.endsWith(line)) {
      return text.substring(0, text.length - line.length);
    }
    return text;
  }

  /// Append the signature line to [text] (no-op if already present or unset).
  static String appendSignature(String text) {
    final line = signatureLine;
    if (line == null) return text;
    if (text.endsWith(line)) return text;
    return text + line;
  }

  /// Whether the auto-insert rule applies for this room: signature is set
  /// AND the room's most recent message is older than 24h (or there is none).
  static bool shouldAutoInsertForRoom(Room room) {
    if (!isSet) return false;
    final lastEv = room.lastEvent;
    if (lastEv == null) return true;
    return DateTime.now().difference(lastEv.originServerTs) >
        const Duration(hours: 24);
  }
}

class _CbSignatureNotifier {
  final List<void Function()> _listeners = [];
  void addListener(void Function() cb) => _listeners.add(cb);
  void removeListener(void Function() cb) => _listeners.remove(cb);
  void bump() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}
