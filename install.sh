#!/bin/sh
# RouteIQ agent installer.
#
# Downloads the agent for this machine, verifies it against the published
# checksums, writes its config, and installs a service that keeps it running.
#
# It installs nothing else. The agent provisions its own toolchain — Node and the
# coding CLIs — into its own directory the first time it starts.
#
#   curl -fsSL https://raw.githubusercontent.com/Antrika-Technologies-LLP/routeiq-agent-releases/main/install.sh \
#     | sh -s -- --token <ENROLLMENT_TOKEN> --server https://app.example.com
#
# Piping to a shell is a choice, not a requirement. To read it first:
#   curl -fsSLO https://raw.githubusercontent.com/.../install.sh
#   less install.sh && sh install.sh --token ... --server ...

set -eu

REPO="Antrika-Technologies-LLP/routeiq-agent-releases"
BASE="https://github.com/${REPO}/releases/latest/download"

TOKEN=""
SERVER=""
PREFIX="${HOME}/.routeiq"
BIN="${HOME}/routeiq-agent"
JOBS="2"
NO_SERVICE=""

usage() {
    cat <<USAGE
RouteIQ agent installer

  --token   <token>   enrollment token from the console (required)
  --server  <url>     control plane URL (required)
  --prefix  <dir>     where state and tools live (default: ~/.routeiq)
  --jobs    <n>       max concurrent jobs (default: 2)
  --no-service        install and configure, but do not start a service
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --token)  TOKEN="$2"; shift 2 ;;
        --server) SERVER="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --jobs)   JOBS="$2"; shift 2 ;;
        --no-service) NO_SERVICE="1"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[ -n "$TOKEN" ]  || { echo "error: --token is required (register a runner in the console)" >&2; exit 1; }
[ -n "$SERVER" ] || { echo "error: --server is required" >&2; exit 1; }

# ── Platform ────────────────────────────────────────────────────────────────

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
    linux|darwin) ;;
    *) echo "error: unsupported operating system: $OS" >&2; exit 1 ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)  ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "error: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

ASSET="routeiq-agent-${OS}-${ARCH}"
echo "Installing the RouteIQ agent for ${OS}/${ARCH}"

# ── Download and verify ─────────────────────────────────────────────────────

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "  downloading ${ASSET}"
curl -fsSL "${BASE}/${ASSET}" -o "${TMP}/${ASSET}"
curl -fsSL "${BASE}/SHA256SUMS" -o "${TMP}/SHA256SUMS"

# Verifying is the point of publishing the sums. A binary that runs your code
# and holds your credentials is not something to take on trust from a redirect.
EXPECTED="$(grep " ${ASSET}\$" "${TMP}/SHA256SUMS" | awk '{print $1}')"
[ -n "$EXPECTED" ] || { echo "error: ${ASSET} is not listed in SHA256SUMS" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL="$(sha256sum "${TMP}/${ASSET}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    ACTUAL="$(shasum -a 256 "${TMP}/${ASSET}" | awk '{print $1}')"
else
    echo "error: need sha256sum or shasum to verify the download" >&2; exit 1
fi

[ "$EXPECTED" = "$ACTUAL" ] || {
    echo "error: checksum mismatch for ${ASSET}" >&2
    echo "  expected ${EXPECTED}" >&2
    echo "  got      ${ACTUAL}" >&2
    exit 1
}
echo "  checksum verified"

install -m 0755 "${TMP}/${ASSET}" "$BIN"

# ── Configure ───────────────────────────────────────────────────────────────

mkdir -p "${PREFIX}/workspaces"
cat > "${PREFIX}/agent.json" <<JSON
{
  "serverUrl": "${SERVER}",
  "enrollmentToken": "${TOKEN}",
  "statePath": "${PREFIX}/state.json",
  "workspaceRoot": "${PREFIX}/workspaces",
  "maxConcurrentJobs": ${JOBS},
  "pollIntervalSec": 5
}
JSON
chmod 600 "${PREFIX}/agent.json"
echo "  wrote ${PREFIX}/agent.json"

if [ -n "$NO_SERVICE" ]; then
    echo
    echo "Installed. Start it with:"
    echo "  ${BIN} -config ${PREFIX}/agent.json"
    exit 0
fi

# ── Service ─────────────────────────────────────────────────────────────────

if [ "$OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
    UNIT_DIR="${HOME}/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    cat > "${UNIT_DIR}/routeiq-agent.service" <<UNIT
[Unit]
Description=RouteIQ agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN} -config ${PREFIX}/agent.json
Restart=always
RestartSec=10
WorkingDirectory=${HOME}
StandardOutput=append:${PREFIX}/agent.log
StandardError=append:${PREFIX}/agent.log

[Install]
WantedBy=default.target
UNIT

    systemctl --user daemon-reload
    systemctl --user enable --now routeiq-agent

    # Without lingering the service dies at logout, which looks like a crash days later.
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$(id -un)" 2>/dev/null \
            || echo "  note: could not enable lingering; run 'sudo loginctl enable-linger $(id -un)' so the agent survives logout"
    fi

    echo
    echo "Running. It provisions its toolchain on first start — about 10 seconds."
    echo "  systemctl --user status routeiq-agent"
    echo "  tail -f ${PREFIX}/agent.log"
    exit 0
fi

if [ "$OS" = "darwin" ]; then
    PLIST="${HOME}/Library/LaunchAgents/ai.routeiq.agent.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>ai.routeiq.agent</string>
  <key>ProgramArguments</key>
  <array><string>${BIN}</string><string>-config</string><string>${PREFIX}/agent.json</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${PREFIX}/agent.log</string>
  <key>StandardErrorPath</key><string>${PREFIX}/agent.log</string>
</dict>
</plist>
PLIST
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo
    echo "Running. It provisions its toolchain on first start — about 10 seconds."
    echo "  tail -f ${PREFIX}/agent.log"
    exit 0
fi

echo
echo "No supported service manager found. Start it yourself with:"
echo "  ${BIN} -config ${PREFIX}/agent.json"
