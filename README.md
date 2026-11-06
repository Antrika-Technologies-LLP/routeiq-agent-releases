# RouteIQ agent — releases

Binaries with SHA-256 checksums and the installer for the **RouteIQ agent**: a long-lived
runner that executes development work on a machine you own.

This repository holds **only the released binaries and the install script**. It is public
so that installing needs no credentials.

## Install

Install and start the runner once on your machine:

```sh
curl -fsSL https://raw.githubusercontent.com/Antrika-Technologies-LLP/routeiq-agent-releases/main/install.sh \
  | sh -s -- --server https://app.example.com
```

The installer starts the background service and displays a connection code. Approve it
in **RouteIQ → Runners → Connect runner**. Then open that runner in the portal:

- **Setup:** workspace folder, storage budget, disk reserve, automatic tool installation,
  job limit, and encrypted provider API keys or a GitHub personal access token.
- **Coding CLIs:** install/update Codex, Claude and Cursor, sign in through your browser,
  and sign out.
- **Git:** connect GitHub through browser approval, or disconnect an existing account.
- **Logs:** see setup and update outcomes.

You do not need to run `routeiq-agent setup`. Credentials entered in Setup are encrypted
in your browser for the runner's public key; only that machine decrypts and stores them.
Setup waits for current jobs to finish. Storage settings restart the runner automatically.
Release retained task copies in the portal before changing the workspace folder.
The Setup page requires the matching RouteIQ portal/backend release and agent **1.22.0+**.

Existing installations keep their configuration when the installer is run again.

| Option | Default | |
|---|---|---|
| `--token` | — | optional enrollment token for automated fleet installation |
| `--server` | — | your control plane URL |
| `--prefix` | `~/.routeiq` | where state, tools and logs live |
| `--jobs` | `2` | maximum concurrent jobs |
| `--no-service` | | install and configure without starting a service |

The installer verifies the download against `SHA256SUMS` before it runs anything, installs
a user-level service (systemd or launchd), and enables lingering so the agent survives
logout.

## What gets installed

Only the agent — a single static binary, about 6 MB, with no runtime dependencies.

It then provisions its **own** toolchain into `~/.routeiq/tools`, roughly ten seconds on
first start:

```
~/.routeiq/tools/node/bin/    node, npm, npx   (pinned, verified against nodejs.org)
~/.routeiq/tools/bin/         codex, claude, cursor-agent
```

Nothing is installed system-wide, nothing needs root, and anything already on the machine
is left alone.

## What it does on your machine

- Dials **out** only. No inbound port is opened and no listener is started.
- Keeps a separate workspace per task until you release it in the portal.
- Runs the coding CLI selected for the project using credentials held on the runner.
- Isolates each concurrent job’s MCP configuration and temporary materials.
- Reports prose, identifiers and counts. Output is redacted here, before it is sent —
  private key blocks, key-shaped strings, and any secret the job carried.

The RouteIQ control plane receives reports, logs and metadata. Coding providers process
project context according to the CLI and provider you choose.

## Platforms

| | |
|---|---|
| Linux | `amd64`, `arm64` |
| macOS | `amd64` (Intel), `arm64` (Apple silicon) |

## Uninstall

```sh
systemctl --user disable --now routeiq-agent    # or: launchctl unload ~/Library/LaunchAgents/ai.routeiq.agent.plist
rm -rf ~/.routeiq ~/routeiq-agent ~/.config/systemd/user/routeiq-agent.service
```

Remove the runner in the console too, so it stops being offered work.
