# Tabs and the Agents tab

Date: 2026-11-14
Status: approved by the owner on 2026-11-14.
Extends: `2026-11-14-symbiodock-v1-design.md` (sections 5.3, 5.4, 5.8, 5.9) and
`2026-11-14-side-docking-design.md`.

## 1. Goal

The island shows running AI coding agent sessions next to the media it already shows.

1. The expanded island has tabs. The first two are `Agents` and `Media`. The owner
   chooses which one is first.
2. The Agents tab lists the sessions of AI coding tools running on this Mac: which
   tool, the session's name, its project, and whether it is working, waiting for the
   user, finished, or idle.
3. A session that waits for the user (a question, a permission) never opens the island
   by itself. The collapsed island signals it with a status mark and a light along its
   rim. The same goes, more quietly, for a session that has just finished.
4. Clicking a session brings the terminal or app that hosts it to the front.

## 2. Scope

In scope:

- Tabs in the expanded island, a stored tab order, a menu entry to change it.
- Session discovery by reading files and the process list. Read-only.
- Claude Code and Codex with full state. Gemini CLI, Cursor Agent, OpenCode, Aider and
  GitHub Copilot CLI at process level (section 6.3).
- The status mark, the rim light, the pets, the collapsed faces in all three collapsed forms.

Out of scope:

- Hooks, plugins, or any write into a tool's configuration or data directory.
- Answering a question or granting a permission from the island. The island shows the
  question; the answer is given in the tool.
- Selecting the right terminal tab or window. Only the hosting app is activated.
- Opening a tool's SQLite databases.
- Sounds, notifications, haptics for agent events.
- Sessions on other machines or in the cloud.
- More than two tabs. The order is stored as a list so later tabs need no migration.

## 3. Constraints carried over

- No new third-party dependency. No new macOS permission prompt: everything read lives
  under the user's home in directories that are not privacy-protected, and reading
  another process's working directory needs no consent for a non-sandboxed app.
- Interface text is English.
- Pure logic lives in `Packages/SymbiodockCore` and is tested with `swift test`;
  file and process access lives in the app target under `Symbiodock/Agents/`.
- Session titles, project paths and question text are user content. They are never
  logged, at any log level.

## 4. Model (core)

```swift
public enum AgentTool: String, CaseIterable, Sendable {
    case claudeCode, codex, geminiCLI, cursorAgent, openCode, aider, copilotCLI
}

public enum AgentActivity: Equatable, Sendable {
    case working
    /// Waiting for the user. `prompt` is the question, when it could be read.
    case needsInput(prompt: String?)
    /// The turn is over and the session waits for the next request.
    case idle
    /// The tool is running; nothing more is known (process-level detection).
    case running
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String            // "<tool>:<native id>"
    public let tool: AgentTool
    public let title: String         // session name, else the project folder's name
    public let projectPath: String?
    public let activity: AgentActivity
    public let since: Date           // when `activity` began
    public let pid: Int32?           // the tool's process, when known
    public var hostAppPID: Int32?    // the regular app that hosts it, filled in by the app
}

public protocol AgentSessionProvider: Sendable {
    var tool: AgentTool { get }
    /// `context` carries the time and the process list, read once per scan.
    func sessions(in context: AgentScanContext) async -> [AgentSession]
}
```

A provider returns what it is sure of. A record it cannot parse is left out; a field it
cannot read is `nil`. It never throws to its caller.

### 4.1 AgentSessionBoard

`AgentSessionBoard` is a value type in core that turns the providers' lists into what
the island shows.

- `update(_ sessions: [AgentSession], now:)` replaces the list.
- Sessions are sorted: needs input, working, finished and not yet seen, running, idle.
  Within a group, the most recent `since` first.
- A session is *finished and not yet seen* when the board saw it go from `working` or
  `needsInput` to `idle`. Sessions that are already idle when the app starts are not.
- `markSeen()` clears every finished mark. It is called when the island leaves the
  Agents tab (it collapses, a drag begins, or another tab is chosen), so the rows still
  say `Done` while they are looked at.
- `attention`: `.needsInput` if any session needs input, else `.finished` if any is
  finished and not yet seen, else `.none`.
- `lead`: the first session in sorted order, if it needs input, is working, or is
  finished and not yet seen; otherwise nil.
- `hasFace`: true when `lead` is not nil. Sessions that are idle or merely running do
  not widen the island, for the same reason a paused player does not.

## 5. Tabs

```swift
public enum IslandTab: String, CaseIterable, Sendable { case agents, media }
```

- The order is a list stored in `UserDefaults` (`tabOrder`, raw values). Default:
  `[agents, media]`. On read, unknown values are dropped and missing tabs are appended
  in default order, so the stored list always holds every tab once.
- `IslandState` gains `tabOrder`, `selectedTab` and the board.
- **Which tab opens.** When the island goes from collapsed to expanded:
  `agents` if `attention` is not `.none`; otherwise the first tab in order that has
  something to show; otherwise the first tab. Media has something to show when a track
  is known; Agents when the list is not empty.
- While the island stays expanded, the selected tab changes only by a click.
- **Tab strip.** Two glyph buttons, `sparkles` (Agents) and `music.note` (Media), in
  tab order, each a 28 × 22 pt target, 14 pt from the island's leading edge. The
  selected glyph is white with a 3 pt dot under it, the other is white at 40 %. At the
  notch the strip sits in the band left of the camera housing. Away from the notch the
  strip is a row of its own, and the expanded content's top inset grows from 8 to 26 pt.
- When Media is selected and `attention` is not `.none`, the Agents glyph carries a
  5 pt pip in the attention colour.
- **Summary.** On the Agents tab, the band right of the camera housing (or the trailing
  end of the strip row) shows counts at 10 pt, white 50 %: `1 needs input · 2 working`.
  Groups with a count of zero are left out.
- **Menu.** The island's context menu gains `First tab` with a submenu of the tabs as
  radio items. Choosing one moves it to the front of the stored order.

## 6. Providers

All paths are under the user's home. A missing directory means no sessions.

### 6.1 Claude Code (verified on 2026-11-14, version 2.1.325)

- Source: `~/.claude/sessions/<pid>.json`, one file per running session. Fields used:
  `pid`, `sessionId`, `cwd`, `name`, `status`, `waitingFor`, `statusUpdatedAt`, `spare`.
- A file is used only if its process is alive (`kill(pid, 0)`), `spare` is not true, and
  the file is at most 64 KB. `*.key` files are never opened.
- `status`: `busy` → working, `idle` → idle, `waiting` → needs input. Any other value →
  running. Observed live: `busy` → `waiting` with `waitingFor: "input needed"` while a
  question was open → `busy`.
- Title: `name`, else the last component of `cwd`. `since`: `statusUpdatedAt`.
- Question text, best effort: the last 256 KB of
  `~/.claude/projects/<cwd with "/" replaced by "-">/<sessionId>.jsonl`. If the last
  assistant `tool_use` named `AskUserQuestion` has no later `tool_result` of its own, the
  prompt is its `input.questions[0].question`. Another tool called beside or after the
  question does not answer it. Anything else → `prompt` is nil and the row says
  `Needs input`.

### 6.2 Codex, CLI and desktop (verified on 2026-11-14)

- Source: rollout files `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, in the folders
  of today and yesterday. Titles: `~/.codex/session_index.jsonl` (`id`, `thread_name`;
  the last line for an id wins). The SQLite files are not opened.
- Codex sessions are listed only while a Codex process is running.
- First line (`session_meta`): `id`, `cwd`, `parent_thread_id`, `originator`. A thread
  with a parent is a sub-agent and is left out.
- State: the last of `task_started`, `task_complete`, `turn_aborted` among the
  `event_msg` lines in the last 256 KB. `task_started` → working, the others → idle.
  `since` is that line's timestamp. No such line → the file is left out.
- An idle thread is listed only if its file changed in the last 30 minutes; a working
  one only if it changed in the last two hours (a turn abandoned by a crash).
- The newest three day folders are read, so a thread that runs past midnight stays.
- A tail is parsed again only when the file's size or modification time changed.
- No approval or question event was found in the rollouts on this Mac. Until one is
  identified, Codex never reports needs input.
- `pid`: a running `codex` process whose working directory equals the thread's `cwd`,
  when exactly one matches; for a desktop thread, the desktop app.

### 6.3 Gemini CLI, Cursor Agent, OpenCode, Aider, Copilot CLI (not installed here)

These are detected from the process list, which needs no knowledge of their files:

- `ProcessScanner` (app target) lists every process with its parent, and for the user's
  own processes the executable path, arguments (fetched only for interpreter processes
  such as `node` and `python`), working directory, start time and controlling terminal.
- `AgentProcessMatcher` (core, pure) maps a process to a tool: an executable or script
  named `gemini`, `cursor-agent`, `opencode`, `aider`, `copilot`, or an argument path
  containing `@google/gemini-cli` or `@github/copilot`.
- Only processes with a controlling terminal count, and one row is made per tool and
  terminal. Helper and daemon processes are thereby ignored.
- The row's activity is `running`: the tool is open, with its project folder as the
  title. It never claims working, needs input or finished.

Each of these tools keeps its provider behind `AgentSessionProvider`, so a state reader
can replace process-level detection later. The implementation plan contains one research
task per tool: read the tool's source or documentation for its session storage, and add
a state reader only if the files carry an explicit turn start and turn end. The outcome
is recorded in `CLAUDE.md` whether or not a reader is added.

### 6.4 Coordinator

`AgentSessionCoordinator` (app target) polls the providers off the main thread and
hands the merged list to the board on the main actor.

- Every second while the Agents tab is shown expanded, every three seconds otherwise.
- A tick is skipped while the previous one is still running.
- At rest the app's average CPU use stays under 1 %.

## 7. Appearance

Two colours say what a session's state is: **red** `#FF4D4F` for needs input and **mint**
`#63E6A9` for finished. Each tool's pet has the tool's own colour (section 7.5). Everything
else stays white on black.

### 7.1 Status mark

`AgentStatusMark` is one 14 pt glyph used in every place a session's state is shown.
It morphs between its looks with a 0.3 s spring instead of switching.

| Activity | Look |
|---|---|
| working | An open arc (270°), 1.75 pt round-capped stroke, white 90 %, one turn per 1.1 s |
| needs input | The arc closes into a red ring around a 4 pt red dot. Every 2.4 s the dot knocks twice (scale 1 → 1.35 → 1) and each knock sends one ring outward to twice the mark's size while it fades |
| finished, not yet seen | A mint ring; a check mark draws itself in 0.35 s and one ring goes outward once. Then it is still |
| running | A ring and a centre dot, white 50 %, still |
| idle | A ring, white 28 %, still |

### 7.2 Rim light

Only on the collapsed island, drawn inside its outline (`strokeBorder`, 1.5 pt, plus a
blurred copy as glow), so the island's frame and hit area do not change.

- Needs input: red. Its opacity breathes between 35 % and 90 % over 1.8 s, and every
  3.6 s a brighter highlight travels along the island's long axis.
- Finished: one mint highlight travels across in 0.9 s, then a steady mint line at 50 %
  stays until the Agents tab has been looked at.
- Otherwise: no rim light.

With Reduce Motion on, nothing travels, knocks or breathes: the mark and the rim are
shown still in their colour.

### 7.3 Collapsed faces

The collapsed island shows one face. The face is the first tab's if that tab has one,
otherwise the other tab's, otherwise none (the bare notch, as today). Media has a face
when `showsWings` is true; Agents when `hasFace` is true.

| Form | Agents face |
|---|---|
| At the notch | Left wing: the lead session's pet (24 pt). Right wing: its status mark |
| Floating capsule (200 × 36) | Pet, the lead session's title, status mark |
| Side strip (36 × 170) | Pet on top, the title rotated in the middle, status mark at the bottom |

When the face is Media and `attention` is not `.none`, the status mark of the lead
session takes the place of the level bars. The rim light shows on either face.

The island at the notch widens by its wings when either tab has a face or `attention`
is not `.none`; `IslandLayout`'s `hasTrack` parameter becomes `showsWings` with that
meaning.

### 7.4 Agents tab, expanded

- At most two sessions are visible at a time, one under the other; the rest are reached
  by scrolling down, and the list comes to rest on a row. With more than two sessions the
  list fades out at its lower edge to show that it goes on. One or two rows are centred
  in the space below the header.
- A row is 46 pt: the tool's pet (36 pt, section 7.5), then two lines, then at the
  trailing end a label (11 pt) and the status mark.
- First line: the session's title (13 pt semibold). Second line (11 pt): the tool's name
  and the project folder, `Claude Code · storefront`, white 50 %. A row that needs input
  and has a prompt shows the prompt there instead, white 75 %, one line, truncated at the
  end; such a row has a red bar (2 pt) on its leading edge and a red background at
  12 %, 8 pt corner radius.
- Labels: `Working 2m`, `Needs input` (red), `Done 1m` (mint), `Running`, `Idle 5m`.
  Under a minute the time reads `<1m`; from an hour on, `1h 4m`.
- Empty: the `sparkles` glyph and `No agents running`, styled like `Nothing playing`.

### 7.5 Pets

Each tool is shown by its pet: a small figure of what the tool is known by, in the tool's
own colour. A pet is a square field of 21 fine vertical lines with round ends. Where
there is no figure the lines are faint (8.5 % of the colour); the figure shows as the
lines growing brighter and dimmer along their length, the way light falls on a form. A
line is a little wider than the gap beside it, so the colour stays strong.

The brightness comes from a model, not from a picture: each figure is a small relief
(domes, plates, tubes, holes) lit from the upper left. What faces the light shows the
tool's colour at full strength; what turns away, lies in a hollow or stands farther back
is dimmer, never below 30 %. The shading is deliberately gentle. None of the tool colours
is the red or the mint that a state uses.

| Tool | Colour | Pet |
|---|---|---|
| Claude Code | `#D97757` | A blocky creature: a flat-topped body with two eyes, an arm on each side, four legs, the far pair standing back |
| Codex | `#4F9CF9` | A rounded cloud with a prompt cut into it, `>` and `_`, and a second cloud behind it |
| Gemini CLI | `#9D7BFF` | A four-pointed star, faceted like a cut stone, and a small one far behind it |
| Cursor Agent | `#D7D7DB` | A cube seen from a corner; the light gives each of its three faces its own tone |
| OpenCode | `#F0D9A8` | A terminal window with a sunken screen and a prompt, `>` and `_`, and a second window behind it |
| Aider | `#A3E635` | The letter A made of three tubes: the left stroke nearest, the right one farthest |
| Copilot CLI | `#F27FC0` | A round helmeted head: two goggles with sunken glass, two eyes below them, an ear on each side |

The reliefs and their lighting are in the core package (`AgentPetReliefs`,
`AgentPetFigure`), so every tool is guaranteed a figure and its properties are tested. No
logo file is bundled or downloaded.

The pet moves with its session, and only a little:

- Working: each line is a little longer or shorter, by at most 2.5 % of the figure's
  side (under a point), each at its own slow pace of two to four seconds a cycle. It
  stirs; it does not dance. This is all the motion a working pet has.
- Needs input: it hops by 8 % of its side, twice, together with the status mark's knocks,
  then rests.
- Finished it stands still at full strength; running it is at 70 %, idle at 45 %.
- With Reduce Motion on it never moves.

The pet is 36 pt in the Agents tab's rows and 24 pt in every collapsed agents face.

## 8. Jumping to a session

A row whose session has a `pid` is a button. `AppActivator` walks the parent processes
from that pid to the first one that is a regular app (`NSRunningApplication`, activation
policy `.regular`) and brings it forward with `NSWorkspace.openApplication(at:)`.

A row without a resolvable app (no pid, or a parent chain that ends in `tmux` or
`launchd`) is not a button and shows no press state.

## 9. Error handling

| Situation | Behaviour |
|---|---|
| A tool's directory is missing or unreadable | That provider returns no sessions |
| A file is malformed, too large, or changes while it is read | That file is left out for this tick |
| A session file whose process has died | Left out |
| An unknown status value | The row is shown as `Running` |
| The question text cannot be read | `Needs input` without a second line |
| A provider takes longer than a tick | The next tick is skipped; the list keeps its last value |
| The stored tab order is damaged | Repaired on read (section 5) |
| The hosting app cannot be found | The row is not clickable |

A tool update can change these formats without notice. The readers then fall back as
above; they do not crash and do not show a state they did not read.

## 10. Testing

Core, with `swift test`:

- `ClaudeSessionParser`, `ClaudeTranscriptPromptReader`, `CodexRolloutParser`,
  `CodexSessionIndex`: fixtures written by hand in the shapes observed on 2026-11-14,
  containing no real user content; plus truncated, malformed and unknown-value inputs.
- `AgentProcessMatcher`: every tool's process shapes, and near misses.
- `AgentSessionBoard`: sorting, finished marking, `markSeen`, `attention`, `lead`.
- Tab order: repair of damaged lists, moving a tab to the front.
- Face selection and the tab that opens, for every combination of tab order, media
  state and attention.
- `IslandLayout`: the wings with the new `showsWings` meaning.

App, by the owner's eye:

- Each look of the status mark and the rim light is rendered off screen to images
  before the live check, as the symbiote effect was.
- A hand checklist at the end of the implementation plan.

## 11. Not yet verified

To be checked first in the implementation; each has its fallback here.

- A Claude Code permission prompt also sets `status: "waiting"`. Only a question was
  observed. Fallback: none needed; an unknown status shows `Running`.
- `sessionId` in the session file follows `/clear`. Fallback: no prompt text.
- Scroll events reach a `ScrollView` in the overlay panel. Fallback: no scrolling; the
  two most urgent rows, then a `+N more` line.
- `NSWorkspace.openApplication(at:)` brings another app forward from an agent app on
  macOS 27. Fallback: `NSRunningApplication.activate()`.
- Codex writes an event when it waits for an approval. Fallback: Codex shows only
  working and idle.

## 12. Order of work

1. Core: model, Claude Code parser, board, tab order, face selection.
2. App: Claude Code provider, coordinator, tab strip, Agents tab, `First tab` menu.
3. Status mark, rim light, collapsed faces in the three forms.
4. Codex provider.
5. Process scanner, the five process-level tools, jumping to a session.
6. Research per process-level tool for a state reader.
