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
- **Dashed means "drop here" or "not chosen" — never "here is a fact".**
  Dropzones and ghost hatches wear dashes; a read-only file list is a plain
  card (`<.file_list>`: mono, muted, the common directory printed once).
  The media form's source list used to wear the dropzone costume, which
  promised a drop it couldn't take.
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
aren't one. The records *cards* on the import form are decision blocks,
not bare evidence (each carries the level's identity/doubt state), and
both wear the rail with one reading: **amber only for an unsure match
nobody has curated; lime for everything else** — trusted is settled, and
nothing-found is settled too (there is nothing to choose between; the
seeder approves both). One card must never rail a state the other card
shows in a different color. The rail is the *only* thing that encodes
settledness at block level; don't also dim, collapse, or re-order.

**Evidence before the decisions it feeds — within a section too.** §9 puts
the evidence panel above the edit forms; the import form's sections follow
the same order internally: the records card first, then the identity and
field decisions below it (the work section asked "already have it?" above
the records for a while, which had the operator deciding before seeing).

## 3. Geometry

**Two left edges, never three.** Every container has exactly two
x-positions: the **box edge** (cards, inputs, record rows, buttons) and the
**text rail** — box edge + 12px (`pl-3`), matching the text inset inside the
inputs — where every bare-text element sits (labels, hints, helper prose,
microlabels, eyebrows).

**The rail belongs to a container, so ground level has none — with one
deliberate exception.** A block on the ground (`zinc-950`) — a section
heading, a line of helper prose — sits on the page's own edge; there is no
box whose padding it is matching, and a `pl-3` there is a *third*
x-position 12px right of every heading around it. If a fact wants the
rail, what it actually wants is a card. (An uncarded "This release is …"
line on the import form is what taught this.) The exception: **ground
helper prose sitting directly against a card or a run of cards** may wear
`pl-3` to align with the railed text inside them (the import form's "This
book isn't in these yet" line). Labels are no longer in this exception —
a card names itself (§3b), so no label lives on the ground at all.

**A card's own text sits on the rail relative to the card's padding edge.**
The single-sentence empty-state cards kept forgetting this: a bare
`<p class="… p-4">` puts its text at the padding edge, 12px left of every
sibling card's railed header. The text inside a card wears `pl-3` like
everything else.

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

**A long editable list scrolls inside its card; it does not fold.** The
chapter editor is the case: dozens of rows would swallow the form, but a
fold hides the content *and* fights the autosave patches, while
`max-h` + `overflow-y-auto` on the rows container bounds the card's height
with every input still visible and in the DOM. Folds are for content the
operator mostly doesn't need (evidence panels, file stats), not for the
thing a section exists to edit.

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

**Radius is a ladder, and it follows size**: `rounded-lg` for blocks and
floating panels, `rounded-md` for anything you click or type in (buttons,
inputs, selects, pills, chips, listboxes), `rounded-sm` for inline tint
spans and small images. It was never written down, so the newer surfaces
drifted to `md`/`lg` while buttons and inputs stayed at `sm` — a primary
button next to a chip visibly disagreed about what shape a control is.

**A date and its display precision are one composite fact, one control.**
`<.date_with_format>`: date left, precision select right, one shared well —
never two fields, and on the import form never two decision blocks whose
proposal could be *split* across sources. A chip proposes both halves
("2015 (year only)") and accepting settles both; a claimed precision on a
day-specific date normalizes to full ("October 3rd is not a year in
disguise"), and a precision the operator sets deliberately is never
overruled.

**One control height: 40px.** `py-[7px]` + `leading-6` + a 1px border, which
is what `<.input>` has always been — so buttons carry the same padding
rather than `py-2`, and the inbox's segmented filter bar (`p-1` + `py-1.5`
segments) lands on it too. §7 says adjacent bar controls share exact height;
this is the number.

**A sticky bar has to be told about the scroller's padding.** `#main-content`
scrolls with `p-4`, and a sticky offset is measured from the scrollport's
**content** box — so `bottom-0` parks a bar 16px shy of the window edge with
the page showing through underneath. A sticky box also can't leave its
containing block, so at the end of the scroll that block's own bottom edge
holds it up by the same 16px again. Both halves need saying: `-bottom-4` on
the bar, `-mb-4` on the page's content wrapper. Measured in Chrome — 16px,
then 80px at the bottom of the page, before the fix; 0 and 0 after.

**Corners share baselines.** A card's right rail aligns its first element
with the title line and its last with the content's last line
(`self-stretch` + `justify-between`).

## 3b. Forms are blocks, like everything else

An edit form is not a special case: it is a page of decisions, so it is a
page of blocks. `<.field_group>` is the unit — one `zinc-900` block per
*cluster*, being the fields that answer one question about the record ("who
wrote it", "where the files live"). Its label names the cluster and sits on
the text rail; fields that speak for themselves need no label, because the
block and the gap around it are already the grouping.

**A card names itself.** Every label — with its provenance flag, badges,
and hint — lives *inside* the card it describes, at the top, on the rail.
This was the decision cards' shape all along (`decision_row`, the credit
and series cards, "Library root"); `field_group` always did it; the list
clusters were the holdouts, naming their container from the ground — and
the import form's list sections did *both*, a ground "Authors" floating
over cards that already said "Written by". Ground level carries only
section headings (`<h2>`) and helper prose. The documented exception:
a disclosure fold names itself in its `<summary>`, which is a control.

**A list the operator is building has exactly one grammar, on every form:
label (and flag and hint) at the top of the container, rows inside it,
proposal chips after the rows, add below the container** —
`<.list_cluster>`. An **empty list states itself** instead of rendering a
bare grey slab: a railed sentence in the card ("Not in a series.",
"No narrators."), with the add still offered below. What varies between forms is only what
the container holds: one card of single-input rows on an edit form, a run
of per-decision cards on the import form (whose credits can't nest inside
a block without eating the elevation ladder). It used to be two grammars —
the legacy forms kept the label and the add *inside* their block — so the
same content type wore a different anatomy depending on the form, which
§6's "same costume for the same job" exists to prevent. Never bless a
divergence by documenting both halves as intentional; that is how this one
survived two audits.

**Every form saves from the same place: the sticky footer slab**
(`<.form_footer>` — shadowed `zinc-900`, `-bottom-4`, with `-mb-4` on the
page wrapper per §3's sticky rule). A bare Save floating on the ground
after the last card was the legacy forms' tell, at its worst on the
47-row chapters form.

**One form measure: `max-w-4xl`.** The import form always had it; the
legacy forms sat at `3xl` and the two settings-ish pages centered
themselves, three layouts for one kind of page.

`<.form_section>` wraps a run of blocks under a ground-level `<h2>` — only
for a form long enough that you need to find your way around it (the media
form has two; the book form needs none).

**Every label an `<.input>` renders is on the rail** (`pl-3`), because the
control's own text is. Before this, labels sat at the container edge and
their inputs' text 12px in — every legacy form was two left edges out of
alignment with itself, which is precisely §3's near-miss.

The image-stack thumbnails (`multi_image`) are the documented exception to
§1: overlapping images have no fill to separate them with, so they draw
their own 1px edge.

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
normal weight. Blue = location/info. Everything else zinc. A file size is
not a location and a missing description is not a blocker — when a fact
has no semantic color, it's a gray chip or a muted glyph, not a borrowed
bright one.

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

**Three tiers of action, and nothing else.** Loudness follows consequence:

| Tier | Costume | For |
|---|---|---|
| Primary | solid `bg-brand-dark` | the one thing the page is for — Save, Import, Scan |
| Action | `<.button color={:zinc}>`, opaque raised fill, `size={:sm}` inside a card | Confirm, Split, Re-match, Ignore, Search |
| Add a row | `<.add_button>`, the faintest fill that still reads as a control | adding a blank row, the least consequential thing on a form |

**An action must be visibly raised, or it is a label.** Quiet actions used
to be `bg-white/5`, which on a `zinc-900` card computes *darker* than the
`bg-white/10` count chips beside them — labels reading as raised and buttons
as recessed, so Confirm looked exactly like a tag. Actions are an opaque
fill one rung up from what they sit on; tags and counts stay flat, muted and
smaller, with no hover.

**The add follows its list — below the container, on the ground** (§3b's
one grammar). The `<.add_button>` box sits on the container edge like every
other control, and its `px-3` lands the label on the text rail; nudging
the *box* onto the rail put its text at a third x-position nothing else
shares, which read as misalignment on every form it touched.

**Removing a row is ✕; destroying a thing is a trash can.** A list row's
remove (`<.delete_button>`) is undoable until save, so it wears the import
form's ✕. The trash can is reserved for actions that destroy something
real — the file audit's deletes, an index row's delete — with red revealed
on hover (§6 danger).

**Documented exception — icon-only actions on dense index rows.** The
quiet-row-action costume is worded, but an index row carrying five verbs
(media: chapters, edit, replace, search, delete) would drown its content
in words; pencils and trash cans on index rows stay icon-only with
`title` text. Queue cards (the inbox) have room and stakes, and stay
worded.

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
have to. Headings are sentence case — "Orphaned audiobook files", never
"Orphaned Audiobook Files"; Title Case is for titles of works.

**One vocabulary** (decided 2026-08-11). The playable thing is an
**audiobook** — never "media", "recording", or "release" in anything
rendered. The abstract work is a **book**, never "work". A
`RecordingGroup` is a **set**. "Edition" survives only as a relation
("another edition of this book"). Code, schema, and module names keep
their old words; the rule is for text an operator or listener reads.
The admin routes follow the words: `/admin/audiobooks`, `/admin/sets`.

**Credits are the mobile app's stack**: title (bold), series
("Name #3"), bare author names — no "by" — then "Read by …" muted, with
size and color carrying the roles. "Narrated by" is retired as a verb;
the noun "Narrator" stays. When one line must hold it all (page titles,
match rows, option labels), the joins are words: "The Martian by Andy
Weir read by R.C. Bray". Names join with commas.

**No em or en dashes in rendered text.** Rewrite the sentence instead:
two short sentences, a semicolon, parentheses ("Name (context)"), or a
comma. The only "—" left is the empty-value placeholder in table cells.
The " · " middle dot stays, but only between metadata facts (file stats,
record-row facts), never inside a credit.

**Hints are one plain sentence** — two at most, no asides, no "not X,
but Y" rhetoric, no reassurance ("that is common and not a problem"),
no mechanism lectures, no changelog notes ("… is a later addition").
Flashes say what happened, then what to do, in at most two short
sentences. Control labels that answer a question use a comma: "Yes,
another edition of this", "No, a different book", "None of these".

## 9. Curation is the import form, everywhere

The edit forms run the import form's model on records that already exist —
one mechanism for "ask the databases", not a modal per provider:

- **The evidence panel** (`<.evidence_panel>`) sits above the form —
  evidence first, then the decisions it feeds — and starts **folded to one
  line**: an edit form is mostly visited for reasons that aren't curation,
  and instructions about records that aren't there yet are noise. One
  search fans out to every capable provider (`Ambry.Metadata.Search`);
  results are the same tickable `record_row`s and `Asked` outcome chips
  the inbox uses, **scored and ranked the way matching ranks them**
  (`Ambry.Inbox.score_records/3`, hinted by the record's own fields) so
  the study guides sink. The recording level asks twice, like the import
  form: Audible directly, plus the audio editions the work-level
  databases keep.
- **Records identify themselves**: every record row wears its cover or
  face as a small thumbnail — identification, visible *before* ticking —
  while the chips below stay the place a photo or cover is *chosen*. Tiny
  images everywhere carry a corner magnifier that opens the full-size
  image in the lightbox; disambiguating twins sometimes takes the art at
  full size.
- **Provenance closes the loop**: accepted proposals and imports record
  the provider *record* behind each field (`"record"` in the provenance
  entry). A later search that returns that record recognizes it — arrives
  pre-ticked, wearing a "filled title · published" note — so "which record
  did this come from?" has an answer years later.
- **Ticked records grow "Proposed" chip rows** under the fields they can
  fill (`<.curated_input>` / `<.proposal_row>`), in the import form's chip
  anatomy exactly. Accepting a scalar chip takes the value; accepting an
  entity chip (author, narrator, series) resolves or creates the entity
  and adds its row. Evidence is session state — added, never replaced
  while the page lives, gone when it's left.
- **Provenance is worn inline** on each field's header
  (`<.provenance_flag>`): "from hardcover" muted for the recorded source,
  "will record rreading-glasses" amber for an accepted-but-unsaved one,
  with the lock beside it — the import form's "from …" idiom pointed at
  `Ambry.Provenance`. Accepting records the provider unlocked; editing the
  value afterwards makes it a manual edit again, locked.
- **A proposal that is a *merge* previews in place, inside the thing it
  changes.** Chapters are the case (`AmbryWeb.Admin.ChapterEditor`, both
  forms): a ticked record's ASIN grows a chip, but the chip's value is
  thirty rows changing at once — so clicking it renders the fetched titles
  **into the rows themselves**, a proposed-title cell beside each title
  input, with one Take/Cancel header at the top of the card. No second
  card, no modal: the rows are the preview, and nothing lands until Take.
  The one place a chip is two clicks, argued from consequence; scalar and
  entity chips stay one. **Take exists only when the counts match** — a
  list that doesn't pair one-to-one stays visible (the proposed column
  shows where the lists diverge, which is what to fix) but is never
  poured.

Structural lists (authors, narrators, series) carry **list-level
provenance** — one entry per list, worn as the same "from …" flag on the
list cluster's label — because the import form visibly chooses credits
from sources and losing that at the library door read as something
missing. Locks still exist in the data (manual = locked, accepted =
unlocked) but have **no UI**: nothing consumes them yet, and a toggle for
a promise nothing tests was theater. The lock icon returns when a refresh
feature exists to honor it.

What stays different from the inbox is only what the context demands: no
state rails (nothing here is *waiting* — the record is real and every
field already holds a value) and no stored draft. If a new difference
wants in, it argues from the context's lifetime, not from convenience.
