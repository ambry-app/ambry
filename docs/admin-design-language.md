# The admin design language

The rules every admin surface follows. An admin built one widget at a time
reads like it: five kinds of pill in one card, three left edges on one form,
labels quieter than the chips they name, a thousand 1px lines on pure black
going mushy at high DPI. Each rule below rules out one class of that. When a
surface is built or touched, it follows this document; when a rule has to
bend, this document gets amended rather than silently ignored.

The public-facing app shares the brand tokens but not the composition rules:
it is a reading surface, not an operating one.

## What this admin is not allowed to know about you

**Ambry is self-hosted open source, and whoever is running it is not whoever
wrote it.** Nothing rendered may assume otherwise.

- **No placeholder, example or copy drawn from what one operator happens to
  be doing.** A real forthcoming title as placeholder text is accurate for a
  week and belongs to one person. A placeholder either teaches the _format_
  of the field or it is absent; a worked example that has to be concrete (the
  naming template's preview) uses a book, an author and a narrator any
  library plausibly holds.
- **No policy stated as a preference.** A feature that grades one operator's
  arrangement as right and another's as wrong is a feature that is wrong: all
  four file-placement policies are valid and mixable, so the file audit
  describes the distribution rather than scoring it.
- **No copy that reads as the author talking to themselves.** No "we", no
  asides about what is planned, no reassurance that something is normal, and
  no archaeology: this document and the code both state the rule and the
  consequence that makes it right, never the history of arriving at it.

## Comments earn their place, or they go

The code says what it does. A comment is for what the code cannot say: the
decision behind it, the measurement that settles it, the failure it exists to
prevent. A comment that narrates the line under it is noise, and a run of
them is worse than noise, because it buries the two that were load-bearing.

## 0. One theme

**The whole app is dark-only, by decision**: one theme, half the styling
overhead. Every color class is an **absolute value** — there are no `dark:`
variants anywhere and no theme machinery; both root layouts carry
`color-scheme: dark` so native controls follow. Don't write `dark:` prefixes:
Tailwind's dark mode is set to the class strategy with no `.dark` element in
the tree, so any `dark:` class that sneaks in is a visible no-op instead of
an OS-dependent surprise.

## 1. Elevation, not borders

Hairlines on pure black read as harsh and "mushy" at high DPI, where
horizontal and vertical 1px lines don't even render the same weight. So the
admin separates surfaces by **background contrast and spacing**, and (almost)
never by border:

| Level  | Color                                    | What sits on it                             |
| ------ | ---------------------------------------- | ------------------------------------------- |
| Ground | `zinc-950` (body)                        | page titles, section headings, helper prose |
| Block  | `zinc-900`, `rounded-lg p-4`             | one decision, one queue item, one card      |
| Well   | `zinc-800` (or `/60`)                    | inputs, evidence rows, chips, nested panes  |
| Hover  | one step lighter (`white/5`, `zinc-700`) | interactive wells                           |

Rules that fall out of this:

- **No 1px container borders.** A box is a fill. If an edge must be drawn,
  it is ≥2px: a `ring-2 ring-inset` for selection, a `border-l-4` rail for
  state, a `border-l-2` indent guide. Dashed 1px borders are allowed only on
  ghost escape hatches, where looking faint is the point. The header's
  scroll-spy seam is the other exception, and it is not a container edge —
  see §3.
- **Dashed means "drop here" or "not chosen" — never "here is a fact".**
  Dropzones and ghost hatches wear dashes; a read-only file list is a plain
  card (`<.file_list>`: mono, muted, the common directory printed once). A
  fact display in the dropzone costume promises a drop it cannot take.
- **Section headings carry no underline.** `text-xl font-bold text-zinc-100`
  plus the 56px section gap is the divider.
- **Inputs are filled, not outlined**: `bg-zinc-800`, transparent border,
  soft brand focus ring (`focus:ring-brand-dark/20`).
- **Shadows are for layers that float** (sticky bars, menus), not for cards.

## 2. State rails — where the decisions are

Every **decision block** (a `decision_row`, a series row, the work/recording
identity clusters, the library-root chooser, an inbox queue item) wears a
`border-l-4` rail that says its state at a scroll:

| Rail                   | Meaning                                                  | Condition                               |
| ---------------------- | -------------------------------------------------------- | --------------------------------------- |
| `border-red-400/70`    | blocked — nothing proposed a value, or the files changed | not settled, and nothing to choose from |
| `border-amber-400/70`  | the machine couldn't settle it; look here                | not settled                             |
| `border-blue-400/70`   | the machine settled it and nobody has looked             | settled, not curated                    |
| `border-brand-dark/60` | you've been here                                         | curated                                 |

**Four tiers, not two, and the fourth is the point.** Lime-versus-amber
answers "is this settled" and throws away the more useful question, which is
_did a human ever look at this_. A freshly matched import is entirely blue,
and greens accumulate as the operator works through it, so the form is a map
of where they have been. Amber and red are what still need them; **blue is a
legitimate end state**, because the machine was confident and you do not have
to look if you do not want to. The goal of an import is no amber and no red,
never "all green", or every import becomes a chore of clicking chips that
were already right.

**Green is one-way.** It records that a human looked, which is a fact about
history and cannot be un-done; a control that turned it back to blue would
assert something false. What must always exist instead is a way back to the
machine's _value_ — reverting a field leaves it green, because you looked and
decided the machine was right, which is exactly the distinction the tier
buys. Green is set by changing a decision, never by merely touching the UI:
unfolding something, scrolling, or opening a form marks nothing.

**A card whose children disagree reads worst-first**: red if any child is
red, else amber if any is amber, else green only if _every_ child is green,
else blue. That keeps a scroll honest — you look for amber, then decide
whether you care about blue — and it is what makes an item's progress from
all-blue to all-green mean anything.

Evidence blocks (record lists) get no rail — they inform decisions, they
aren't one. The records _cards_ on the import form are decision blocks, not
bare evidence (each carries the level's identity state), and they wear the
same four tiers as everything else. One card must never rail a state another
card shows in a different colour. The rail is the _only_ thing that encodes
settledness at block level; don't also dim, collapse, or re-order.

**One vocabulary, and the rail is it.** Two settledness systems with
different words for the same states (per-decision "settled" and "needs
confirming", per-level "confirmed", "trusted" and "unsure") describe one
thing twice, and a Confirm button beside them changes nothing but its own
badge. Identity and field decisions are the same shape (options, a choice,
settled, touched-by-a-human), so they wear one encoding. **Importing is the
confirmation**: pressing Add accepts every blue on the item.

**Evidence before the decisions it feeds, within a section too.** §9 puts
the evidence panel above the edit forms, and the import form's sections
follow the same order internally: the records card first, then the identity
and field decisions below it. A section that asks "already have it?" above
its records has the operator deciding before seeing.

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
at its end state, where what varies is the _result's_ state (missing files, a
recording still processing) rather than the item's.

The row must still be able to state that its result is gone: a record that
outlives the thing it describes says so plainly rather than falling back to
the process view, which would describe a decision whose outcome no longer
exists.

**And that its result is no longer its own.** A third state sits between
those two: the outcome still exists, but it belongs to a later record — an
import replaced by another import of the same audiobook. Wearing the result
there is the worst of the three, because it is not merely stale, it is
_someone else's_, and it keeps updating: the row would go on showing a cover,
credits and state badges that another record is responsible for.

So the row goes back to describing **itself** — the release it holds, its own
files, the date it landed — and carries a badge for the one thing that shape
cannot say, which is that this was imported and then superseded. This is the
documented exception to "the status badge goes": the badge is what stops an
import-shaped row from reading as work still to do.

It does not offer the result. A way to the record that _replaced_ it is the
honest link, and the way to the audiobook is that record's to give.

## 3. Geometry

**Two left edges, never three.** Every container has exactly two
x-positions: the **box edge** (cards, inputs, record rows, buttons) and the
**text rail** — box edge + 12px (`pl-3`), matching the text inset inside the
inputs — where every bare-text element sits (labels, hints, helper prose,
microlabels, eyebrows).

**The rail belongs to a container, so ground level has none — with one
deliberate exception.** A block on the ground (`zinc-950`) — a section
heading, a line of helper prose — sits on the page's own edge; there is no
box whose padding it is matching, and a `pl-3` there is a _third_
x-position 12px right of every heading around it. If a fact wants the
rail, what it actually wants is a card. The exception: **ground
helper prose sitting directly against a card or a run of cards** may wear
`pl-3` to align with the railed text inside them (the import form's "This
book isn't in these yet" line). Labels are not in this exception: a card
names itself (§3b), so no label lives on the ground at all.

**A card's own text sits on the rail relative to the card's padding edge.**
A bare `<p class="… p-4">` puts its text at the padding edge, 12px left of
every sibling card's railed header, which is the easy mistake on a
single-sentence empty-state card. The text inside a card wears `pl-3` like
everything else.

**Text lands on the rail exactly, wherever it lives.** A control's own text
counts: a borderless pill pads `px-3`; a 1px-bordered box pads `px-[11px]`
so border + padding = 12 (the inputs' trick, worth a transparent border in
the borderless state so toggling doesn't shift the box); a card's leading
checkbox sits on the rail itself. Two pixels shy of the rail reads worse
than either edge — near-misses are what "feels off" is made of.

**Images are content, not containers.** A bare image (a cover preview, a
person photo, its empty-state placeholder) sits on the text rail like the
words around it. The box edge exists so a _container's_ padding can land
its inner text on the rail — an image has no inner text to land. An image
inside a chip or well follows that container's rules.

**Disclosure markers hang in the gutter.** A fold's summary text sits on
the rail with its chevron in the 12px gutter to the left — the
hanging-indicator pattern, always via `<.disclosure>`. Browser-default
summary markers are never used bare: Firefox draws them `inside`, pushing
the text off the rail; other engines pick their own widths.

**So a fold needs a container to hang that gutter in.** On the ground there
is no padding edge for the chevron to sit on, and `<.disclosure>` makes one
anyway: its summary lands 12px right of every heading around it, its chevron
on the page edge, and neither agrees with the 28px rail of the cards above
it. Three x-positions, arrived at by following the rule. **A ground-level
fold gets a card, and its summary becomes that card's label** — the chevron
takes the padding edge and the summary lands on the rail with everything
else. The duplicates report's "marked intentional" fold is the case.

**A long editable list scrolls inside its card; it does not fold.** The
chapter editor is the case: dozens of rows would swallow the form, but a
fold hides the content _and_ fights the autosave patches, while
`max-h` + `overflow-y-auto` on the rows container bounds the card's height
with every input still visible and in the DOM. Folds are for content the
operator mostly doesn't need (evidence panels, file stats), not for the
thing a section exists to edit.

**One label column for annotated rows.** Any run of "label: value" rows
(match lines, `Proposed`/`Results` rows, the source line) shares a fixed label
column via grid (`grid-cols-[4rem_minmax(0,1fr)]`), sized once per surface;
wrapped content stays in the value column. The width is the _widest label in
the family_ and nothing more: `Proposed` at 11px uppercase is a shade under
4rem, and anything wider leaves the short ones (`Results`, `Photos`) sitting
in a lake of air. The alignment is the point, so size the column honestly and
never give each row its own width: `max-content` in separate grids lines
nothing up at all.

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
spans and small images. Unwritten, this drifts per surface, and a primary
button next to a chip ends up visibly disagreeing about what shape a control
is.

**A date and its display precision are one composite fact, one control.**
`<.date_with_format>`: date left, precision select right, one shared well —
never two fields, and on the import form never two decision blocks whose
proposal could be _split_ across sources. A chip proposes both halves
("2015 (year only)") and accepting settles both; a claimed precision on a
day-specific date normalizes to full ("October 3rd is not a year in
disguise"), and a precision the operator sets deliberately is never
overruled.

**One control height: 40px.** `py-[7px]` + `leading-6` + a 1px border, which
is what `<.input>` is, so buttons carry the same padding rather than `py-2`
and the inbox's segmented filter bar (`p-1` + `py-1.5` segments) lands on it
too. §7 says adjacent bar controls share exact height; this is the number.

**The document is the scroller, and the chrome is sticky.** There is no app
shell: the body scrolls, the side nav is `fixed inset-y-0`, the page header is
`sticky top-0`, and the content clears the nav with `lg:pl-64`. This is not a
style preference: LiveView sets `history.scrollRestoration = "manual"` and
then saves and restores `window.scrollY` and nothing else, so an admin whose
scrolling happens inside `#main-content` cannot restore a position on back,
forward, or anything else. `#main-content` keeps its id and its `p-4`,
because the hooks and the arithmetic below name them.

**A sticky bar still has to be told about its containing block.** The offset
is the simple half: the viewport has no padding, so `bottom-0` puts a bar
flush with the bottom of the window. But a sticky box cannot leave its
containing block, so at the end of the scroll that block's own bottom edge
holds the bar up by `#main-content`'s 16px, which is what `-mb-4` on the
page's content wrapper is for and why it is required.

**Content passes behind the chrome, so the chrome is opaque and above it.**
The header paints `bg-zinc-950`, and there is one z-index ladder for the whole
admin, stated once on `layout_header/1`, in tens with the gaps left in on
purpose:

| z   | what                                                    |
| --- | ------------------------------------------------------- |
| 10  | the clickable layer inside a card (a row's action rail) |
| 20  | a busy scrim over a single card                         |
| 30  | the sticky page footers (`sticky_slab_classes/0`)       |
| 35  | a typeahead's popup                                     |
| 40  | a page-wide busy scrim                                  |
| 50  | the page header, admin and public                       |
| 60  | the drawer's scrim                                      |
| 70  | the side nav drawer                                     |
| 80  | a modal                                                 |
| 90  | the image lightbox                                      |
| 100 | flash toasts                                            |

Rows matter here because `index_row` is `relative` with no z-index of its own,
so its layers are **not** scoped to the card and compete directly with the
page's chrome. A bar with no z-index at all paints above a
row's card body and _underneath_ the same row's action rail, so its controls
flicker in and out of view depending which part of the list they cross.
**Anything pinned over the page needs a number, not a DOM position**: a tie
falls back to document order, and page content always comes after the
header.

Two rules fall out of the ladder. **A full-viewport overlay goes above the
nav, not beside it**: a nav that is `fixed` is a peer of everything rather
than a column the content sits next to, so an overlay numbered below it lands
under the sidebar. And **a scrim has to cover the control it is protecting the
operator from**: the import form's page-wide scrim is 40 rather than
`busy_overlay/1`'s own 20 precisely so it covers the sticky Save, and stays
under the header so the job indicator explaining the wait is still lit.

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
phone, by hundreds of pixels. **Truncating the string does not fix it**;
`truncate` clamps the
element, not its contribution to the ancestor's minimum. The item has to be
allowed to be narrower than its contents, and then the text inside it
wraps (`break-words`) or truncates as it likes.

Wrap rather than truncate when the string _is_ the content — an ellipsis on
a phone hides the end of the line, which for an error is the part that names
the failure. And prefer ordinary wrapping to `whitespace-pre-wrap` unless
the value really carries meaningful spacing: pre-wrap also preserves the
template's own newline and indentation around the interpolation, which
renders as a mystery indent on the first line.

**Corners share baselines.** A card's right rail aligns its first element
with the title line and its last with the content's last line
(`self-stretch` + `justify-between`).

## 3a. One row anatomy, for every list

List rows built independently inside an anonymous `:row` slot read like it:
several rail widths, several title weights, two places to put a state badge,
and a facts column that vanishes on a phone instead of folding.
`<.index_row>` is the anatomy, and each thing has exactly one home:

| Slot        | What goes in it                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------ |
| `:cover`    | `<.row_cover>`: a 64px image at the card's left edge; round for a face, `rounded-sm` for a cover |
| `:headline` | the title, `font-semibold`, and always the link                                                  |
| default     | the credit stack and meta lines under the headline                                               |
| `:badges`   | state, top of the rail, on the headline's baseline                                               |
| `:facts`    | counts and boolean glyphs, nothing that reads as a sentence                                      |
| `:action`   | one entry per verb, worded, right-aligned                                                        |
| `:footer`   | **system timestamps only**, at the card's bottom baseline                                        |
| `:overlay`  | a scrim that owns the whole card (`busy_overlay/1`)                                              |

**The footer corner is a record of what the app did, and nothing else** —
Added, Imported, Joined, Found, Last seen. A duration and a publication date
are facts about the _work_, and in the column that says "Added 8/17/26" three
lines of date read as three timestamps.

**And what they are instead is a sentence, not a cell.** `record_meta/1` is
the last line of the content column, under the credits. Terse cells
(`8/30/22`, `14:04:02`) are the shape a spreadsheet wants rather than a
reader, and the full words cost nothing, because that line is a line either
way. **The rule that
falls out: `:facts` holds what you count and glance at, the meta line holds
what you read.** One helper for both flat views, so the audiobooks list and
the queue's imported rows cannot phrase it differently.

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
detail pages and the mobile app keep §8's stack intact: the divergence is
this surface's, and it stops here.

**The rail is `w-56` (224px), which is two buttons wide, and actions wrap.**
Four buttons stacked one per line is tall and ragged; two rows of two is
neither. 224px is measured, not guessed: the tightest pair in the admin is
Playthroughs (120px) beside Devices (86px), 211px with the gap, and every
other pair is under 183px. Three never fit, which is what makes a four-verb
rail a clean 2 × 2.

The constraint that falls out lands on the **labels**, so keep them inside
the budget the rail is sized for — twelve characters, "Playthroughs" being
the longest — and don't put two long ones side by side. The inbox's second
action is "Origin" rather than "Import record" for exactly this reason.

(`fit-or-stack` is **not** the tool here. It is for metadata chip rows, where
the number of chips genuinely varies per record; a rail's verbs are fixed by
the surface, so its width can just be right.)

**A verb that isn't available yet is disabled, not absent.** A verb that
appears only once a row qualifies for it changes the rail's shape and the
order of its buttons from row to row, moving the primary action under the
cursor as the operator works down the list. A disabled button in its own
place says "not yet" without rearranging everything around it, and it has to
say _why_ in its `title`, or it is only a dead button. Note that
`disabled:` variants are a `:disabled` pseudo-class and a `<span>` can never
match one, so `row_action` spells the state out and drops the binding.

**The whole card is the link, and it is a real one.** The headline is an
`<a>` whose `::after` covers the card. The two obvious alternatives each get
half of this: `JS.navigate` on the container is a big target but not a link,
so no focus, no middle click and no open-in-new-tab, while linking the title
alone is a real link with a 200px target. The pseudo-element also avoids a
defect neither can see: LiveView dispatches a click to the _closest_
`phx-click` ancestor, so an `<a>` nested inside a `JS.navigate` row fires
both, and clicking one row action navigates to another. Everything clickable
therefore sits in a `z-10` layer above the pseudo-element; an overlay is
`z-20` above both.

**A row that goes nowhere is not a link and wears no pointer.** A
`cursor-pointer` hardcoded on every row invites clicks on dead space.

**The rail needs `self-stretch` or its `justify-between` is decoration.**
The card is `items-center`, so an unstretched rail is content-height and the
dates sit jammed under the actions instead of on the card's bottom baseline.

**64px is the row's height floor**, so no list's rows are visibly shorter
than another's on the same page of the same app.

**A row whose record has an image shows it, and one whose record has none
shows the empty box.** `<.row_cover>` is that box: an anatomy each list
writes out by hand is one a new surface can simply not have, which is how a
list ends up with no image at all while holding a cover URL. It is also where
a remote URL goes through the image proxy (§7) rather than at each call site,
so a caller never has to know which kind of path it is holding.

**Paging is the list's own sticky footer.** The header holds what _narrows_ a
list (search, sort, and the one button that adds to it); `pagination_footer/1`
holds what _moves through_ it. Chevrons in the header corner are wrong three
ways: the control for moving through a list sits as far from the rows as the
page allows, it says neither which page you are on nor how many there are,
and because the header does not move, clicking "next" leaves the scroll where
it was so the operator arrives looking at the bottom of the page they just
asked for.

**Sticky, not merely in the flow.** A bar at the foot of the rows and nothing
more only trades one kind of "far away" for another: a page is 50 rows, two
or three screens, so reaching page 3 from the top of a list would mean
scrolling to the bottom to find it. It wears `form_footer/1`'s costume, from
`sticky_slab_classes/0`, because it is the same object doing the same job:
the thing the page is _for_, at the end of the thing, reachable without
hunting. Both bars settle into place at the end of the scroll, and the
`sticky-footer` hook undresses them into ordinary cards when the page has
nothing to scroll.

The footer states the range and the total ("Showing 51 to 100 of 412", "Page
2 of 9"), its steps are worded like every other action (§3a), an unavailable
step is dead rather than absent so the bar keeps its shape at both ends, and
`list-scroll-reset` takes the page back to the top whenever the page, the sort
or the search changes.

**A page is 50 rows.** Ten makes a library of a few hundred audiobooks dozens
of pages deep, each reachable only by clicking through every page before it.

**A form goes back where it came from, to the record it just saved.** A form
that ends with `push_navigate(to: ~p"/admin/books")` lands on the front of an
unfiltered, default-sorted page one, whoever you were and wherever you had
been. `AmbryWeb.Admin.ReturnTo` is two halves: a list writes its state into
every row link, and the form reads it back and returns there, naming the
record so the list can scroll to it and flash it (`focus-row`). It anchors to
the **record**, not to a scroll offset, because those are different answers
the moment an edit changes the sort key: rename a book on a title-sorted list
and its row moves, so the pixel the operator left from belongs to somebody
else. A row that is gone or off-page focuses nothing and they land at the
top, which is the honest result. The "New" button deliberately carries no
list state: a record that does not exist yet cannot be on the page you were
filtering.

**This is not optional on a form that has a list behind it**, and a form that
skips it fails silently: saving works, the operator lands on the list, and
the row they just edited is somewhere on it. A form that does one half of
`ReturnTo` has done neither.

**Counted where the rows are queried, from the same filters.** A total
assembled anywhere else eventually describes a different query from the rows
above it. The flat views make this cheap when nothing is filtering: their
credit arrays are correlated subqueries in the target list and the planner
drops every one of them for a bare count.

## 3b. Forms are blocks, like everything else

An edit form is not a special case: it is a page of decisions, so it is a
page of blocks. `<.field_group>` is the unit — one `zinc-900` block per
_cluster_, being the fields that answer one question about the record ("who
wrote it", "where the files live"). Its label names the cluster and sits on
the text rail; fields that speak for themselves need no label, because the
block and the gap around it are already the grouping.

**A card names itself.** Every label — with its provenance flag, badges,
and hint — lives _inside_ the card it describes, at the top, on the rail.
Naming a container from the ground puts a heading over cards that already
name themselves, so ground level carries only section headings (`<h2>`) and
helper prose. The documented exception: a disclosure fold names itself in its
`<summary>`, which is a control.

**A list the operator is building has exactly one grammar, on every form:
label (and flag and hint) at the top of the container, rows inside it,
proposal chips after the rows, add below the container** —
`<.list_cluster>`. An **empty list states itself** instead of rendering a
bare grey slab: a railed sentence in the card ("Not in a series.", "No
narrators."), with the add still offered below. What varies between forms is
only what the container holds: one card of single-input rows on an edit form,
a run of per-decision cards on the import form (whose credits cannot nest
inside a block without eating the elevation ladder). A second grammar, with
the label and the add _inside_ the block, makes the same content type wear a
different anatomy depending on the form, which §6's "same costume for the
same job" exists to prevent. Never bless a divergence by documenting both
halves as intentional.

**The documented exception: a derived list has no add.** The import form's
**People** section lists one card per human the import introduces, and
the operator cannot add one there — a person exists because a _credit_ names
them (`Draft.referenced_keys/1` mints the decisions from the credits), so
adding a person happens on the credit and appears here. The label and the
rows are the ordinary grammar; the add below the container is absent, and
that absence is the honest statement that this list is derived rather than
built. The people behind a _linked credit_ are not listed: they were chosen
in the credit's typeahead, they carry their own curation which an import may
never overwrite, and the one dangerous case — a name matching two existing
identities — is a decision on the credit, where `Credit.state/1` computes it.
A person the operator matched to the library _from their own card_ does stay,
because that decision was made here: dropping the card the moment the link is
made takes the way back with it.

**The other documented exception: an upload sits inside its block.** A
dropzone is not an add-button. `<.file_input>` is a control the block owns —
the same way the media form's cover and the person form's photo own theirs —
so it renders inside the card rather than under it, and supplemental files
follow the cover rather than the series rows. The rule the `:add` slot
encodes is about the _button that appends a row_, and reading a dropzone as
one puts a file input outside the thing it belongs to.

**A card asks nothing it can state.** The person card carries no name box in
the ordinary import, because the credit names the human, and a box on every
card in every state leaves "This is a pen name" with no visible effect to
have. Reveal the exception, state the rule: the box appears when the name is
genuinely the person's own, and a control that reveals it always offers the
way back. The other question a card like this answers, whether this is
somebody the library already has, is _evidence_, and wears the local-row
costume the work level uses ("Yes, it's them"), not a permanent search
box.

**Pen names are bracketed, not nested.** One author credit can stand for
several humans, so those person cards sit adjacent under a shared labelled
rail. The label states what the cards can't — "2 people behind this name" —
because each card is already titled by the credit it belongs to. A bracket is
a label and a rail, never a filled block: wrapping cards in a card eats the
elevation ladder.

**Every form saves from the same place: the sticky footer slab**
(`<.form_footer>` — shadowed `zinc-900`, `-bottom-4`, with `-mb-4` on the
page wrapper per §3's sticky rule). A bare Save floating on the ground after
the last card is at the bottom of the scroll on any form long enough to
matter.

**The browser already has a Back button, so no form draws one.** A Back
control on a form does nothing the browser's own does not, and spends a slot
in the row of controls the form is actually for. A form goes back on its own
when it is done (the `ReturnTo` rule in §3a); leaving without finishing is
the browser's job, and one it does better, because it knows where the
operator actually came from. The general form: **don't re-invent what the
browser already does.**

**The footer is also where outstanding work is listed**, not merely counted.
It is the one thing always in view, and `Draft.unresolved/1` returns a
section and a label for every decision still waiting, so it names them and
links to them. Without that, a form long enough to have sections has work
below the fold that nothing announces.

**One form measure: `max-w-4xl`.** Every form, whatever it holds. A measure
is shared only if every form takes it from the same place, and "narrow
because this form is short" is a judgement each form makes differently.

**A page of settings is a form, and wears the form rules.** A switch and a
template are decisions like any other, so a settings page is built from
`<.form_section>`, `<.field_group>` and `<.form_footer>` like every other
form. `text-lg` headings with hand-tuned margins under them, 32px between
sections where every form uses 56px, several primary buttons on one page and
a Save sitting on the ground are what make such a page read as a different
app. `<.form_section>`'s `:blurb` slot is where the prose under a heading
goes, so that spacing is decided once.

`<.form_section>` wraps a run of blocks under a ground-level `<h2>` — only
for a form long enough that you need to find your way around it (the media
form has two; the book form needs none).

**Every label an `<.input>` renders is on the rail** (`pl-3`), because the
control's own text is. A label at the container edge over an input whose text
is 12px in leaves a form two left edges out of alignment with itself, which
is precisely §3's near-miss.

The image-stack thumbnails (`multi_image`) are the documented exception to
§1: overlapping images have no fill to separate them with, so they draw
their own 1px edge.

## 4. Type

| Role                             | Spec                                                                                 |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| Page title                       | `text-2xl font-bold text-zinc-100`                                                   |
| Section heading                  | `text-xl font-bold text-zinc-100`, no rule                                           |
| Field label                      | `text-sm font-semibold` (zinc-200), on the text rail                                 |
| Body / control text              | `text-sm text-zinc-300`                                                              |
| Hint / helper / meta             | `text-xs`/`text-sm` `text-zinc-400` (`zinc-500` for the faintest) — **never italic** |
| Microlabel (`Proposed`, `Asked`) | `<.microlabel>`: 11px medium uppercase tracking-wider muted                          |
| Paths, queries, identifiers      | `font-mono text-xs`, muted; a repeated common prefix is printed once                 |

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

| Job                                   | Anatomy                                                                                  |
| ------------------------------------- | ---------------------------------------------------------------------------------------- |
| Primary action                        | solid `bg-brand-dark text-zinc-900` (the loudest thing on the page)                      |
| Secondary button                      | filled `bg-zinc-800 text-zinc-200 hover:bg-zinc-700`, borderless                         |
| Quiet row action                      | `<.row_action>`: the `:sm` button costume, always worded, content-sized, right-aligned   |
| Danger                                | `bg-red-400/10 text-red-300`, or red text revealed on hover                              |
| Status badge                          | `<.badge>`: soft tint + colored text, borderless                                         |
| Count chip                            | `bg-white/10 text-zinc-300 tabular-nums`                                                 |
| Option chip — _chosen_                | `bg-brand-dark/15` + `ring-2 ring-inset ring-brand-dark/50` + ✓ + filled lime source tag |
| Option chip — _unchosen_              | `bg-zinc-800 hover:bg-zinc-700`; source tag bare muted uppercase                         |
| Option chip — _escape hatch_ (`None`) | dashed `border-zinc-600 text-zinc-400`, transparent                                      |
| Evidence row — _ticked_               | well: `bg-brand-dark/10` + `ring-2 ring-inset ring-brand-dark/50` + lime checkbox        |
| Evidence row — _unticked_             | `bg-zinc-800/60 hover:bg-zinc-800`                                                       |

If two pills on one surface do the same job, they wear the same costume, the
same height, and start on the same rail.

**Three tiers of action, and nothing else.** Loudness follows consequence:

| Tier      | Costume                                                                   | For                                                         |
| --------- | ------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Primary   | solid `bg-brand-dark`                                                     | the one thing the page is for — Save, Import, Scan          |
| Action    | `<.button color={:zinc}>`, opaque raised fill, `size={:sm}` inside a card | Confirm, Split, Re-match, Ignore, Search                    |
| Add a row | `<.add_button>`, the faintest fill that still reads as a control          | adding a blank row, the least consequential thing on a form |

**An action must be visibly raised, or it is a label.** A `bg-white/5` quiet
action computes _darker_ on a `zinc-900` card than the `bg-white/10` count
chips beside it, so the labels read as raised and the buttons as recessed and
Confirm looks exactly like a tag. Actions are an opaque fill one rung up from
what they sit on; tags and counts stay flat, muted and smaller, with no
hover.

**The add follows its list — below the container, on the ground** (§3b's
one grammar). The `<.add_button>` box sits on the container edge like every
other control, and its `px-3` lands the label on the text rail; nudging the
_box_ onto the rail puts its text at a third x-position nothing else shares,
which reads as misalignment on every form it touches.

**Removing a row is ✕; destroying a thing is a trash can.** A list row's
remove (`<.delete_button>`) is undoable until save, so it wears the import
form's ✕. The trash can is reserved for actions that destroy something
real — the file audit's deletes, an index row's delete — with red revealed
on hover (§6 danger).

**Row actions are worded, everywhere**, with no icon-only exception: a rail
holds at most four verbs (§3a), which is few enough that all of them fit as
words. `<.row_action>` is the one costume, a link when it goes somewhere and
a `role="button"` span when it fires an event, and the trash can survives
only where §6's danger rule puts it, on a row that is not itself a link (the
file audit's deletes).

**Actions are content-sized and right-aligned, never one fixed width per
rail.** One shared width across every list forces the longest label anywhere
in the admin onto every "Edit". Right alignment is what makes the edge read
as a column. How a rail lays out is decided by its verb count (§3a), never by
measurement.

**Every destructive confirm names what dies and what survives.** "Are you
sure?" says nothing, least of all on the action that deletes an audiobook's
audio files off the disk.

**Destroying a record is offered in exactly two places, and they are the same
two for every record type: the record's row in its list, and its form's
sticky footer** (`<.form_footer>`'s `:danger` slot, at the far end of the
bar, with the whole width of it between the irreversible thing and the thing
pressed every time). Decided per record type, this becomes several answers to
one question, and which one an operator gets depends on which record they are
looking at.

**The rule stops at delete, deliberately.** "Every action in both places"
would drag the workflow verbs along with it (Dismiss, It's out, Import,
Ignore), and those belong to the row, because they are what you do while
surveying a list rather than while editing one record. Delete is the
exception because it is the one verb an operator reaches for from either
position: pruning a list, and finding out on the form that this record should
not exist.

**A record that does not exist yet cannot be destroyed**, so the slot is
absent on a `:new` form rather than disabled. §3a's "disabled, not absent"
rule is about a verb whose _place_ must not move as the operator works down a
list of rows; a form is one record, and there is no list of forms for the
button to jump around in.

**What a delete says has one home**, `AmbryWeb.Admin.Deletion`. The words
have to be the same on both surfaces, and spelled per handler they are not:
every list ends up with its own way of saying a delete worked, and every
refusal is a heredoc beside the handler that raised it. The context is what
knows _why_ a record cannot go, so the reason atoms it already returns are
the whole vocabulary; a reason with no words is a crash rather than a shrug,
because a delete that reports "couldn't" without saying why is what the
refusals exist to prevent. There are two success verbs and the caller picks:
deleting a book destroys it, while removing a source or a library root only
stops Ambry looking there, and "Deleted" of a folder still on the disk is
this section's own confirm rule broken by the message that follows it.

## 6b. Toasts and ambient chrome

**A flash is a toast: top centre, quiet, and gone on its own.** Top _right_
is where the admin keeps the user menu and the job indicator, so a "saved"
notice there covers the two controls most likely to be wanted next; one that
waits to be clicked then keeps covering them.

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
  _server-side_, not just hide it, or it returns on the next navigation.
- **A toast that is a state rather than an event never times out.** The
  connection notices are the live state of the socket; timing one out would
  claim the connection came back.
- **Never put a display utility on an element hidden by the `hidden`
  attribute.** `[hidden] { display: none }` comes from the UA stylesheet, so
  an author-level `flex` (or `block`, or `grid`) on the same element
  outranks it. A `flex` on the flash root makes both connection notices
  visible on every navigation, for the moment between first paint and
  `phx-connected` firing: too brief to read and impossible to miss. Put the
  layout on an inner element.

**An ambient indicator renders its quiet state too**, and wears one costume
(`<.status_dot>`). The header's background-work widget shows a dim dot and
the word Idle when nothing is running: a widget that only appears when there
is news is indistinguishable from a broken one, and rendering the calm state
is what makes the busy state mean something. Where the state is genuinely two
questions ("is it busy" and "did something break") they get two marks,
because only one of them is a reason to stop what you are doing.

**A link that leaves the app says so before it is clicked.** Oban Web and
the Phoenix dashboard open in a new tab with
`fa-arrow-up-right-from-square` beside the label — the admin is a page you
leave open while you watch something, and taking the tab costs you that.

## 7. Controls

- **A remote image goes through the admin proxy.** Tracking protection blocks
  hotlinks to provider CDNs, so a surface that renders a provider's cover URL
  directly is blank in some browsers and not others, which is invisible to
  whoever built it. `proxied_remote_image_url/1` leaves a local path alone,
  so apply it wherever an image is rendered rather than only at the call
  sites that happen to be remote today. `<.row_cover>` and `preview_src/2`
  are where that lives.
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

**One vocabulary.** The playable thing is an **audiobook**, never "media",
"recording", or "release" in anything rendered. The abstract work is a
**book**, never "work". A `RecordingGroup` is a **set**. "Edition" appears
only as a relation ("another edition of this book"). Code, schema and module
names keep their own words; the rule is for text an operator or listener
reads. The admin routes follow the words: `/admin/audiobooks`,
`/admin/sets`.

**Credits are the mobile app's stack**: title (bold), series
("Name #3"), bare author names — no "by" — then "Read by …" muted, with
size and color carrying the roles. (Index rows are the documented
exception: the series moves down to their variable line, §3a.) "Narrated by"
is not used as a verb; the noun "Narrator" stays. When one line must hold it
all (page titles, match rows, option labels), the joins are words: "The
Martian by Andy Weir read by R.C. Bray". Names join with commas.

**No em or en dashes in rendered text.** Rewrite the sentence instead:
two short sentences, a semicolon, parentheses ("Name (context)"), or a
comma. The only "—" left is the empty-value placeholder in table cells,
which has one home in `empty_value/0`. The " · " middle dot stays, but only
between metadata facts (file stats, record-row facts), never inside a credit.

**And it is a test, not a rule** (`AmbryWeb.VoiceTest`). A dash slips into a
provider's setup help, a token expiry warning, a match explanation or a
flash, written by somebody who has read the rule and is writing prose, which
is the failure a prose rule cannot prevent. The test reads the source rather
than rendering pages, because rendered strings live in contexts an admin test
never reaches, and a check that only covers the pages somebody thought to
test is no check at all. Comments, `@doc`s and non-`~H` sigils are exempt: a
release name is full of dashes and the patterns that parse one have to say
so.

**This is the shape to reach for whenever a rule here is about a string.** A
rule that has to be remembered while writing a sentence will be broken while
writing a sentence.

**Hints are one plain sentence**, two at most: no asides, no "not X, but Y"
rhetoric, no reassurance ("that is common and not a problem"), no mechanism
lectures, and no notes about what changed or what is planned.
Flashes say what happened, then what to do, in at most two short
sentences. Control labels that answer a question use a comma: "Yes,
another edition of this", "No, a different book", "None of these".

## 9. Curation is the import form, everywhere

The edit forms run the import form's model on records that already exist: one
mechanism for "ask the databases", never a modal per provider.

- **One card holds a search: the query, then who answered, then what they
  said.** That order is the grammar, and `<.provider_outcomes_row>` is the
  "who answered" line in every one of them. A surface that writes its own
  outcome summary invents a second way of saying a provider failed, and the
  copy it invents is where §8's rules get broken.

- **The evidence panel** (`<.evidence_panel>`) sits above the form —
  evidence first, then the decisions it feeds — and starts **folded to one
  line**: an edit form is mostly visited for reasons that aren't curation,
  and instructions about records that aren't there yet are noise. One
  search fans out to every capable provider (`Ambry.Metadata.Search`);
  results are the same tickable `record_row`s and `Asked` outcome chips
  the inbox uses, **scored and ranked the way matching ranks them**
  (`Ambry.Inbox.score_records/3`, hinted by the record's own fields) so
  the study guides sink. The recording level asks twice, like the import
  form: recording-level providers directly, plus the audio editions the
  work-level databases keep.
- **One list, ranked once, whoever answered.** Which database found a record
  is a fact about the record and wears a badge on its row; it is not a
  heading and it is not an axis to sort by. Grouped by provider, a run of
  headings ranks each provider's guesses on a different yardstick and then
  asks the operator to judge across them, when a provider either can produce
  audio editions or it cannot and the ones that can are all asked. Anything a
  heading would carry that the rows do not, such as which book a work-level
  provider says a recording is of, becomes a fact on the row. Ranking is
  `Ambry.Inbox.score_records/3` everywhere, matching's own scorer: an operator
  who ranks provider records one way on the import form and another way on a
  search page is being asked to learn two orderings of the same evidence.

- **Records identify themselves**: every record row wears its cover or
  face as a small thumbnail — identification, visible _before_ ticking —
  while the chips below stay the place a photo or cover is _chosen_. Tiny
  images everywhere carry a corner magnifier that opens the full-size
  image in the lightbox; disambiguating twins sometimes takes the art at
  full size.
- **Provenance closes the loop**: accepted proposals and imports record
  the provider _record_ behind each field (`"record"` in the provenance
  entry). A later search that returns that record recognizes it — arrives
  pre-ticked, wearing a "filled title · published" note — so "which record
  did this come from?" has an answer years later.
- **Ticked records grow "Proposed" chip rows** under the fields they can
  fill (`<.curated_input>` / `<.proposal_row>`), in the import form's chip
  anatomy exactly. Accepting a scalar chip takes the value; accepting an
  entity chip (author, narrator, series) **stages** a row that names the
  entity, and nothing is created until Save: a chip that writes a record on
  the spot leaves a person behind on every form the operator opens and
  abandons. Evidence is session state, added and never replaced while the
  page lives, gone when it is left.
- **Provenance is worn inline** on each field's header
  (`<.provenance_flag>`): "from hardcover" muted for the recorded source,
  "will record rreading-glasses" amber for an accepted-but-unsaved one,
  with the lock beside it: the import form's "from …" idiom pointed at
  `Ambry.Provenance`. Accepting records the provider unlocked; editing the
  value afterwards makes it a manual edit again, locked.
- **A proposal that is a _merge_ previews in place, inside the thing it
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

- **A control tells the form when it is left, not while it is being typed
  in.** Typing a name and meaning it post the same string, so anything
  downstream of a per-keystroke `change` reacts on the first letter — hardest
  of all while the operator is searching for a record that already exists.
  The picker moves its hidden inputs under the typing, so a save posts
  whatever the box says, and raises the change on pick, create or blur, which
  is where a native input raises it. Answering the same question with a second
  hidden input carrying "the operator clicked Create" pushes the job onto
  everything that stages a credit _without_ the picker, and a provider chip
  crediting a new narrator will not set it, so their card never appears.
  **A surface should read the state, not a flag beside it.**

- **A credit that names somebody new gets that person's card — literally the
  inbox's card.** A picker may name a record the library has never heard of,
  so an edit form can invent a `Person`, and a person made of a name and
  nothing else is the asymmetry to avoid. So the edit forms render
  `person_card/1` itself, never a redrawing of it:
  `AmbryWeb.Admin.NewPerson` builds a `PersonDecision` and its `Credit` out
  of the nested person changeset and the card's own `Evidence`. **A person is
  a person on both surfaces** — same overlay while a search runs, same photo
  strip at the size a face is seen, same bio box with its preview and chips,
  same record list.

  It lives in a **section of its own** under the credits that name them — the
  inbox's `#people` anatomy down to the heading, a heading on the ground with
  cards below — never inside the credits card, which would be a card inside a
  card. It renders **only where the nested chain reaches a person nobody has
  made yet**, which is never true of a credit pointing at somebody who
  exists, and the credit rows are walked a second time (`skip_hidden`,
  `skip_persistent_id`) because the pickers above already post those.

  It is called **People** on both surfaces, never "New people" on one of
  them: a card can link somebody the library already holds, so the section is
  not only about the ones being made. A heading that narrows what its section
  contains is a difference to justify.

  The card hangs off the **join row** that holds the person — `author_people`
  for a pen name, `media_narrators[i][narrator]` for a stage name — not off
  the person itself, because that row is where "which human is this" is
  answered. It is what lets the card offer the people the library already has
  by that name and link one, and what lets a pen name carry more than one
  human (James S.A. Corey), the same as the inbox.

  **A ticked record about this human answers what nobody has answered.** An
  import takes the best record's face and biography and leaves the rest one
  click away; a credit that is merely _offered_ them leaves the operator who
  ticked a record and saved with a person who has a name and nothing else,
  which is the same asymmetry one level down. Records that spell the same
  name arrive ticked (person search is recall-first, so the rest are listed
  and left alone) and the best of them fills the boxes nobody has filled.
  **Absent is unanswered; present-and-empty is an answer**: the card's
  controls are inputs, so "no photo" and a cleared biography post as `""` and
  are left exactly as they are.

  **A card rendered more than once keys its ids by the card, not by its
  address.** An import form's people are a grid (this credit, this human
  behind it) so the address is unique there; on an edit form every card is
  the first person behind the first credit of the only section, and the
  hook-bearing elements collide. LiveView finds elements by id when it
  patches, so a bio box vanishes when an unrelated part of the form changes.
  Anything repeated takes its ids from whatever is actually one per copy.

  One thing genuinely differs, and `input_prefix` is where it is said: the
  import form saves on change and has no form of its own, so each of the
  card's controls is a little `<form>`; an edit form is one form with a Save
  button, and forms cannot nest. Given a prefix, the three form-bearing
  controls become plain inputs posting under it, the chips write those inputs
  on the client (`assets/js/hooks/set-input.js`) instead of raising events,
  and the state rail goes, because nothing here is part-way through a
  decision tree. Everything else is the same markup.

- **A section whose work repeats gets one control for all of it.** Ten
  credits accepted from a record is ten new-person cards, each with a Search
  of its own, and finding out about them one at a time is ten clicks in ten
  places. So the section heading carries "Search all _n_", chained
  `JS.push/3`, because pressing them all _is_ the feature and each card's
  handler already knows what to do with one. It counts what it would ask
  about and disappears when that is nothing, because a control that might do
  nothing should say so before it is pressed. Same control on the import
  form, where matching has usually asked already, so the same rule shows it
  only where the operator has added credits by hand.

Structural lists (authors, narrators, series) carry **list-level
provenance**: one entry per list, worn as the same "from …" flag on the list
cluster's label, because the import form visibly chooses credits from sources
and dropping that at the library door reads as something missing. Locks exist
in the data (manual = locked, accepted = unlocked) but have **no UI**:
nothing consumes them, and a toggle for a promise nothing tests is theater.
The lock icon belongs with a refresh feature that honors it.

What differs from the inbox is only what the context demands: no state rails
(nothing here is _waiting_, because the record is real and every field
already holds a value) and no stored draft. A new difference argues from the
context's lifetime, not from convenience.
