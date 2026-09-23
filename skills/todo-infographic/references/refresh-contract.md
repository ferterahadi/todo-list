# Infographic refresh contract

Read this reference for semantic refresh, legacy migration, and full builds. The
markers below separate stable visual structure from values that can be updated
without regenerating the page.

## Helper

Resolve the helper relative to this skill directory. `--html` defaults to
`<project-dir>/artifacts/infographic.html`:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py inspect \
  <project-dir> [--html <infographic.html>] --date <YYYY-MM-DD> \
  --status <registry-status> --output <temporary-manifest.json>
```

Run `inspect` without a footprint. Pass `--footprint-json <temporary-footprint.json>`
only for a full build or when the user explicitly asks to refresh the footprint; a
changed footprint routes to `full-build`. Without one, the recorded footprint hash
is carried forward. The helper hashes the file; never paste the full footprint into
a subagent prompt.

`inspect` returns one mode:

| Mode | Meaning | Action |
|---|---|---|
| `stub` | `plan.md` still has the template Goal sentence, an empty or missing Goal, or template Scope bullets | Report the stub; write nothing |
| `fresh` | Sources and derived values match | Do nothing |
| `fast-refresh` | Only checkbox state, status, date, another derived value, or an unrendered plan section (Relationships, References, Repo, Verification) changed | Run `apply`; no model or design skill |
| `semantic-refresh` | Rendered prose may be stale, but the marked structure still fits | Write a small inline patch, then run `apply` |
| `legacy-migration` | Existing HTML has no embedded refresh state, but its bindings can be inserted safely | Run `migrate`, optionally with one bounded exact patch |
| `full-build` | HTML is missing, legacy migration is ambiguous, or phase/decision/footprint structure changed | Run the full design path |

## Tasks and phases

Counts follow the hub's canonical task rule, the same one `graph-report.py` uses. A
task is a `- [ ]`, `- [x]`, or `- [X]` line under any level-2 section except Status,
Notes, or Context, outside HTML comments and fenced blocks. Lines before the first
level-2 heading do not count; Revisions checkboxes do.

A phase is a level-2 or level-3 heading that starts `Phase <number><optional letter>`;
the number may carry one decimal part. Its key is the lower-case number and letter:
`### Phase 6a — Split` becomes `phase-6a`, and `## Phase 4.5` becomes `phase-4.5`. A level-3 phase ends at the next level-2 or level-3 heading; a level-2
phase ends at the next level-2 heading, so a level-3 heading inside it is a
subsection. A flat list with no phase headings is valid and has phase count 0. Two
headings with the same key (for example `Phase 4` twice) are refused.

## Required HTML markers

Every new or fully rebuilt infographic must contain these leaf bindings. Keep the
existing classes and visual markup; add only the attributes.

```html
<span data-todo-value="phase-count">10</span>
<span data-todo-value="task-summary">105 done / 119</span>
<time data-todo-value="generated-date">2026-09-18</time>
```

`task-summary` may be replaced by the pair `task-done` plus `task-total` when the
design renders the two numbers separately. Optional derived bindings are `task-open`,
`project-status`, and `phase-done` (phases whose tasks are all checked). When present,
the helper updates them too.

Each phase needs one leaf count and one progress element, keyed as above:

```html
<span data-todo-phase-count="phase-6">24/31</span>
<div class="progress-fill"
     data-todo-phase-progress="phase-6"
     style="width: 77%"
     aria-valuenow="77"></div>
```

When the design also prints a percentage beside the bar, bind that leaf too so it
cannot drift from the width:

```html
<span data-todo-phase-percent="phase-6">77%</span>
```

Put `data-todo-review-id="D<n>"` on each decision card. The set must match the
current `## Key Decisions` (numbered or bulleted `**D<n>**` items); adding or
removing a decision is intentionally a full build because it changes page structure.

Mark prose that may change without layout work as a **leaf element**. Full builds
mark every one of these standard keys that the page renders:

| Key | Element |
|---|---|
| `goal` | The goal sentence, as one plain-text leaf |
| `what-why` | The `W1` what-and-why paragraph |
| `phase:<key>` | Each phase summary, such as `phase:phase-6` |
| `note` | The biggest-risk note |
| `decision:D<n>:status` | Each decision card's status line |

```html
<p data-todo-content="note">Nothing is deployed; Meta gates remain open.</p>
<p data-todo-content="phase:phase-6">Simplification is applied on staging.</p>
<span data-todo-content="decision:D20:status">Merged, not deployed.</span>
```

Other keys are project-local but must be stable. A marked element cannot contain
child tags; the helper escapes replacement text. Never put a task or phase count or
a percentage inside a content leaf: bind it instead, or it goes stale. Adding a new
card, list row, diagram node, section, or rich-text structure is a full build rather
than a prose patch.

## Fast refresh

Apply exact derived values directly, then verify:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply \
  <project-dir> --date <YYYY-MM-DD> --status <registry-status>
python3 <skill-dir>/scripts/refresh-infographic.py verify <project-dir>
```

This edits only marked values and the embedded refresh state. It refuses semantic
or structural changes.

## Semantic refresh

The orchestrator writes the patch inline from the manifest; no subagent. Use the
manifest's `changed.plan_sections`, `changed.phases`, and `bindings.content`. Do not
read the full HTML, unchanged plan sections, unchanged task phases, `artifact-design`,
`dataviz`, or a design critique.

A content patch replaces existing leaves with plain text. Every key must already
appear in `bindings.content_keys`:

```json
{
  "content": {
    "note": "Replacement plain text for the existing note leaf",
    "phase:phase-6": "Replacement plain text for the Phase 6 summary"
  }
}
```

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply \
  <project-dir> --date <YYYY-MM-DD> --status <registry-status> \
  --content-patch <temporary-patch.json>
```

When changed prose has no leaf, such as an unmarked goal on an older page, extract
the smallest block with `fragment` (see below) and write an exact patch in the
same shape as legacy migration. Apply it with `apply --exact-patch <patch.json>`,
alone or together with `--content-patch`. The bounds match migration: at most eight
replacements and 64 KiB total, each `before` occurring exactly once, no change to
CSS or the embedded refresh state, and every binding still valid afterward.
`--exact-patch` is refused outside `semantic-refresh`.

If the changed source does not affect any visible prose, use
`--confirm-no-content-change` instead. Run `verify` after any apply. If the fix needs
a new card, section, list row, rich markup, or an absent binding, escalate to
`full-build`; do not force prose into the wrong existing element.

## Legacy migration

`legacy-migration` is the one-time bridge for an existing page that predates refresh
markers. The helper reads its source positions and inserts attributes/wrappers without
serializing the document, so the stylesheet stays byte-identical. It binds only what
it can prove:

- one Phases stat whose number (or `done/total` ratio) equals the parsed phase count;
- one task-progress ratio, an optional open-task stat, and one generated date;
- one block per parsed phase, holding exactly one phase label, one count, and one
  width bar, with no per-task check marks, state-styled rows, or unbound percent or
  ratio outside its task rows;
- one card per current decision.

It refuses, and `inspect` routes to `full-build`, when the page's phase blocks cannot
be reconciled with the parsed phases, a stat caption restates progress it cannot bind,
or the page may be truncated. A page must close `</body>` and `</html>`, or omit the
optional html and body tags entirely and leave no element open.

Finish source edits first, then keep the inspection manifest. It freezes the complete
HTML, plan, tasks, optional footprint, and CSS. Because legacy HTML has no semantic
baseline, migration requires either a bounded exact patch or an explicit bounded review
that found its visible content current. The latter needs no model to read the full HTML:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py migrate \
  <project-dir> --date <YYYY-MM-DD> --status <registry-status> \
  --manifest <inspection-manifest.json> --confirm-content-current
```

If the manifest reports stale content, extract only the relevant fragment:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py fragment \
  --html <infographic.html> --needle '<stable ID or text>' \
  [--contains '<additional anchor>'] --output <fragment.json>
```

Write the exact patch inline from the changed source block plus that fragment:

```json
{
  "replacements": [
    {
      "before": "<exact fragment from fragment.json>",
      "after": "<small corrected fragment>"
    }
  ]
}
```

Apply it with `migrate --exact-patch <patch.json>`. The helper accepts at most eight
replacements and 64 KiB total, requires every `before` value to occur exactly once,
and rejects changed sources, changed CSS, unknown structure, or incomplete bindings.
Run `verify` afterward. If inspection says `legacy-migration-ambiguous`, use a full
build rather than guessing a patch.

## Full build and one-time legacy upgrade

After the design agent writes HTML with all required markers, initialize the
embedded source hashes and verify it:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply \
  <project-dir> --date <YYYY-MM-DD> --status <registry-status> --initialize \
  [--expected-style-sha256 <inspect.theme.style_sha256>] \
  [--footprint-json <temporary-footprint.json>]

python3 <skill-dir>/scripts/refresh-infographic.py verify <project-dir>
```

For an existing infographic that could not be migrated, pass the pre-build
`theme.style_sha256` emitted by `inspect`; initialization then refuses a rebuild
whose CSS changed. A missing infographic has no expected hash. After the one-time
migration or rebuild, routine refreshes use the cheap paths.

The helper records a hash of every `<style>` block and refuses later refreshes if
the theme CSS drifted. It also refuses network-loaded assets and unknown content
patch keys.
