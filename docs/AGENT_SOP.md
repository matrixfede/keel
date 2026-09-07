# AGENT SOP — Plan-Driven Execution

Standard operating procedures. Referenced by `AGENTS.md`.
Scope: any multi-step task, extended refactoring, feature touching several
files, or work that may outlast a session.

---

## SOP-0 — Planning gate (precedes every other SOP)

The gate is defined in `AGENTS.md` and is binding. Here is the operational detail.

**Why it exists.** A plan produced and passed in the same turn is not a plan:
it is a narrative preamble to work already decided. The value is in the pause —
thirty seconds of human reading cost less than a wrong refactor discovered at
the fourth task.

**Check before every write.** Before creating or modifying any file other than
`PLAN.md`, check the plan header:

```bash
head -5 PLAN.md
```

- `Plan status: DRAFT` → do not write. Remind the user the plan is awaiting
  approval and stop.
- `PLAN.md` missing → do not write. Go to the planning gate.
- `Plan status: APPROVED` → you may proceed on the tasks of the approved plan.

**Approval covers the plan, not the project.** It applies to the table as it
was at the moment of the go. If during the work unplanned tasks emerge that
change the structure — not an implementation detail, but an extra piece of
work — set the plan back to `DRAFT`, present the change and wait again. Adding
a row to the table and carrying on autonomously empties the gate.

**One exception only.** If the user explicitly writes "skip the plan" or "just
do it", proceed without the gate. It is not a permission to be inferred from
the brisk tone of a request: it must be said.

## SOP-1 — Long-term memory

- `PLAN.md` is the single source of truth on the state of the work.
  Conversational memory is a volatile cache: every conflict resolves in favor
  of the file.
- **What persists in `PLAN.md`**: objective, dated requirements with source,
  plan with statuses, output contracts, architectural decisions with rationale,
  pre-mortem outcome. It is the **current state**: it says where we are.
- **What persists in `PROGRESS.md`** (SOP-10): the **history**, one entry per
  checkpoint, append-only. It says how we got here. Separating the two roles
  is what lets `PLAN.md` stay short without losing the trail.
- **What goes in neither**: debug output, stack traces, code diffs, anything
  reproducible by a command. `PLAN.md` stays under ~150 lines; past that
  threshold, archive finished sections in `PLAN_ARCHIVE.md`. `PROGRESS.md`
  just grows: that is its job.
- Decisions are recorded at the moment they are made, not afterwards: an
  unwritten decision is a decision the next session will re-argue.

## SOP-2 — Context persistence (resume protocol)

At the start of every session on a project with an existing `PLAN.md`:

1. Run `./scripts/health_report.sh` for the state snapshot (it also shows the
   last `PROGRESS.md` entry and the graph result).
2. Read `PLAN.md` in full, then `PROGRESS.md` in full, top to bottom: the
   latest entry has the `NEXT` to resume from, but the earlier ones say what
   was already tried and discarded — do not repeat it.
3. **Check state↔code consistency**: for every `✅` task of the last session,
   a quick check that the artifact really exists (file created, test present,
   function implemented, migration applied). For `critical` tasks, that
   `logs/agent/checker_task<n>.txt` exists with `VERDICT: KEEP`.
4. Inconsistency found (task `✅` but code missing or broken) → demote the
   task to `🔄`, note the anomaly in Notes, flag it to the user in one line,
   and record an entry in `PROGRESS.md` (BLOCKED: inconsistency found on resume).
5. Resume from the first non-`✅` task respecting dependencies — normally the
   `NEXT` of the last `PROGRESS.md` entry; if the two disagree, `PLAN.md` wins
   and you say so.
6. Do not ask the user for information already present in "Active
   requirements", "Decisions" or `PROGRESS.md`.

## SOP-3 — Task validation (definition of done)

Standard mapping between task type and minimum mandatory verification:

| Task type               | Minimum mandatory verification                     |
|-------------------------|----------------------------------------------------|
| Business logic          | New/existing unit tests green                      |
| API / integration       | Integration test or real call with logs            |
| Frontend / UI           | Build ok + inspected screenshot + clean console    |
| Refactoring             | Full suite green + diff review                     |
| Config / infrastructure | The tool's own validation command (dry-run)        |
| Data pipeline           | Run on a test dataset + comparison with expected   |
| Documentation           | Markdown lint + link check                         |
| Report / analysis / text| Rubric loop: all criteria ≥ 8 (SOP-7)              |
| Task marked `critical`  | Standard verification + `checker.sh` → `CHECKER: KEEP` (SOP-8) |
| Task in a `[P]` group   | Standard verification + output conforming to the contract (SOP-8) |

Rules:
- The verification is **run**, not assumed.
- Command and result are noted in Notes.
- Three consecutive failures on the same verification → `⛔` and a diagnosis
  presented to the user. The blind change-and-retry loop is forbidden: it
  burns tokens and hides the real cause.
- Before the final `✅`: remove the `AGENTDBG|` debug prints you introduced.
- Before `✅`, the surgical-diff test: does every changed line trace back to
  the task? Reformatting, renames or unrequested "improvements" are removed
  from the diff (or proposed as a separate task).

## SOP-4 — Handling requirement changes

1. Record the new requirement under "Active requirements" with date and source.
2. Assess the impact: which existing tasks change, lapse or get added.
3. Update the table (strike the lapsed ones with a reason, insert the new ones).
4. Report the impact delta in chat, in common words:
   "The new requirement R4 makes tasks 5 and 6 useless, I'm adding 2 new
   ones; what is already done (tasks 1-3) stays valid."
5. Only then, touch the code.

## SOP-5 — Manual intervention by the user

The user may edit `PLAN.md` directly between sessions, or while the agent is
idle. Therefore:

- Never assume the file is identical to how you left it. The SOP-2 re-read is
  mandatory even mid-session after a long pause.
- The user's manual edits **prevail** over the state in memory and are not to
  be "corrected", except for an evident inconsistency — which is flagged, not
  fixed on your own initiative.
- A task manually demoted from `✅` to `⬜` with the note
  `(reopened by user: ...)` is treated as to-be-redone, without arguing the decision.

## SOP-6 — Context hygiene (for long windows)

Current models have very large context windows: the risk is no longer running
out of it, but **diluting** it. Rules (valid for any agent):

- Do not re-read files already read in the same session unless they changed;
  use `git diff` to see what changed instead of reloading whole files.
- Do not paste long test outputs into the context: use the runners' compact
  formats (already configured in `verify.sh`) and quote only the error lines.
- At every `✅`, the implementation detail of the closed task can be dropped:
  what the future session needs is already in `PLAN.md`.

## SOP-7 — Rubric loop (for outputs that tests cannot verify)

`verify.sh` covers code: binary result, no opinion. But when the deliverable
is a document, a report, an analysis or a text, a test cannot give PASS. For
these tasks the "Verification" column says `rubric` and this cycle applies.

**In the plan, before starting the task**, declare the rubric: 3-5 measurable
criteria, not adjectives. "Clear" is not a criterion; "every claim has a
dated source" is. The rubric goes in the Notes column or, if long, in a
dedicated plan section — the user approves it with the plan, not discovers it
when the work is done.

**The cycle** (maximum 5 passes, unless the plan says otherwise):

1. DRAFT — produce or improve the output.
2. SCORE — grade 1-10 on EVERY criterion, harshly. One-line rationale for
   every grade below 8.
3. GAPS — list what is still weak, by severity.
4. LOG — before moving to the next pass, add a row to the pass table (below).
   Without this row the pass did not happen.
5. CALL — all criteria ≥ 8 → the task is verifiable as closed: note the final
   scores in Notes and move on. Otherwise: next pass, fixing FIRST the
   criterion with the lowest score.

**Pass table** — the loop must show its work, not just the result. For every
rubric task keep `logs/agent/rubric_task<n>.md` with one row per pass:

```
| pass | weakest criterion last round | score | what I changed | new score |
|------|------------------------------|-------|----------------|-----------|
| 1    | —                            | —     | first draft    | c1=6 c2=7 c3=5 |
| 2    | c3 (undated sources)         | 5     | added dates to 7 sources | c1=6 c2=7 c3=8 |
```

The full table is reported in chat at every pass, so the user sees the
movement. Two rules follow from it:
- **A score goes down instead of up → stop.** The last change made the work
  worse; go back to the previous draft and tell the user before continuing.
  Do not "compensate" on the next round.
- **The same criterion is the weakest three passes in a row → the problem is
  the criterion, not the text.** It is probably vague. Do not keep iterating:
  propose a rewording of the criterion to the user. Rewriting a criterion is a
  change to the approved rubric, so the plan goes back to `DRAFT` and the new
  rubric is re-approved (SOP-0). It is the only legitimate way to change a
  criterion mid-loop.

**Stop conditions** — always two, never one:
- success: all criteria ≥ 8;
- ceiling: maximum passes reached without success → the task goes to `⛔`
  with the last round's scores and hypotheses on why it does not converge.
  As with the three verify.sh failures: iterating blindly past the ceiling is
  forbidden.

**Keep rate.** At the end of the task note in Notes how many passes it took
and how many drafts were discarded (the pass table makes it a count, not an
estimate). If more than half the passes are systematically discarded, the loop
costs more than it yields: flag it to the user and propose revising the rubric
or splitting the task.

**When the loop is not worth it.** Before declaring `rubric` as verification,
four conditions must hold together: this type of output will come up again
(it is not a one-off); the criteria can be judged without the user's eye; the
task closes without human input midway; the finish line is a measurable fact,
not a feeling. If one is missing, the right verification is "user review",
declared as such, and the loop is not run.

**Anti-patterns to avoid**: complacent grades (all 8s on the first round is a
sign of soft scoring, not quality), criteria rewritten mid-loop without going
through the gate, and passes that "improve" things the rubric did not ask for.

## SOP-8 — Task graph: real dependencies, parallelism, fresh checker

The "Depends on" column is not an execution order: it is a graph. An edge
exists only if one task's output is REALLY an input to another. The order the
tasks were written in is not a dependency.

### Fake edge test (mandatory in the planning gate)

After building the table, for EVERY value in "Depends on" ask yourself: does
the data produced by task X materially flow into task Y (a file, a result, a
decision that Y consumes)?

- Yes → the edge stays.
- No → remove it: it was sequence, not dependency.

Tasks left with no mutual dependencies get a parallel-group label in the Notes
column: `[P1]`, `[P2]`, ... Tasks in the same group can run in any order or
at the same time.

**The test has a deterministic part.** `python3 scripts/plan_graph.py` reads
the table as a graph and fails (`GRAPH: FAIL`) if it finds: cycles;
dependencies on non-existent or removed tasks; two tasks in the same `[P]`
group depending on each other (either the edge is fake or the group is wrong);
tasks without a declared verification; tasks in a group without an output
contract. It also prints the execution "waves" — every task with no incoming
edge is wave 1, and so on — the quickest way to see whether the plan has the
"diamond" shape (fan out, then converge) or is a chain. `verify.sh static`
and the pre-commit hook run it: a plan with a broken graph is not committed.

### Output contracts (nodes with a declared shape)

A task that returns free text is readable only by a human. A task with an
output of declared shape is readable by the next task, with nobody in between.
That is why every task in a parallel group — and, recommended, every task that
produces a file — has a line in the "Contracts" section of `PLAN.md`:

```
- Task 2 — OUT: `out/variants.tsv` — shape: TSV, columns chrom,pos,ref,alt,gene, no blank lines — check: `head -1 out/variants.tsv | grep -q "^chrom"`
```

`OUT` is the file (one per task, never shared). `shape` is what it must
contain, in words. `check` is optional but is the only part verifiable without
a model: a command that exits 0 if the shape is respected. Contract rule:
**if the output does not respect the shape, it is rejected and redone** — the
convergence task must never adapt to a malformed input.

### Running parallel groups

By default the tasks of a group still run sequentially in the same session:
the label serves first to keep the plan honest and to allow resuming from any
task in the group. One coherent sequential agent wins in most cases:
parallelism is paid in tokens and fragmented context, and should be chosen,
not suffered.

Real fan-out (several agent sessions at once) is OPTIONAL and activates only
if the user asks for it or approves it in the plan. `scripts/fanout.sh <group>`
runs it:

- preconditions: plan `APPROVED`, `GRAPH: OK`, a contract for every task in
  the group, no more than 4 tasks (`FANOUT_MAX` ceiling);
- one session per task, launched together by the available agent CLI
  (`scripts/lib_agent.sh`: Codex with a write sandbox on the workspace only,
  or Claude Code, Gemini CLI, OpenCode, Copilot, or a `custom` command); each
  session receives ONLY its task, the contract, the objective and the active
  requirements — not the main conversation — and opens with `FANOUT WORKER`,
  which in `AGENTS.md` disables the gate and forbids touching
  `PLAN.md`/`PROGRESS.md`;
- **model-free reduction** (zero tokens): at the end the script checks that
  every `OUT` exists and is non-empty, that the `check` passes, that the
  worker ended with `TASK n: DONE`, and that `PLAN.md` and `PROGRESS.md` are
  intact. Only `FANOUT: PASS` authorizes the convergence task;
- the statuses in the plan are updated by the main session after the
  reduction, which runs each task's required verification itself before
  marking `✅`;
- without an agent CLI, `--prompt` writes the prompts to open the sessions by
  hand (with any agent, even via chat) and `--reduce` runs only the reduction
  afterwards;
- cost warning: fan-out multiplies token consumption by the number of
  sessions. Without an active budget guardrail, use it with judgment.

### Fresh-context checker (for tasks marked `critical`)

Whoever produces an output is not a good judge of that same output: the
chain of reasoning that produced the error is the same one that would look
for it. For tasks the plan marks `critical` in the Notes column, the
verification is done by `scripts/checker.sh <n> <artifact> [others...]`:

1. It opens a NEW session in a temporary folder containing ONLY a copy of the
   artifact (file, report, diff saved with `git diff > ...`). No repo, no
   `PLAN.md`, no conversation: if the checker sees the reasoning that produced
   the output, it is not a second pair of eyes, it is the same agent playing
   two parts.
2. It gives it the hostile prompt of `prompts/checker.md`: find the reason the
   output should be rejected, not improve it. Three independent checks — is it
   accurate? is it current? do the references hold? — with the "at least two
   out of three" rule and the option to DROP even with two if one defect alone
   makes the artifact unusable.
3. The final verdict is computed by the script, not the model: KEEP only if
   the model says KEEP AND at least two checks are PASS. The answer is
   requested as JSON (`prompts/checker.schema.json`; with Codex the schema is
   enforced by the CLI, with other agents the script extracts it tolerantly).
   If unreadable: `CHECKER: ERROR`, no verdict — never a guessed KEEP.
4. It writes `logs/agent/checker_task<n>.txt` with verdict, rationale, date,
   path and **SHA-256 hash of the artifact**. The pre-commit hook requires
   this file for every `critical` `✅` task and recomputes the hash: if the
   artifact changed after the review, the KEEP no longer holds and the checker
   must run again. A `KEEP` written in Notes by the working agent counts for
   nothing: the worker cannot grade itself.
5. `CHECKER: DROP` → the task goes back to `🔄` in the main session, with the
   rationale in Notes and an entry in `PROGRESS.md`.

Without an agent CLI: `--prompt` writes the prompt to paste into a new session
opened by hand (any agent), and `--record <n> KEEP|DROP "<rationale>" <artifact>`
records the verdict in the same format (hash included), so the hook sees no
difference.

The fresh checker does NOT replace `verify.sh` where applicable: it adds to it.
First the deterministic check, then the hostile one.

## SOP-9 — Plan pre-mortem (the arguer)

The checker attacks artifacts. Nothing, so far, attacked the plan: and the
plan is where a mistake costs the most, because all the work after it inherits
it. Asking the same agent "is the plan good?" yields a yes: it is trained to
agree, and on top of that it defends what it has just written.

The remedy is to flip the question. Not "is it good?", but "it failed: why?".
The brain defends a plan it has committed to and hides the risks it does not
want to see; the pre-mortem drags them out.

**When it is mandatory**: the plan contains at least one `critical` task, or
actions that are hard to undo — data migrations, deletions, changes to
pipelines or services in use, format changes to files that others read. For
other plans it is optional and the user can ask for it ("run the pre-mortem").

**How it runs**: `scripts/premortem.sh`, in the plan turn, before closing with
the waiting line. It opens a NEW session that sees ONLY `PLAN.md` (copied to a
temporary read-only folder) and gives it `prompts/arguer.md`: restate the plan
in one sentence, narrate the failure 12 months out from most to least likely,
and for the top three failure modes give the early warning sign and the
countermeasure possible today. It has precise instructions to look where the
plan is weak by construction: the `ASSUMED:` lines (which one, if false,
brings everything down?), the edges and `[P]` groups (is there a hidden
dependency treated as independence?), the "Verification" column (which
verification would pass even with a wrong result?).

**What is done with it**: the full outcome stays in
`logs/agent/premortem_<date>.md`. In `PLAN.md`, "Decisions" section, the top
three failure modes go in as `PRE-MORTEM:` lines, each with the countermeasure
adopted in the plan (a task added, a verification strengthened, an edge added)
or `accepted: <why>`. Ignoring a failure mode without writing down the reason
is not allowed: the user approves the plan reading those lines too.

Without an agent CLI: `--prompt` writes the prompt to paste into a new session
opened by hand, with any agent.

The pre-mortem does not decide: the user decides. But decides seeing the
risks, not after discovering them at the fourth task.

## SOP-10 — Progress log (`PROGRESS.md`)

A checkpoint says where you are now; it does not say how you got there. For
work that spans days, or that someone else will have to understand, the
history is the part that really matters — and it is lost if every checkpoint
overwrites the previous one.

`PROGRESS.md` is the log: **append-only, never rewritten, never deleted**.
It is created from `PROGRESS.template.md` when the plan is approved, and it is
versioned.

**When an entry is added**: plan approved; every `✅` task; every `⛔` task;
every checker `DROP`; end of session; perceived risk of interruption;
inconsistency found on resume (SOP-2).

**Exact entry shape** (under 100 words; vague is useless):

```
## <date time>
- DID: what got done since the previous entry
- DECIDED: the decision made and the one-line reason (or —)
- BLOCKED: what failed or is waiting, and on what (or —)
- NEXT: the single next action
```

**On resume** read everything top to bottom before doing anything, and start
from the last `NEXT` (SOP-2). When the work drifts, scrolling the log shows
the exact entry where it went sideways, instead of guessing.

**Relation to `PLAN.md`**: the plan is the state, the log is the history. No
duplication: `PROGRESS.md` does not copy the table, it records what changed.
In `PLAN.md` the old "Session log" section is replaced by a pointer to the log.

**Handover**: to bring a person up to speed, point them at `PROGRESS.md`. Two
minutes of reading, no meeting.

`health_report.sh` shows the last entry at session start. If a diff shows
lines removed from `PROGRESS.md`, that is an error to fix before committing:
the log can only get longer.
