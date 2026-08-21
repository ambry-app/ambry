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
  ghost escape hatches, where looking faint is the point. The header's
  scroll-spy seam is the other exception, and it is not a container edge —
  see §3.
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

| Rail | Meaning | Condition |
|---|---|---|
| `border-red-400/70` | blocked — nothing proposed a value, or the files changed | not settled, and nothing to choose from |
| `border-amber-400/70` | the machine couldn't settle it; look here | not settled |
| `border-blue-400/70` | the machine settled it and nobody has looked | settled, not curated |
| `border-brand-dark/60` | you've been here | curated |

**Four tiers, not two, and the fourth is the point** (operator, 2026-08-13).
Lime-versus-amber answered "is this settled" and threw away the more useful
question, which is *did a human ever look at this*. A freshly matched import
is now entirely blue, and greens accumulate as the operator works through it,
so the form is a map of where they have been. Amber and red are what still
need them; **blue is a legitimate end state** — the machine was confident and
you don't have to look if you don't want to. The goal of an import is no
amber and no red, never "all green", or every import becomes a chore of
clicking chips that were already right.

**Green is one-way.** It records that a human looked, which is a fact about
history and cannot be un-done; a control that turned it back to blue would
assert something false. What must always exist instead is a way back to the
machine's *value* — reverting a field leaves it green, because you looked and
decided the machine was right, which is exactly the distinction the tier
buys. Green is set by changing a decision, never by merely touching the UI:
unfolding something, scrolling, or opening a form marks nothing.

**A card whose children disagree reads worst-first**: red if any child is
red, else amber if any is amber, else green only if *every* child is green,
else blue. That keeps a scroll honest — you look for amber, then decide
whether you care about blue — and it is what makes an item's progress from
all-blue to all-green mean anything.

Evidence blocks (record lists) get no rail — they inform decisions, they
aren't one. The records *cards* on the import form are decision blocks, not
bare evidence (each carries the level's identity state), and they wear the
same four tiers as everything else. One card must never rail a state another
card shows in a different colour. The rail is the *only* thing that encodes
settledness at block level; don't also dim, collapse, or re-order.

**One vocabulary, and the rail is it.** The form used to carry two
settledness systems with different words for the same states — per-decision
("settled", "needs confirming") and per-level ("confirmed", "trusted",
"unsure") — plus a Confirm button that, in every state where it was visible,
changed nothing but its own badge. Identity and field decisions are the same
shape (options, a choice, settled, touched-by-a-human), so they wear one
encoding. **Importing is the confirmation**: pressing Add accepts every blue
on the item, which is what the button was groping for.

**Evidence before the decisions it feeds — within a section too.** §9 puts
the evidence panel above the edit forms; the import form's sections follow
the same order internally: the records card first, then the identity and
field decisions below it (the work section asked "already have it?" above
the records for a while, which had the operator deciding before seeing).

## 2b. A finished row shows the result, not the process

A queue row is about the work it is asking for, so while the item is open it
wears the workflow: what matched, how sure the machine was, which files it
came from, what is still outstanding. **The moment the workflow ends, all of
that becomes history and the row becomes the thing it produced.** An imported
inbox row is the audiobook — cover, title, series, credits, the library's own
state badges — in the same shape the audiobooks list draws, because it is the
same thing; the release folder and the match tiers are on the item's form,
one worded action away.

Two things follow. **A settled row is dated by the moment it settled**, not
by the moment it was found: "Found" is the least interesting date a finished
row has. And **the status badge goes**, because the row's shape and its date
already say it — this is §2's "one badge, and it says what varies" arriving
at its end state, where what varies is the *result's* state (missing files, a
recording still processing) rather than the item's.

The row must still be able to state that its result is gone: a record that
outlives the thing it describes says so plainly rather than falling back to
the process view, which would describe a decision whose outcome no longer
exists.

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
(match lines, `Proposed`/`Results` rows, the source line) shares a fixed label
column via grid (`grid-cols-[4rem_minmax(0,1fr)]`), sized once per surface;
wrapped content stays in the value column. The width is the *widest label in
the family* and nothing more — `Proposed` at 11px uppercase is a shade under
4rem, and the column was 4.5rem for a while, which left the short ones
(`Results`, `Photos`) sitting in a lake of air. The alignment is the point,
so the answer is to size the column honestly, never to give each row its own
width: `max-content` in separate grids lines nothing up at all.

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

**The document is the scroller, and the chrome is sticky.** There is no app
shell: the body scrolls, the side nav is `fixed inset-y-0`, the page header is
`sticky top-0`, and the content clears the nav with `lg:pl-64`. This is not a
style preference — LiveView sets `history.scrollRestoration = "manual"` and
then saves and restores `window.scrollY` and nothing else, so an admin whose
scrolling happened inside `#main-content` could not restore a position on
back, forward, or anything else. `#main-content` survives as an id and its
`p-4`, because the hooks and the arithmetic below name it.

**A sticky bar still has to be told about its containing block.** The offset
itself is now the simple half: the viewport has no padding, so `bottom-0` puts
a bar flush with the bottom of the window. But a sticky box can't leave its
containing block, so at the end of the scroll that block's own bottom edge
holds the bar up by `#main-content`'s 16px — which is what `-mb-4` on the
page's content wrapper is for, and it is still required. (It was `-bottom-4`
plus `-mb-4` when `#main-content` was the scrollport and the offset had to
reach through that box's own padding.)

**Content passes behind the chrome, so the chrome is opaque and above it.**
The header paints `bg-zinc-950`, and there is one z-index ladder for the whole
admin, stated once on `layout_header/1`, in tens with the gaps left in on
purpose:

| z | what |
|---|---|
| 10 | the clickable layer inside a card (a row's action rail) |
| 20 | a busy scrim over a single card |
| 30 | the sticky page footers (`sticky_slab_classes/0`) |
| 35 | a typeahead's popup |
| 40 | a page-wide busy scrim |
| 50 | the page header, admin and public |
| 60 | the drawer's scrim |
| 70 | the side nav drawer |
| 80 | a modal |
| 90 | the image lightbox |
| 100 | flash toasts |

Rows matter here because `index_row` is `relative` with no z-index of its own,
so its layers are **not** scoped to the card and compete directly with the
page's chrome. That is what a bar with no z-index at all looks like: the
sticky pagination footer painted above a row's card body and *underneath* the
same row's action rail, so its controls flickered in and out of view depending
which part of the list they crossed. **Anything pinned over the page needs a
number, not a DOM position** — a tie falls back to document order, and page
content always comes after the header.

Two rules the renumbering was worth writing down. **A full-viewport overlay
goes above the nav, not beside it**: the modal sat below the sidebar for a
while, because a nav that is `fixed` is a peer of everything rather than a
column the content sits next to. And **a scrim has to cover the control it is
protecting the operator from** — the import form's page-wide scrim is 40
rather than `busy_overlay/1`'s own 20 precisely so it covers the sticky Save,
and stays under the header so the job indicator explaining the wait is still
lit.

**The header's separator is a hairline, drawn only when there is something
above it.** `border-b border-zinc-900`, toggled by the `header-scrollspy`
hook against `window.scrollY` — the same treatment as the public header, and
the one place §1's no-1px-borders rule doesn't hold: this is not a container
edge, it is the seam where scrolled content passes under the chrome, and an
elevation step can't draw a seam between two things that overlap.

**A grid or flex item that can hold a long string needs `min-w-0`.** Its
automatic minimum size is the min-content width of its contents, so one
unbroken run of characters — an exception message, a path, a provider id —
makes the whole column refuse to shrink and pushes the page sideways on a
phone. Measured on the overview's failure card: 711px of card in a 390px
viewport. **Truncating the string does not fix it**; `truncate` clamps the
element, not its contribution to the ancestor's minimum. The item has to be
allowed to be narrower than its contents, and then the text inside it
wraps (`break-words`) or truncates as it likes.

Wrap rather than truncate when the string *is* the content — an ellipsis on
a phone hides the end of the line, which for an error is the part that names
the failure. And prefer ordinary wrapping to `whitespace-pre-wrap` unless
the value really carries meaningful spacing: pre-wrap also preserves the
template's own newline and indentation around the interpolation, which
renders as a mystery indent on the first line.

**Corners share baselines.** A card's right rail aligns its first element
with the title line and its last with the content's last line
(`self-stretch` + `justify-between`).

## 3a. One row anatomy, for every list

Ten list pages grew their rows independently inside one anonymous `:row`
slot, and read like it: four rail widths, three title weights, two places to
put a state badge, and a facts column that vanished on a phone instead of
folding. `<.index_row>` is the anatomy, and each thing has exactly one home:

| Slot | What goes in it |
|---|---|
| `:cover` | a 64px image at the card's left edge; round for a face, `rounded-sm` for a cover |
| `:headline` | the title, `font-semibold`, and always the link |
| default | the credit stack and meta lines under the headline |
| `:badges` | state, top of the rail, on the headline's baseline |
| `:facts` | counts and boolean glyphs, nothing that reads as a sentence |
| `:action` | one entry per verb, worded, right-aligned |
| `:footer` | **system timestamps only**, at the card's bottom baseline |
| `:overlay` | a scrim that owns the whole card (`busy_overlay/1`) |

**The footer corner is a record of what the app did, and nothing else** —
Added, Imported, Joined, Found, Last seen. A duration and a publication date
are facts about the *work*; putting them in the column that says "Added
8/17/26" made three lines of date read as three timestamps.

**And what they are instead is a sentence, not a cell.** `record_meta/1` is
the last line of the content column, under the credits. They passed through
the facts strip on the way out of the footer, as `8/30/22` and `14:04:02`,
which is the shape a spreadsheet wants rather than a reader — and the full
words cost nothing, because that line is a line either way. **The rule that
falls out: `:facts` holds what you count and glance at, the meta line holds
what you read.** One helper for both flat views, so the audiobooks list and
the queue's imported rows cannot phrase it differently again.

**Three fixed lines, then one variable one.** Title, authors and narrators
are what every record has, so a row is always those three; the series, the
publisher, the publication date and the duration are each only sometimes
there, so they share the fourth and it collapses to nothing when a record has
none of them:

> **The Way of Kings**
> Brandon Sanderson
> Read by Michael Kramer, Kate Reading
> The Stormlight Archive #1 · Published August 30, 2022 by Recorded Books · 32 hours and 43 minutes

**This moves the series out of the credit stack, and it is the one place that
diverges from §8.** The argument is density and not convenience: a series
that owns a line of its own makes every audiobook row taller to state a fact
most rows say in four words, and on a row a series reads as a locator
alongside the publisher rather than as a credit alongside the people. The
detail pages and the mobile app keep §8's stack intact — the divergence is
this surface's, and it stops here.

**The rail is `w-56` (224px), which is two buttons wide, and actions wrap.**
Four buttons stacked one per line is tall and ragged; two rows of two is
neither, and wrapping was never the problem — the 176px rail was. 224px is
measured, not guessed: the tightest real pair is Playthroughs (120px) beside
Devices (86px), 211px with the gap, and every other pair on every list is
under 183px. Three never fit, which is what makes the queue's four verbs a
clean 2 × 2.

The constraint that falls out lands on the **labels**, so keep them inside
the budget the rail was sized for — twelve characters, "Playthroughs" being
the longest — and don't put two long ones side by side. The inbox's second
action is "Origin" rather than "Import record" for exactly this reason.

(`fit-or-stack` is **not** the tool here. It is for metadata chip rows, where
the number of chips genuinely varies per record; a rail's verbs are fixed by
the surface, so its width can just be right.)

**A verb that isn't available yet is disabled, not absent.** The queue's
Import used to appear only once a row was settled, so the rail's shape and
the order of its buttons changed from row to row and the primary action moved
under the cursor as the operator worked down the list. A disabled button in
its own place says "not yet" without rearranging everything around it — and
it has to say *why* in its `title`, or it is only a dead button. Note that
`disabled:` variants are a `:disabled` pseudo-class and a `<span>` can never
match one, so `row_action` spells the state out and drops the binding.

**The whole card is the link, and it is a real one.** The headline is an
`<a>` whose `::after` covers the card. The two older idioms each had half of
this: the library lists made the whole row clickable with `JS.navigate` on
the div — a big target, but not a link, so no focus, no middle click, no
open-in-new-tab — and the queue linked only its title, a real link with a
200px target. It also fixes a defect neither could see: LiveView dispatches a
click to the *closest* `phx-click` ancestor, so an `<a>` nested inside a
`JS.navigate` row fired both, which on the users list meant clicking Devices
also navigated to Playthroughs. Everything clickable therefore sits in a
`z-10` layer above the pseudo-element; an overlay is `z-20` above both.

**A row that goes nowhere is not a link and wears no pointer.** The old
container hardcoded `cursor-pointer` on every row whether or not it had a
destination, so the queue and the devices list invited clicks on dead space.

**The rail needs `self-stretch` or its `justify-between` is decoration.**
The card is `items-center`, so an unstretched rail is content-height and the
dates sit jammed under the actions instead of on the card's bottom baseline —
which is what every pre-redesign list did while writing the rule's classes.

**64px is the row's height floor.** People rows were 48px, so they were
visibly shorter than every other list's on the same page of the same app.

**Paging is the list's own sticky footer.** The header holds what *narrows* a
list (search, sort, and the one button that adds to it); `pagination_footer/1`
holds what *moves through* it. Two bare chevrons in the top right corner was
the old arrangement, and it was wrong three ways: the control for moving
through a list sat as far from the rows as the page allows, it never said
which page you were on or how many there were, and because the header doesn't
move, clicking "next" left the scroll where it was so the operator arrived
looking at the bottom of the page they had just asked for.

**Sticky, not merely in the flow** — this is the correction worth recording,
because putting the bar at the foot of the rows and stopping there only trades
one kind of "far away" for another. A page is 50 rows, two or three screens,
so reaching page 3 from the top of a list would mean scrolling to the bottom
to find a control that used to be one click away. It wears `form_footer/1`'s
costume, from `sticky_slab_classes/0`, because it is the same object doing the
same job: the thing the page is *for*, at the end of the thing, reachable
without hunting. Both bars settle into place at the end of the scroll, and the
`sticky-footer` hook undresses them into ordinary cards when the page has
nothing to scroll.

The footer states the range and the total ("Showing 51 to 100 of 435", "Page 2
of 9"), its steps are worded like every other action (§3a), an unavailable
step is dead rather than absent so the bar keeps its shape at both ends, and
`list-scroll-reset` takes the page back to the top whenever the page, the sort
or the search changes.

**A page is 50 rows.** It was 10 for years, which made a 435-audiobook
library 44 pages deep with no way to tell which one you were on.

**A form goes back where it came from, to the record it just saved.** Every
form used to end with `push_navigate(to: ~p"/admin/books")` — the front of an
unfiltered, default-sorted page one, whoever you were and wherever you had
been. `AmbryWeb.Admin.ReturnTo` is the two halves of the fix: a list writes
its state into every row link, and the form reads it back and returns there,
naming the record so the list can scroll to it and flash it (`focus-row`).
It anchors to the **record**, not to a scroll offset, because those are
different answers the moment an edit changes the sort key — rename a book on
a title-sorted list and its row moves, so the pixel the operator left from
belongs to somebody else now. A row that is gone or off-page focuses nothing
and they land at the top, which is the honest result. The "New" button
deliberately carries no list state: a record that doesn't exist yet cannot be
on the page you were filtering.

**Counted where the rows are queried, from the same filters.** A total
assembled anywhere else eventually describes a different query from the rows
above it. The flat views make this cheap when nothing is filtering: their
credit arrays are correlated subqueries in the target list and the planner
drops every one of them for a bare count.

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

**The documented exception: a derived list has no add.** The import form's
**People** section lists one card per human the import introduces, and
the operator cannot add one there — a person exists because a *credit* names
them (`Draft.referenced_keys/1` mints the decisions from the credits), so
adding a person happens on the credit and appears here. The label and the
rows are the ordinary grammar; the add below the container is absent, and
that absence is the honest statement that this list is derived rather than
built. The people behind a *linked credit* are not listed: they were chosen
in the credit's typeahead, they carry their own curation which an import may
never overwrite, and the one dangerous case — a name matching two existing
identities — is a decision on the credit, where `Credit.state/1` computes it.
A person the operator matched to the library *from their own card* does stay,
because that decision was made here: dropping the card the moment the link is
made takes the way back with it.

**The other documented exception: an upload sits inside its block.** A
dropzone is not an add-button. `<.file_input>` is a control the block owns —
the same way the media form's cover and the person form's photo own theirs —
so it renders inside the card rather than under it, and supplemental files
follow the cover rather than the series rows. The rule the `:add` slot
encodes is about the *button that appends a row*, and reading a dropzone as
one put the only file input in the admin outside the thing it belonged to.

**A card asks nothing it can state.** The person card carries no name box in
the ordinary import, because the credit names the human and a box on every
card in every state is what left "This is a pen name" with no visible effect
to have. Reveal the exception, state the rule: the box appears when the name
is genuinely the person's own, and a control that reveals it always offers
the way back. The other question a card like this answers — is this somebody
the library already has — is *evidence*, and wears the local-row costume the
work level uses ("Yes, it's them"), not a permanent search box.

**Pen names are bracketed, not nested.** One author credit can stand for
several humans, so those person cards sit adjacent under a shared labelled
rail. The label states what the cards can't — "2 people behind this name" —
because each card is already titled by the credit it belongs to. A bracket is a label and a rail, never a filled block —
wrapping cards in a card is what eats the elevation ladder, and this is the
same device the person rows used when they were nested inside a credit,
promoted to group siblings instead.

**Every form saves from the same place: the sticky footer slab**
(`<.form_footer>` — shadowed `zinc-900`, `-bottom-4`, with `-mb-4` on the
page wrapper per §3's sticky rule). A bare Save floating on the ground
after the last card was the legacy forms' tell, at its worst on the
47-row chapters form.

**The footer is also where outstanding work is listed**, not merely counted.
It is the one thing always in view, and `Draft.unresolved/1` already returns
a section and a label for every decision still waiting — so it names them and
links to them. Without that, a form long enough to have sections has work
below the fold that nothing announces, which is the objection that decided
where the People section goes.

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
| Quiet row action | `<.row_action>`: the `:sm` button costume, always worded, content-sized, right-aligned |
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

**Row actions are worded, everywhere.** This used to have an exception for
"an index row carrying five verbs (media: chapters, edit, replace, search,
delete)", and the exception outlived its case: those five verbs moved onto
the media form during the redesign, leaving that row with two, while the
inbox carried four and wore words for them. A rule kept alive only by the
thing it excepted no longer existing is a rule to delete. `<.row_action>` is
the one costume — a link when it goes somewhere, a `role="button"` span when
it fires an event — and the trash can survives only where §6's danger rule
puts it, on a row that is not itself a link (the file audit's deletes).

**Actions are content-sized and right-aligned, not one fixed width per
rail.** The fixed width was written when the queue was the only surface with
a rail and stacked four identical buttons down it. One shared rail across
every list would force the widest label anywhere onto every "Edit". Right
alignment is what makes the edge read as a column; the fixed width never was.
How a rail lays out is decided by its verb count (§3a), never by measurement.

**Every destructive confirm names what dies and what survives.** "Are you
sure?" was on five index rows, including the one that deletes an audiobook's
audio files off the disk.

## 6b. Toasts and ambient chrome

**A flash is a toast: top centre, quiet, and gone on its own.** They used to
be solid lime and red slabs pinned top *right*, which is where the admin
keeps the user menu and the job indicator, and they stayed until clicked —
so a "saved" notice covered the two controls most likely to be wanted next
and then waited to be dismissed.

- The rail is `fixed top-4 left-1/2 -translate-x-1/2` and
  `pointer-events-none`, so an empty one is not an invisible lid over the
  top of the page; each toast turns pointer events back on for itself.
- The box is the ordinary floating-layer fill (`zinc-900` + shadow, §1),
  **not a coloured slab**. Only the glyph is coloured, per §8's rule that
  the icon carries the severity so the words don't have to.
- No severity heading. "Success!" above "Saved." says nothing the icon
  doesn't and makes a one-line toast two lines.
- It dismisses itself — 5s for info, 10s for an error, held open while
  hovered, because a message that vanishes mid-sentence is the complaint
  that replaces "they never go away". Dismissing must clear the flash
  *server-side*, not just hide it, or it returns on the next navigation.
- **A toast that is a state rather than an event never times out.** The
  connection notices are the live state of the socket; timing one out would
  claim the connection came back.
- **Never put a display utility on an element hidden by the `hidden`
  attribute.** `[hidden] { display: none }` comes from the UA stylesheet, so
  an author-level `flex` (or `block`, or `grid`) on the same element
  outranks it. A `flex` on the flash root once made both connection notices
  visible on every navigation, for the moment between first paint and
  `phx-connected` firing — too brief to read and impossible to miss. Put the
  layout on an inner element.

**An ambient indicator renders its quiet state too.** The header's
background-work widget shows a dim dot and the word Idle when nothing is
running. A widget that only appears when there is news is indistinguishable
from a broken one, and rendering the calm state is what makes the busy state
mean something. Where the state is genuinely two questions — here, "is it
busy" and "did something break" — they get two marks, because only one of
them is a reason to stop what you are doing.

**A link that leaves the app says so before it is clicked.** Oban Web and
the Phoenix dashboard open in a new tab with
`fa-arrow-up-right-from-square` beside the label — the admin is a page you
leave open while you watch something, and taking the tab costs you that.

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
size and color carrying the roles. (Index rows are the documented
exception: the series moves down to their variable line, §3a.) "Narrated by" is retired as a verb;
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
  entity chip (author, narrator, series) **stages** a row that names the
  entity, and nothing is created until Save — a chip that wrote a record
  on the spot left a person behind on every form the operator opened and
  abandoned. Evidence is session state — added, never replaced while the
  page lives, gone when it's left.
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

- **A credit that names somebody new gets that person's card — literally the
  inbox's card.** A picker may name a record the library has never heard of,
  so an edit form can invent a `Person`, and a person made of a name and
  nothing else was the asymmetry this arc was about. So the edit forms render
  `person_card/1` itself, not a redrawing of it:
  `AmbryWeb.Admin.NewPerson` builds a `PersonDecision` and its `Credit` out
  of the nested person changeset and the card's own `Evidence`. **A person is
  a person on both surfaces** — same overlay while a search runs, same photo
  strip at the size a face is seen, same bio box with its preview and chips,
  same record list.

  It lives in a **section of its own** under the credits that name them — the
  inbox's `#people` anatomy, a heading on the ground with cards below — never
  inside the credits card, which would be a card inside a card. It renders
  **only where the nested chain reaches a person nobody has made yet**, which
  is never true of a credit pointing at somebody who exists, and the credit
  rows are walked a second time (`skip_hidden`, `skip_persistent_id`) because
  the pickers above already post those.

  The card hangs off the **join row** that holds the person — `author_people`
  for a pen name, `media_narrators[i][narrator]` for a stage name — not off
  the person itself, because that row is where "which human is this" is
  answered. It is what lets the card offer the people the library already has
  by that name and link one, and what lets a pen name carry more than one
  human (James S.A. Corey) the way the inbox always could.

  One thing genuinely differs, and `input_prefix` is where it is said: the
  import form saves on change and has no form of its own, so each of the
  card's controls is a little `<form>`; an edit form is one form with a Save
  button, and forms cannot nest. Given a prefix, the three form-bearing
  controls become plain inputs posting under it, the chips write those inputs
  on the client (`assets/js/hooks/set-input.js`) instead of raising events,
  and the state rail goes — nothing here is part-way through a decision tree.
  Everything else is the same markup.

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
