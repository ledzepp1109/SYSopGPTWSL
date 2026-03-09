#!/usr/bin/env python3
"""Classify a plain-text /compact blob against the Phase 3 Codex target state."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def usage() -> int:
    print("usage: compact-target-diff.py <compact-source-file>", file=sys.stderr)
    return 2


def compile_many(patterns: list[str]) -> list[re.Pattern[str]]:
    return [re.compile(pattern, re.IGNORECASE | re.MULTILINE | re.DOTALL) for pattern in patterns]


def first_match(text: str, patterns: list[re.Pattern[str]]) -> str:
    for pattern in patterns:
        match = pattern.search(text)
        if match:
            snippet = match.group(0).strip().replace("\n", " ")
            return " ".join(snippet.split())[:160]
    return ""


def classify(
    text: str,
    *,
    correct: list[str],
    present: list[str] | None = None,
    wrong: list[str] | None = None,
) -> tuple[str, str]:
    correct_patterns = compile_many(correct)
    present_patterns = compile_many(present or [])
    wrong_patterns = compile_many(wrong or [])

    wrong_hit = first_match(text, wrong_patterns)
    if wrong_hit:
        return "present but misconfigured", wrong_hit

    if correct_patterns:
        if all(pattern.search(text) for pattern in correct_patterns):
            return "already encoded correctly", first_match(text, correct_patterns)

    present_hit = first_match(text, present_patterns) or first_match(text, correct_patterns)
    if present_hit:
        return "present but misconfigured", present_hit

    return "completely missing", "no matching evidence in compact blob"


def md_escape(value: str) -> str:
    return value.replace("|", r"\|")


def main() -> int:
    if len(sys.argv) != 2:
        return usage()

    source_path = Path(sys.argv[1])
    if not source_path.is_file():
        print(f"error: file not found: {source_path}", file=sys.stderr)
        return 2

    text = source_path.read_text(encoding="utf-8", errors="replace")
    placeholder = "[PASTE YOUR /compact OUTPUT HERE]" in text

    rows = [
        (
            "user config exists",
            classify(
                text,
                correct=[r"(?:/home/xhott|~)/\.codex/config\.toml"],
                present=[r"\.codex/config\.toml"],
            ),
        ),
        (
            "repo config exists",
            classify(
                text,
                correct=[r"(?:/home/xhott|~)/SYSopGPTWSL/\.codex/config\.toml"],
                present=[r"SYSopGPTWSL/.codex/config\.toml"],
            ),
        ),
        (
            "repo model",
            classify(
                text,
                correct=[r'model\s*=\s*"gpt-5\.4"'],
                present=[r'model\s*='],
            ),
        ),
        (
            "repo reasoning",
            classify(
                text,
                correct=[r'model_reasoning_effort\s*=\s*"xhigh"'],
                present=[r'model_reasoning_effort\s*='],
                wrong=[r'model_reasoning_effort\s*=\s*"(?!xhigh)[^"]+"'],
            ),
        ),
        (
            "repo web_search",
            classify(
                text,
                correct=[r'web_search\s*=\s*"live"'],
                present=[r'web_search\s*='],
                wrong=[r'web_search\s*=\s*"(?!live)[^"]+"'],
            ),
        ),
        (
            "repo approval policy",
            classify(
                text,
                correct=[r'approval_policy\s*=\s*"on-request"'],
                present=[r'approval_policy\s*='],
                wrong=[r'approval_policy\s*=\s*"(?!on-request)[^"]+"'],
            ),
        ),
        (
            "repo sandbox_mode",
            classify(
                text,
                correct=[r'sandbox_mode\s*=\s*"workspace-write"'],
                present=[r'sandbox_mode\s*='],
                wrong=[r'sandbox_mode\s*=\s*"(?!workspace-write)[^"]+"'],
            ),
        ),
        (
            "repo shell network denial",
            classify(
                text,
                correct=[r'\[sandbox_workspace_write\]', r'network_access\s*=\s*false'],
                present=[r'network_access\s*='],
                wrong=[r'network_access\s*=\s*true'],
            ),
        ),
        (
            "multi-agent feature flag",
            classify(
                text,
                correct=[r'\[features\]', r'multi_agent\s*=\s*true'],
                present=[r'multi_agent\s*='],
                wrong=[r'multi_agent\s*=\s*false'],
            ),
        ),
        (
            "agents.max_threads",
            classify(
                text,
                correct=[r'max_threads\s*=\s*4'],
                present=[r'max_threads\s*='],
                wrong=[r'max_threads\s*=\s*(?!4)\d+'],
            ),
        ),
        (
            "agents.max_depth",
            classify(
                text,
                correct=[r'max_depth\s*=\s*2'],
                present=[r'max_depth\s*='],
                wrong=[r'max_depth\s*=\s*(?!2)\d+'],
            ),
        ),
        (
            "researcher role",
            classify(
                text,
                correct=[r'\[agents\.researcher\]', r'config_file\s*=\s*"agents/researcher\.toml"'],
                present=[r'researcher'],
            ),
        ),
        (
            "challenger role",
            classify(
                text,
                correct=[r'\[agents\.challenger\]', r'config_file\s*=\s*"agents/challenger\.toml"'],
                present=[r'challenger'],
            ),
        ),
        (
            "implementer role",
            classify(
                text,
                correct=[r'\[agents\.implementer\]', r'config_file\s*=\s*"agents/implementer\.toml"'],
                present=[r'implementer'],
            ),
        ),
        (
            "verifier role",
            classify(
                text,
                correct=[r'\[agents\.verifier\]', r'config_file\s*=\s*"agents/verifier\.toml"'],
                present=[r'verifier'],
            ),
        ),
        (
            "AGENTS doctrine",
            classify(
                text,
                correct=[
                    r"Researcher\s*[-–>]+\s*Challenger\s*[-–>]+\s*Implementer\s*[-–>]+\s*Verifier",
                    r"sysop/sysop-gate\.sh",
                    r"Primary docs|official changelog",
                ],
                present=[r'AGENTS\.md', r'Researcher', r'Challenger', r'Verifier'],
            ),
        ),
        (
            "network denial probe",
            classify(
                text,
                correct=[r'codex-network-denial-probe\.sh'],
                present=[r'network denial', r'PermissionError'],
            ),
        ),
        (
            "deterministic gate wrapper",
            classify(
                text,
                correct=[r'sysop/sysop-gate\.sh'],
                present=[r'gate', r'wrapper'],
            ),
        ),
    ]

    print("# Compact vs Target Diff")
    print()
    print(f"- Source file: `{source_path}`")
    if placeholder:
        print("- Compact blob status: placeholder content detected; absence of evidence here is not evidence of absence in the live repo.")
    print()
    print("| Target element | Classification | Evidence from compact |")
    print("| --- | --- | --- |")
    for element, (status, evidence) in rows:
        print(f"| {md_escape(element)} | {md_escape(status)} | {md_escape(evidence)} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
