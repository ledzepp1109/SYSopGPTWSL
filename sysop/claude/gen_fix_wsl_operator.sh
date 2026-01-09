#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

say() { printf '%s\n' "$*"; }
ts_compact() { date +%Y%m%d-%H%M%S 2>/dev/null || date +%s; }

out_dir="$repo_root/sysop/out/fixes"
mkdir -p "$out_dir"

fix_path="$out_dir/claude_wsl_operator_fix.sh"
ts="$(ts_compact)"

cat >"$fix_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

say() { printf '%s\n' "$*"; }
ts_compact() { date +%Y%m%d-%H%M%S 2>/dev/null || date +%s; }

fix_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$fix_dir/../../.." && pwd)"

target="$HOME/.claude/CLAUDE.md"
ts="$(ts_compact)"
backup="${target}.bak-${ts}"

mkdir -p "$(dirname "$target")"

if [ -f "$target" ]; then
  cp -a "$target" "$backup"
  say "Backup:   $backup"
  say "Rollback: cp -a \"$backup\" \"$target\""
fi

cat >"$target" <<'MD'
# Claude Operator (WSL)

This file is intentionally small.

Canonical operator spec (SSOT):
- `~/ops-operator/config/CLAUDE.md`

If you are running Claude Code on Windows as well, ensure your Windows-side entrypoint docs also point to the same SSOT (or an explicitly archived legacy spec).
MD

say "Wrote: $target"
say "Verify:"
say "  \"$repo_root/sysop/claude/check_wsl.sh\""
EOF

chmod +x "$fix_path"

say "Wrote fix script: $fix_path"
say "Run manually (it writes outside this repo):"
say "  bash \"$fix_path\""
say ""
say "Then re-check:"
say "  ./sysop/claude/check_wsl.sh"
