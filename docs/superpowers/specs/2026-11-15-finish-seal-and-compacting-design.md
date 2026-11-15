# A Face ID-style finish, and a compacting session

Date: 2026-11-15
Status: approved by the owner on 2026-11-15.
Extends: `2026-11-14-agents-tab-design.md` (sections 4, 6) and
`2026-11-15-subagent-branches-design.md`.

## 1. Goal

1. When an agent session finishes, the pet on the collapsed island plays a confirmation
   like the iPhone's Face ID check, and then the island lets go of it: the wings close, the
   mark and the rim light end. The Agents list still says `Done ✓` until the tab is opened.
2. While a Claude Code session compacts its conversation (`/compact`), a purple dashed line
   runs around the collapsed island, the right mark becomes a purple dashed ring that
   turns, and the pet's wave runs from top to bottom instead of left to right. When the
   compaction ends, all of it goes away.

## 2. Owner's decisions (2026-11-15)

| Topic | Decision |
|---|---|
| Finish effect | "agentın işi bittiği zaman sol tarafta gözüken petin orada iphone face id onaylama efekti olsun ve öyle kapansın" |
| After the effect | Option B: the island closes, the list keeps `Done ✓` until the Agents tab is opened ("öneriyi yap") |
| Compacting look | "mor bir şekilde kesikli çizgilerle loop şeklinde compact bitene kadar dönsün"; both "adanın etrafında gezsin kesikli çizgi" and "sağdaki halka yerine gelsin" |
| Compacting pet | "agentın şu an çalıştığını gösteren soldan sağa olan efektin aynısını yukarıdan aşağıya doğru yapsın" |
| Compaction ends | "compact bitince de gitsin": everything goes away; it is not a finish, so no Face ID effect and no `Done ✓` |
| Detection | Without hooks. Another app on this Mac (Vibe Island) uses Claude Code's `PreCompact` hook; this project does not ("hook yok", agents-tab decision) |

## 3. Constraints carried over

Read-only, no hooks, nothing written into any tool's folders, no new dependency, no
permission prompt, user content never logged. No view redraws frame by frame at rest: every
loop runs in Core Animation with keyframes sampled from tested core formulas. The rim
light's own effect, the line under the notch and the right mark's existing effects
(working arc, knocking dot, mint check with its ripple) are not changed; this spec only
changes how long a finish lasts and adds new layers beside them.

## 4. The finish seal

### 4.1 Look

The effect plays where the finished session's pet stands on the collapsed face: the left
wing at the notch, the left of a floating island, the top of a side strip. It lasts
1.7 s and plays once:

| Time (s) | What happens |
|---|---|
| 0.00–0.45 | Four white corner brackets, like Face ID's frame, appear at 125 % of the pet's size and close in to its edges; the pet stands still at full color |
| 0.45–0.75 | The brackets grow into a closed circle; the pet fades out and shrinks to 90 % |
| 0.75–1.15 | The circle turns mint, and a check draws inside it with a light pop (100 % → 108 % → 100 %) |
| 1.15–1.70 | Holds |
| 1.70 | The session settles (4.2); the wings close with the island's usual spring |

At the same time the right mark shows its existing mint check and ripple, unchanged.
With Reduce Motion the seal is a still mint circle with a check, shown for 1.0 s.

The effect plays once: SwiftUI's `keyframeAnimator` runs one time value from 0 to 1.7 s
and the view draws the pose a tested core function (`AgentSealTiming.pose(at:)`) gives for
it. It redraws only during those 1.7 s, like the check the mark already draws with a
spring; nothing animates after it, so the rule about rest holds.

### 4.2 Settling (core)

`AgentSessionBoard` gains a set of settled ids next to `finishedIDs`:

- `settle(_ id:)` marks a finished session as settled. A settled row stays in `rows` with
  state `.finished`, so the list still shows `Done ✓`.
- `lead`, `attention`, `attentionRow` and `hasFace` ignore settled rows. With nothing else
  to show, the island has no agents face and the wings close.
- `markSeen()` clears both sets. A session that turns active again (working, needs input,
  compacting) leaves both.
- Row order: needs input, then finished and not yet settled, then working and compacting,
  then finished and settled, then running, then idle. A session that has just finished
  therefore takes the face long enough to play its seal, even while another one works,
  and then gives the face back. A question still comes first; a finish behind it plays
  once the question is answered.

`IslandState.settleFinished(_ id:)` forwards to the board, assigning only on change.

### 4.3 When the seal plays

`IslandView` owns one timer: while the island is collapsed and `attention == .finished`,
it waits 1.7 s (1.0 s with Reduce Motion), keyed on `attentionRow.id`, then calls
`settleFinished`. The face views only play the animation, which starts when the row
appears on the face, so both begin together.

- If the island opens mid-effect it opens on `Agents` (a finish is attention); leaving the
  tab clears the finish, so no seal replays. If a question takes the face, or the island is
  dragged, the timer is cancelled and the row stays unsettled; the seal plays again from
  the start next time.
- If the Agents tab is opened, `markSeen` clears the finish and nothing plays.
- Several sessions that finish play one after another: when one settles, the next
  unsettled one becomes `attentionRow`.
- The media face has no pet. When it is the face, its right side shows the existing mint
  check instead of the level bars for the same time, and the same timer settles it.

### 4.4 Claude Code's `shell` status

Claude Code 2.1.325 writes `status: "shell"` when its turn has ended while a background
shell command still runs (seen live on 2026-11-15: twice right after a turn ended with a
background task open, then `busy` when a new message came). Today it falls under
"something newer" and shows as `Running`, which hides the finish. It becomes `.idle`, so
that a turn which ends this way finishes and plays the seal.

## 5. Compacting

### 5.1 Detection (Claude Code only)

Claude Code writes no compaction field to its session file; `isCompacting` lives only in
its process. The transcript shows it, though: the records that describe a manual
compaction are written when it ends, but its start leaves a mark.

Evidence (this Mac, 2026-11-15):

- Claude Code 2.1.303–2.1.318, eight manual compactions: a `user` record whose
  `message.content` is the plain string `/compact` is written at the start; nothing but
  a `file-history-snapshot` and queue operations follows until the `compact_boundary`.
- Claude Code 2.1.325, two manual compactions (79 s and 18 s): at the start, a
  `file-history-snapshot` whose `messageId` names the `/compact` command record, which
  itself is written only at the end. Only metadata (`last-prompt`, `mode`,
  `permission-mode`, `session-owner`, `atis-latch`, `bridge-session`, `tools-used`) and
  queue operations follow until the boundary. For a normal prompt the user record
  follows its snapshot at once.
- The session file says `busy` for the whole compaction (18 s live: `busy` 27 ms after
  the snapshot, `idle` 0.1 s after the boundary).
- `/model` with its dialog open for 7 s writes nothing to the transcript until the dialog
  closes, and the session file says `waiting` / `dialog open` meanwhile: no false alarm.
- `/compact` in a session without messages fails at once ("Not enough messages to
  compact.") and the status never changes: nothing to show.

Rule, in a new core reader `ClaudeCompactionReader.compactionMark(inTail:) -> CompactionMark?`,
asked only when the session file says `busy`, over the last 64 KB of the transcript:

1. Walk the lines from the end, skipping every record that is not `user`, `assistant`,
   `system`, `attachment` or a `file-history-snapshot` that is not an update. (New
   metadata types are skipped without being listed.)
2. A `file-history-snapshot` whose `messageId` is a record already in the tail is an
   ordinary snapshot and is passed over too (2.1.303–2.1.318 write the `/compact` record
   first and its snapshot after it). The first record left decides:
   - a `file-history-snapshot` whose `messageId` is no record's `uuid` in the tail →
     its timestamp (2.1.325);
   - a `user` record whose content is a plain string starting with `/compact` → its
     timestamp (2.1.303–2.1.318);
   - anything else → nil.
3. The session is compacting when the start is at least 1 s old
   (`ClaudeCompactionReader.isCompacting(_:now:)`).

The end. Once `compact_boundary` is written there is no start mark any more, yet the
session file stays `busy` for about 0.1 s more; a scan in that window would read plain
working, and the following `idle` would count as a finish (seal and `Done ✓`), which is
ruled out. So the reader also walks past `attachment` records and bookkeeping `user`
records (`isMeta`, `isCompactSummary`, content starting `<local-command-stdout>` or
`<command-name>/compact`), and a `system` record `compact_boundary` whose
`compactMetadata.trigger` is `manual` gives `.ended(timestamp)`. A busy session counts as
compacting for up to 5 s after that boundary (`endGrace`), so the end is never a finish.
An `auto` boundary counts for nothing.

The 1 s age keeps the instant between a normal prompt's snapshot and its user record from
counting. The provider caches the start, not the verdict, by the transcript's size and
modification time, and judges the age on every scan: the transcript does not change while
a compaction runs, so a cached verdict would stay "too young" forever. The reader parses
only the lines it walks, like `ClaudeTranscriptPromptReader`.

Latency: the session file turns `busy` just after the snapshot, so the immediate scan sees
the snapshot but still too young; the next periodic scan (3 s) shows the compaction. For
those first seconds the session shows as working. The end shows within 0.25 s, because
the session file turns `idle`.

Not detected: automatic compaction (it leaves nothing at its start) and Codex. A manual
compaction shorter than the first scan shows only as working, and its end then counts as a
finish.

### 5.2 Model (core)

- `AgentActivity.compacting` and `AgentRowState.compacting` (label `Compacting`).
- `ClaudeSessionParser.session(from:prompt:compacting:fallbackSince:)` maps `busy` with
  `compacting == true` to `.compacting`.
- Board: compacting is not attention. It ranks with working (4.2), so it can lead and
  gives the island a face. It clears a finish that was showing. It does not make the next
  `idle` a finish: compacting → idle ends quietly. A message queued during the compaction
  runs after it as a normal turn (working → idle → finished).

### 5.3 Look

Purple is `#BF5AF2` (`AgentPalette.compacting`), apart from the tool colors, mint and
amber.

- **Dashed rim.** A new `CompactingRim` layer beside `RimLight`, on the same outline and
  with no line along the edges that touch the screen: at the notch the line runs down the
  left side, under the notch through the 2 pt lip, and up the right side. A
  1.5 pt purple dashed stroke (6 pt dash, 5 pt gap) whose dash phase moves continuously
  at about 40 pt/s, clockwise. Shown while the island is collapsed and the agents face's
  row is compacting. It never meets the rim light: a finish outranks a compaction, and a
  question takes the face.
- **Right mark.** `AgentStatusMark(.compacting)`: a purple ring of eight dashes that turns
  once every 2 s (Core Animation rotation, like `SpinningArc`). With Reduce Motion it
  stands still.
- **Pet.** The wave runs from top to bottom: all lines rest at 82 % (`waveRest`); a soft
  horizontal band travels from the top to the bottom in `waveTravel` (1.3 s) once every
  `wavePeriod` (2.4 s), at the pace of the wave across, and
  inside it the lines show at full color and 10 % wider (`waveGrowth`). Nothing moves up
  or down and no white is added. Done with two copies of the figure, the crest copy
  revealed by a moving gradient mask; the band position is a tested core formula. With
  Reduce Motion the pet stands still.
- **List.** The row shows the compacting pet, the purple ring and `Compacting`. The dashed
  rim belongs to the collapsed island only, like the rim light.

## 6. Testing

Core (`swift test`):

- `ClaudeCompactionReader`: the 2.1.325 start (a start); snapshot followed by its user
  record (nil); snapshot updates ignored; metadata and queue operations after the
  snapshot (still a start); the old plain `/compact` record (a start); after a
  `compact_boundary` (nil); broken lines skipped; a start younger than 1 s is not yet
  compacting, an older one is.
- `ClaudeSessionParser`: `busy` + compacting → `.compacting`; `shell` → `.idle`.
- `AgentSessionBoard`: settle hides a finish from `lead`, `attention`, `hasFace` but keeps
  the row `.finished`; `markSeen` clears settled; turning active clears settled; an
  unsettled finish outranks working; compacting ranks with working, leads, has a face,
  is not attention; compacting → idle is not a finish; compacting clears a finish.
- `IslandState`: `settleFinished`; whether the compacting rim shows.
- Pet motion: the band position over a period.
- `AgentSealTiming`: the poses at the phase boundaries, and that the phases fit the
  duration.

App: frozen renders through `DebugRender` (seal at 0.2, 0.6, 1.0, 1.5 s; compacting at
notch, side, corner and in the list), and `SYMBIODOCK_DEMO_AGENTS=compacting` beside the
existing demo modes. CPU checked with `top` while compacting: it must stay at 0 %.

## 7. Out of scope

Automatic compaction, Codex compaction, changes to the rim light, answering from the
island.

## 8. Unverified

- The 2.1.325 start mark was seen in two compactions; a Claude Code update may change it.
  If it does, the session shows as working during compaction (no wrong state), and the
  reader gets the new mark.
- `shell` meaning "turn over, background shell running" was seen twice in one session.
