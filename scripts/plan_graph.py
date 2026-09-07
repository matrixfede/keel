#!/usr/bin/env python3
"""plan_graph.py — reads the PLAN.md table as a graph and validates it (SOP-8).

Usage:
    python3 scripts/plan_graph.py                 # full report + execution waves
    python3 scripts/plan_graph.py --quiet         # errors + final line only (for verify.sh and the hook)
    python3 scripts/plan_graph.py --json          # everything as JSON (for other scripts)
    python3 scripts/plan_graph.py --group P1      # task numbers of group P1, one per line
    python3 scripts/plan_graph.py --task 3        # task 3 row + its contract (for fanout.sh)
    python3 scripts/plan_graph.py --contract 3    # task 3 contract only (OUT|shape|check, tab-separated)

Result: last line "GRAPH: OK" or "GRAPH: FAIL" + exit code 1.
The file is the only source: no external dependencies, standard library only.

Checks (error → FAIL):
  - dependency on a non-existent task or on itself
  - cycle in the graph
  - two tasks in the same parallel group [Pn] depending on each other
  - active task without a declared verification
  - task in a parallel group without an output contract ("Contracts" section)
  - contract pointing to a non-existent or removed task
Warnings (non-blocking):
  - ✅ task depending on a non-✅ task
  - more than one 🔄 task
  - parallel group with a single task
  - `critical` ✅ task without KEEP in Notes (the hook checks the verdict file)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PLAN = Path("PLAN.md")

ROW_RE = re.compile(r"^\|\s*(\d+)\s*\|")
GROUP_RE = re.compile(r"\[P(\d+)\]")
# - Task 3 — OUT: `out/variants.tsv` — shape: TSV with columns ... — check: `head -1 out/variants.tsv | grep -q chrom`
CONTRACT_RE = re.compile(
    r"^-\s*Task\s+(\d+)\s*[—–-]+\s*OUT:\s*`([^`]+)`"
    r"(?:\s*[—–-]+\s*shape:\s*(.*?))?"
    r"(?:\s*[—–-]+\s*check:\s*`([^`]+)`)?\s*$"
)

DONE, DOING, TODO, BLOCKED = "✅", "🔄", "⬜", "⛔"


def split_row(line: str) -> list[str]:
    cells = line.strip().strip("|").split("|")
    return [c.strip() for c in cells]


def parse(text: str) -> dict:
    tasks: dict[int, dict] = {}
    contracts: dict[int, dict] = {}
    errors: list[str] = []
    in_contracts = False

    for raw in text.splitlines():
        line = raw.rstrip()
        if line.startswith("## "):
            in_contracts = line.lower().startswith("## contracts")
            continue

        if in_contracts and line.startswith("- "):
            m = CONTRACT_RE.match(line)
            if m:
                n = int(m.group(1))
                contracts[n] = {
                    "task": n,
                    "out": m.group(2).strip(),
                    "shape": (m.group(3) or "").strip(),
                    "check": (m.group(4) or "").strip(),
                }
            elif line.lower().lstrip("- ").startswith("task"):
                errors.append(f"unreadable contract: {line.strip()!r} "
                              "(expected: - Task N — OUT: `file` — shape: ... — check: `cmd`)")
            continue

        m = ROW_RE.match(line)
        if not m:
            continue
        cells = split_row(line)
        if len(cells) < 6:
            errors.append(f"task row {m.group(1)}: expected 6 columns, found {len(cells)}")
            continue
        n = int(cells[0])
        name, state, deps_raw, verify, note = cells[1], cells[2], cells[3], cells[4], cells[5]
        removed = name.startswith("~~")
        deps: list[int] = []
        if not removed and deps_raw not in ("", "—", "-", "–"):
            for tok in re.split(r"[,\s]+", deps_raw):
                if tok.isdigit():
                    deps.append(int(tok))
                elif tok:
                    errors.append(f"task {n}: non-numeric value in 'Depends on': {tok!r}")
        g = GROUP_RE.search(note)
        if n in tasks:
            errors.append(f"duplicate task number: {n}")
        tasks[n] = {
            "n": n,
            "task": name,
            "state": (DONE if DONE in state else DOING if DOING in state
                      else BLOCKED if BLOCKED in state else TODO),
            "deps": deps,
            "verify": verify,
            "note": note,
            "group": f"P{g.group(1)}" if g else None,
            "critical": "critical" in note.lower(),
            "removed": removed,
        }

    return {"tasks": tasks, "contracts": contracts, "errors": errors}


def analyze(model: dict) -> dict:
    tasks, contracts = model["tasks"], model["contracts"]
    errors, warnings = list(model["errors"]), []
    active = {n: t for n, t in tasks.items() if not t["removed"]}

    for n, t in active.items():
        if t["verify"] in ("", "—", "-", "–"):
            errors.append(f"task {n}: no verification declared (a row without verification is not planned)")
        for d in t["deps"]:
            if d == n:
                errors.append(f"task {n}: depends on itself")
            elif d not in tasks:
                errors.append(f"task {n}: depends on task {d}, which does not exist")
            elif tasks[d]["removed"]:
                errors.append(f"task {n}: depends on task {d}, which was removed")
            elif t["group"] and tasks[d].get("group") == t["group"]:
                errors.append(f"task {n} and task {d} are both in [{t['group']}] but {n} depends on {d}: "
                              "either the edge is fake, or the group is wrong")
            elif t["state"] == DONE and tasks[d]["state"] != DONE:
                warnings.append(f"task {n} is ✅ but depends on task {d} which is not: check consistency")
        if t["critical"] and t["state"] == DONE and "keep" not in t["note"].lower():
            warnings.append(f"task {n} is critical and ✅ but Notes carry no KEEP verdict")

    groups: dict[str, list[int]] = {}
    for n, t in active.items():
        if t["group"]:
            groups.setdefault(t["group"], []).append(n)
    for g, members in sorted(groups.items()):
        if len(members) == 1:
            warnings.append(f"group [{g}] has a single task ({members[0]}): the label is unnecessary")
        for n in members:
            if n not in contracts:
                errors.append(f"task {n} is in group [{g}] but has no output contract "
                              "('Contracts' section: - Task N — OUT: `file` — shape: ...)")

    for n in contracts:
        if n not in tasks:
            errors.append(f"contract for task {n}, which does not exist in the table")
        elif tasks[n]["removed"]:
            errors.append(f"contract for task {n}, which was removed")

    doing = [n for n, t in active.items() if t["state"] == DOING]
    if len(doing) > 1:
        warnings.append(f"more than one 🔄 task at the same time: {doing} (rule: only one)")

    # Execution waves (layered Kahn) — only if the graph is well formed.
    waves: list[list[int]] = []
    valid_deps = {n: [d for d in t["deps"] if d in active] for n, t in active.items()}
    remaining = set(active)
    while remaining:
        ready = sorted(n for n in remaining if all(d not in remaining for d in valid_deps[n]))
        if not ready:
            errors.append(f"cycle in the dependencies among tasks {sorted(remaining)}")
            break
        waves.append(ready)
        remaining -= set(ready)

    finals = sorted(n for n in active if not any(n in valid_deps[m] for m in active))

    return {
        "tasks": [active[n] for n in sorted(active)],
        "removed": sorted(n for n, t in tasks.items() if t["removed"]),
        "contracts": [contracts[n] for n in sorted(contracts)],
        "groups": groups,
        "waves": waves,
        "finals": finals,
        "errors": errors,
        "warnings": warnings,
        "ok": not errors,
    }


def report(a: dict, quiet: bool) -> None:
    if not quiet:
        print("═ PLAN GRAPH ═")
        for t in a["tasks"]:
            deps = ",".join(map(str, t["deps"])) or "—"
            tags = " ".join(x for x in ([t["group"]] if t["group"] else []) + (["critical"] if t["critical"] else []))
            print(f"  #{t['n']:<3} {t['state']} {t['task'][:44]:<44} deps:{deps:<8} {tags}")
        if a["removed"]:
            print(f"  removed: {a['removed']}")
        print("─ Execution waves (same wave = runnable together)")
        for i, w in enumerate(a["waves"], 1):
            print(f"  wave {i}: {w}")
        print(f"─ Final outputs (no task consumes them): {a['finals']}")
        if a["contracts"]:
            print("─ Contracts")
            for c in a["contracts"]:
                extra = f" — check: {c['check']}" if c["check"] else ""
                print(f"  task {c['task']}: {c['out']} — {c['shape'] or 'shape not declared'}{extra}")
        for w in a["warnings"]:
            print(f"  ⚠ {w}")
    for e in a["errors"]:
        print(f"  ✗ {e}")
    print("GRAPH: OK" if a["ok"] else "GRAPH: FAIL")


def main(argv: list[str]) -> int:
    if not PLAN.exists():
        print("PLAN.md missing")
        print("GRAPH: FAIL")
        return 1
    a = analyze(parse(PLAN.read_text(encoding="utf-8")))

    if "--json" in argv:
        print(json.dumps(a, ensure_ascii=False, indent=2))
        return 0 if a["ok"] else 1

    if "--group" in argv:
        g = argv[argv.index("--group") + 1]
        for n in a["groups"].get(g, []):
            print(n)
        return 0 if a["groups"].get(g) else 1

    if "--contract" in argv:
        n = int(argv[argv.index("--contract") + 1])
        c = next((c for c in a["contracts"] if c["task"] == n), None)
        if not c:
            return 1
        print(f"{c['out']}\t{c['shape']}\t{c['check']}")
        return 0

    if "--task" in argv:
        n = int(argv[argv.index("--task") + 1])
        t = next((t for t in a["tasks"] if t["n"] == n), None)
        if not t:
            print(f"task {n} not found")
            return 1
        c = next((c for c in a["contracts"] if c["task"] == n), None)
        print(f"TASK {n}: {t['task']}")
        print(f"VERIFICATION: {t['verify']}")
        print(f"NOTES: {t['note']}")
        if c:
            print(f"OUT: {c['out']}")
            print(f"SHAPE: {c['shape'] or 'not declared'}")
            if c["check"]:
                print(f"CHECK: {c['check']}")
        return 0

    report(a, quiet="--quiet" in argv)
    return 0 if a["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
