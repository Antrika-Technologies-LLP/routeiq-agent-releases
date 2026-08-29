# RouteIQ agent — releases

Signed-by-checksum binaries and the installer for the **RouteIQ agent**: a long-lived
runner that executes development work on a machine you own.

This repository holds **only the released binaries and the install script**. It is public
so that installing needs no credentials.

## Install

Register a runner in the RouteIQ console to get an enrollment token, then:

```sh
curl -fsSL https://raw.githubusercontent.com/Antrika-Technologies-LLP/routeiq-agent-releases/main/install.sh \
  | sh -s -- --token <ENROLLMENT_TOKEN> --server https://app.example.com
```

Piping to a shell is a choice, not a requirement — the script is short and worth reading:

```sh
curl -fsSLO https://raw.githubusercontent.com/Antrika-Technologies-LLP/routeiq-agent-releases/main/install.sh
less install.sh
sh install.sh --token <ENROLLMENT_TOKEN> --server https://app.example.com
```

| Option | Default | |
|---|---|---|
| `--token` | — | enrollment token, shown once when you register a runner |
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
- Clones into a temporary workspace that is deleted when the job ends, successful or not.
- Runs the coding CLI you selected for the project, with credentials that are supplied per
  job and removed afterwards.
- Reports prose, identifiers and counts. Output is redacted here, before it is sent —
  private key blocks, key-shaped strings, and any secret the job carried.

**Your source code does not leave the machine.**

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
