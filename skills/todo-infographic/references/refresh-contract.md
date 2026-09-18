# Infographic refresh contract

Read this reference when inspecting, refreshing, or building an infographic. The
markers below separate stable visual structure from values that can be updated
without regenerating the page.

## Helper

Resolve the helper relative to this skill directory:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py inspect \
  <project-dir> --html <infographic.html> --date <YYYY-MM-DD> \
  --status <registry-status> --output <temporary-manifest.json>
```

Pass `--footprint-json <temporary-footprint.json>` when the orchestrator gathered a
file footprint. The helper hashes that file; never paste the full footprint into a
subagent prompt.

`inspect` returns one mode:

| Mode | Meaning | Action |
|---|---|---|
| `fresh` | Sources and derived values match | Do nothing |
| `fast-refresh` | Only checkbox state, status, date, or another derived value changed | Run `apply`; no model or design skill |
| `semantic-refresh` | Existing prose may be stale, but the marked structure still fits | Produce a small content patch, then run `apply` |
| `legacy-migration` | Existing HTML has no embedded refresh state, but its bindings can be inserted safely | Run `migrate`, optionally with one bounded exact patch |
| `full-build` | HTML is missing, legacy migration is ambiguous, or phase/decision/footprint structure changed | Run the full design path |

## Required HTML markers

Every new or fully rebuilt infographic must contain these leaf bindings. Keep the
existing classes and visual markup; add only the attributes.

```html
<span data-todo-value="phase-count">10</span>
<span data-todo-value="task-summary">105 done / 119</span>
<time data-todo-value="generated-date">2026-09-18</time>
```

`task-summary` may be replaced by the pair `task-done` plus `task-total` when the
design renders the two numbers separately. Optional derived bindings are `task-open`
and `project-status`. When present, the helper updates them too.

Each phase needs one leaf count and one progress element. The key is the lower-case
phase number from its `## Phase` heading (`Phase 6a` becomes `phase-6a`):

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
current `## Key Decisions`; adding or removing a decision is intentionally a full
build because it changes page structure.

Mark prose that may change without layout work as a **leaf element**:

```html
<p data-todo-content="note">Nothing is deployed; Meta gates remain open.</p>
<p data-todo-content="phase:phase-6">Simplification is applied on staging.</p>
<span data-todo-content="decision:D20:status">Merged, not deployed.</span>
```

Keys are project-local but must be stable. A marked element cannot contain child
tags; the helper escapes replacement text. Adding a new card, list row, diagram
node, section, or rich-text structure is a full build rather than a prose patch.

## Fast refresh

Apply exact derived values directly:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply \
  <project-dir> --html <infographic.html> --date <YYYY-MM-DD> \
  --status <registry-status> [--footprint-json <temporary-footprint.json>]
```

This edits only marked values and the embedded refresh state. It refuses semantic
or structural changes.

## Semantic refresh

Give the build agent only the manifest emitted by `inspect`. Do not give it the
full HTML, unchanged plan sections, unchanged task phases, `artifact-design`,
`dataviz`, or a design critique. Ask it to return only:

```json
{
  "content": {
    "note": "Replacement plain text for the existing note leaf",
    "phase:phase-6": "Replacement plain text for the Phase 6 summary"
  }
}
```

Every key must already appear in `bindings.content_keys`. Apply the patch:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply \
  <project-dir> --html <infographic.html> --date <YYYY-MM-DD> \
  --status <registry-status> --content-patch <temporary-patch.json>
```

If the changed source does not affect any visible prose, use
`--confirm-no-content-change` instead. If the agent needs a key that is absent or
needs markup rather than plain text, escalate to `full-build`; do not force prose
into the wrong existing element.

## Legacy migration

`legacy-migration` is the one-time bridge for an existing page that predates refresh
markers. The helper reads its source positions and inserts attributes/wrappers without
serializing the document, so the stylesheet stays byte-identical.

Finish source edits first, then keep the inspection manifest. It freezes the complete
HTML, plan, tasks, optional footprint, and CSS. Because legacy HTML has no semantic
baseline, migration requires either a bounded exact patch or an explicit bounded review
that found its visible content current. The latter needs no model to read the full HTML:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py migrate \
  <project-dir> --html <infographic.html> --date <YYYY-MM-DD> \
  --status <registry-status> --manifest <inspection-manifest.json> \
  --confirm-content-current \
  [--footprint-json <temporary-footprint.json>]
```

If the manifest reports stale content, extract only the relevant fragment:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py fragment \
  --html <infographic.html> --needle '<stable ID or text>' \
  [--contains '<additional anchor>'] --output <fragment.json>
```

Give the content agent only the changed source block plus that fragment. It returns:

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
  <project-dir> --html <infographic.html> --date <YYYY-MM-DD> \
  --status <registry-status> --initialize \
  [--expected-style-sha256 <inspect.theme.style_sha256>] \
  [--footprint-json <temporary-footprint.json>]

python3 <skill-dir>/scripts/refresh-infographic.py verify \
  <project-dir> --html <infographic.html>
```

For an existing infographic that could not be migrated, pass the pre-build
`theme.style_sha256` emitted by
`inspect`; initialization then refuses a rebuild whose CSS changed. A missing
infographic has no expected hash. An existing unmarked infographic requires one
deterministic migration or, when ambiguous, one content-preserving rebuild to add the
contract. After that migration, routine refreshes use the cheap paths.

The helper records a hash of every `<style>` block and refuses later refreshes if
the theme CSS drifted. It also refuses network-loaded assets and unknown content
patch keys.
