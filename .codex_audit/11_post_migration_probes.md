# Post-Migration Probes

## 1. Precedence probes

### Repo root vs `/tmp`
Command:
```bash
cd /home/xhott/SYSopGPTWSL && codex features list
cd /tmp && codex features list
```
Outcome:
- In `/home/xhott/SYSopGPTWSL`, `multi_agent` resolved to `true`.
- In `/tmp`, `multi_agent` resolved to `false`.
- Conclusion: trusted repo-root `.codex/config.toml` materially changes runtime state relative to the user-only default layer.

### Deeper nested `.codex/config.toml` override
Command:
```bash
tmpdir=/home/xhott/SYSopGPTWSL/.tmp-precedence-override-$$
mkdir -p "$tmpdir/.codex"
cat > "$tmpdir/.codex/config.toml" <<'EOF'
[features]
multi_agent = false
EOF
cd "$tmpdir" && codex features list
unlink "$tmpdir/.codex/config.toml"
rmdir "$tmpdir/.codex"
rmdir "$tmpdir"
```
Outcome:
- Nested directory resolved `multi_agent` to `false`.
- Repo root outside that nested directory resolved `multi_agent` to `true`.
- Conclusion: deeper project config overrides the repo-root config for descendants.

### CLI `-c` override beats repo-root defaults
Command:
```bash
cd /home/xhott/SYSopGPTWSL
codex exec -s read-only --output-schema /tmp/schema.json -o /tmp/default.json 'Return raw JSON only: {"ok":true}'
codex exec -s read-only -c 'model_reasoning_effort="high"' --output-schema /tmp/schema.json -o /tmp/override.json 'Return raw JSON only: {"ok":true}'
```
Observed stderr headers:
- default run: `reasoning effort: xhigh`
- override run: `reasoning effort: high`
Conclusion:
- CLI `-c` overrides beat repo-root defaults, matching the documented precedence model.

## 2. Network denial probe

Command:
```bash
cd /home/xhott/SYSopGPTWSL
bash sysop/codex-network-denial-probe.sh --report-dir /tmp/codex-network-denial-phase3-20260309
```

Observed result:
```text
REPORT_DIR=/tmp/codex-network-denial-phase3-20260309
HOST_RC=0
HOST_HTTP_CODE=200
DIRECT_RC=1
EXEC_RC=0
EXEC_SHELL_RC=1
RESULT=pass
```

Conclusion:
- Host control reached the public network.
- Direct `codex sandbox linux --full-auto` raw socket creation failed.
- Repo-root `codex exec` raw socket creation failed.
- Runtime shell-network denial remains enforced.

## 3. Deterministic gate probes

Disposable validation repos:
- challenger-block probe repo: `/tmp/sysop-phase3-gate-probe-FuViSo`
- verifier-fail and pass probe repo: `/tmp/sysop-phase3-gate-probe-wwPyk1`

These were disposable local git repos initialized from the current working tree solely to satisfy the gate's mandatory clean-repo precondition without committing the real repository.

### Challenger block path
Command:
```bash
bash /tmp/sysop-phase3-gate-probe-FuViSo/sysop/sysop-gate.sh \
  --repo /tmp/sysop-phase3-gate-probe-FuViSo \
  --task 'Create blocker-probe.txt at the repo root with one line.' \
  --probe-challenger-block
```
Outcome:
```text
RC=1
Preparing worktree (checking out 'gate-20260309-045219')
GATE_BLOCK
WORKTREE_REMOVED=/tmp/sysop-phase3-gate-probe-FuViSo/wt/.gate-20260309-045219
LEFTOVER_GATES=0
BLOCKER_FILE=0
```
Conclusion:
- Challenger block stops the flow before implementation is treated as successful.
- Disposable worktree is removed on block.
- The target file was never created.

### Verifier fail path
Command:
```bash
bash /tmp/sysop-phase3-gate-probe-wwPyk1/sysop/sysop-gate.sh \
  --repo /tmp/sysop-phase3-gate-probe-wwPyk1 \
  --task 'Create verifier-fail-probe.txt at the repo root with one line.' \
  --probe-verifier-fail
```
Outcome:
```text
RC=1
Preparing worktree (checking out 'gate-20260309-045427')
GATE_FAIL
WORKTREE_REMOVED=/tmp/sysop-phase3-gate-probe-wwPyk1/wt/.gate-20260309-045427
LEFTOVER_GATES=0
FAIL_PROBE_FILE=0
```
Additional observed stage artifacts before cleanup:
- Challenger returned `PASS`.
- Implementer created:
  - `verifier-fail-probe.txt`
  - `.codex_audit/gate-runs/20260309-045427/probe-verifier-fail.txt`
- Verifier then failed because `.codex_audit/gate-runs/20260309-045427/probe-verifier-fail.expected` was intentionally absent.
Conclusion:
- The wrapper reaches Verifier deterministically in verifier-fail probe mode.
- Verifier failure returns non-zero and removes the disposable worktree.

### Real pass path without commit
Command:
```bash
bash /tmp/sysop-phase3-gate-probe-wwPyk1/sysop/sysop-gate.sh \
  --repo /tmp/sysop-phase3-gate-probe-wwPyk1 \
  --task 'Create docs/gate-pass-probe.md with exactly one line: gate pass probe'
```
Outcome:
```text
RC=0
Preparing worktree (checking out 'gate-20260309-045643')
GATE_PASS
WORKTREE=/tmp/sysop-phase3-gate-probe-wwPyk1/wt/.gate-20260309-045643
RUN_DIR=/tmp/sysop-phase3-gate-probe-wwPyk1/wt/.gate-20260309-045643/.codex_audit/gate-runs/20260309-045643
BASE_HEAD=0ed969bd21eb5ee506fd3f79b0e31e7a00da589c
WORKTREE_HEAD=0ed969bd21eb5ee506fd3f79b0e31e7a00da589c
HEAD_MATCH=yes
STATUS_LINES=2
RUN_DIR_EXISTS=yes
PASS_FILE=yes
```
Verifier JSON:
```json
{"stage":"verifier","verdict":"PASS","validated_effects":["Verified `/tmp/sysop-phase3-gate-probe-wwPyk1/wt/.gate-20260309-045643/docs/gate-pass-probe.md` exists as a regular file.","Verified the file has exactly one line and that line is the exact literal `gate pass probe`.","Verified the file bytes are `gate pass probe\\n`, with no extra content beyond the single newline terminator."],"remaining_risks":["`git status --short` still shows pre-existing untracked `.codex_audit/gate-runs/`; this does not contradict the claimed file creation, but whole-tree cleanliness was not the claimed effect."]}
```
Conclusion:
- The wrapper can complete the full `Researcher -> Challenger -> Implementer -> Verifier` chain and emit `GATE_PASS`.
- The disposable worktree remains in place on pass as designed.
- No commit was created because `--commit` was not supplied; `BASE_HEAD` and `WORKTREE_HEAD` remained identical.

## Overall probe verdict
- High confidence: config precedence works as intended.
- High confidence: shell-network denial still holds under sandboxed execution.
- High confidence: the external wrapper now enforces the four-stage gate deterministically for block, fail, and pass paths.
- Medium confidence: stage latency is non-trivial even for trivial tasks because each `codex exec` stage still performs its own local reasoning and checks.
