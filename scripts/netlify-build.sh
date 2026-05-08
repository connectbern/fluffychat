#!/usr/bin/env bash
# Connect-Bern: Netlify build script — installs Flutter + Rust on demand,
# runs the project's prepare-web.sh, then builds the release web bundle.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_DIR="${HOME}/flutter"
CARGO_HOME="${CARGO_HOME:-${HOME}/.cargo}"

echo "==> Installing yq"
if ! command -v yq >/dev/null 2>&1; then
  curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    -o "${HOME}/yq" && chmod +x "${HOME}/yq"
  export PATH="${HOME}:${PATH}"
fi

echo "==> Installing Flutter ${FLUTTER_VERSION} (${FLUTTER_CHANNEL})"
if [ ! -d "${FLUTTER_DIR}" ]; then
  git clone --depth 1 -b "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"
flutter --version
flutter config --no-analytics --no-cli-animations

echo "==> Installing Rust (for vodozemac)"
# Netlify images ship rustup without a default toolchain; handle both cases.
if command -v rustup >/dev/null 2>&1; then
  rustup default stable
elif ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
fi
export PATH="${CARGO_HOME}/bin:${PATH}"
cargo --version

echo "==> Adding wasm32 target and installing wasm-pack"
rustup target add wasm32-unknown-unknown
if ! command -v wasm-pack >/dev/null 2>&1; then
  curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
fi
wasm-pack --version

echo "==> Running project's prepare-web.sh"
bash scripts/prepare-web.sh

echo "==> Building web release"
flutter build web --release

echo "==> Build complete: build/web"
