# Claude operator in WSL (verify + repair)

This repo never writes outside itself. If your Claude-on-WSL wiring needs changes (for example `~/.claude/CLAUDE.md`), this repo generates a manual fix script under `sysop/out/fixes/` for you to review and run.

## Verify (read-only)

From repo root:

```bash
./sysop/claude/check_wsl.sh
```

## Repair (manual; writes outside repo)

Generate a fix script:

```bash
./sysop/claude/gen_fix_wsl_operator.sh
```

Review + run the generated script:

```bash
bash sysop/out/fixes/claude_wsl_operator_fix.sh
```

Re-verify:

```bash
./sysop/claude/check_wsl.sh
```

## Expected wiring (WSL-first)

- Claude CLI installed and on PATH (`command -v claude`)
- Claude runtime state: `~/.claude/`
- Entry-point operator doc: `~/.claude/CLAUDE.md`
- Canonical spec (SSOT): `~/ops-operator/config/CLAUDE.md`

## Hybrid automation (WSL ↔ Windows)

If `/etc/wsl.conf` has `[interop] appendWindowsPath=true`, Windows binaries (for example `powershell.exe`, `pwsh.exe`) are callable from WSL and can be used for cross-OS automation.

See: `docs/CODEX_SETUP.md` (Hybrid Automation Capabilities) for examples and safety notes (drive-backed cwd, PATH precedence).
