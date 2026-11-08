#!/usr/bin/env python3
"""PreToolUse hook (Bash): refuse commits, pushes and GitHub writes that credit an AI.

Looks at the command text, at files it passes as a message or body, at the git
identity a commit would use, and at the local commits a push would send.
A problem inside this hook never blocks work: it then lets the command through.
"""
import json
import os
import re
import subprocess
import sys

OWNER = "ahmad-sy1 <153828359+ahmad-sy1@users.noreply.github.com>"

ARG = r"""(?:'[^']*'|"[^"]*"|[^\s;&|]+)"""
GIT_WRITE = re.compile(rf"\bgit(?:\s+-[Cc]\s+{ARG}|\s+--?[\w-]+(?:={ARG})?)*\s+(commit|push)\b")
GH_WRITE = re.compile(r"\bgh\s+(?:pr\s+(?:create|edit|comment|review)|issue\s+(?:create|edit|comment)|release\s+(?:create|edit))\b")
GH_API_WRITE = re.compile(r"\bgh\s+api\b.*(?:(?:-X|--method)[ =]?\s*(?:POST|PATCH|PUT)|\s-[fF]\s|--field|--raw-field|--input)", re.S)

ATTRIBUTION = [re.compile(p, re.I) for p in (
    r"co-authored-by:[^\n]*(?:claude|anthropic)",
    r"noreply@anthropic\.com",
    r"generated\s+(?:with|by)\s+\[?\s*claude",
    r"claude\.com/claude-code",
    r"claude-session:",
    r"claude\.ai/code/session",
    r"""(?:user\.name|user\.email|GIT_(?:AUTHOR|COMMITTER)_(?:NAME|EMAIL))\s*=\s*["']?[^\s"']*(?:claude|anthropic)""",
    r"""--author[= ]\s*["']?[^"'\n]*(?:claude|anthropic)""",
)]
AI_IDENTITY = re.compile(r"\bclaude\b|@anthropic\.com", re.I)
FILE_ARG = re.compile(rf"(?:--body-file|--file|-F)[= ]\s*({ARG})")
CAT_ARG = re.compile(rf"\$\(\s*cat\s+({ARG})\s*\)")
CD_ARG = re.compile(rf"(?:^|[;&|]\s*)cd\s+({ARG})")
DASH_C_ARG = re.compile(rf"\bgit\s+-C\s+({ARG})")
EXPLICIT_IDENTITY = re.compile(r"user\.(?:name|email)=|GIT_(?:AUTHOR|COMMITTER)_")


def unquote(value):
    return os.path.expanduser(value.strip("'\""))


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Blocked: {reason}. This project allows no AI attribution in commits, "
            f"pull requests or issues. Remove it and use the owner's identity: {OWNER}."
        ),
    }}))
    sys.exit(0)


def attribution_in(text):
    return next((m.group(0) for p in ATTRIBUTION if (m := p.search(text))), None)


def git(workdir, *args):
    done = subprocess.run(["git", *args], cwd=workdir, capture_output=True, text=True, timeout=5)
    return done.stdout if done.returncode == 0 else ""


def scan_files(command, workdir):
    for match in (*FILE_ARG.finditer(command), *CAT_ARG.finditer(command)):
        path = os.path.join(workdir, unquote(match.group(1)))
        try:
            with open(path, encoding="utf8", errors="ignore") as handle:
                text = handle.read(1_000_000)
        except OSError:
            continue
        if found := attribution_in(text):
            deny(f"'{found}' in {path}")


def main():
    data = json.load(sys.stdin)
    command = (data.get("tool_input") or {}).get("command") or ""
    git_write = GIT_WRITE.search(command)
    if not (git_write or GH_WRITE.search(command) or GH_API_WRITE.search(command)):
        return

    if found := attribution_in(command):
        deny(f"'{found}' in the command")

    workdir = data.get("cwd") or os.getcwd()
    moved = DASH_C_ARG.search(command) or CD_ARG.search(command)
    if moved:
        workdir = os.path.join(workdir, unquote(moved.group(1)))
    if not os.path.isdir(workdir):
        return
    scan_files(command, workdir)

    verbs = {m.group(1) for m in GIT_WRITE.finditer(command)}
    if "commit" in verbs and not EXPLICIT_IDENTITY.search(command):
        for kind in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
            identity = git(workdir, "var", kind)
            if AI_IDENTITY.search(identity.rsplit(">", 1)[0]):
                deny(f"git would commit as '{identity.split('>')[0]}>'")

    if "push" in verbs:
        log = git(workdir, "log", "HEAD", "--not", "--remotes", "--max-count=200",
                  "--format=%h%x00%an <%ae>%x00%cn <%ce>%x00%B%x01")
        for entry in filter(str.strip, log.split("\x01")):
            sha, author, committer, body = entry.strip().split("\x00", 3)
            if AI_IDENTITY.search(author) or AI_IDENTITY.search(committer):
                deny(f"commit {sha} is by '{author}' / '{committer}'")
            if found := attribution_in(body):
                deny(f"'{found}' in commit {sha}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
