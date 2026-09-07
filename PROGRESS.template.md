# PROGRESS — <task name>

Progress log. **Append-only: never rewrite, never delete entries.**
`PLAN.md` says where we are; this file says how we got here.

One entry at every checkpoint (task ✅, task ⛔, plan approved, end of
session, risk of interruption), under 100 words, in this exact shape.
At session start read everything top to bottom and resume from the last NEXT.

## 2026-01-01 10:00
- DID: plan approved by the user (5 tasks, group [P1] = tasks 1-2, task 3 critical)
- DECIDED: D1 — streaming parser instead of in-memory: files exceed 2 GB
- BLOCKED: —
- NEXT: task 1

## 2026-01-01 11:40
- DID: task 1 ✅ (`verify.sh unit` → 42 passed); task 2 🔄 started
- DECIDED: —
- BLOCKED: —
- NEXT: task 2, missing the test for the header-less case
