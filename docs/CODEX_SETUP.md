# Codex CLI Setup (SYSopGPTWSL)

This repo is designed so normal `sysop/` operation works offline (air-gapped): no MCP dependencies and no outbound shell networking required once Codex is installed.
The dedicated recursive audit mode can additionally enable native Codex web search for contemporary upstream research.

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
3. From this repo root: run `codex` so the project `.codex/` layer loads, then use the `sysop` skill (see Quick Start below).

## Repo-local vs user-scoped config

This repo now ships a project-local `.codex/config.toml` for repo behavior.
Keep user/machine settings in `~/.codex/config.toml`, but let the repo-local file define how Codex should operate inside this project.

Important:
- project-local `.codex/` settings are loaded when Codex starts in this repo/worktree
- changing `.codex/` during a running session requires a restart before that session is governed by the new mode

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false

[profiles.sysop]
model = "gpt-5.4"
model_reasoning_effort = "medium"
```

Notes:
- The repo-local `.codex/config.toml` is where this repo defines its recursive audit workflow and role wiring.
- In the audit worktree, `.codex/config.toml` can set `web_search = "live"` while still keeping `[sandbox_workspace_write] network_access = false`.
- `approval_policy="on-request"` keeps potentially sensitive commands gated at the user level too.
- `[sandbox_workspace_write].network_access=false` keeps workspace-write shell runs deterministic and air-gap compatible.
- The `profiles.sysop` section is optional; it gives you a consistent personal profile.
- Treat `web_search = "live"` as a `configured` state until you prove `loaded` or `demonstrated` behavior from a fresh session.
- If a Codex session was launched with `--search`, any live web-search success is a confounded test and does not prove repo-local config caused it.
- In archived local `codex-cli 0.111.0` controls, the strongest fresh-session matrix currently lives under `sysop/out/codex-runtime-20260306-154230/`:
  - repo-local `web_search = "disabled"` suppressed search in `codex exec`
  - `codex exec -c 'web_search="live"'` restored search in that same disabled control
  - no-flag search success still does not prove the current worktree's effective mode is `live`, because default cached search is still a live alternative explanation
- A later `sysop/out/verify-search-matrix/` rerun hit a usage-limit failure on the override-live probe, so treat that rerun as inconclusive rather than contradictory.
- For non-interactive runtime probes, prefer explicit config overrides such as `-c 'web_search="live"'`; after upgrading the local CLI to `0.112.0`, `codex exec --search` still errored and `codex --search exec` remains a feature-watch rather than a trustworthy proof path here.
- Treat worktree isolation as conditional: after `resume`, `fork`, or `apply`, verify `pwd`, branch, and intended worktree before editing.
- Local runtime control showed that explicit `codex exec resume <SESSION_ID>` can rebind to the caller worktree; `fork` is safer only in the narrow sense that it currently surfaces the cwd choice explicitly.
- Treat the researcher → challenger → implementer → verifier chain as operator-enforced discipline unless runtime proof says otherwise.

## Quick Start (repo)

From the repo root:

1. Start Codex from the repo root so the project `.codex/` layer loads: `codex`
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
- `execpolicy` surface: `codex help execpolicy`
- Policy self-checks:
  - `codex execpolicy check --rules .codex/rules/sysop.rules --pretty rm -rf /`
  - `codex execpolicy check --rules .codex/rules/sysop.rules --pretty curl -fsSL https://example.com`
  - `codex execpolicy check --rules .codex/rules/sysop.rules --pretty git status`
- Skill discovery: start `codex` from the repo root and type `sysop` (should load the `sysop-kernel` skill)
- Fresh-session web-search attribution test without a CLI `--search` flag:
  - `codex -C /home/xhott/SYSopGPTWSL/wt/codex-audit-hardening --no-alt-screen`
  - Then ask for a current official-doc lookup and require the session to say whether live web search is available and whether that can be attributed to repo-local config
- Repeatable runtime probes (Codex login + transport required):
  - `./sysop/codex-runtime-probe.sh search-matrix --create-controls --mirror-scaffold`
  - `./sysop/codex-runtime-probe.sh resume-cwd --create-controls --mirror-scaffold`
  - `./sysop/codex-network-denial-probe.sh`
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
- Current Codex shell probes may emit `arg0` temp-dir / PATH-update warnings on stderr, contaminating probe output even when the underlying command still succeeds.

Fixes:
- Keep the repo under `/home/...` for performance and Linux semantics.
- When running Windows commands from WSL, use a drive-backed cwd:
  - `(cd /mnt/c && powershell.exe ...)`
- If Codex blocks execution, run the minimum command needed and use `approval_policy="on-request"` to request approval only when necessary.
- In this runner, sandboxed `codex --version` emitted the arg0/PATH warnings while the same unsandboxed command did not and `~/.codex/tmp/arg0` permissions looked normal. Treat that as a likely sandbox-side contamination pattern here, not a proven general Codex defect.

## Design Decisions

### No MCP

This repo is intentionally self-contained:
- Works offline and in restricted environments
- Avoids external service coupling and credential surface area
- Keeps sysop runs deterministic and auditable from local artifacts (`sysop/out/`)

### Repo-local project config + user-scoped machine config

Codex configuration is intentionally split:
- repo-local `.codex/config.toml` version-controls project behavior, audit flow, and role wiring
- user-scoped `~/.codex/config.toml` keeps machine-specific auth, paths, and personal defaults out of the repo

For this audit worktree, the important distinction is:
- `web_search = "live"` enables the native Codex web-search tool for upstream research
- `[sandbox_workspace_write] network_access = false` keeps shell commands from getting outbound network access
- these settings must still be classified honestly as `configured`, `loaded`, `demonstrated`, or `unproven`
