# Subagent branches, a larger island, an amber question, a faster clear

Date: 2026-11-15
Status: approved by the owner on 2026-11-15.
Extends: `2026-11-14-agents-tab-design.md` (sections 4, 6.1, 6.2, 6.4, 7.1, 7.2, 7.4) and
`2026-11-14-side-docking-design.md` (open size at a side edge).

## 1. Goal

1. When a Claude Code or Codex session runs subagents, its row in the Agents tab grows
   branches, one under the other, like a fork: each subagent's name and how long it has
   run, or that it is done.
2. The open island is larger: 600 × 150 instead of 540 × 134.
3. A session that waits for the user is shown in amber, not red. Red read as a failure.
4. After the user answers a question, the island stops showing it at once, not 1–3 s
   later.

## 2. Owner's decisions (2026-11-15)

| Topic | Decision |
|---|---|
| Look | Branch lines under the session row (`├─`, `└─`), each with the subagent's name and time. At most three lines; with more subagents, two lines and `+N more` |
| A finished subagent | Stays, dimmed, with a mint `Done` until the parent's turn ends; then it is removed. Working ones come first |
| Height | The island keeps one size while open; a session with branches may fill the list on its own and the next session is reached by scrolling |
| Size | Open island 600 × 150 ("adanın boyunu da uzatalım biraz kısa geldi"); at a side edge 600 × 170 |
| Question color | Amber `#FFD60A` ("kırmızı olmasın, sanki fail olmuş gibi duruyor") |
| Collapsed island | No subagent indicator |

## 3. Constraints carried over

All of `2026-11-14-agents-tab-design.md` section 3 holds: read-only, no hooks, no new
dependency, no permission prompt, user content never logged. Subagent names are user
content (the parent writes them) and are never logged either. No view redraws frame by
frame at rest: the branches add no animation.

## 4. Model (core)

```swift
/// One subagent of a session.
public struct AgentSubagent: Identifiable, Equatable, Sendable {
    /// The tool's own id for the subagent.
    public let id: String
    public let title: String
    public let isFinished: Bool
    /// When it started while it works; when it finished once it is done.
    public let since: Date
}

// AgentSession gains, defaulting to []:
public var subagents: [AgentSubagent]

/// What a row shows below itself.
public enum AgentBranch: Equatable, Sendable {
    case subagent(AgentSubagent)
    case more(Int)
}

// AgentRow gains:
public let branches: [AgentBranch]
```

`AgentSessionBoard` decides the branches. It already remembers which sessions are
active (working or needs input); it now also remembers each active session's turn start:
the session's `since` on the update where it became active (or was first seen active).
The turn start is kept while the session stays active, so a question in the middle of a
turn does not move it. It is forgotten when the session stops being active.

A row's branches, in `AgentBranches.lines(for:state:turnStart:)`:

1. Working subagents, oldest start first.
2. Finished subagents, newest finish first, only while the row's state is `working` or
   `needsInput` and only those that finished at or after the turn start. When the parent
   becomes idle, `finished` or `running`, they are gone.
3. Three lines or fewer: all of them. More: the first two, then `more(N)` for the rest.

A working subagent is shown whatever its parent's state: a background subagent can run
on after its parent's turn has ended.

## 5. Providers

### 5.1 Claude Code (verified on 2026-11-15, version 2.1.325)

- Folder: `~/.claude/projects/<cwd with "/" replaced by "-">/<sessionId>/subagents/`,
  next to the transcript the provider already reads. One pair per subagent:
  `agent-<id>.meta.json` and `agent-<id>.jsonl`. The folder is read only for sessions
  that are listed.
- `meta.json` (at most 16 KB): `description` is the title; else `agentType`; else
  `Subagent`. `finished: true` means done. While the subagent runs the key is absent;
  it is added when it ends normally (seen live: a background subagent's meta file
  without `finished` while it slept, with `finished: true` after).
- Start: the creation time of `agent-<id>.jsonl`, which is created at the spawn and only
  appended to. The meta file is replaced when the subagent finishes, so its creation time
  is the finish; its modification time is used as the finish time.
- A stopped subagent never gets `finished` (seen live: stopped with `TaskStop`, its meta
  file stayed without the key). Two signs that it has ended, read from the last 256 KB of
  the parent's transcript, which is read only while the session has at least one
  subagent without `finished`, and again only when the transcript's size or time changed:
  - a background subagent (`requestShape: "background"`): a `<task-id><id></task-id>`
    line (a `task-notification`, any status);
  - any other: a `tool_result` whose `tool_use_id` is the meta file's `toolUseId`.
  An ended subagent without `finished` is left out. Its id is remembered for the session,
  so it stays out when the sign scrolls out of the 256 KB.
- A subagent without `finished` whose `.jsonl` has not changed for 10 minutes is left out.
- Finished subagents are passed only if they finished in the last 2 hours; the board
  narrows them to the current turn.
- A meta file is parsed again only when its size or time changed.

### 5.2 Codex (verified on 2026-11-15, rollouts of Codex Desktop 0.169)

- A rollout whose `session_meta.payload.source.subagent.thread_spawn` exists is a
  subagent; until now such rollouts were left out. Its parent is
  `thread_spawn.parent_thread_id`, else `payload.parent_thread_id`.
- Title: the last component of `thread_spawn.agent_path` (`/root/notch_market_research`)
  with `_` and `-` turned into spaces, `notch market research`; else `agent_nickname`;
  else `Subagent`.
- A subagent hangs under the listed session it descends from: parents are followed through
  the rollouts already read. If none of them is a listed session it is left out.
- State, from the same turn events as a thread: `task_started` last → working, `since` is
  the `session_meta` line's `timestamp`; `task_complete` last → finished, `since` is that
  event's time; `turn_aborted` last → left out.
- A working subagent whose rollout has not changed for 10 minutes is left out.

## 6. Appearance

### 6.1 Size

- `IslandLayout.expandedSize` becomes 600 × 150. At the notch, the island is still at
  least as wide as the notch.
- At a side edge the open island is 600 × 170: as tall as the strip, as before.
- The Media tab keeps its layout; it gains room around it.

### 6.2 Branches

- A branch line is 16 pt tall, below the 46 pt row, inside the same block.
- The connector is drawn at the pet's centre (28 pt from the row's leading edge): a 1 pt
  vertical line from under the pet to the last branch, and an 8 pt tick into each line,
  white 22 %. The last line's vertical ends at its tick (`└─`).
- Name: 11 pt, white 70 %, one line, truncated at the end. A finished subagent's name is
  white 40 %.
- Trailing end, aligned with the row's label: working → its time, `2m` (same format as
  the row labels, 10 pt monospaced digits, white 50 %); finished → `Done` and an 8 pt
  `checkmark`, mint.
- `more(N)`: `+N more`, 11 pt, white 45 %, no trailing text.
- Colour (owner, 2026-11-15: "her bir forka farklı renkler de verelim"; chose the parent
  pet's tones): each subagent line's tick and a 4 pt dot at its end take one of three tones
  of the parent tool's pet colours (`AgentPalette.tint(for:across:)` at 0, 0.5 and 1;
  Claude: peach, orange, brick). A subagent's tone comes from a stable hash of its id
  (FNV-1a, the same in every run); a tone a line above already took passes to the next free
  one, so up to three lines never share a colour. Working: 90 %; finished: 45 %. The vertical
  stays white 22 %; `+N more` has a white tick and no dot. Names stay white.
- The branches belong to the row's button: a click anywhere in the block brings the
  session's app forward.
- Accessibility: each branch line is labelled `Subagent <name>, working 2m`,
  `Subagent <name>, done` or `<N> more subagents`, and is read as part of its row.

### 6.3 List

- Each block (row and branches) is one scroll target; the list comes to rest on a block.
- The viewport is as tall as the first two blocks with their spacing, but never taller
  than the space below the header (less a 6 pt bottom margin). One or two blocks that fit
  are centred, as before. When the blocks are taller than the viewport the lower edge
  fades out, as before.

### 6.4 Question color

`AgentPalette.alert` becomes amber `#FFD60A` (255, 214, 10). Every use follows: the status
mark's ring and knocking dot, the rim light, the tab strip's dot, a row's leading bar and
its 12 % background, and the `Needs input` label. OpenCode's pet runs from pale yellow to
orange; it never shows `Needs input` (process level only), so the two never meet.

## 7. Faster scans

Measured on 2026-11-15: Claude Code wrote `status: "busy"` 0.1 s before the answer reached
its transcript, and it writes the session file only when the status changes
(`updatedAt == statusUpdatedAt` during a long busy turn). The delay was the coordinator:
while the Agents tab is not on screen it scans every 3 s.

- `SessionFolderWatcher` (app target) runs an FSEvents stream on `~/.claude/sessions` with
  file-level events, no defer, 0.05 s latency, on a private queue. Any event wakes the
  coordinator. If the folder cannot be watched (missing), each scan tries again.
- The coordinator waits through a `ScanSignal` instead of plain sleeps: a wait of up to
  1 s, repeated up to 3 times at rest and once while the Agents tab is on screen, that a
  wake ends at once. A wake that comes while no one waits is kept for the next wait.
- Two scans start at least 0.25 s apart (`ScanPacing`, core, tested).
- Codex is not watched: it never reports needs input, and its rollouts are written all
  through a turn.
- Target: the needs-input look ends within 0.3 s of the answer.

## 8. Error handling

| Situation | Behaviour |
|---|---|
| The subagents folder is missing or unreadable | No branches |
| A meta file is malformed or too large | That subagent is left out |
| No `.jsonl` beside a meta file | Start time: the meta file's creation time |
| A stopped subagent whose end sign was never seen | Left out after 10 minutes without a write |
| A Codex subagent whose parent is unknown | Left out |
| The sessions folder cannot be watched | Scans run on the old timer; the watcher retries |

## 9. Testing

Core, with `swift test`:

- `ClaudeSubagentParser`: meta fields, title fallbacks, `finished`, oversize and malformed
  input; the end signs in a transcript tail (task notification, tool result, neither).
- `CodexRolloutParser`: subagent meta with parent and title; `turn_aborted`.
- `AgentBranches` and `AgentSessionBoard`: turn start kept through a question, finished
  subagents before the turn start left out, cleared when the parent goes idle, working
  subagents under an idle parent, ordering, the three-line limit.
- `ScanPacing`: the minimum gap.
- `IslandLayout`: 600 × 150, and 600 × 170 at a side edge.

App, by the owner's eye: a hand checklist at the end of the plan, including the measured
time from answering a question to the island clearing.

## 10. Not yet verified

- A foreground Claude Code subagent interrupted with Esc gets a `tool_result` in the
  parent's transcript. Fallback: the 10-minute rule.
- A nested Claude Code subagent (spawn depth 2) writes to the same `subagents` folder.
  Fallback: it is not shown.
- Codex subagents deeper than one level. Fallback: the parent walk; unknown → left out.
