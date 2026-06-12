#!/usr/bin/env python3
"""backlog.py — drive an ISSUES_PLAN.json through GitHub via `gh`.

Subcommands:
  validate   local-only: schema, unique ids, dep refs, hard-dep cycles
  render     local-only: (re)generate ISSUES_PLAN.md from the .json
  dedupe     mark issues whose backlog-id marker already exists on GitHub
  create     idempotent labels, then file each pending issue (body on stdin)
  link       replace DEPS_PLACEHOLDER with the resolved dependency section,
             add the `blocked` label where a hard prerequisite exists

Only `validate` / `render` are safe before the confirm gate. The others call
`gh` and write to GitHub. The artifact is written back after every gh call so
an interrupted run resumes cleanly (already-`created` items are skipped).

Stdlib only. Bodies are always delivered to `gh` on stdin via `--body-file -`
— never interpolated into a shell command (multi-line bodies break quoting).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

MARKER_RE = re.compile(r"<!--\s*backlog-id:\s*([a-z0-9][a-z0-9-]*)\s*-->")
PLACEHOLDER = "<!-- DEPS_PLACEHOLDER -->"
KEYSTONE_THRESHOLD = 3


# ---------- artifact io --------------------------------------------------- #

def load_plan(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save_plan(path: str, data: dict) -> None:
    """Atomic write so a crash mid-write never corrupts the artifact."""
    d = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".issues_plan.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def marker_for(backlog_id: str) -> str:
    return f"<!-- backlog-id: {backlog_id} -->"


def ensure_markers(issue: dict) -> str:
    """Return the body with the backlog-id marker + placeholder guaranteed."""
    body = issue["body"]
    if marker_for(issue["backlog_id"]) not in body:
        body = body.rstrip() + "\n\n" + marker_for(issue["backlog_id"])
    if PLACEHOLDER not in body:
        body = body.rstrip() + "\n" + PLACEHOLDER
    return body


# ---------- gh helpers ---------------------------------------------------- #

def gh_available() -> bool:
    try:
        subprocess.run(["gh", "--version"], capture_output=True, check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def require_gh() -> None:
    if not gh_available():
        sys.exit("error: `gh` CLI not available — cannot reach GitHub")
    r = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("error: `gh` not authenticated — run `gh auth login`")


def gh_json(args: list[str]):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"error: gh {' '.join(args)}\n{r.stderr.strip()}")
    return json.loads(r.stdout or "[]")


# ---------- validate ------------------------------------------------------ #

def cmd_validate(plan: dict, path: str) -> int:
    errs: list[str] = []
    warns: list[str] = []

    if plan.get("schema_version") != 1:
        errs.append("schema_version must be 1")

    issues = plan.get("issues", [])
    label_names = {l["name"] for l in plan.get("labels", [])}
    ids: dict[str, int] = {}
    titles: dict[str, int] = {}
    is_gap_mode = plan.get("mode") == "gap-analysis"

    for i, iss in enumerate(issues):
        bid = iss.get("backlog_id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", bid or ""):
            errs.append(f"issue[{i}] backlog_id '{bid}' not kebab-case")
        ids[bid] = ids.get(bid, 0) + 1
        t = (iss.get("title") or "").strip().lower()
        titles[t] = titles.get(t, 0) + 1
        if iss.get("horizon") not in ("near-term", "deferred"):
            errs.append(f"{bid}: horizon must be near-term|deferred")
        if iss.get("status") not in ("pending", "created", "failed"):
            errs.append(f"{bid}: status must be pending|created|failed")
        for lb in iss.get("labels", []):
            if lb not in label_names:
                errs.append(f"{bid}: label '{lb}' not declared in labels[]")
        body = iss.get("body", "")
        if marker_for(bid) not in body:
            warns.append(f"{bid}: body missing backlog-id marker (auto-added on create)")
        if PLACEHOLDER not in body:
            warns.append(f"{bid}: body missing DEPS_PLACEHOLDER (auto-added on create)")
        if is_gap_mode and not (iss.get("evidence") or "").strip():
            warns.append(
                f"{bid}: gap-analysis issue has no `evidence` — the "
                "verification step (Phase 2) was skipped or its result lost"
            )

    for bid, n in ids.items():
        if n > 1:
            errs.append(f"duplicate backlog_id: {bid} (x{n})")
    for t, n in titles.items():
        if n > 1:
            warns.append(f"duplicate title: '{t}' (x{n})")

    known = set(ids)
    for iss in issues:
        for kind in ("depends_on_hard", "depends_on_soft"):
            for ref in iss.get(kind, []):
                if ref not in known:
                    errs.append(
                        f"{iss.get('backlog_id')}: {kind} -> unknown '{ref}'"
                    )

    cycle = _find_cycle(issues)
    if cycle:
        errs.append("hard-dependency cycle: " + " -> ".join(cycle))

    for w in warns:
        print(f"warn: {w}")
    if errs:
        for e in errs:
            print(f"ERROR: {e}", file=sys.stderr)
        print(f"\nvalidate: {len(errs)} error(s)", file=sys.stderr)
        return 1
    print(f"validate: OK ({len(issues)} issues, {len(warns)} warning(s))")
    return 0


def _find_cycle(issues: list[dict]) -> list[str] | None:
    graph = {i["backlog_id"]: list(i.get("depends_on_hard", [])) for i in issues}
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {n: WHITE for n in graph}
    stack: list[str] = []

    def dfs(n: str) -> list[str] | None:
        color[n] = GRAY
        stack.append(n)
        for m in graph.get(n, []):
            if m not in color:
                continue
            if color[m] == GRAY:
                return stack[stack.index(m):] + [m]
            if color[m] == WHITE:
                r = dfs(m)
                if r:
                    return r
        stack.pop()
        color[n] = BLACK
        return None

    for n in graph:
        if color[n] == WHITE:
            r = dfs(n)
            if r:
                return r
    return None


# ---------- render -------------------------------------------------------- #

def _dependents(issues: list[dict]) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {i["backlog_id"]: [] for i in issues}
    for iss in issues:
        for ref in iss.get("depends_on_hard", []):
            if ref in out:
                out[ref].append(iss["backlog_id"])
    return out


def cmd_render(plan: dict, path: str) -> int:
    issues = plan.get("issues", [])
    deps = _dependents(issues)
    md_path = os.path.join(
        os.path.dirname(os.path.abspath(path)) or ".", "ISSUES_PLAN.md"
    )
    lines: list[str] = []
    lines.append(f"# Backlog plan — {plan.get('repo','?')}  (mode: {plan.get('mode','?')})")
    lines.append("")
    src = ", ".join(plan.get("source_docs") or []) or "(list mode)"
    lines.append(
        f"Source: {src} · {len(issues)} issues · {len(plan.get('labels',[]))} labels"
    )
    lines.append("")
    keystones = sorted(
        ((len(d), b) for b, d in deps.items() if len(d) >= KEYSTONE_THRESHOLD),
        reverse=True,
    )
    if keystones:
        lines.append("## Keystones")
        for n, b in keystones:
            lines.append(f"- **{b}** unblocks {n} issues — high-leverage start.")
        lines.append("")
    lines.append("## Proposed issues")
    lines.append("| backlog_id | Title | Labels | Horizon | Hard deps | Soft deps | Status |")
    lines.append("|---|---|---|---|---|---|---|")
    for iss in issues:
        lines.append(
            "| {bid} | {title} | {labels} | {hz} | {hd} | {sd} | {st} |".format(
                bid=iss["backlog_id"],
                title=iss["title"].replace("|", "\\|"),
                labels=", ".join(iss.get("labels", [])),
                hz=iss.get("horizon", ""),
                hd=", ".join(iss.get("depends_on_hard", [])) or "—",
                sd=", ".join(iss.get("depends_on_soft", [])) or "—",
                st=iss.get("status", "pending"),
            )
        )
    lines.append("")
    lines.append("## New labels")
    lines.append(
        ", ".join(
            f"`{l['name']}` (#{l['color']})" for l in plan.get("labels", [])
        )
    )
    lines.append("")
    excluded = plan.get("excluded") or []
    if excluded:
        lines.append("## Tracked elsewhere (not filed)")
        for ex in excluded:
            bid = ex.get("backlog_id", "?")
            reason = ex.get("reason", "?")
            detail = ex.get("detail", "")
            lines.append(f"- `{bid}` — {reason}: {detail}")
        lines.append("")
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"render: wrote {md_path}")
    return 0


# ---------- dedupe -------------------------------------------------------- #

def cmd_dedupe(plan: dict, path: str) -> int:
    require_gh()
    existing = gh_json(
        ["issue", "list", "--state", "all", "--limit", "1000",
         "--json", "number,title,state,body"]
    )
    by_marker: dict[str, int] = {}
    for e in existing:
        m = MARKER_RE.search(e.get("body") or "")
        if m:
            by_marker[m.group(1)] = e["number"]

    def norm(t: str) -> str:
        return re.sub(r"[^a-z0-9]+", " ", (t or "").lower()).strip()

    existing_titles = {norm(e["title"]): e["number"] for e in existing}

    matched = 0
    for iss in plan.get("issues", []):
        if iss.get("status") == "created":
            continue
        bid = iss["backlog_id"]
        if bid in by_marker:
            iss["status"] = "created"
            iss["github_issue_number"] = by_marker[bid]
            iss["error"] = None
            matched += 1
            print(f"dedupe: {bid} already filed as #{by_marker[bid]} — skip")
            save_plan(path, plan)
        else:
            tn = norm(iss["title"])
            if tn in existing_titles:
                print(
                    f"dedupe: ADVISORY {bid} title ~ existing "
                    f"#{existing_titles[tn]} — review before filing"
                )
    print(f"dedupe: {matched} already-existing issue(s) marked created")
    return 0


# ---------- create -------------------------------------------------------- #

def _ensure_labels(plan: dict) -> None:
    for lb in plan.get("labels", []):
        r = subprocess.run(
            ["gh", "label", "create", lb["name"],
             "--color", lb.get("color", "ededed"),
             "--description", lb.get("description", ""), "--force"],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            print(f"warn: label {lb['name']}: {r.stderr.strip()}",
                  file=sys.stderr)


def _issue_number_from_url(out: str) -> int | None:
    line = (out or "").strip().splitlines()[-1] if out.strip() else ""
    m = re.search(r"/issues/(\d+)", line)
    return int(m.group(1)) if m else None


def cmd_create(plan: dict, path: str) -> int:
    require_gh()
    _ensure_labels(plan)
    filed = failed = 0
    for iss in plan.get("issues", []):
        if iss.get("status") == "created":
            continue
        body = ensure_markers(iss)
        if iss.get("horizon") == "deferred" and "deferred" not in iss.get("labels", []):
            iss.setdefault("labels", []).append("deferred")
        args = ["gh", "issue", "create", "--title", iss["title"],
                "--body-file", "-"]
        for lb in iss.get("labels", []):
            args += ["--label", lb]
        r = subprocess.run(args, input=body, capture_output=True, text=True)
        if r.returncode == 0:
            num = _issue_number_from_url(r.stdout)
            iss["status"] = "created"
            iss["github_issue_number"] = num
            iss["error"] = None
            filed += 1
            print(f"create: {iss['backlog_id']} -> #{num}")
        else:
            iss["status"] = "failed"
            iss["error"] = r.stderr.strip()
            failed += 1
            print(f"create: FAILED {iss['backlog_id']}: {r.stderr.strip()}",
                  file=sys.stderr)
        save_plan(path, plan)  # write-back after every call (resumable)
    print(f"create: {filed} filed, {failed} failed")
    return 1 if failed else 0


# ---------- link ---------------------------------------------------------- #

def _dep_section(iss: dict, num: dict[str, int], dependents: list[str]) -> str:
    out = ["### Dependencies"]
    hard = [num[d] for d in iss.get("depends_on_hard", []) if d in num]
    soft = [num[d] for d in iss.get("depends_on_soft", []) if d in num]
    if hard:
        out.append("Blocked by: " + ", ".join(f"#{n}" for n in sorted(hard)))
    if soft:
        out.append("Soft: " + ", ".join(f"#{n}" for n in sorted(soft)))
    dep_nums = sorted(num[d] for d in dependents if d in num)
    if len(dep_nums) >= KEYSTONE_THRESHOLD:
        out.append("Keystone: unblocks "
                   + ", ".join(f"#{n}" for n in dep_nums))
    if len(out) == 1:
        return ""  # no deps, nothing to write
    return "\n".join(out)


def cmd_link(plan: dict, path: str) -> int:
    require_gh()
    issues = plan.get("issues", [])
    num = {i["backlog_id"]: i["github_issue_number"]
           for i in issues if i.get("github_issue_number")}
    deps = _dependents(issues)
    edited = 0
    for iss in issues:
        n = iss.get("github_issue_number")
        if not n:
            continue
        section = _dep_section(iss, num, deps.get(iss["backlog_id"], []))
        body = ensure_markers(iss)
        body = body.replace(PLACEHOLDER, section).rstrip() + "\n"
        r = subprocess.run(
            ["gh", "issue", "edit", str(n), "--body-file", "-"],
            input=body, capture_output=True, text=True,
        )
        if r.returncode != 0:
            print(f"link: FAILED edit #{n}: {r.stderr.strip()}",
                  file=sys.stderr)
            continue
        if iss.get("depends_on_hard"):
            subprocess.run(
                ["gh", "issue", "edit", str(n), "--add-label", "blocked"],
                capture_output=True, text=True,
            )
        edited += 1
        print(f"link: #{n} ({iss['backlog_id']})")
    print(f"link: {edited} issue(s) updated")
    return 0


# ---------- cli ----------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="backlog.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("validate", "render", "dedupe", "create", "link"):
        sp = sub.add_parser(name)
        sp.add_argument("--plan", default="ISSUES_PLAN.json")
    args = p.parse_args(argv)
    plan = load_plan(args.plan)
    return {
        "validate": cmd_validate,
        "render": cmd_render,
        "dedupe": cmd_dedupe,
        "create": cmd_create,
        "link": cmd_link,
    }[args.cmd](plan, args.plan)


if __name__ == "__main__":
    raise SystemExit(main())
