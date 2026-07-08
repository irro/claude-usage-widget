# Changelog

All notable changes to the Claude Usage Widget.

## v1.16.0 — 2026-07-07

- **Minimize to system tray.** A new button in the top-right corner (next to
  History/Refresh/Close) hides the widget and parks it in the system tray
  instead of closing it. Hover the tray icon for a live glance at today's
  spend and token count; left-click it to bring the widget straight back to
  the desktop. Right-click gives you Restore/Exit. Also reachable from the
  right-click menu ("Minimize to tray").
- **Fixed a real crash this uncovered**: the widget's main loop used
  `$form.ShowDialog()`, and calling `.Hide()` on a form shown that way ends
  the dialog loop immediately — the whole app would have silently exited the
  instant you clicked minimize. Switched the main loop to
  `[System.Windows.Forms.Application]::Run($form)`, the standard pattern for
  apps that need to hide and later re-show their window.
- The widget now also remembers its exact screen position across a
  minimize/restore cycle, working around a Windows quirk where a hidden/
  re-shown borderless always-on-top window can otherwise land somewhere
  slightly different than where you left it.

## v1.15.3 — 2026-07-07

- **The Tokens/Spend/Local Usage/Model detail pages now have real charts**
  instead of a flat bar-of-divs with no axis or gridlines. Each day-by-day
  trend is now a line+area chart with gridlines, rounded axis labels, a
  hover crosshair + tooltip, and a direct end-label — the Tokens page shows
  Cloud and Local as two distinguishable lines with a legend when you've used
  a local model; the Spend page gets a spend trend it never had before; the
  Local Usage page gets a day-by-day local-tokens trend it never had before.
  All four charts still click through to that day's full detail, same as
  before.
- **Every per-day/per-item table and list on those four pages now ends in a
  bold "Total" row** — the Tokens, Spend, and Model detail tables, and both
  lists on the Local Usage page (local models and local sessions).
- Charts measure their own container width at render time (so on-chart text
  is never stretched) and redraw crisply if the window is resized.

## v1.15.2 — 2026-07-07

- **Fixed: a stray `<synthetic>` entry could show up as a "local model"** in
  the Local model rows / Local Usage page. Claude Code writes this literal
  placeholder as the model id for a client-rendered API-error message (e.g. a
  529 overload) — it's not a real model turn and always carries zero tokens.
  These entries are now skipped everywhere turns are counted (today's totals,
  the all-time scan, and the per-session "last model used" lookup), so they
  can never appear as a fake local model or inflate a turn count.

## v1.15.1 — 2026-07-07

Bug fixes found by an adversarial review of the v1.15.0 changes.

- **Fixed: Recent Local Chats could show empty even with qualifying local
  chats on disk.** The candidate pool `Get-Sessions` scans was previously
  shared between Cloud and Local and capped at a fixed size sorted by overall
  recency — a heavy Cloud day could crowd every Local candidate out of that
  pool entirely. It now keeps walking further back in history until both
  lists are satisfied (still bounded, so it can't scan forever).
- **Fixed: the calendar's browser Back button could skip a level** — going
  Calendar → Day → a model/Tokens/Spend/Local page, then pressing Back, used
  to jump straight to the Calendar instead of back to the Day you came from.
  Every page now tracks its own place in browser history correctly.
- Local Usage page now says explicitly when older local transcripts have been
  pruned (matching the wording already used elsewhere), instead of reading as
  "no local usage" while the all-time total above it is still nonzero.
- Minor hardening: a model name is now HTML-escaped everywhere it's
  displayed, including one spot inside a day's session list that was missed.

## v1.15.0 — 2026-07-07

- **Recent Local Chats is now its own collapsible section**, laid out exactly
  like Recent Cloud Chats (its own "Context Used" header, its own collapse
  arrow, its own context-fill bars) — Local chats had previously been mixed
  into the same list as Cloud chats. Local's context-fill bars auto-detect a
  local-model-appropriate window (8K–256K) instead of Claude's 200K/1K
  windows, since local model sizes vary a lot.
- **Model rows are now split into "Claude Cloud:" and "Local:" groups.** The
  Local group shows the **last 5 distinct local models used today** (e.g.
  different Ollama tags), each with its own token count — not just one
  aggregate "Local" row.
- **A "Local All-Time:" total** now shows in the widget itself, right-justified
  like the Cloud "All Time Usage:" line (previously this was calendar-only).
- **New settings row**: "Recent local chats shown" alongside the existing
  cloud setting, in the calendar's Widget Settings panel.
- **Four new calendar pages**, reached by clicking a summary card or any
  model chip: **Tokens** (day-by-day token trend), **Spend** (all-time spend
  cards + a ranked busiest-days table), **Local Usage** (all-time local
  models + local chat sessions), and a **per-model detail page** (day-by-day
  trend + all-time totals for one model family — reached from any model chip
  in All Chats, a day's model bars, or Usage Windows' model mix).
- **"Patterns" section on the Usage Windows page** — your all-time-high
  reference points (highest day, highest peak-5h, highest trailing-7d) and a
  "today vs. your own high" comparison, computed over your full history.

## v1.14.1 — 2026-07-07

- Added a small **·** marker between the cached/per-token costs, and between
  output/turns/sessions, so the split is visible even when the values
  themselves are short.

## v1.14.0 — 2026-07-07

- **Every row now uses the panel's full width, justified edge to edge**
  instead of being left-aligned with dead space after it: the model rows'
  cost/tokens, the "All Time Usage:" line, the cached/per-token cost line,
  and the output/turns/sessions line all now stretch from the left margin to
  the true right edge.
- **"Recent Chats" is now "Recent Cloud Chats"**, and swapped places with
  "Context Used" — "Context Used" is on the left, "Recent Cloud Chats" is
  right-justified, with the collapse arrow to its right (the very last thing
  in the row).
- **Each model's cost now lines up with where the context bar starts** in
  the recent-chats rows below it, instead of sitting further left.

## v1.13.0 — 2026-07-06

- **Local and Cloud totals are now kept fully separate.** "All Time Usage:"
  (widget + calendar) is now Claude/Cloud tokens only — Local (Ollama etc.)
  tokens never get blended in, since it's a different tokenizer. The
  calendar's home page gets its own "Local (Ollama etc.)" card once you've
  used one, and the Usage Windows page's Day/Trailing-7d columns are
  Cloud-only too (Peak-5h stays combined — hourly detail isn't split by
  model).
- **Bottom-4-lines spacing fixed** — more room between "All Time Usage:" and
  the cost line below it, tighter spacing between the cost line and
  output/turns/sessions, "Updated Xs ago" capitalized.
- **"If Billed Per Token:" value now sits flush against the panel's true
  right edge** instead of floating short of it.
- **Trimmed the trailing whitespace** after each recent chat's token count.

## v1.12.0 — 2026-07-06

- **Removed the "Local AI can only run one chat..." notice banner** from both
  the widget and the calendar's All Chats section.
- **New "Known limitations" list** at the bottom of the calendar's home page —
  what this tool can't track (Claude Design, claude.ai chat/co-work, reasoning
  effort/fast mode) and why, kept in one place. Also added to `START HERE.txt`
  so new installs see it upfront.

## v1.11.0 — 2026-07-06

- **Settings panel in the calendar.** A new panel at the top of the history
  calendar lets you change how many recent chats the widget shows, with
  **Save** and **Update** buttons — it applies immediately, no restart. (The
  widget runs a tiny `127.0.0.1`-only listener to make this possible; it's
  never reachable off your machine.)
- **New "Usage Windows" page** in the calendar. Since Anthropic doesn't
  publish exactly how many tokens you get in a 5-hour / weekly window, this
  tracks **your own observed usage** in each window over time — day totals,
  the busiest 5-consecutive-hour stretch each day, and a trailing 7-day sum —
  so you can spot a pattern if that changes. Reuses data already saved; no
  extra scanning.
- **Local models (e.g. Claude Code pointed at Ollama) are now tracked
  correctly.** Previously a non-Claude model would silently get priced as if
  it were Opus and hidden from the model rows. Now it gets its own **Local**
  row/color, always $0 (never priced), clearly separated from your Claude
  totals.
- Internal: moved maintainer-only docs (`HANDOFF.md`, `PUBLISH.md`) into a
  `Non Deployed Files` folder so they can never accidentally ship.

## v1.10.0 — 2026-07-06

- **Capitalized labels** for readability: "Spent Today · Cached", "If Billed Per
  Token:", "Recent Chats · Context Used" (including the collapsed-header variant).
- **Cleaner bottom spacing.** The four bottom lines (All Time Usage, its costs,
  today's output/turns/sessions, and "updated Xs ago") now read as two clear
  groups with a real gap between them, instead of one cluttered block.
- **New notice banner** above the chats list — in both the panel and the history
  calendar — flagging that local-AI chats run one at a time and can take up to
  5 seconds for an initial reply.
- **Calendar: click a session in a day's detail view** to jump straight to that
  chat's all-time totals in the All Chats list (it scrolls to, expands, and
  briefly highlights the matching row).
- **Desktop + Start Menu shortcuts** now point at wherever you actually keep the
  widget (the installer already offered these; this just makes sure they exist).

## v1.9.0 — 2026-07-05

- **Cleaner layout (a middle/bottom redesign).** The title is now **Claude Usage**,
  and the panel reads top-to-bottom: spend → per-model → recent chats → all-time.
- **Per-model rows show today's tokens.** Each model you've used today (up to four
  — Opus / Sonnet / Haiku / Fable) now shows its cost and **the total tokens it
  used today**, instead of just output tokens.
- **Removed the "rolling usage" section** from the panel (the last-5h/7d/Fable
  windows are still available as cards in the history calendar).
- **Reorganized the bottom.** The all-time figures are now labelled **"All Time
  Usage:"**; the **output / turns / sessions** line sits just below it, left-aligned;
  and **"updated Xs ago"** moved to the very bottom, right-aligned, so it stays out
  of the way.

## v1.8.0 — 2026-07-05

- **Collapsible recent-chats list.** Click the **recent chats** header to fold the
  list away (the chevron flips and it shows the count, e.g. `▸ recent chats (10)`)
  and click again to expand it. Your choice is remembered between launches.
- **Less horizontal white space / a bit narrower.** The panel is narrower, and the
  right-hand figures (the per-token total, each model's output, each rolling
  window's tokens, and each chat's %) now line up in one tidy column instead of
  floating out at the far edge with a gap.

## v1.7.0 — 2026-07-05

- **All-time ticker.** A new line at the very bottom of the panel shows your
  **all-time totals**: total tokens used, plus the cache-aware and per-token cost
  estimates — summed from your saved history. (This is the number that grows into
  the millions and billions over time.)
- **Sortable, collapsible "All Chats".** In the history calendar, the **All Chats**
  catalog can now be **sorted** — Most recent, Name (A–Z), Tokens high→low, or
  Tokens low→high — and the whole section **collapses** with a click on its header.
- **A little narrower**, and the per-chat **context-token count now sits tight
  against the divider** (e.g. `74% │ 743k`) instead of floating with a gap. The
  number is formatted to stay readable as usage grows.

## v1.6.0 — 2026-07-05

- **Archive chats.** A new **archive** action puts a chat away: it disappears
  from the widget's recent-chats list **and** the calendar's "All chats" catalog
  and per-day session cards — but its tokens **still count in every total**
  (today, rolling, all-time, the heatmap, per-model). Right-click a chat →
  **Archive this chat**; right-click → **Unarchive N chats** brings them back.
  Nothing is ever deleted. Stored in `usage-widget-archived.json` (the old
  `usage-widget-hidden.json` from v1.4 is still honoured). *Note:* Claude Code's
  own archive action can't be auto-detected — that state lives in the app's
  internal database, not a readable file — so archiving here is manual.
- **Context tokens on each recent chat.** Every recent-chat row now shows the
  chat's current **context token count** to the right of the percentage, split
  by a thin separator (e.g. `67% │ 670k`) — so you can see both the fraction and
  the absolute size at a glance. The panel is a little wider to fit.
- **Removed the daily "tokens" budget bar.** It was an arbitrary gauge with no
  unique job now that cost, rolling windows, and per-chat context are all shown.
- **Per-model breakdown per chat, in the calendar.** Expanding a chat in the
  "All chats" catalog now shows a **Tokens-by-model table** — for each model
  (Opus/Sonnet/Haiku/Fable): tokens, cost, turns, and output, with a share bar.

## v1.5.0 — 2026-07-05

- **Rolling usage windows.** A new **rolling usage** section shows how much
  you've used in the **last 5 hours** and the **last 7 days** (cost + tokens),
  plus **Fable's** slice of the last 7 days. It's an honest, transcript-derived
  measure of *your usage in that window* — deliberately **not** a plan-limit
  percentage (Claude Code never writes your real rate-limit to disk, so no
  offline tool can show the official 5-hour/weekly meters; this is the faithful
  alternative). The same three figures also appear as cards at the top of the
  history calendar. Configurable via `$Roll5hHours`, `$Roll7dDays`, and
  `$ShowRolling`.
- The rolling data is gathered by the same efficient incremental reader the rest
  of the widget uses, with the per-tick work bounded so it never freezes the
  panel — the rows show "reading…" for a moment on first launch (longer only if
  you have a very heavy week of history), then fill in.

## v1.4.0 — 2026-07-05

- **Remove a chat from the list.** Right-click any chat in the **recent chats**
  section → **Remove this chat from the list** to hide it from the panel. Handy
  for parking finished or noisy chats so the list shows what you care about.
  Hidden chats persist across restarts (`usage-widget-hidden.json`) and can be
  brought back any time via right-click → **Show hidden chats** (also on the
  main menu). This only hides them from the widget — **no transcript is ever
  deleted**.
- **"All chats" catalog in the history calendar.** Under the month grid there's
  now a list of **every chat you still have logs for**, each named as in the
  Claude app. It's a **zebra-striped, collapsed-by-default** list — click any
  row to expand a full breakdown of that chat: total tokens, cache-aware and
  per-token cost, turns, tokens generated, the date range it was active, and a
  per-model bar breakdown. Sort by **Recent** or **Heaviest** (most tokens).
- The calendar's per-day session cards and the catalog now use each chat's app
  title (custom or AI-generated) instead of just its opening prompt.
- Small fix: the recent-chats percentage no longer clips the "%" at exactly 100%.

## v1.3.0 — 2026-07-05

- **Recent chats · context used.** The widget now shows a live list of your up to
  **10 most-recent chat sessions**, each named exactly as in the Claude app
  (its custom or AI-generated title), with a bar for **how full that chat's
  context window is** right now. No more a single context bar that flips as you
  switch chats — every chat is visible at once, green → amber → red as it fills,
  with the percentage alongside. Hover any row for exact tokens, model, and how
  long ago it was active.
- **Auto-detected context window.** Each chat's fill is measured against the
  right window automatically — 200K normally, bumping to **1M** if any recent
  chat is larger (the long-context beta). Override with `$ContextWindowTokens`;
  cap the list with `$MaxSessions`.
- Efficient: each chat is sampled by tail-reading only the end of its transcript,
  cached by modified-time, so idle ticks touch no files and only the chat you're
  actively using is re-read.

## v1.2.1 — 2026-07-03

- **Installer asks about shortcuts.** `Install.cmd` now prompts whether to add a
  **Desktop** shortcut and a **Start Menu** shortcut (both default Yes), instead
  of always creating just the Desktop one.

## v1.2.0 — 2026-06-25

- **Click a day → full detail page.** Every date in the calendar is now
  clickable and opens (in the same tab) a detailed breakdown of that day: day
  totals, a by-model breakdown, an activity-by-hour chart, and — the headline —
  **every chat session that ran that day, individually**, each labelled by its
  opening prompt, with its time range, turns, tokens, cost, and model.
- **Per-session, not per-project.** Replaced the old "by project" view (which was
  useless because every session runs from the same folder) with per-session
  tracking. Sessions are identified by their first user message.
- Browser Back returns to the calendar; the Cost/Tokens toggle applies to the day
  view too.

## v1.1.3 — 2026-06-25

- **"By project" breakdown in the calendar.** The history calendar now shows a
  ranked bar list of how many tokens (or how much cost) each project used — each
  turn is attributed to its working directory. Follows the Cost/Tokens toggle,
  and is persisted to `usage-widget-projects.json` so it survives transcript
  pruning.

## v1.1.2 — 2026-06-25

- **Version shown in the widget.** A small version tag (e.g. `v1.1.2`) now sits
  next to the title, so you can see at a glance which build is running.

## v1.1.1 — 2026-06-25

- **Continuous history auto-save.** Today's total is now written to the
  persistent store (`usage-widget-history.json`) automatically while the widget
  runs (about once a minute, and on close) — not only when you open the calendar.
  So long-term history accrues on its own and survives Claude Code pruning old
  transcripts, even if you never open the calendar.

## v1.1.0 — 2026-06-25

- **History calendar.** A new calendar button (and right-click → "History
  (calendar)") opens a per-day usage calendar in your browser: summary cards
  (all-time spend, if-billed-per-token, busiest day, avg/active-day, total
  tokens), a heat-mapped month grid with month navigation, a Cost/Tokens toggle,
  hover tooltips, and today highlighted. Self-contained dark page matching the
  widget.
- **Persistent history store.** Per-day totals are saved to
  `%USERPROFILE%\.claude\usage-widget-history.json` (kept as the fuller record
  per day), so your history survives Claude Code pruning old transcripts.
- **More accurate counts (dedup).** Turns copied into resumed/forked transcripts
  are now de-duplicated (by message id + request id), so today's figure and the
  calendar no longer double-count. Today's number dropped to its true value.
- **One-click installer.** `Install.cmd` copies the widget to a stable location,
  clears the "downloaded from the internet" flag, adds a Desktop shortcut, and
  launches it — for easy sharing.
- **Desktop icon.** A custom `widget.ico` (dark tile with the green/cyan/amber
  bars) for the Desktop shortcut.

## v1.0.0 — 2026-06-25

First release.

- Always-on-top, draggable, borderless **Windows** panel (PowerShell + .NET
  WinForms). Zero install, no network, no background service.
- **Today's-total dashboard.** Aggregates every Claude Code session since local
  midnight into one stable view — it never flips between sessions, and resets
  each morning.
- Headline **spent today (cache-aware)** cost, plus a raw **if billed per token**
  figure (every token at full list rate, no cache discount).
- **Daily-tokens gauge** against a tunable budget (`$DailyBudgetTokens`).
- **Per-model rows** (Opus / Sonnet / Haiku / Fable) summed across all of today's
  sessions, sub-agents included.
- Footer: total output tokens, turn count, and the number of distinct sessions
  that contributed today.
- **Incremental byte-offset transcript reader** — live refresh in ~25 ms; cold
  start ~5 s. Re-reads only newly-appended bytes of changed files.
- Single-instance mutex (no duplicate panels), double-buffered + opaque labels
  (no flicker), responsive cold start.
- Right-click menu, title-bar refresh (⟳) and close (×), remembered position.

### Notes
- Dollar figures are **estimates at API list prices**, not a bill — on a Max/Pro
  plan you pay nothing per token. Read them as a sense of weight.
- The daily-tokens bar is a tunable gauge, **not** your real plan rate-limit.
- Tracks **Claude Code** usage on this PC only (not claude.ai web/app chats).
- Windows only (WinForms + VBS).
