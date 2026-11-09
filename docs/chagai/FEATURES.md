# Connect-Bern features on top of upstream FluffyChat

Branch `Connect-Bern` (live at https://connect-bern-chat.netlify.app). Re-check every item after
each upstream merge. Keep patches small; new behaviour goes in new files where possible.

| # | Feature | Where | How to verify |
|---|---|---|---|
| 1 | Default homeserver **chagai.website**, username prefilled | `lib/pages/login/login.dart`, `setting_keys.dart` | login screen shows chagai.website |
| 2 | **Spaces UI hidden** (rail, filter chip, search) | `chat_list_body.dart`, `chat_list_view.dart`, `chat_list_header.dart` | no spaces rail / chip on the chat list |
| 3 | **Auto-accept invites** + DMs tagged in `m.direct` | `lib/utils/cb_auto_accept_invites.dart` | invite the test account → joins, shows under DMs |
| 4 | **Message signature** (composer chip, auto-insert) + Signature settings page | `cb_signature.dart`, `cb_signing_chip.dart`, `settings_signature/` | settings → Signature; compose shows the chip |
| 5 | **Unread tab default, large-group filter (>5 members), empty state** | `chat_list.dart`, `chat_list_body.dart` | chat list opens on Unread; big groups not listed there |
| 6 | **"Message a phone number"** (start a WhatsApp chat from a number) | `lib/pages/wa_start_chat/`, `new_private_chat*` | New chat → Message a phone number → opens the bridge DM |
| 7 | **No white screen on chat open** (LateInitializationError fix) | `lib/pages/chat/chat.dart` | open any chat after a cold start |
| 8 | **Netlify build** (rust/wasm-pack/vodozemac script, COOP/COEP headers) | `netlify.toml`, `scripts/netlify-build.sh` | Netlify deploy log green |
| 9 | **"Reply?" filter chip** (formerly "Not answered"; DE "Antwort?"), placed right after Messages — chats whose newest message from them has no later answer from us; our side = logged-in user, @stayinginbern, @me and the WhatsApp puppets (phone + LID form) of both our numbers; the WhatsApp-Business greeting and voice/video transcript posts are not answers; a reaction or any other message (emoji-only too) is. Lazy: local sync store first, one 30-event `/messages` fetch only when needed, newest chats first, cached per last event. Same >5-member group rule as Unread. **Saved results:** every verdict that needed a closer look is stored as a fingerprint of (room, last event) in localStorage (`cb.reply_cache.<mxid>`, every 3 s) and in account data `website.chagai.reply_cache` (at most every 3 min + when leaving the tab) → instant on reload and on other devices; only rooms with a new last event are re-checked. **Never stuck:** each check gives up after 15 s (a lost request used to freeze the whole queue = endless spinner, fixed 2026-11-09); 4 checks in parallel; status line "Still checking N chats" / "N chats couldn't be checked · Try again" (`cb_reply_status_bar.dart`, ARB `checkingChatsLeft`, `chatsNotChecked`); leaving the tab lets the queued checks finish in the background. **Custom name:** Settings → Chat → "Name of the Reply? tab" (`cb.reply_tab_label`, empty = default). | `lib/pages/chat_list/cb_unanswered.dart`, `lib/pages/settings_chat/cb_reply_tab_label_tile.dart` (+ hooks in `chat_list.dart` enum order/label, `chat_list_body.dart`, `settings_chat_view.dart`, `setting_keys.dart` `cbReplyTabLabel`; ARB `notAnswered`, `checkingChats`, `noUnansweredChats`, `replyTabName`, `replyTabNameHint`) | `flutter test test/chat_list/`; tap the chip → list fills in; reload → list appears at once without a progress bar sweep |

Merge hot spots: `lib/pages/chat_list/{chat_list,chat_list_body,chat_list_header,chat_list_view}.dart`,
`lib/pages/chat/chat_view.dart`.
