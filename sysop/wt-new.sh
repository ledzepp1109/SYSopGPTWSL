#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*"; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./sysop/wt-new.sh <task-slug> [base-ref]

Creates a dedicated worktree + branch for a single task:
  worktree: wt/<task-slug>
  branch:   wt/<task-slug>

Defaults:
  base-ref: main

Examples:
  ./sysop/wt-new.sh fix-windows-snapshot
  ./sysop/wt-new.sh ui-bug-123 main
  ./sysop/wt-new.sh refactor-foo origin/main
EOF
}

task_slug="${1:-}"
base_ref="${2:-main}"

if [ -z "$task_slug" ] || [ "$task_slug" = "-h" ] || [ "$task_slug" = "--help" ]; then
  usage
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  die "git not found on PATH"
fi

if ! (cd -- "$repo_root" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  die "not inside a git repo: $repo_root"
fi

if [[ ! "$task_slug" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  die "task-slug must match ^[a-z0-9][a-z0-9-]*$ (got: $task_slug)"
fi

worktree_dir="$repo_root/wt/$task_slug"
branch_name="wt/$task_slug"

mkdir -p "$repo_root/wt"

if [ -e "$worktree_dir" ]; then
  die "worktree path already exists: $worktree_dir"
fi

if (cd -- "$repo_root" && git show-ref --verify --quiet "refs/heads/$branch_name"); then
  die "branch already exists: $branch_name"
fi

(cd -- "$repo_root" && git worktree add "$worktree_dir" -b "$branch_name" "$base_ref")

say "OK: created worktree: $worktree_dir"
say "OK: created branch:  $branch_name (base: $base_ref)"
say "Next:"
say "  cd \"$worktree_dir\""
