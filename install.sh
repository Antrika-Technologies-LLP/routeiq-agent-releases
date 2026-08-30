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
BIN=""   # resolved from PREFIX once options are parsed
JOBS="2"
NO_SERVICE=""

usage() {
    cat <<USAGE
RouteIQ agent installer

  --server  <url>     control plane URL (required)
  --token   <token>   enrollment token; omit it to sign in with a code instead
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

# --token is optional. Without one the agent signs in the way a device with no
# browser should: it prints a short code, and somebody already signed in to the
# console approves it. Nothing secret is typed on this machine, nothing lands in
# shell history, and nothing sits in a config file waiting to be read.
[ -n "$SERVER" ] || { echo "error: --server is required" >&2; exit 1; }

# The binary lives with everything else the agent owns, and a symlink puts it on
# PATH so it can be run by name rather than by path.
BIN="${PREFIX}/bin/routeiq-agent"
mkdir -p "${PREFIX}/bin"

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

# Earlier versions installed straight into $HOME. Leaving that copy behind means
# two binaries and no way to tell which one ran.
if [ -f "${HOME}/routeiq-agent" ] && [ "${HOME}/routeiq-agent" != "$BIN" ]; then
    rm -f "${HOME}/routeiq-agent"
    echo "  removed the old ${HOME}/routeiq-agent"
fi

# Put it on PATH. /usr/local/bin is on every default PATH; ~/.local/bin often is
# not, which is exactly how a tool ends up installed and still "not found".
LINKED=""
for dir in /usr/local/bin "${HOME}/.local/bin"; do
    if [ -w "$dir" ] 2>/dev/null; then
        ln -sf "$BIN" "${dir}/routeiq-agent" && LINKED="${dir}/routeiq-agent" && break
    elif [ "$dir" = "/usr/local/bin" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo ln -sf "$BIN" "${dir}/routeiq-agent" && LINKED="${dir}/routeiq-agent" && break
    fi
done
if [ -z "$LINKED" ]; then
    mkdir -p "${HOME}/.local/bin"
    ln -sf "$BIN" "${HOME}/.local/bin/routeiq-agent"
    LINKED="${HOME}/.local/bin/routeiq-agent"
fi
echo "  linked ${LINKED}"

# Say what actually landed.
#
# The checksum proves the download was not tampered with. It does not prove it is
# current: GitHub can serve the "latest" assets from an edge cache for a few
# minutes after a release, and the binary and its SHA256SUMS go stale together —
# so an upgrade verifies perfectly and installs the version you already had. That
# is invisible unless the installer says which one it is.
INSTALLED="$("$BIN" --version 2>/dev/null || "$BIN" version 2>/dev/null || echo 'unknown version')"
echo "  ${INSTALLED}"

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
    echo "  routeiq-agent"
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
    systemctl --user enable routeiq-agent
    # restart, not `enable --now`: --now does nothing to an already-running
    # service, so an upgrade would report success while the old binary kept
    # running - the kind of thing that costs an afternoon to notice.
    systemctl --user restart routeiq-agent

    # Without lingering the service dies at logout, which looks like a crash days later.
    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$(id -un)" 2>/dev/null \
            || echo "  note: could not enable lingering; run 'sudo loginctl enable-linger $(id -un)' so the agent survives logout"
    fi

    echo
    if [ -z "$TOKEN" ]; then
        echo "Sign this machine in:"
        echo "  routeiq-agent setup"
        echo
        echo "It will show a code to approve in the console."
    else
        echo "Running. It provisions its toolchain on first start — about 10 seconds."
    fi
    echo
    echo "  routeiq-agent doctor           what this machine can do"
    echo "  systemctl --user status routeiq-agent"
    echo "  tail -f ${PREFIX}/agent.log"
    case ":${PATH}:" in
        *":$(dirname "$LINKED"):"*) ;;
        *) echo; echo "  note: $(dirname "$LINKED") is not on your PATH — add it, or run ${BIN}" ;;
    esac
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
