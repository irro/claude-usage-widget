# Claude Usage Widget

A tiny **always-on-top desktop panel for Windows** that shows your **Claude Code
usage for today** — summed across **every session you've run since midnight**,
so the numbers only grow through the day and reset each morning. Because it's a
daily total rather than a single session, it never flips between sessions —
everything stays put and just climbs as you work. Shown all at once:

- **Spent Today · Cached** — the big headline number: a cache-aware estimate,
  the way a real API bill works with prompt caching (cache reads ~90% off)
- **If Billed Per Token:** — the raw "sticker" price: every token at full list
  rate, no cache discount (always the larger number)
- **a row for every model used today** — up to five (Opus, Sonnet, Haiku, Fable,
  and **Local** if you ever point Claude Code at a local model like Ollama),
  each with that model's cache-aware cost — **lined up with where the context
  bar starts** in the recent-chats rows below — and **the total tokens it used
  today** (Local always shows $0 — it's never priced)
- **Context Used · Recent Cloud Chats** — a live list of your up to **10
  most-recent chat sessions**, each named exactly as in the Claude app (its
  custom or AI-generated title) with a bar for **how full that chat's context
  window is** right now (green → amber → red as it fills), the **percentage**,
  and the **absolute context-token count** beside it (e.g. `67% │ 670k`). See
  every chat's context at a glance instead of one bar that flips as you switch
  chats; hover a row for model + last-active time. **Right-click a chat →
  Archive** to put it away (see below), or **click the section header to
  collapse the list** (click anywhere on it — including the collapse arrow at
  the far right)
- **archive** — archiving a chat drops it from the recent-chats list **and** the
  calendar's catalog and day cards, but its tokens **still count in every total**.
  Nothing is deleted; right-click → *Unarchive N chats* restores them
- **All Time Usage** — near the bottom, your **all-time Claude/Cloud** total
  tokens (right-justified to the panel's edge) and both cost estimates
  (cache-aware and per-token, one on each side of the row), summed from your
  saved history — the figure that climbs into the millions and billions.
  **Local (Ollama etc.) tokens are never mixed into this** — a different
  tokenizer, always $0, tracked separately (see the calendar for its own
  total). Just below it: the day's **output / turns / sessions**, spread
  evenly left/center/right across the row, and — right-aligned on the very
  bottom line — how fresh the reading is (**Updated Xs ago**)
- **history calendar** — click the calendar button for a per-day usage calendar:
  a heat-mapped month grid, all-time summary cards, **rolling-usage cards**
  (last 5h / 7d / Fable), and a Cost/Tokens toggle. **Click any day** for a full
  breakdown — by model, by hour, and **every chat session individually**; **click
  a session card** there to jump straight to that chat's all-time totals. Under
  the grid, a collapsible **All Chats** catalog lists every chat you still have
  logs for — a zebra-striped list you can **sort** (Most recent, Name A–Z, Tokens
  high→low, or low→high); expand a row for its tokens, cost, turns, active date
  range, and a **per-model table** (tokens/cost/turns/output for each model)
- **a settings panel at the top of the calendar** — change how many recent
  chats the widget shows, with **Save** and **Update** buttons; applies
  immediately, no restart (talks to a tiny `127.0.0.1`-only listener the
  widget runs while it's open — never reachable off your machine)
- **a "Usage Windows" page** — since Anthropic doesn't publish exactly how
  many tokens you get in a 5-hour / weekly window, this tracks **your own
  observed usage** in each window over time (day totals, the busiest
  5-consecutive-hour stretch each day, and a trailing 7-day sum) so you can
  spot a pattern if it ever changes. Reuses data already saved, no new scanning
- **a "Known limitations" list** at the bottom of the calendar's home page —
  what this tool genuinely can't track (Claude Design, claude.ai chat/co-work,
  reasoning effort/fast mode) and why, kept in one place and shown on first
  install too

It's a single small PowerShell program. No installer, no dependencies, no
network, no background service — it just reads the transcript files Claude Code
already writes to disk.

```
┌──────────────────────────────────────┐
│ Claude Usage v1.14.1    🗓  ⟳   ×      │
│ Spent Today · Cached                   │
│ $480.44                                │
│ If Billed Per Token:       $2,256.56   │
│ ────────────────────────────────────── │
│ Opus              $480.44        1.04B │
│ Fable               $14.83       29.6M │
│ ────────────────────────────────────── │
│ Context Used     Recent Cloud Chats ▾  │
│ Hearth        ▓▓▓▓░░░  41% │ 410k       │
│ United Dise…  ▓▓▓▓▓▓▓  95% │ 950k       │
│ …up to 10 (right-click → archive)      │
│ ────────────────────────────────────── │
│ All Time Usage:         6.38B tokens   │
│ $5,528.96 cached    · $31,343.45/token │
│ ↓ 1.9M output · 739 turns · 6 sessions │
│                        Updated 1s ago  │
└──────────────────────────────────────┘
```

Click the **Recent Cloud Chats** header (or the ▾ arrow to its right) to
collapse the list (`Recent Cloud Chats (10) ▸`) and again to expand it — your
choice is remembered.

Only models you've actually used today get a row, so the panel grows or shrinks
to fit — no empty placeholders. The **recent-chats** list shows up to 10 of your
latest sessions (cap it with `$MaxSessions`).

## Why a floating window instead of a real sidebar item?

Nothing can inject a widget *inside* the Claude Code app's sidebar — that part
of the UI isn't extendable by any plugin. This is the faithful workaround: a
separate always-on-top chip you drag wherever you want it (many people park it
at the bottom-left, next to the account/settings area).

## Requirements

- **Windows 10 or 11** — uses built-in Windows PowerShell + .NET WinForms.
- **Claude Code**, used at least once today. The widget reads the local session
  transcripts Claude Code writes under `%USERPROFILE%\.claude\projects\`.

That's it. It never makes a network connection.

## Install & run

**Easiest — one-click install.** Unzip the folder, then double-click
**`Install.cmd`**. It copies the widget to a stable spot, clears the "downloaded
from the internet" flag (so nothing gets blocked), **asks whether to add a
Desktop and/or Start Menu shortcut** (both default Yes), and launches it. If
Windows shows a "Windows protected your PC" box, click **More info → Run anyway**
(it's a small, readable script).

**Or run it in place.** Prefer not to install? Just double-click
**`Start Widget.vbs`** to run it straight from the folder. Only one copy ever
runs, so double-clicking again won't stack duplicates.

*(Optional)* Double-click **`Add to Startup.cmd`** to launch it automatically
every time you sign in. **`Remove from Startup.cmd`** undoes it.

Using it: drag the panel anywhere; the **calendar** button opens your history,
the **⟳** re-scans now, and the **×** (or right-click → **Exit**) closes it.

> **If Windows blocks the `.vbs`/`.cmd`** (only if you skipped `Install.cmd`,
> which unblocks for you): right-click the file → **Properties** → tick
> **Unblock** → OK.

## Keeping it running day to day

The widget keeps running until you close it or restart the PC (it survives
sleep, so leaving the machine on is fine — it's still there when you come back).
At midnight the totals reset and start counting the new day.

- **Bring it back any time:** double-click `Start Widget.vbs` again — same as
  the first launch.
- **Never think about it again:** double-click `Add to Startup.cmd` once. After
  that it launches automatically at every Windows sign-in, so the day after a
  shutdown or reboot you just log in and it's already running.

Auto-start only fires at sign-in — if you close the widget mid-session, it
won't reappear on its own until your next login; relaunch with
`Start Widget.vbs`.

## The two dollar figures

Both are **estimates at API list prices** — if you're on a Max/Pro plan you pay
nothing per token, so read them as "what today would cost on the pay-as-you-go
API," a sense of weight rather than a bill.

- **Spent Today · Cached** is the realistic one. Real API billing charges cache
  *reads* at ~10% of the input rate and cache *writes* at a small premium, and
  Claude Code caches aggressively — so this is what a per-token API bill would
  actually total for today's work.
- **If Billed Per Token:** strips the caching cleverness away: it prices *every*
  input, cache-read, cache-write and output token at full list rate. It's the
  honest "sticker price" of the raw token volume that flowed — usually several
  times the cached figure, because ~90% of tokens are cache reads.

Both numbers (and the per-model rows) include work done by any sub-agents your
sessions spawned (Explore/Task/parallel helpers).

## How it works

Every turn, Claude Code appends your conversation — including exact token counts
and a timestamp — to a transcript `.jsonl` under
`%USERPROFILE%\.claude\projects\`. The widget looks at every transcript touched
today (plus any `subagents\*.jsonl` beside them), and for each one reads **only
the bytes appended since it last looked**, keeping a per-file running total of
the turns timestamped *today*. It sums those into one daily figure and buckets
cost + output **by model family**. From that it paints the headline cost, one
row per model used today, the raw cost, and the footer.
Because it only re-reads new bytes, even a busy live session refreshes in a few
milliseconds — it's effectively free to leave running. At local midnight the
counters reset and the new day begins.

The **recent-chats** list works differently: for each of your most-recent chat
sessions it reads only the **tail** of that chat's transcript to find the last
turn's context size (input + cache + the reply = the tokens then in the model's
context) and the chat's title as the app shows it (its custom or AI title).
Tail reads are cached by the file's modified-time, so an idle second touches no
files and only the chat you're actively working in gets re-read. The percentage
is that context measured against the window — 200K, or 1M if any recent chat is
bigger (the long-context beta), detected automatically.

The **history calendar** does a fuller (de-duplicated) scan of every transcript,
buckets it per day, and merges the result into a persistent store
(`usage-widget-history.json`) that keeps the fuller record for each day — so your
history survives even after Claude Code prunes old transcripts. It then renders
the calendar from `calendar-template.html` and opens it in your browser.

## Configuring

Open `usage-widget.ps1` in any text editor:

- **`Get-Price`** — per-model list rates used for the cost estimates. The
  cache-aware figure derives cache rates from the input rate (read 0.1×,
  write-5m 1.25×, write-1h 2×); the per-token figure uses the input rate flat.
  Edit if prices change.
- **`$FamColor` / `$FamOrder`** — the colour and ordering of the per-model rows.
  Every family in `$FamOrder` with usage today is shown automatically. `Other`
  (unknown model ids) has no row by design, but its tokens still count in the
  totals.
- **`$MaxSessionsDefault`** (default `10`) — how many recent chats the **Recent
  Chats · Context Used** list shows, until you change it from the calendar's
  settings panel (which writes `usage-widget-settings.json` and takes effect
  immediately — no restart). `$MaxSessionsCap` (`50`) is the hard ceiling.
- **`$SettingsPort`** (default `8907`) — the `127.0.0.1`-only port the
  settings panel talks to. Change it if something else on your machine
  already uses that port.
- **`$ContextWindowTokens`** (default `0` = auto) — the window each chat's
  context bar is measured against. Auto picks 200K, bumping to 1M if any recent
  chat exceeds 200K (the long-context beta). Set a fixed number (e.g. `200000`
  or `1000000`) to force it. Tiers live in `$CtxWindowTiers`.
- **`$Roll5hHours` / `$Roll7dDays`** (default `5` / `7`) — the two rolling
  windows shown as cards in the **history calendar** (the panel itself no longer
  has a rolling section).

## Why not the real 5-hour / weekly / Fable meters?

Claude Code shows official plan meters (the 5-hour session limit, the weekly
all-models limit, the weekly Fable limit) in its `/usage` view. Those percentages
come **live from Anthropic's API** and are **never written to any local file** —
so a standalone, offline, transcript-only tool like this one genuinely cannot
read them without making authenticated network calls, which would break its
no-network promise. The **rolling-usage cards** in the history calendar are the
honest alternative: they
sums *your* actual token usage in the last 5 hours / 7 days from the transcripts.
It tells you how heavily you've been working in those windows — it just can't
know your plan's remaining percentage.

## Files

| File | Purpose |
|------|---------|
| `usage-widget.ps1` | The widget itself |
| `calendar-template.html` | Template the history calendar is generated from |
| `widget.ico` | Icon for the Desktop shortcut |
| `Install.cmd` / `install.ps1` | One-click install (copy + unblock + Desktop icon + launch) |
| `Start Widget.vbs` | Double-click to launch in place (no console flash) |
| `Add to Startup.cmd` | Launch automatically at sign-in |
| `Remove from Startup.cmd` | Undo auto-launch |
| `START HERE.txt` | Quick-start for first-time users |
| `admin-instructions.html` | Friendly illustrated guide (with a mockup) |
| `README.md` / `CHANGELOG.md` | This file / version history |
| `HANDOFF.md` | Maintainer's guide: architecture, gotchas, how to edit/restart |

The widget also writes small files under `%USERPROFILE%\.claude\`:
`usage-widget-pos.txt` (window position), `usage-widget-history.json` (the
per-day history store), `usage-widget-archived.json` (chats you archived), and
`usage-widget-calendar.html` (the generated calendar).

## License

MIT — see `LICENSE`. Do whatever you like with it.
