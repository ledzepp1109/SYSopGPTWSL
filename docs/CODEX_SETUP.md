# Codex CLI Setup (SYSopGPTWSL)

This repo is designed to work offline (air-gapped): no MCP dependencies and no internet fetching required to use the operator scripts and skills once Codex is installed.

## Prerequisites

- Codex CLI `>=0.76.0`
- WSL2 (for the Windows/WSL sysop workflow in this repo)
- Python `3.8+` (used to parse Windows snapshot JSON via `utf-8-sig`)

## Install Codex CLI

Pick one method for your host OS.

### macOS (DMG)

1. Download the Codex DMG from the official release page.
2. Install the app as prompted.
3. Ensure the `codex` binary is on your `PATH` (often via the app’s bundled CLI helper).
4. Verify: `codex --version`

### Linux (curl installer)

This method requires internet access.

```bash
curl -fsSL "<CODEX_INSTALLER_URL>" | sh
codex --version
```

If you are air-gapped, install Codex via a pre-downloaded artifact instead of `curl`.

### WSL2 (native)

Install Codex inside your WSL distro (recommended for this repo), then run it from the repo root.

1. Install Codex using a Linux method appropriate for your environment (package, artifact, or local installer).
2. Verify: `codex --version`
3. From this repo root: run `codex` and use the `sysop` skill (see Quick Start below).

## Recommended `~/.codex/config.toml`

This repo does not ship a `config.toml`. Keep user/machine settings in your home directory.

```toml
approval_policy = "on-request"
sandbox = "workspace-write"
network_access = false

[profiles.sysop]
model = "gpt-5-pro"
reasoning_effort = "medium"
verbosity = "low"
```

Notes:
- `approval_policy="on-request"` keeps potentially sensitive commands gated.
- `network_access=false` keeps runs deterministic and air-gap compatible.
- The `profiles.sysop` section is optional; it gives you a consistent “sysop operator” profile.

## Quick Start (repo)

From the repo root:

1. Start Codex: `codex`
2. Trigger the skill by typing: `sysop`
3. Follow the Plan → Approval flow, then run the operator kernel as directed (typically: `./sysop/run.sh all`)

Artifacts are written under `sysop/out/` and the learning ledger is appended at `learn/LEDGER.md`.

## Hybrid Automation Capabilities (WSL ↔ Windows)

As of `2026-01-15`, WSL is configured to append the Windows PATH into WSL (`/etc/wsl.conf`):

```ini
[interop]
enabled=true
appendWindowsPath=true
```

This enables hybrid automation from WSL:
- Windows executables are discoverable on WSL `$PATH` and callable from WSL by name (for example `powershell.exe`, `pwsh.exe`, `cmd.exe`, `powercfg.exe`, `explorer.exe`).
- Prefer a drive-backed working directory for Windows commands (avoids UNC-path quirks):
  - `(cd /mnt/c && powershell.exe ...)`
- Translate WSL paths when passing them to Windows tools:
  - `wslpath -w "$PWD/sysop/windows/collect-windows.ps1"`

Example use cases:

```bash
# Query Windows system info (PowerShell 5.1)
(cd /mnt/c && powershell.exe -NoProfile -Command "Get-ComputerInfo | Select-Object CsName, OsName, OsVersion")

# Query Windows power plan
(cd /mnt/c && powercfg.exe /GETACTIVESCHEME)

# Launch a Windows app from WSL
explorer.exe .

# Cross-OS workflow: collect Windows snapshot (writes into sysop/out/)
./sysop/run.sh snapshot
```

Notes:
- This repo does not edit `/etc/wsl.conf`; treat it as a host-level setting managed manually.
- With `appendWindowsPath=true`, PATH precedence can surprise you (a Windows tool can shadow a Linux one). Use explicit `.exe` when you intend to call Windows.
- Some restricted runners can still block WSL↔Windows interop even when the PATH is present (common symptom: `UtilBindVsockAnyPort: ... socket failed 1`). If that happens, run the Windows command from a normal interactive WSL shell, or fall back to native Windows PowerShell.

## Verification

- Version gate: `codex --version` shows `>=0.76.0`
- Skill discovery: start `codex` from the repo root and type `sysop` (should load the `sysop-kernel` skill)
- Operator kernel: `./sysop/run.sh all` produces:
  - `sysop/out/report.md`
  - `sysop/out/windows_snapshot.json`
  - `sysop/out/wsl_snapshot.txt`
  - `sysop/out/bench.txt`
  - Appends `learn/LEDGER.md`

## Troubleshooting

### Skills not loading

Symptoms:
- Typing `sysop` doesn’t load skill instructions.
- Codex behaves as if `.codex/skills/` is missing.

Checks:
- Start Codex from the repo root (so `.codex/` is discoverable).
- Confirm the skill file exists: `.codex/skills/sysop-kernel/SKILL.md`
- Confirm SKILL frontmatter includes `name`, `description`, and `codex-version: ">=0.76.0"`
- Confirm there are no YAML frontmatter syntax errors (the block must start with `---` and end with `---`).

### Permission errors

Common causes:
- Running in a restricted sandbox profile that blocks required subprocesses.
- Running Windows commands from a UNC-backed cwd.
- Placing the repo under `/mnt/c` (drvfs/9p) causing slow IO and occasional permission oddities.

Fixes:
- Keep the repo under `/home/...` for performance and Linux semantics.
- When running Windows commands from WSL, use a drive-backed cwd:
  - `(cd /mnt/c && powershell.exe ...)`
- If Codex blocks execution, run the minimum command needed and use `approval_policy="on-request"` to request approval only when necessary.

## Design Decisions

### No MCP

This repo is intentionally self-contained:
- Works offline and in restricted environments
- Avoids external service coupling and credential surface area
- Keeps sysop runs deterministic and auditable from local artifacts (`sysop/out/`)

### No shipped `config.toml`

Codex configuration is intentionally user-scoped:
- Avoids committing machine-specific paths, tokens, or policies
- Lets operators choose their own sandbox and approvals while keeping repo defaults documented here
