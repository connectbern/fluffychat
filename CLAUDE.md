# Claude Instructions — Connect-Bern / FluffyChat

## ALWAYS work natively on Windows. NEVER use the Linux sandbox.

This project lives at `C:\Users\chaga\OneDrive\Documents\fluffychat` (the mounted workspace folder).
All file edits, git operations, and Flutter commands must be run **directly on Windows**, either via:
- The **Read / Write / Edit** file tools (which write directly to the Windows filesystem), or
- A **Windows terminal** opened via computer-use (PowerShell or Windows Terminal).

**Do NOT:**
- Clone the repo to `/tmp/` or any Linux path and work from there
- Use the Linux bash sandbox for git commits or pushes
- Run flutter, dart, or cargo from the Linux sandbox

**Do instead:**
- Edit files directly in `C:\Users\chaga\OneDrive\Documents\fluffychat\` using the file tools
- For git operations (commit, push), open a Windows Terminal via computer-use and run commands there
- Push credentials: `https://connectbern:TOKEN@github.com/connectbern/fluffychat.git`

## Branch

All Connect-Bern work happens on the **`Connect-Bern`** branch.
Never commit to `main`. Keep history clean — squash fixup commits before pushing.

## Running locally

Flutter is installed on the user's Windows machine. To run locally:
```powershell
cd C:\Users\chaga\OneDrive\Documents\fluffychat
git checkout Connect-Bern
bash scripts/prepare-web.sh   # builds vodozemac WASM (requires Rust)
flutter run -d chrome
```

To just test UI changes without vodozemac (faster):
```powershell
flutter run -d chrome --dart-define=SKIP_VODOZEMAC=true
```

## Architecture — Connect-Bern custom features

All custom code is marked with `// Connect-Bern:` comments. Key files:

| Feature | File |
|---|---|
| Pre-filled homeserver + username | `lib/pages/sign_in/view_model/sign_in_view_model.dart` |
| Auto-accept invites | `lib/widgets/matrix.dart` |
| Message signature chip | `lib/pages/chat/input_bar.dart`, `lib/pages/chat/chat.dart` |
| Signature settings page | `lib/pages/settings/settings.dart`, `lib/pages/settings/settings_view.dart` |
| Pencil icon in sidebar | `lib/widgets/navigation_rail.dart` |
| Hide spaces UI | `lib/pages/chat_list/chat_list_body.dart` |
| Unread tab filter + default | `lib/pages/chat_list/chat_list.dart` |
| Netlify build script | `scripts/netlify-build.sh` |
| Netlify config (COOP/COEP headers) | `netlify.toml` |

## Deployment

Pushing to `Connect-Bern` on GitHub triggers an automatic Netlify build.
Live URL: **https://connect-bern-chat.netlify.app/web**
Netlify build time: ~4 minutes.

## Git hygiene

- Commit messages: `Connect-Bern: short description of change`
- Squash WIP/fixup commits before pushing: `git rebase -i HEAD~N`
- Never force-push unless fixing a bad commit on Connect-Bern only
