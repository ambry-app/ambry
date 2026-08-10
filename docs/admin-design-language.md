# The admin design language

The rules every admin surface follows. They exist because the admin grew one
widget at a time and read like it: five kinds of pill in one card, three left
edges on one form, labels quieter than the chips they named, and a thousand
1px lines on pure black that went mushy on a 4K monitor. Each rule below
kills one class of that. When a new surface is built or an old one is
touched, it follows this document; when a rule has to bend, this document
gets amended, not silently ignored.

The public-facing app shares the brand tokens but not the composition rules —
it's a reading surface, not an operating one.

## 0. One theme

**The whole app is dark-only, by decision** (2026-08-09): one theme, half
the styling overhead. Every color class is an **absolute value** — there are
no `dark:` variants anywhere and no theme machinery; both root layouts carry
`color-scheme: dark` so native controls follow. Don't write `dark:` prefixes:
Tailwind's dark mode is set to the class strategy with no `.dark` element in
the tree, so any `dark:` class that sneaks in is a visible no-op instead of
an OS-dependent surprise.

## 1. Elevation, not borders

Pure black under hairlines is what made the old admin harsh and "mushy" at
high DPI — horizontal and vertical 1px lines don't even render the same
weight. So the admin separates surfaces by **background contrast and
spacing**, and (almost) never by border:

| Level | Color | What sits on it |
|---|---|---|
| Ground | `zinc-950` (body) | page titles, section headings, helper prose |
| Block | `zinc-900`, `rounded-lg p-4` | one decision, one queue item, one card |
| Well | `zinc-800` (or `/60`) | inputs, evidence rows, chips, nested panes |
| Hover | one step lighter (`white/5`, `zinc-700`) | interactive wells |

Rules that fall out of this:

- **No 1px container borders.** A box is a fill. If an edge must be drawn,
  it is ≥2px: a `ring-2 ring-inset` for selection, a `border-l-4` rail for
  state, a `border-l-2` indent guide. Dashed 1px borders are allowed only on
  ghost escape hatches, where looking faint is the point.
- **Section headings carry no underline.** `text-xl font-bold text-zinc-100`
  plus the 56px section gap is the divider.
- **Inputs are filled, not outlined**: `bg-zinc-800`, transparent border,
  soft brand focus ring (`focus:ring-brand-dark/20`).
- **Shadows are for layers that float** (sticky bars, menus), not for cards.

## 2. State rails — where the decisions are

Every **decision block** (a `decision_row`, a series row, the work/recording
identity clusters, the library-root chooser, an inbox queue item) wears a
`border-l-4` rail that says its state at a scroll:

| Rail | Meaning |
|---|---|
| `border-amber-400/70` | waiting on the operator |
| `border-brand-dark/60` | settled / ready |
| `border-red-400/70` | blocked (nothing proposed it, files changed) |
| none / `border-zinc-700` | informational, or out of the queue |

Evidence blocks (record lists) get no rail — they inform decisions, they
aren't one. The rail is the *only* thing that encodes settledness at block
level; don't also dim, collapse, or re-order.

## 3. Geometry

**Two left edges, never three.** Every container has exactly two
x-positions: the **box edge** (cards, inputs, record rows, buttons) and the
**text rail** — box edge + 12px (`pl-3`), matching the text inset inside the
inputs — where every bare-text element sits (labels, hints, helper prose,
microlabels, eyebrows).

**Text lands on the rail exactly, wherever it lives.** A control's own text
counts: a borderless pill pads `px-3`; a 1px-bordered box pads `px-[11px]`
so border + padding = 12 (the inputs' trick, worth a transparent border in
the borderless state so toggling doesn't shift the box); a card's leading
checkbox sits on the rail itself. Two pixels shy of the rail reads worse
than either edge — near-misses are what "feels off" is made of.

**Images are content, not containers.** A bare image (a cover preview, a
person photo, its empty-state placeholder) sits on the text rail like the
words around it. The box edge exists so a *container's* padding can land
its inner text on the rail — an image has no inner text to land. An image
inside a chip or well follows that container's rules.

**Disclosure markers hang in the gutter.** A fold's summary text sits on
the rail with its chevron in the 12px gutter to the left — the
hanging-indicator pattern, always via `<.disclosure>`. Browser-default
summary markers are never used bare: Firefox draws them `inside`, pushing
the text off the rail; other engines pick their own widths.

**One label column for annotated rows.** Any run of "label: value" rows
(match lines, `Proposed`/`Asked` rows, the source line) shares a fixed label
column via grid (`grid-cols-[<w>_minmax(0,1fr)]`), sized once per surface;
wrapped content stays in the value column.

**A proposal-chip row is one line or a list, never a partial wrap.** A row
that breaks just its last chip reads as an accident; either every chip
shares the line or every chip gets its own. No flow mechanism expresses
"stack only if they don't all fit", so the `fit-or-stack` hook measures the
chips' natural widths and commits the row to one of the two modes.

**The other axis: mixed text sizes on one line align by baseline, never by
box centre.** A label row (label + badge + provenance), a microlabel grid
(`Asked`, `Proposed`), the footer's buttons-plus-count: `items-baseline`
(flex and grid both support it), never a `pt-*` nudge — near-misses read
as badly on this axis as off the rail. What stays center- or top-aligned
instead: rows of boxes (adjacent controls share exact height, §7),
icon-only actions, image rows (a baseline puts the label on the first
image's bottom edge), and any row whose first line truncates —
`overflow: hidden` exports a synthesized baseline (the box bottom), worse
than the centre it replaces.

**Rhythm is 8 · 28 · 56** (`gap-2` / `gap-7` / `gap-14`): inside a field
cluster / between blocks / between sections. Queue cards stack with
`space-y-3`.

**Corners share baselines.** A card's right rail aligns its first element
with the title line and its last with the content's last line
(`self-stretch` + `justify-between`).

## 4. Type

| Role | Spec |
|---|---|
| Page title | `text-2xl font-bold text-zinc-100` |
| Section heading | `text-xl font-bold text-zinc-100`, no rule |
| Field label | `text-sm font-semibold` (zinc-200), on the text rail |
| Body / control text | `text-sm text-zinc-300` |
| Hint / helper / meta | `text-xs`/`text-sm` `text-zinc-400` (`zinc-500` for the faintest) — **never italic** |
| Microlabel (`Proposed`, `Asked`) | `<.microlabel>`: 11px medium uppercase tracking-wider muted |
| Paths, queries, identifiers | `font-mono text-xs`, muted; a repeated common prefix is printed once |

Italics are reserved for actual titles of works. Emphasis is weight, not
slant. Digits that stack use `tabular-nums`. Body text is `zinc-300` on
`zinc-950` — pure white on pure black is glare, not contrast.

## 5. Color

Semantic only — color states a fact, never decorates. Lime = chosen /
settled / primary. Amber = needs attention. Red = blocker, with an icon,
normal weight. Blue = location/info. Everything else zinc.

Fills for meaning are **soft tints with colored text** (`bg-amber-400/15
text-amber-300`), never solid bright chips. The one solid lime is the
primary button and the chosen chip's source tag.

## 6. Pills and buttons — one costume per job

| Job | Anatomy |
|---|---|
| Primary action | solid `bg-brand-dark text-zinc-900` (the loudest thing on the page) |
| Secondary button | filled `bg-zinc-800 text-zinc-200 hover:bg-zinc-700`, borderless |
| Quiet row action | filled `bg-white/5 text-zinc-300 hover:bg-white/10`, worded, uniform width per rail |
| Danger | `bg-red-400/10 text-red-300`, or red text revealed on hover |
| Status badge | `<.badge>`: soft tint + colored text, borderless |
| Count chip | `bg-white/10 text-zinc-300 tabular-nums` |
| Option chip — *chosen* | `bg-brand-dark/15` + `ring-2 ring-inset ring-brand-dark/50` + ✓ + filled lime source tag |
| Option chip — *unchosen* | `bg-zinc-800 hover:bg-zinc-700`; source tag bare muted uppercase |
| Option chip — *escape hatch* (`None`) | dashed `border-zinc-600 text-zinc-400`, transparent |
| Evidence row — *ticked* | well: `bg-brand-dark/10` + `ring-2 ring-inset ring-brand-dark/50` + lime checkbox |
| Evidence row — *unticked* | `bg-zinc-800/60 hover:bg-zinc-800` |

If two pills on one surface do the same job, they wear the same costume, the
same height, and start on the same rail.

## 7. Controls

- **Adjacent bar controls share exact height** — no exceptions.
- **Inputs are sized to their content**: dates `max-w-48`, format selects
  `max-w-56`, names/publishers `max-w-md`, titles `max-w-xl`, URLs and
  descriptions full width.
- Checkbox checked state is lime (`text-lime-600`), never the browser blue.
- Buttons never wrap their label; when a bar runs out of room the bar wraps
  as a whole.
- Below `sm`, right rails fold into the card as a full-width bottom line;
  below `lg`, the nav is a drawer with a scrim. Truncation drops meta before
  content, and the candidate title is always the last thing to give.

## 8. Voice

Labels name what the operator decides, not what the system stores. Hints
teach in one sentence, lowercase-calm, no exclamation. Alerts say what's
wrong and what to do, with an icon carrying the severity so the words don't
have to.
