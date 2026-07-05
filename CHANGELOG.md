# Changelog

All notable changes to the Claude Usage Widget.

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
