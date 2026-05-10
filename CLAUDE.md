# Claude Instructions — Connect-Bern / FluffyChat

## Working on this project

**For file edits:** Use the Read / Write / Edit tools directly on the Windows path
`C:\Users\chaga\OneDrive\Documents\fluffychat\`. These write straight to disk.

**For git and build commands:** Use WSL (see below). Do NOT use the Linux sandbox —
it cannot push to git (EPERM on `.git/` over virtiofs) and background processes
die between tool calls.

**Never:**
- Clone the repo to `/tmp/` in the sandbox and work from there
- Run `flutter`, `dart`, or `cargo` from the Linux sandbox
- Use the sandbox bash for git commits or pushes

---

## Branch

All Connect-Bern work is on the **`Connect-Bern`** branch. Never commit to `main`.
Squash WIP commits before pushing: `git rebase -i HEAD~N`.
Commit message format: `Connect-Bern: short description`

---

## Local development via WSL (recommended)

WSL2 is the right environment for builds. It has a native Linux filesystem
(fast git, no permission issues), persistent processes, and `localhost` is
shared with Windows Chrome.

### One-time WSL setup

Open a WSL terminal (Ubuntu) and run:

```bash
# 1. Clone the repo inside WSL's native filesystem (fast I/O, no virtiofs)
cd ~
git clone https://github.com/connectbern/fluffychat.git
cd fluffychat
git checkout Connect-Bern

# 2. Install Flutter (stable)
cd ~
curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.3-stable.tar.xz \
  -o flutter.tar.xz
tar xf flutter.tar.xz
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
flutter --version   # first run downloads Dart SDK (~30s)
flutter config --no-analytics

# 3. Install Rust stable + nightly (needed for vodozemac WASM)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env
rustup toolchain install nightly
rustup component add rust-src --toolchain nightly
rustup target add wasm32-unknown-unknown
rustup target add wasm32-unknown-unknown --toolchain nightly

# 4. Install wasm-pack
curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh

# 5. Install yq (needed by prepare-web.sh)
curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
  -o ~/yq && chmod +x ~/yq && sudo mv ~/yq /usr/local/bin/yq
```

### Running the app locally

```bash
cd ~/fluffychat
git checkout Connect-Bern
git pull

# Build vodozemac WASM (~3-5 min first time, cached after)
bash -euo pipefail scripts/prepare-web.sh

# Run on localhost:8080 (opens in Windows Chrome)
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Then open `http://localhost:8080` in Chrome on Windows.

**Faster iteration (skip vodozemac, UI changes only):**
```bash
flutt