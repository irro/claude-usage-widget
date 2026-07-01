# Claude Usage Widget

A tiny **always-on-top desktop panel for Windows** that shows your **Claude Code
usage for today** — summed across **every session you've run since midnight**,
so the numbers only grow through the day and reset each morning. Because it's a
daily total rather than a single session, it never flips between sessions —
everything stays put and just climbs as you work. Shown all at once:

- **spent today (cached)** — the big headline number: a cache-aware estimate,
  the way a real API bill works with prompt caching (cache reads ~90% off)
- **if billed per token** — the raw "sticker" price: every token at full list
  rate, no cache discount (always the larger number)
- **tokens** — today's cumulative tokens (input + output + cache) as a bar
  against a configurable daily budget — a "how heavy is today" gauge
- **a row for every model used today** — Opus, Sonnet, Haiku, Fable, … each with
  that model's cache-aware cost and the tokens it generated
- **output / turns / sessions** — total tokens generated, assistant-turn count,
  and how many distinct sessions contributed today, plus how fresh the reading is
- **history calendar** — click the calendar button for a per-day usage calendar:
  a heat-mapped month grid, summary cards (all-time spend, busiest day, averages,
  total tokens), a Cost/Tokens toggle, and hover-for-details

It's a single small PowerShell program. No installer, no dependencies, no
network, no background service — it just reads the transcript files Claude Code
already writes to disk.

```
┌────────────────────────────────────────┐
│ Claude usage                  ⟳    ×     │
│ spent today · cached                     │
│ $480.44                                  │
│ if billed per token          $2,256.56   │
│ ──────────────────────────────────────── │
│ tokens ▓▓▓░░░░░░░░░   443.6M / 2.00B      │
│ Opus       $480.44             ↓ 1.9M     │
│ ──────────────────────────────────────── │
│ ↓ 1.9M output · 739 turns · 6 sessions    │
│ updated 1s ago                           │
└────────────────────────────────────────┘
```

Only models you've actually used today get a row, so the panel grows or shrinks
to fit — no empty placeholders.

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
from the internet" flag (so nothing gets blocked), drops a **Desktop shortcut**
with a matching icon, and launches it. If Windows shows a "Windows protected your
PC" box, click **More info → Run anyway** (it's a small, readable script).

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

- **spent today · cached** is the realistic one. Real API billing charges cache
  *reads* at ~10% of the input rate and cache *writes* at a small premium, and
  Claude Code caches aggressively — so this is what a per-token API bill would
  actually total for today's work.
- **if billed per token** strips the caching cleverness away: it prices *every*
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
cost + output **by model family**. From that it paints the headline cost, the
daily-tokens bar, one row per model used today, the raw cost, and the footer.
Because it only re-reads new bytes, even a busy live session refreshes in a few
milliseconds — it's effectively free to leave running. At local midnight the
counters reset and the new day begins.

The **history calendar** does a fuller (de-duplicated) scan of every transcript,
buckets it per day, and merges the result into a persistent store
(`usage-widget-history.json`) that keeps the fuller record for each day — so your
history survives even after Claude Code prunes old transcripts. It then renders
the calendar from `calendar-template.html` and opens it in your browser.

## Configuring

Open `usage-widget.ps1` in any text editor:

- **`$DailyBudgetTokens`** (default `2000000000` = 2B) — what the **tokens** bar
  is measured against. A transcript-only widget can't read your real plan
  rate-limit (that lives only in Claude Code's status-line payload), so this is
  a tunable "how heavy is today" gauge. The default is set so an ordinary day
  sits low-to-mid and only a marathon day fills the bar. Lower it if you want
  the bar more sensitive.
- **`Get-Price`** — per-model list rates used for the cost estimates. The
  cache-aware figure derives cache rates from the input rate (read 0.1×,
  write-5m 1.25×, write-1h 2×); the per-token figure uses the input rate flat.
  Edit if prices change.
- **`$FamColor` / `$FamOrder`** — the colour and ordering of the per-model rows.
  Every family in `$FamOrder` with usage today is shown automatically. `Other`
  (unknown model ids) has no row by design, but its tokens still count in the
  totals.

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

The widget also writes small files under `%USERPROFILE%\.claude\`:
`usage-widget-pos.txt` (window position), `usage-widget-history.json` (the
per-day history store), and `usage-widget-calendar.html` (the generated calendar).

## License

MIT — see `LICENSE`. Do whatever you like with it.
