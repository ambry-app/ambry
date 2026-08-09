# The admin design language

The rules every admin surface follows. They exist because the admin grew one
widget at a time and read like it: five kinds of pill in one card, three left
edges on one form, labels quieter than the chips they named. Each rule below
kills one class of that. When a new surface is built or an old one is
touched, it follows this document; when a rule has to bend, this document
gets amended, not silently ignored.

The public-facing app shares the tokens (brand color, button identity) but
not the composition rules — it's a reading surface, not an operating one.

## 1. Geometry

**Two left edges, never three.** Every container (page column, card) has
exactly two x-positions:

- **The box edge** — where cards, inputs, record rows, buttons, and section
  rules sit. This is the container's padding edge.
- **The text rail** — box edge + 12px (`pl-3`), matching the inset of text
  *inside* the inputs. Every bare-text element sits here: labels, hints,
  helper prose, microlabels, option rows, eyebrows.

The result: box edges align with box edges, text aligns with text (including
the text inside inputs), and nothing zigzags. Section headings are the one
exception — they own a full-width border and sit on the box edge.

**One label column for annotated rows.** Any run of "label: value" rows —
match lines on an inbox card, `Proposed`/`Asked` rows on the form, the
source/path line — shares a fixed label column via grid
(`grid-cols-[<w>_minmax(0,1fr)]`), sized once per surface, with the value
cell owning its own wrapping. Wrapped content stays in the value column;
it never falls back under the label. Colored elements (badges, chips) in
these rows therefore all start on the same rail.

**Rhythm is 8 · 28 · 56** (`gap-2` / `gap-7` / `gap-14`): inside a field
cluster / between fields / between sections. Inside a card, lines group into
blocks — identity, detail, alert — separated by 8px (`mt-2`), never one flat
pitch. A gap states a relationship; equal gaps say "siblings".

**Corners share baselines.** When a card has a right rail, the rail's first
element aligns with the title line and its last element with the content's
last line (`self-stretch` + `justify-between`). A rail element that aligns
with nothing reads as floating.

## 2. Type

| Role | Spec |
|---|---|
| Page title | `text-2xl font-bold` |
| Section heading | `text-xl font-bold` + `border-b`, on the box edge |
| Field label | `text-sm font-semibold`, on the text rail |
| Body / control text | `text-sm` |
| Hint / helper / meta | `text-xs` or `text-sm`, `text-zinc-500 dark:text-zinc-400` — **never italic** |
| Microlabel (`Proposed`, `Asked`, eyebrows) | `text-[11px] font-medium uppercase tracking-wider text-zinc-500 dark:text-zinc-400` — use `<.microlabel>` |
| Paths, queries, identifiers | `font-mono text-xs`, muted |

Italics are reserved for actual titles of works. Emphasis in helper prose is
weight or color, not slant. Digits that stack use `tabular-nums`.

## 3. Color

Semantic only — color states a fact, never decorates:

| Meaning | Light | Dark |
|---|---|---|
| Selected / primary / success | lime (`brand` #84cc16, text `lime-700`) | lime (`brand-dark` #a3e635, text `lime-400`) |
| Needs attention / pending / disagreement | amber | amber |
| Blocker / destructive | red — with an icon, **normal weight**; red text never shouts in bold sentences | red |
| Location / info | blue | blue |
| Everything else | zinc | zinc |

Muted text floor: `zinc-500` on light, `zinc-400` on dark. `zinc-600` on a
dark ground fails; don't use it.

## 4. Pills — one costume per job

| Job | Anatomy | Weight |
|---|---|---|
| **Status badge** (`pending`, `near-certain`) | `.badge`: soft fill + border, one height | quiet |
| **Count chip** (`27 files`, `Hardcover: 3`) | filled `zinc-100/zinc-800`, `tabular-nums`, never bordered | quiet |
| **Option chip** (proposed values) — *chosen* | lime border + `brand/10` tint + ✓ + **filled** lime source tag | the loudest pill on the page |
| **Option chip** — *unchosen* | plain `zinc-300/zinc-700` border; source tag is bare uppercase muted text, **no fill** | quiet |
| **Option chip** — *escape hatch* (`None`) | dashed border, muted text (`ghost`) | quietest |
| **Action mini-button** (row actions) | outlined, worded, icon + label, **uniform width per rail** (`w-28`) | quiet until hover |

If two pills on one surface do the same job, they wear the same costume, the
same height, and start on the same rail.

## 5. Controls

- **Adjacent bar controls share exact height.** A button next to a
  segmented control next to a search input in one toolbar: all the same
  height (the `<.button>` height, 42px). No exceptions — a 4px mismatch
  reads as a bug.
- **Inputs are sized to their content**: dates `max-w-48`, format selects
  `max-w-56`, names/publishers `max-w-md`, titles `max-w-xl`, URLs and
  descriptions full width. A date in a 900px box is not "roomy", it's
  unanchored.
- Buttons never wrap their label; when a bar runs out of room the bar
  wraps as a whole.
- Below `sm`, right rails fold into the card as a full-width bottom line;
  below `lg`, the nav is a drawer with a scrim. Truncation drops meta
  before content, and the candidate title is always the last thing to give.

## 6. Voice

Labels name what the operator decides, not what the system stores. Hints
teach in one sentence, lowercase-calm, no exclamation. Alerts say what's
wrong and what to do, with an icon carrying the severity so the words don't
have to.
