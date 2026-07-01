# Changelog

All notable changes to the Claude Usage Widget.

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
