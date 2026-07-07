# Claude Usage Widget  -  always-on-top desktop panel (transcript-driven)
# ---------------------------------------------------------------------------
# TODAY'S TOTAL dashboard. It sums EVERY Claude Code session you've used since
# local midnight (all transcripts + their sub-agents) into one stable view, so
# it never flips between sessions - the numbers only grow through the day and
# reset each morning. Shows, all at once:
#   * a big "spent today" figure  - cache-aware API estimate (the realistic one)
#   * "if billed per token"        - raw sticker cost, no cache discount
#   * a daily-tokens gauge         - today's tokens vs a tunable daily budget
#   * one row per model family used (Opus/Sonnet/Haiku/Fable) - cost + output
#   * a footer  - total output, turns, distinct sessions, and freshness
#   * recent chats - up to 10 of your most-recent chat sessions (named exactly
#     as in the Claude app), each with a live "context used" bar showing how
#     full that chat's context window is - so you can see every chat at once
#     instead of one bar that flips as you switch chats
# Reads *.jsonl under %USERPROFILE%\.claude\projects\ incrementally (only the
# newly-appended bytes of changed files), so even a busy live session stays
# smooth. Drag anywhere to move; the round arrow refreshes; x closes.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Single-instance guard: if a widget is already running, this launch exits
# quietly (prevents stacked duplicate panels). The mutex is held for the life
# of the process and released automatically on exit.
$script:singleInstance = New-Object System.Threading.Mutex($false,'Global\ClaudeUsageWidget_SingleInstance')
try { $gotInstance = $script:singleInstance.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $gotInstance = $true }   # prior crash left it abandoned -> take it
if(-not $gotInstance){ return }

$ProjRoot = Join-Path $env:USERPROFILE '.claude\projects'
$PosPath  = Join-Path $env:USERPROFILE '.claude\usage-widget-pos.txt'
# History calendar: a persistent per-day datastore (survives transcript pruning)
# and the generated calendar page; the template ships beside this script.
$HistPath = Join-Path $env:USERPROFILE '.claude\usage-widget-history.json'
$CalOut   = Join-Path $env:USERPROFILE '.claude\usage-widget-calendar.html'
$CalTpl   = Join-Path $PSScriptRoot 'calendar-template.html'
# Chats the user has archived (session ids). Archived chats drop out of the
# widget + calendar session lists but still count in every total; never deleted.
$ArchivePath = Join-Path $env:USERPROFILE '.claude\usage-widget-archived.json'
$LegacyHiddenPath = Join-Path $env:USERPROFILE '.claude\usage-widget-hidden.json'  # v1.4 name, still honoured
$Version  = '1.15.0'   # bump on each release; shown next to the title in the widget

# --- pricing (USD per 1M tokens, current-generation list prices) ----------
# Each turn is priced by its own model. Cache rates are derived from the input
# rate: read = 0.1x, write-5m = 1.25x, write-1h = 2x. Edit here to adjust.
function Get-Price($m){
    switch -Wildcard ($m){
        'claude-fable-*'  { return @{ In=10.0; Out=50.0 } }
        'claude-mythos-*' { return @{ In=10.0; Out=50.0 } }
        'claude-opus-*'   { return @{ In=5.0;  Out=25.0 } }
        'claude-sonnet-*' { return @{ In=3.0;  Out=15.0 } }
        'claude-haiku-*'  { return @{ In=1.0;  Out=5.0  } }
        'claude-*'        { return @{ In=5.0;  Out=25.0 } }   # unrecognized Claude model -> Opus-tier guess
        default           { return @{ In=0.0;  Out=0.0  } }   # not a Claude model at all (e.g. Claude Code pointed
                                                                # at a local Ollama model via ANTHROPIC_BASE_URL) ->
                                                                # always free, never priced - see Family() below
    }
}

# Group a model id into a display family for the per-model usage rows.
function Family($m){
    # NOTE: PowerShell's switch runs EVERY matching clause, not just the first
    # (no implicit break, unlike C/JS) - each clause needs an explicit break or
    # a broader later pattern (like 'claude-*') would ALSO fire after a more
    # specific one already matched, returning a 2-element array instead of one.
    switch -Wildcard ($m){
        'claude-opus-*'   { 'Opus';   break }
        'claude-sonnet-*' { 'Sonnet'; break }
        'claude-haiku-*'  { 'Haiku';  break }
        'claude-fable-*'  { 'Fable';  break }
        'claude-mythos-*' { 'Fable';  break }
        'claude-*'        { 'Other';  break }   # unrecognized Claude model
        default           { 'Local' }            # not a Claude model - a locally-run model (e.g. qwen via Ollama), always $0
    }
}

# --- recent-chats context list --------------------------------------------
# The "recent chats" section shows your most-recent chat sessions, each with a
# bar for how full its context window is (last turn's input + cache tokens).
$MaxSessionsDefault = 10   # fallback if no settings file exists yet; edit here to change the built-in default
$MaxSessionsCap = 50       # hard upper bound - how many chat-row controls the widget ever creates
$script:MaxSessions = $MaxSessionsDefault   # LIVE value; loaded from the settings file at startup, and
                                            # changeable at runtime from the calendar's settings panel
# Same idea, for LOCAL (e.g. Ollama) chats - a separate list, own cap, own count.
$MaxLocalSessionsDefault = 5
$MaxLocalSessionsCap = 50
$script:MaxLocalSessions = $MaxLocalSessionsDefault
$SettingsPath = Join-Path $env:USERPROFILE '.claude\usage-widget-settings.json'
$SettingsPort = 8907       # 127.0.0.1-only local listener the calendar's settings panel talks to
# Context window each CLOUD chat's fill is measured against. 0 = auto-detect: 200K
# normally, bumping to 1M if any recent chat exceeds 200K (i.e. the long-context
# beta is on). Set a fixed number (e.g. 200000 or 1000000) to override.
$ContextWindowTokens = 0
# Standard windows auto-detect chooses between (smallest that fits the fullest
# chat wins). Add more here if larger windows appear.
$CtxWindowTiers = @(200000, 1000000)
# Same auto-detect, for LOCAL chats - kept separate because local model context
# windows are all over the map (8K-256K+ depending what you run) and nowhere near
# Claude's 200K/1M tiers - e.g. a "qwen3:8b-32k" tag literally names its own size.
$LocalContextWindowTokens = 0
$LocalCtxWindowTiers = @(8192, 16384, 32768, 65536, 131072, 262144)

# --- rolling windows (calendar only) ---------------------------------------
# The history calendar shows "last 5h / 7d / Fable-7d" rolling-usage cards; these
# set those windows. (The widget itself no longer shows a rolling section.)
$Roll5hHours = 5           # "last 5h" window length
$Roll7dDays  = 7           # "last 7d" window length

# --- state ----------------------------------------------------------------
$script:files     = @{}     # path -> per-file accumulator (today only)
$script:curDay    = $null   # 'yyyy-MM-dd' the accumulators belong to
$script:seenToday = @{}     # message.id|requestId -> 1 (dedup resumed/copied turns)
$script:layoutKey = $null
$script:data      = $null   # latest today aggregate (for the on-close save)
$script:lastPersist = $null # last time today's total was written to the history store
$script:sessCache = @{}     # path -> cached tail read {mtime,ctx,model,tstamp,title}
$script:archived  = @{}     # session-id -> 1 for archived chats (out of lists, still in totals)
$script:sessCollapsed = $false  # recent-chats list collapsed? (persisted in the pos file)
$script:sessCollapsedLocal = $false  # same, for the Local recent-chats list (persisted in the pos file)
$script:allTime    = $null  # cached all-time totals @{tok;cost;raw}
$script:allTimeAt  = $null  # last all-time recompute time
$script:settingsListener = $null  # the 127.0.0.1 HttpListener (Start-SettingsServer)
$script:settingsAsync    = $null  # pending IAsyncResult, polled each timer tick (Poll-SettingsServer)

# --- palette --------------------------------------------------------------
$cBg     = [System.Drawing.Color]::FromArgb(22,27,34)
$cDim    = [System.Drawing.Color]::FromArgb(139,148,158)
$cCyan   = [System.Drawing.Color]::FromArgb(57,197,207)
$cGreen  = [System.Drawing.Color]::FromArgb(63,185,80)
$cAmber  = [System.Drawing.Color]::FromArgb(227,179,65)
$cRed    = [System.Drawing.Color]::FromArgb(229,83,75)
$cText   = [System.Drawing.Color]::FromArgb(230,237,243)
$cTrack  = [System.Drawing.Color]::FromArgb(48,54,61)
$cPurple = [System.Drawing.Color]::FromArgb(168,85,247)
$cBlue   = [System.Drawing.Color]::FromArgb(88,166,255)   # 'Local' family (a local model, e.g. qwen via Ollama)

# Fixed family order + colour for the per-model rows. Only families with usage
# are shown, in this order. 'Other' (unrecognized Claude model ids) is
# intentionally NOT in the order, so it gets no row - but its tokens/cost still
# count in the totals. 'Local' (Claude Code pointed at a non-Claude model, e.g.
# a local Ollama model) IS in the order - it's always $0 (see Get-Price), so it
# never affects the cost totals, but its own tokens are worth seeing.
$FamOrder = @('Opus','Sonnet','Haiku','Fable','Local')
$FamColor = @{ Opus=$cCyan; Sonnet=$cPurple; Haiku=$cGreen; Fable=$cAmber; Local=$cBlue; Other=$cDim }

function Hue([double]$p){ if($p -ge 90){$cRed}elseif($p -ge 70){$cAmber}else{$cGreen} }

# --- layout constants -----------------------------------------------------
$W        = 300            # form width
$padL     = 12
$rowH     = 20             # per-model row height
$heroTagY = 32
$heroY    = 45             # big "spent today" number
$rawY     = 83             # "if billed per token" line
$div1Y    = 105
$rowsTop  = 116            # first model row (right below divider 1)
$sRowH    = 18             # per-chat context row height
$sTrackX  = 100            # x of the context bar in a chat row
$sTrackW  = 94             # width of the context bar track
$sPctX    = 200            # x of the context % (right-justified in its column)
$sSepX    = 236            # x of the thin separator between % and tokens
$sTokX    = 242            # x of the context tokens (LEFT-aligned, hugs the separator)

# --- form -----------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.BackColor       = $cBg
$form.TopMost         = $true
$form.ShowInTaskbar   = $false
$form.Width           = $W
$form.Height          = 210
$form.StartPosition   = 'Manual'
# Double-buffer the form to kill repaint flicker on the 1s refresh.
try {
    $form.GetType().GetProperty('DoubleBuffered',[System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form,$true,$null)
} catch {}

# Rounded-corner region. Rebuilt whenever the height changes (rows added/removed).
function Set-Region($h){
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 14; $w = $form.Width
    $gp.AddArc(0,0,$r,$r,180,90)
    $gp.AddArc($w-$r,0,$r,$r,270,90)
    $gp.AddArc($w-$r,$h-$r,$r,$r,0,90)
    $gp.AddArc(0,$h-$r,$r,$r,90,90)
    $gp.CloseAllFigures()
    $form.Region = New-Object System.Drawing.Region($gp)
}
Set-Region $form.Height

$wa   = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$defX = $wa.Left + 8
$defY = $wa.Bottom - $form.Height - 8
$form.Left = $defX; $form.Top = $defY
if (Test-Path $PosPath) {
    try {
        $p = (Get-Content $PosPath -Raw) -split ','
        $form.Left=[int]$p[0]; $form.Top=[int]$p[1]
        if($p.Count -ge 3){ $script:sessCollapsed = ($p[2].Trim() -eq '1') }   # restore collapse state
        if($p.Count -ge 4){ $script:sessCollapsedLocal = ($p[3].Trim() -eq '1') }   # same, for Local chats
    }
    catch { $form.Left=$defX; $form.Top=$defY }
}
if ($form.Left -lt $wa.Left -or $form.Left -gt $wa.Right-50) { $form.Left = $defX }
if ($form.Top  -lt $wa.Top  -or $form.Top  -gt $wa.Bottom-30){ $form.Top  = $defY }

# --- control helpers ------------------------------------------------------
# Opaque labels (bg = form colour) repaint without the transparent-label
# flicker; nothing overlaps the bar track, so opacity is invisible.
function New-Lbl($x,$y,$w,$h,$color,$size,$bold){
    $l = New-Object System.Windows.Forms.Label
    $l.Location  = New-Object System.Drawing.Point($x,$y)
    $l.Size      = New-Object System.Drawing.Size($w,$h)
    $l.ForeColor = $color
    $st = if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}
    $l.Font      = New-Object System.Drawing.Font('Segoe UI',$size,$st)
    $l.BackColor = $cBg
    $form.Controls.Add($l); return $l
}
function Set-T($l,$t){ if($l.Text -ne $t){ $l.Text = $t } }

# header
$lblTitle = New-Lbl $padL 9 92 18 $cCyan 9.5 $true ; $lblTitle.Text = 'Claude Usage'
$lblVer   = New-Lbl 95 12 70 14 $cDim 8 $false ; $lblVer.Text = 'v' + $Version

# history (calendar) button - opens a beautiful per-day usage calendar
$btnHist = New-Lbl ($W-70) 7 20 18 $cDim 10 $false
try { $btnHist.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets',10) } catch {}
$btnHist.Text = [string][char]0xE787                 # calendar glyph (Segoe MDL2 Assets)
$btnHist.TextAlign = 'MiddleCenter'
$btnHist.Add_Click({ Open-History })
$btnHist.Add_MouseEnter({ $btnHist.ForeColor = $cCyan })
$btnHist.Add_MouseLeave({ $btnHist.ForeColor = $cDim })

$btnRefresh = New-Lbl ($W-46) 7 18 18 $cDim 10 $false
$btnRefresh.Text = [string][char]0x21BB              # round arrow
$btnRefresh.TextAlign = 'MiddleCenter'
$btnRefresh.Add_Click({ $script:curDay=$null; Update-Widget })
$btnRefresh.Add_MouseEnter({ $btnRefresh.ForeColor = $cCyan })
$btnRefresh.Add_MouseLeave({ $btnRefresh.ForeColor = $cDim })

$btnX = New-Lbl ($W-26) 7 18 18 $cDim 11 $false
$btnX.Text = [string][char]0x00D7
$btnX.TextAlign = 'MiddleCenter'
$btnX.Add_Click({ $form.Close() })
$btnX.Add_MouseEnter({ $btnX.ForeColor = $cRed })
$btnX.Add_MouseLeave({ $btnX.ForeColor = $cDim })

# hero: today's cache-aware spend
$lblHeroTag = New-Lbl $padL $heroTagY 200 14 $cDim 8 $false ; $lblHeroTag.Text = 'Spent Today  ' + [string][char]0x00B7 + '  Cached'
$lblHero    = New-Lbl $padL $heroY ($W-2*$padL) 34 $cCyan 20 $true ; $lblHero.Text = '$0.00' ; $lblHero.TextAlign = 'MiddleLeft'

# raw "if billed per token"
$lblRawTag = New-Lbl $padL $rawY 108 16 $cDim 8.5 $false ; $lblRawTag.Text = 'If Billed Per Token:'
$lblRawVal = New-Lbl 124 $rawY ($W-$padL-124) 16 $cAmber 9.5 $true ; $lblRawVal.TextAlign='MiddleRight'   # right edge = panel's true right margin

# divider 1
$div1 = New-Object System.Windows.Forms.Panel
$div1.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div1.BackColor = $cTrack
$div1.Location = New-Object System.Drawing.Point($padL,$div1Y)
$form.Controls.Add($div1)

# model usage rows: two labeled groups, "Claude Cloud:" (per-family: Opus/
# Sonnet/Haiku/Fable, up to 4 rows) and "Local:" (the last few DISTINCT local
# models used today - e.g. different Ollama tags - up to $MaxLocalModelRows
# rows). Cost starts at $sTrackX (100) so it lines up with the context bar's
# start in the recent-chats rows below; output is right-justified to the true
# right edge (288), not the old ~232 boundary that left dead space after it.
# Local rows skip the cost column (always $0 - see Get-Price - so repeating
# "$0.00" five times would just be noise) and instead give the exact model
# name more room, since local model tags run longer than 'Opus'/'Sonnet'.
$MaxCloudFamilyRows = 4    # Opus/Sonnet/Haiku/Fable - 'Local' no longer takes a family-row slot
$MaxLocalModelRows  = 5    # last N distinct local models used today

$lblCloudHdr = New-Lbl $padL $rowsTop ($W-2*$padL) 14 $cDim 8 $true
$lblCloudHdr.Text = 'Claude Cloud:'
$lblCloudHdr.Visible = $false

$rowName=@(); $rowCost=@(); $rowOut=@()
for($k=0;$k -lt $MaxCloudFamilyRows;$k++){
    $y = $rowsTop + 18 + $k*$rowH
    $rn = New-Lbl $padL $y 52 17 $cText 9.5 $true
    $rc = New-Lbl $sTrackX $y 96 17 $cText 9.5 $false
    $ro = New-Lbl 200 ($y+1) ($W-$padL-200) 15 $cDim 8.5 $false ; $ro.TextAlign = 'MiddleRight'   # right edge = true panel edge
    $rn.Visible=$false; $rc.Visible=$false; $ro.Visible=$false
    $rowName += ,$rn ; $rowCost += ,$rc ; $rowOut += ,$ro
}

$lblLocalModelsHdr = New-Lbl $padL $rowsTop ($W-2*$padL) 14 $cDim 8 $true
$lblLocalModelsHdr.Text = 'Local:'
$lblLocalModelsHdr.Visible = $false

$lmName=@(); $lmOut=@()
for($k=0;$k -lt $MaxLocalModelRows;$k++){
    $y = $rowsTop + 18 + $k*$rowH
    $rn = New-Lbl $padL $y 184 17 $cBlue 9.5 $true
    $rn.AutoEllipsis = $true
    $ro = New-Lbl 200 ($y+1) ($W-$padL-200) 15 $cDim 8.5 $false ; $ro.TextAlign = 'MiddleRight'
    $rn.Visible=$false; $ro.Visible=$false
    $lmName += ,$rn ; $lmOut += ,$ro
}

# divider 2 + footer (positioned by Relayout)
$div2 = New-Object System.Windows.Forms.Panel
$div2.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div2.BackColor = $cTrack
$div2.Location = New-Object System.Drawing.Point($padL,180)
$form.Controls.Add($div2)

# output / turns / sessions: 3 columns spanning the full row width (left /
# center / right), with a small dot marker carved out between each pair so
# the split is visible even when the values are short
$dotChar = [string][char]0x00B7
$lblFoot1a = New-Lbl $padL 188 84 15 $cDim 8 $false ; $lblFoot1a.Text = 'starting...'   # output, left
$lblFoot1Sep1 = New-Lbl 96 188 16 15 $cDim 8 $false ; $lblFoot1Sep1.TextAlign = 'MiddleCenter' ; $lblFoot1Sep1.Text = $dotChar
$lblFoot1b = New-Lbl 112 188 76 15 $cDim 8 $false ; $lblFoot1b.TextAlign = 'MiddleCenter'   # turns, center
$lblFoot1Sep2 = New-Lbl 188 188 16 15 $cDim 8 $false ; $lblFoot1Sep2.TextAlign = 'MiddleCenter' ; $lblFoot1Sep2.Text = $dotChar
$lblFoot1c = New-Lbl 204 188 84 15 $cDim 8 $false ; $lblFoot1c.TextAlign = 'MiddleRight'    # sessions, right
$lblFoot2 = New-Lbl $padL 203 ($W-2*$padL) 14 $cDim 8 $false ; $lblFoot2.Text = '' ; $lblFoot2.TextAlign = 'MiddleRight'  # updated Xs ago, right

# --- recent-chats context section (divider + header + N chat rows) ---------
# One tooltip serves every chat row (full name + exact token detail on hover).
$tip = New-Object System.Windows.Forms.ToolTip
$tip.InitialDelay = 350; $tip.ReshowDelay = 120; $tip.AutoPopDelay = 12000

$div3 = New-Object System.Windows.Forms.Panel
$div3.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div3.BackColor = $cTrack
$div3.Location = New-Object System.Drawing.Point($padL,230)
$div3.Visible = $false
$form.Controls.Add($div3)

# header: "Context Used" left, "Recent Cloud Chats" right-justified, the
# collapse chevron to ITS right (the very last/rightmost element in the row)
$lblCtxUsedHdr = New-Lbl $padL 240 110 14 $cDim 8 $false
$lblCtxUsedHdr.Text = 'Context Used'
$lblCtxUsedHdr.Visible = $false

$lblRecentChatsHdr = New-Lbl 130 240 144 14 $cDim 8 $false
$lblRecentChatsHdr.TextAlign = 'MiddleRight'
$lblRecentChatsHdr.Text = 'Recent Cloud Chats'
$lblRecentChatsHdr.Visible = $false

$lblChevronHdr = New-Lbl 274 240 14 14 $cDim 8 $false
$lblChevronHdr.TextAlign = 'MiddleRight'
$lblChevronHdr.Visible = $false

# Fixed slots: chat name | context bar | percent | separator | context tokens.
# Percent and tokens are both right-justified, split by a thin vertical barrier.
$cSep = [System.Drawing.Color]::FromArgb(78,86,95)
$sName=@(); $sTrack=@(); $sFill=@(); $sPct=@(); $sSep=@(); $sTok=@()
for($k=0;$k -lt $MaxSessionsCap;$k++){
    $nm = New-Lbl $padL 260 ($sTrackX-$padL-4) 16 $cText 8.5 $false
    $nm.AutoEllipsis = $true
    $tr = New-Object System.Windows.Forms.Panel
    $tr.Size = New-Object System.Drawing.Size($sTrackW,7)
    $tr.BackColor = $cTrack
    $tr.Location = New-Object System.Drawing.Point($sTrackX,264)
    $fl = New-Object System.Windows.Forms.Panel
    $fl.Location = New-Object System.Drawing.Point(0,0)
    $fl.Size = New-Object System.Drawing.Size(0,7)
    $fl.BackColor = $cGreen
    $tr.Controls.Add($fl)
    $form.Controls.Add($tr)
    $pc = New-Lbl $sPctX 260 ($sSepX-$sPctX-4) 16 $cDim 8.5 $true
    $pc.TextAlign = 'MiddleRight'
    $sp = New-Object System.Windows.Forms.Panel
    $sp.Size = New-Object System.Drawing.Size(1,11)
    $sp.BackColor = $cSep
    $sp.Location = New-Object System.Drawing.Point($sSepX,262)
    $form.Controls.Add($sp)
    $tk = New-Lbl $sTokX 260 32 16 $cDim 8.5 $false
    $tk.TextAlign = 'MiddleLeft'
    $nm.Visible=$false; $tr.Visible=$false; $pc.Visible=$false; $sp.Visible=$false; $tk.Visible=$false
    $sName += ,$nm ; $sTrack += ,$tr ; $sFill += ,$fl ; $sPct += ,$pc ; $sSep += ,$sp ; $sTok += ,$tk
}

# --- LOCAL recent-chats section (mirrors the cloud one above exactly; sits
# directly under it, same row layout/colors/collapse design, own count/state) -
$div3b = New-Object System.Windows.Forms.Panel
$div3b.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div3b.BackColor = $cTrack
$div3b.Location = New-Object System.Drawing.Point($padL,230)
$div3b.Visible = $false
$form.Controls.Add($div3b)

$lblLocalCtxUsedHdr = New-Lbl $padL 240 110 14 $cDim 8 $false
$lblLocalCtxUsedHdr.Text = 'Context Used'
$lblLocalCtxUsedHdr.Visible = $false

$lblLocalRecentChatsHdr = New-Lbl 130 240 144 14 $cDim 8 $false
$lblLocalRecentChatsHdr.TextAlign = 'MiddleRight'
$lblLocalRecentChatsHdr.Text = 'Recent Local Chats'
$lblLocalRecentChatsHdr.Visible = $false

$lblLocalChevronHdr = New-Lbl 274 240 14 14 $cDim 8 $false
$lblLocalChevronHdr.TextAlign = 'MiddleRight'
$lblLocalChevronHdr.Visible = $false

$lName=@(); $lTrack=@(); $lFill=@(); $lPct=@(); $lSep=@(); $lTok=@()
for($k=0;$k -lt $MaxLocalSessionsCap;$k++){
    $nm = New-Lbl $padL 260 ($sTrackX-$padL-4) 16 $cText 8.5 $false
    $nm.AutoEllipsis = $true
    $tr = New-Object System.Windows.Forms.Panel
    $tr.Size = New-Object System.Drawing.Size($sTrackW,7)
    $tr.BackColor = $cTrack
    $tr.Location = New-Object System.Drawing.Point($sTrackX,264)
    $fl = New-Object System.Windows.Forms.Panel
    $fl.Location = New-Object System.Drawing.Point(0,0)
    $fl.Size = New-Object System.Drawing.Size(0,7)
    $fl.BackColor = $cGreen
    $tr.Controls.Add($fl)
    $form.Controls.Add($tr)
    $pc = New-Lbl $sPctX 260 ($sSepX-$sPctX-4) 16 $cDim 8.5 $true
    $pc.TextAlign = 'MiddleRight'
    $sp = New-Object System.Windows.Forms.Panel
    $sp.Size = New-Object System.Drawing.Size(1,11)
    $sp.BackColor = $cSep
    $sp.Location = New-Object System.Drawing.Point($sSepX,262)
    $form.Controls.Add($sp)
    $tk = New-Lbl $sTokX 260 32 16 $cDim 8.5 $false
    $tk.TextAlign = 'MiddleLeft'
    $nm.Visible=$false; $tr.Visible=$false; $pc.Visible=$false; $sp.Visible=$false; $tk.Visible=$false
    $lName += ,$nm ; $lTrack += ,$tr ; $lFill += ,$fl ; $lPct += ,$pc ; $lSep += ,$sp ; $lTok += ,$tk
}

# --- all-time ticker (the very bottom line) --------------------------------
$divT = New-Object System.Windows.Forms.Panel
$divT.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$divT.BackColor = $cTrack
$divT.Location = New-Object System.Drawing.Point($padL,300)
$divT.Visible = $false
$form.Controls.Add($divT)
# row 1: "All Time Usage:" left, the token count right-justified to the true
# right edge. row 2: cached-cost left, per-token-cost right - same idea, all
# the row's horizontal space used instead of one bunched-up left-aligned string.
$lblTick1a = New-Lbl $padL 308 110 14 $cText 8 $false ; $lblTick1a.Visible=$false ; $lblTick1a.Text='All Time Usage:'
$lblTick1b = New-Lbl 122 308 166 14 $cText 8 $false ; $lblTick1b.TextAlign='MiddleRight' ; $lblTick1b.Visible=$false
$lblTick2a = New-Lbl $padL 322 112 14 $cDim  8 $false ; $lblTick2a.Visible=$false
$lblTick2Sep = New-Lbl 124 322 16 14 $cDim 8 $false ; $lblTick2Sep.TextAlign='MiddleCenter' ; $lblTick2Sep.Text=$dotChar ; $lblTick2Sep.Visible=$false
$lblTick2b = New-Lbl 140 322 148 14 $cDim  8 $false ; $lblTick2b.TextAlign='MiddleRight' ; $lblTick2b.Visible=$false
# row 3 (only shown once any Local/Ollama usage has ever been recorded): the
# Local all-time token total, right-justified the same way as row 1's Cloud
# figure - never blended into it (different tokenizer, always $0 cost).
$lblTickLa = New-Lbl $padL 336 110 14 $cBlue 8 $false ; $lblTickLa.Visible=$false ; $lblTickLa.Text='Local All-Time:'
$lblTickLb = New-Lbl 122 336 166 14 $cBlue 8 $false ; $lblTickLb.TextAlign='MiddleRight' ; $lblTickLb.Visible=$false

# --- right-click menu -----------------------------------------------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miC = $menu.Items.Add('History (calendar)') ; $miC.Add_Click({ Open-History })
$miR = $menu.Items.Add('Refresh now')        ; $miR.Add_Click({ $script:curDay=$null; Update-Widget })
$miS = $menu.Items.Add('Unarchive all chats'); $miS.Add_Click({ Unarchive-All })
$miH = $menu.Items.Add('Open instructions')  ; $miH.Add_Click({ try { Start-Process (Join-Path $PSScriptRoot 'admin-instructions.html') } catch {} })
[void]$menu.Items.Add('-')
$miX = $menu.Items.Add('Exit')               ; $miX.Add_Click({ $form.Close() })
# reflect how many chats are archived; hide the item entirely when none are
$menu.Add_Opening({ $n=$script:archived.Count; $miS.Text = "Unarchive $n chat$(if($n-ne 1){'s'})"; $miS.Visible = ($n -gt 0) })
$form.ContextMenuStrip = $menu

# per-chat menu: right-click a recent-chat row to archive it (or unarchive all).
# The clicked row's session id is captured from the menu's SourceControl.Tag.
$sessMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miHide = $sessMenu.Items.Add('Archive this chat')    ; $miHide.Add_Click({ Archive-Session $script:sessMenuId })
[void]$sessMenu.Items.Add('-')
$miRestore = $sessMenu.Items.Add('Unarchive all chats') ; $miRestore.Add_Click({ Unarchive-All })
$miCal2   = $sessMenu.Items.Add('History (calendar)')   ; $miCal2.Add_Click({ Open-History })
$sessMenu.Add_Opening({
    $src = $sessMenu.SourceControl
    $script:sessMenuId = if($src){ [string]$src.Tag } else { $null }
    $n=$script:archived.Count; $miRestore.Text = "Unarchive $n chat$(if($n-ne 1){'s'})"; $miRestore.Visible = ($n -gt 0)
})

# --- dragging (hand off to the OS window-move loop: grab anywhere, glides) -
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WidgetNative {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@
# WM_NCLBUTTONDOWN = 0xA1, HTCAPTION = 0x2. SendMessage blocks inside the OS
# move loop until release, so we save the new position right after.
$dragHandler = {
    param($s,$e)
    if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){
        [WidgetNative]::ReleaseCapture() | Out-Null
        [WidgetNative]::SendMessage($form.Handle, 0xA1, [IntPtr]0x2, [IntPtr]0) | Out-Null
        Save-Pos
    }
}
function Wire-Drag($c){ $c.ContextMenuStrip = $menu; $c.Add_MouseDown($dragHandler) }
# everything is a drag handle EXCEPT the refresh / close buttons (they click)
$dragCtrls = @($form,$lblTitle,$lblVer,$lblHeroTag,$lblHero,$lblRawTag,$lblRawVal,$div1,$div2,$lblFoot1a,$lblFoot1Sep1,$lblFoot1b,$lblFoot1Sep2,$lblFoot1c,$lblFoot2,$div3,$divT,$lblTick1a,$lblTick1b,$lblTick2a,$lblTick2Sep,$lblTick2b,$lblTickLa,$lblTickLb)
$dragCtrls += $lblCloudHdr,$lblLocalModelsHdr
$dragCtrls += $rowName + $rowCost + $rowOut
$dragCtrls += $lmName + $lmOut
$dragCtrls += $sName + $sTrack + $sFill + $sPct + $sSep + $sTok
$dragCtrls += $lName + $lTrack + $lFill + $lPct + $lSep + $lTok
$dragCtrls += $div3b
foreach($c in $dragCtrls){ Wire-Drag $c }
# recent-chat rows keep drag, but right-click shows the per-chat menu instead
# (archiving works the same regardless of cloud/local - Archive-Session is
# family-agnostic, just a session id)
foreach($c in ($sName + $sTrack + $sFill + $sPct + $sSep + $sTok)){ $c.ContextMenuStrip = $sessMenu }
foreach($c in ($lName + $lTrack + $lFill + $lPct + $lSep + $lTok)){ $c.ContextMenuStrip = $sessMenu }
# the recent-chats HEADER is a click-to-collapse toggle (not a drag handle) -
# now 3 separate controls (Context Used / Recent Cloud Chats / chevron), all
# wired the same way so the whole header stays clickable as one unit
foreach($c in @($lblCtxUsedHdr,$lblRecentChatsHdr,$lblChevronHdr)){
    $c.ContextMenuStrip = $menu
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.Add_Click({ Toggle-Sessions })
}
foreach($c in @($lblLocalCtxUsedHdr,$lblLocalRecentChatsHdr,$lblLocalChevronHdr)){
    $c.ContextMenuStrip = $menu
    $c.Cursor = [System.Windows.Forms.Cursors]::Hand
    $c.Add_Click({ Toggle-SessionsLocal })
}

function Save-Pos { try { "$($form.Left),$($form.Top),$([int][bool]$script:sessCollapsed),$([int][bool]$script:sessCollapsedLocal)" | Set-Content -LiteralPath $PosPath -Encoding ASCII } catch {} }
$form.Add_FormClosing({ Save-Pos; if($script:data){ Persist-Today $script:data }; if($script:settingsListener){ try { $script:settingsListener.Stop() } catch {} } })

# --- data: today's aggregate across all sessions --------------------------
# byLocalModel tracks EXACT local model strings (e.g. 'qwen3:8b-32k'), separate
# from the family-level 'by' bucket (which folds every local model into one
# 'Local' row) - this is what lets the widget show the last few distinct local
# models used today, not just one aggregate line.
function New-FileState { @{ off=[long]0; lw=$null; turns=0; out=0.0; tok=0.0; cost=0.0; raw=0.0; by=@{}; byLocalModel=@{} } }

# Read only the bytes appended since we last looked; count turns timestamped
# today into the file's running accumulators. Append-only transcripts make this
# O(new bytes) per tick, so a live multi-MB session never re-parses in full.
function Read-Today($path,$st,$todayDate){
    $fs=$null
    try { $fs = New-Object System.IO.FileStream($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite) }
    catch { return }
    try {
        $len = $fs.Length
        if($len -lt $st.off){          # file rotated/truncated -> start over
            $st.off=0; $st.turns=0; $st.out=0.0; $st.tok=0.0; $st.cost=0.0; $st.raw=0.0; $st.by=@{}; $st.byLocalModel=@{}
        }
        if($len -le $st.off){ return } # nothing new
        [void]$fs.Seek($st.off,[System.IO.SeekOrigin]::Begin)
        $count = [int]($len - $st.off)
        $buf = New-Object byte[] $count
        $got = 0
        while($got -lt $count){ $r = $fs.Read($buf,$got,$count-$got); if($r -le 0){ break }; $got += $r }
        # only consume up to the last complete line (10 = '\n')
        $lastNl = -1
        for($x=$got-1; $x -ge 0; $x--){ if($buf[$x] -eq 10){ $lastNl=$x; break } }
        if($lastNl -lt 0){ return }
        $text = [System.Text.Encoding]::UTF8.GetString($buf,0,$lastNl+1)
        $st.off += ($lastNl+1)
        foreach($line in ($text -split "`n")){
            if($line.Length -lt 1){ continue }
            if($line.IndexOf('output_tokens') -lt 0){ continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if($o.type -ne 'assistant'){ continue }
            $u = $o.message.usage; if($null -eq $u){ continue }
            $tsOff = $null
            try { $tsOff = [datetimeoffset]::Parse([string]$o.timestamp) } catch { continue }
            if($tsOff.LocalDateTime.Date -ne $todayDate){ continue }
            # dedup turns copied into resumed/forked transcripts (else double-counted)
            $dk = "$($o.message.id)|$($o.requestId)"; if($dk -eq '|'){ $dk = $o.uuid }
            if($script:seenToday.ContainsKey($dk)){ continue }
            $script:seenToday[$dk] = 1
            $i  = [double]$u.input_tokens;            $ou = [double]$u.output_tokens
            $cr = [double]$u.cache_read_input_tokens; $cc = [double]$u.cache_creation_input_tokens
            $e5 = 0.0; $e1 = 0.0
            if($u.cache_creation){ $e5=[double]$u.cache_creation.ephemeral_5m_input_tokens; $e1=[double]$u.cache_creation.ephemeral_1h_input_tokens }
            else { $e5 = $cc }
            $pr = Get-Price $o.message.model
            $bi = $pr.In / 1e6 ; $bo = $pr.Out / 1e6
            $tc = $i*$bi + $ou*$bo + $cr*($bi*0.1) + $e5*($bi*1.25) + $e1*($bi*2.0)
            $tr = ($i + $cr + $cc)*$bi + $ou*$bo
            $st.turns++; $st.out += $ou; $st.cost += $tc; $st.raw += $tr; $st.tok += $i + $ou + $cr + $cc
            $fam = Family $o.message.model
            if(-not $st.by.ContainsKey($fam)){ $st.by[$fam] = @{ out=0.0; cost=0.0; raw=0.0; tok=0.0 } }
            $st.by[$fam].out  += $ou
            $st.by[$fam].cost += $tc
            $st.by[$fam].raw  += $tr
            $st.by[$fam].tok  += $i + $ou + $cr + $cc
            if($fam -eq 'Local'){
                $mkey = [string]$o.message.model
                if([string]::IsNullOrWhiteSpace($mkey)){ $mkey = '(unknown local model)' }
                if(-not $st.byLocalModel.ContainsKey($mkey)){ $st.byLocalModel[$mkey] = @{ tok=0.0; last=$tsOff.UtcDateTime } }
                $st.byLocalModel[$mkey].tok += ($i + $ou + $cr + $cc)
                if($tsOff.UtcDateTime -gt $st.byLocalModel[$mkey].last){ $st.byLocalModel[$mkey].last = $tsOff.UtcDateTime }
            }
        }
    } catch { }
    finally { if($fs){ $fs.Close() } }
}

# Roll up every session touched today (top-level files = sessions; their
# subagents fold into the totals but don't count as separate sessions).
function Aggregate-Today {
    $todayKey  = (Get-Date).ToString('yyyy-MM-dd')
    if($todayKey -ne $script:curDay){ $script:files=@{}; $script:seenToday=@{}; $script:curDay=$todayKey }   # midnight reset
    $todayDate = (Get-Date).Date

    $top=@(); $sub=@()
    try { $top = @(Get-ChildItem (Join-Path $ProjRoot '*\*.jsonl') -ErrorAction Stop | Where-Object { $_.LastWriteTime.Date -ge $todayDate }) } catch {}
    try { $sub = @(Get-ChildItem (Join-Path $ProjRoot '*\*\subagents\*.jsonl') -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime.Date -ge $todayDate }) } catch {}
    $all = @($top) + @($sub)

    $stamp = $null
    foreach($f in $all){
        $key = $f.FullName
        if(-not $script:files.ContainsKey($key)){ $script:files[$key] = New-FileState }
        $st = $script:files[$key]
        if($st.lw -ne $f.LastWriteTimeUtc){ Read-Today $key $st $todayDate; $st.lw = $f.LastWriteTimeUtc }
        if($null -eq $stamp -or $f.LastWriteTimeUtc -gt $stamp){ $stamp = $f.LastWriteTimeUtc }
    }

    $agg = @{ turns=0; out=0.0; tok=0.0; cost=0.0; raw=0.0; by=@{}; byLocalModel=@{}; sessions=0 }
    foreach($f in $all){
        $st = $script:files[$f.FullName]; if($null -eq $st){ continue }
        $isSub = (Split-Path $f.DirectoryName -Leaf) -eq 'subagents'
        $agg.turns += $st.turns; $agg.out += $st.out; $agg.tok += $st.tok; $agg.cost += $st.cost; $agg.raw += $st.raw
        foreach($fam in $st.by.Keys){
            if(-not $agg.by.ContainsKey($fam)){ $agg.by[$fam] = @{ out=0.0; cost=0.0; raw=0.0; tok=0.0 } }
            $agg.by[$fam].out  += $st.by[$fam].out
            $agg.by[$fam].cost += $st.by[$fam].cost
            $agg.by[$fam].raw  += $st.by[$fam].raw
            $agg.by[$fam].tok  += $st.by[$fam].tok
        }
        foreach($mk in $st.byLocalModel.Keys){
            if(-not $agg.byLocalModel.ContainsKey($mk)){ $agg.byLocalModel[$mk] = @{ tok=0.0; last=$st.byLocalModel[$mk].last } }
            $agg.byLocalModel[$mk].tok += $st.byLocalModel[$mk].tok
            if($st.byLocalModel[$mk].last -gt $agg.byLocalModel[$mk].last){ $agg.byLocalModel[$mk].last = $st.byLocalModel[$mk].last }
        }
        if((-not $isSub) -and $st.turns -gt 0){ $agg.sessions++ }
    }
    return @{ agg=$agg; stamp=$stamp }
}

# --- recent chats: per-session context fill -------------------------------
# Read only the TAIL of a transcript (last ~512KB) and scan backwards for the
# most-recent assistant turn's context fill (input + cache_read + cache_creation
# = the tokens that were in the model's context that turn) plus the chat's title
# as the Claude app shows it (custom-title > ai-title). O(1)-ish per file, so
# even a 30MB live transcript is cheap to sample every tick.
function Read-SessionTail($path){
    $fs=$null
    try { $fs = New-Object System.IO.FileStream($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite) }
    catch { return $null }
    $text=$null
    try {
        $len = $fs.Length
        if($len -le 0){ return $null }
        $tailLen = [int][Math]::Min(524288,$len)
        [void]$fs.Seek($len-$tailLen,[System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] $tailLen
        $got=0; while($got -lt $tailLen){ $rd=$fs.Read($buf,$got,$tailLen-$got); if($rd -le 0){break}; $got+=$rd }
        $text = [System.Text.Encoding]::UTF8.GetString($buf,0,$got)
    } catch { return $null } finally { if($fs){ $fs.Close() } }
    if($null -eq $text){ return $null }
    $lines = $text -split "`n"
    $ctx=$null; $model=$null; $tstamp=$null; $ct=$null; $at=$null
    $floor = [Math]::Max(0, $lines.Count-1500)   # bound the backward scan
    for($i=$lines.Count-1; $i -ge $floor; $i--){
        $ln = $lines[$i]
        if($ln.Length -lt 8){ continue }
        if($null -eq $ctx -and $ln.IndexOf('output_tokens') -ge 0){
            # Whole extraction (parse + numeric coercions) is guarded, so a single
            # malformed line just gets skipped instead of aborting this file's scan.
            try {
                $o=$ln|ConvertFrom-Json
                if($o -and $o.type -eq 'assistant' -and $o.message.usage){
                    $u=$o.message.usage
                    # context at rest after this turn = the whole prompt that was sent
                    # (input + cache read + cache write) plus the response just produced
                    $ctx = [double]$u.input_tokens + [double]$u.cache_read_input_tokens + [double]$u.cache_creation_input_tokens + [double]$u.output_tokens
                    $model = [string]$o.message.model
                    try { $tstamp=([datetimeoffset]::Parse([string]$o.timestamp)).UtcDateTime } catch {}
                }
            } catch {}
        }
        elseif($null -eq $ct -and $ln.IndexOf('custom-title') -ge 0){
            try { $ct=[string](($ln|ConvertFrom-Json).customTitle) } catch {}
        }
        elseif($null -eq $at -and $ln.IndexOf('ai-title') -ge 0){
            try { $at=[string](($ln|ConvertFrom-Json).aiTitle) } catch {}
        }
        if($null -ne $ctx -and -not [string]::IsNullOrWhiteSpace($ct)){ break }
    }
    if($null -eq $ctx){ return $null }
    return @{ ctx=$ctx; model=$model; tstamp=$tstamp; customTitle=$ct; aiTitle=$at }
}

# Fallback name for CLI/title-less transcripts: first real user prompt (reads
# only the file HEAD, once). Mirrors the calendar's session-label heuristic.
function Get-HeadPrompt($path){
    $fs=$null
    try { $fs = New-Object System.IO.FileStream($path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite) }
    catch { return $null }
    $text=$null
    try {
        $headLen=[int][Math]::Min(131072,$fs.Length)
        if($headLen -le 0){ return $null }
        $buf=New-Object byte[] $headLen
        $got=0; while($got -lt $headLen){ $rd=$fs.Read($buf,$got,$headLen-$got); if($rd -le 0){break}; $got+=$rd }
        $text=[System.Text.Encoding]::UTF8.GetString($buf,0,$got)
    } catch { return $null } finally { if($fs){ $fs.Close() } }
    if($null -eq $text){ return $null }
    foreach($ln in ($text -split "`n")){
        if($ln.IndexOf('"user"') -lt 0){ continue }
        try { $o=$ln|ConvertFrom-Json } catch { continue }
        if($o.type -ne 'user' -or -not $o.message){ continue }
        $c=$o.message.content; $txt=$null
        if($c -is [string]){ $txt=$c } elseif($c){ $tb=($c | Where-Object { $_.type -eq 'text' } | Select-Object -First 1); if($tb){ $txt=$tb.text } }
        if($txt){
            $txt=($txt -replace '\s+',' ').Trim()
            if($txt -and $txt -notmatch '^(This session is being continued|Caveat:|<command-|<local-command|\[Request interrupted)'){
                if($txt.Length -gt 60){ $txt=$txt.Substring(0,60)+[char]0x2026 }
                return $txt
            }
        }
    }
    return $null
}

# --- archived chats --------------------------------------------------------
# Archiving removes a chat from BOTH the widget's recent list AND the calendar's
# session lists, but its tokens STILL count in every total. Nothing is deleted.
# (Auto-archiving on Claude Code's own archive action isn't possible: that state
# lives in the app's internal database, not in any file we can read.)
function Load-Archived {
    $h=@{}
    $path = if(Test-Path $ArchivePath){ $ArchivePath } elseif(Test-Path $LegacyHiddenPath){ $LegacyHiddenPath } else { $null }
    if($path){
        try {
            $o = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($id in @($o)){ if($id){ $h["$id"]=1 } }
        } catch {}
    }
    return $h
}
function Save-Archived {
    try {
        $ids = @($script:archived.Keys)
        $json = if($ids.Count -eq 0){ '[]' } else { ConvertTo-Json -InputObject $ids }
        Set-Content -LiteralPath $ArchivePath -Value $json -Encoding UTF8
    } catch {}
}
function Archive-Session($id){
    if([string]::IsNullOrWhiteSpace($id)){ return }
    $script:archived["$id"]=1; Save-Archived
    $script:layoutKey=$null            # row count shrank -> force relayout
    Update-Widget
}
function Unarchive-All {
    if($script:archived.Count -eq 0){ return }
    $script:archived=@{}; Save-Archived
    $script:layoutKey=$null
    Update-Widget
}

# --- settings (recent-chats count, editable from the calendar) ------------
function Load-Settings {
    if(Test-Path $SettingsPath){
        try {
            $o = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $n = [int]$o.maxSessions
            if($n -ge 1 -and $n -le $MaxSessionsCap){ $script:MaxSessions = $n }
            if($null -ne $o.maxLocalSessions){
                $nl = [int]$o.maxLocalSessions
                if($nl -ge 1 -and $nl -le $MaxLocalSessionsCap){ $script:MaxLocalSessions = $nl }
            }
        } catch {}
    }
}
function Save-Settings {
    try {
        (@{ maxSessions = $script:MaxSessions; maxLocalSessions = $script:MaxLocalSessions } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    } catch {}
}
# Tiny 127.0.0.1-only HTTP listener so the calendar page (a static file with no
# other write-back path) can read/change the recent-chats count while the
# widget is running. Never reachable off this machine; no auth needed.
# POLLED from the existing 1s timer tick (UI thread only) rather than reacting
# to HttpListener's async callback on a ThreadPool thread - a PowerShell
# runspace can only run one thing at a time, and the main thread spends the
# whole app lifetime inside the blocking $form.ShowDialog() call, so a
# background-thread callback trying to run PowerShell (touching $script:
# state, calling Update-Widget) would race the UI thread for the same
# runspace. Polling IsCompleted from the timer keeps everything single-threaded.
function Handle-SettingsRequest($ctx){
    $req=$ctx.Request; $res=$ctx.Response
    try {
        $res.Headers.Add('Access-Control-Allow-Origin','*')
        $res.Headers.Add('Access-Control-Allow-Methods','GET, POST, OPTIONS')
        $res.Headers.Add('Access-Control-Allow-Headers','Content-Type')
        if($req.HttpMethod -eq 'OPTIONS'){ $res.StatusCode=204; $res.Close(); return }
        if($req.Url.AbsolutePath -ne '/settings'){ $res.StatusCode=404; $res.Close(); return }
        $body=$null
        if($req.HttpMethod -eq 'GET'){
            $body = @{ maxSessions=$script:MaxSessions; cap=$MaxSessionsCap; maxLocalSessions=$script:MaxLocalSessions; localCap=$MaxLocalSessionsCap } | ConvertTo-Json -Compress
        } elseif($req.HttpMethod -eq 'POST'){
            $reader=New-Object System.IO.StreamReader($req.InputStream,$req.ContentEncoding)
            $raw=$reader.ReadToEnd(); $reader.Close()
            $obj=$null; try { $obj = $raw | ConvertFrom-Json } catch {}
            $n = $script:MaxSessions
            if($obj -and ($null -ne $obj.maxSessions)){ $n=[int]$obj.maxSessions }   # -ne null, not truthy: a literal 0 must still clamp to 1 below, not be silently ignored
            if($n -lt 1){ $n=1 }; if($n -gt $MaxSessionsCap){ $n=$MaxSessionsCap }
            $script:MaxSessions = $n
            $nl = $script:MaxLocalSessions
            if($obj -and ($null -ne $obj.maxLocalSessions)){ $nl=[int]$obj.maxLocalSessions }
            if($nl -lt 1){ $nl=1 }; if($nl -gt $MaxLocalSessionsCap){ $nl=$MaxLocalSessionsCap }
            $script:MaxLocalSessions = $nl
            Save-Settings
            $script:layoutKey=$null   # row count may have changed -> force relayout
            Update-Widget
            $body = @{ maxSessions=$script:MaxSessions; cap=$MaxSessionsCap; maxLocalSessions=$script:MaxLocalSessions; localCap=$MaxLocalSessionsCap; ok=$true } | ConvertTo-Json -Compress
        } else {
            $res.StatusCode=405; $res.Close(); return
        }
        $buf=[System.Text.Encoding]::UTF8.GetBytes($body)
        $res.ContentType='application/json'
        $res.ContentLength64=$buf.Length
        $res.OutputStream.Write($buf,0,$buf.Length)
        $res.Close()
    } catch { try { $res.Close() } catch {} }
}
function Start-SettingsServer {
    try {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://127.0.0.1:$SettingsPort/")
        $l.Start()
        $script:settingsListener = $l
        $script:settingsAsync = $l.BeginGetContext($null,$null)
    } catch {}   # port already taken (e.g. another instance, or a test harness) -> settings just won't be reachable
}
# Called every 1s timer tick (UI thread). Cheap no-op when no request is
# pending; only does real work (parse/respond/maybe Update-Widget) once a
# request has actually arrived.
function Poll-SettingsServer {
    if(-not $script:settingsListener -or -not $script:settingsAsync){ return }
    if(-not $script:settingsAsync.IsCompleted){ return }
    try {
        $ctx = $script:settingsListener.EndGetContext($script:settingsAsync)
        Handle-SettingsRequest $ctx
    } catch {}
    finally {
        try { $script:settingsAsync = $script:settingsListener.BeginGetContext($null,$null) }
        catch { $script:settingsAsync = $null }
    }
}
# Collapse/expand the recent-chats list (clicking its header). Persisted.
function Toggle-Sessions {
    $script:sessCollapsed = -not $script:sessCollapsed
    Save-Pos
    $script:layoutKey=$null
    Update-Widget
}
# Same, for the Local recent-chats list.
function Toggle-SessionsLocal {
    $script:sessCollapsedLocal = -not $script:sessCollapsedLocal
    Save-Pos
    $script:layoutKey=$null
    Update-Widget
}

# Fill in pct/win for one bucket of sessions using its own window/tier config
# (Cloud and Local need separate denominators - see $LocalCtxWindowTiers above).
function Set-CtxPct($list, $fixedWin, $tiers){
    $win=[double]$fixedWin
    if($win -le 0){
        $maxc=0.0; foreach($s in $list){ if($s.ctx -gt $maxc){ $maxc=$s.ctx } }
        $sorted = @($tiers | Sort-Object)
        $win = [double]$sorted[-1]
        foreach($tier in $sorted){ if($maxc -le $tier){ $win=[double]$tier; break } }
        if($maxc -gt $win){ $win=[double]$maxc }
    }
    foreach($s in $list){
        $p = if($win -gt 0){ 100.0*$s.ctx/$win } else { 0 }
        if($p -lt 0){ $p=0 }
        $s.pct=$p; $s.win=$win
    }
}
# Enumerate every top-level transcript across all project folders and bucket
# the most-recent ones into CLOUD vs LOCAL (by Family() of each chat's last-seen
# model), each resolved to {title, ctx, pct, win, ...} and capped independently
# at $MaxSessions / $script:MaxLocalSessions. Tail reads are cached by mtime (one
# shared cache for both buckets), so idle ticks touch no files and an active
# tick re-reads only the one chat that changed.
function Get-Sessions {
    $empty = @{ cloud=@(); local=@() }
    $files=@()
    try { $files=@(Get-ChildItem (Join-Path $ProjRoot '*\*.jsonl') -ErrorAction Stop) } catch {}
    if($files.Count -eq 0){ return $empty }
    # drop archived chats (by session id = file base name)
    if($script:archived.Count -gt 0){
        $files = @($files | Where-Object { -not $script:archived.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) })
    }
    $wantCloud = $MaxSessions; $wantLocal = $script:MaxLocalSessions
    $poolSize = [Math]::Max(($wantCloud + $wantLocal) * 2, 20)
    $recent = $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $poolSize
    $outCloud=@(); $outLocal=@()
    foreach($f in $recent){
        if($outCloud.Count -ge $wantCloud -and $outLocal.Count -ge $wantLocal){ break }
        $path=$f.FullName
        $sid=[System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $c=$script:sessCache[$path]
        if($null -eq $c -or $c.mtime -ne $f.LastWriteTimeUtc){
            $t = Read-SessionTail $path
            if($null -eq $t){ $script:sessCache[$path]=@{ mtime=$f.LastWriteTimeUtc; ctx=$null }; continue }
            $title=$t.customTitle
            if([string]::IsNullOrWhiteSpace($title)){ $title=$t.aiTitle }
            if([string]::IsNullOrWhiteSpace($title) -and $c -and $c.title){ $title=$c.title }
            if([string]::IsNullOrWhiteSpace($title)){ $title=Get-HeadPrompt $path }
            if([string]::IsNullOrWhiteSpace($title)){ $title='(untitled chat)' }
            $c=@{ mtime=$f.LastWriteTimeUtc; ctx=$t.ctx; model=$t.model; tstamp=$t.tstamp; title=([string]$title).Trim() }
            $script:sessCache[$path]=$c
        }
        if($null -eq $c.ctx){ continue }
        $isLocal = (Family $c.model) -eq 'Local'
        if($isLocal){
            if($outLocal.Count -ge $wantLocal){ continue }
            $outLocal += ,@{ id=$sid; title=$c.title; ctx=[double]$c.ctx; model=$c.model; tstamp=$c.tstamp }
        } else {
            if($outCloud.Count -ge $wantCloud){ continue }
            $outCloud += ,@{ id=$sid; title=$c.title; ctx=[double]$c.ctx; model=$c.model; tstamp=$c.tstamp }
        }
    }
    Set-CtxPct $outCloud $ContextWindowTokens $CtxWindowTiers
    Set-CtxPct $outLocal $LocalContextWindowTokens $LocalCtxWindowTiers
    # Callers wrap each list with @(...) to normalise 0/1/N into an array.
    return @{ cloud=$outCloud; local=$outLocal }
}

# --- formatting -----------------------------------------------------------
function Fmt-Tok($n){
    $n=[double]$n
    if($n -ge 1e9){ '{0:0.00}B' -f ($n/1e9) }
    elseif($n -ge 1e6){ '{0:0.0}M' -f ($n/1e6) }
    elseif($n -ge 1e3){ '{0:0}k' -f ($n/1e3) }
    else { [string][int]$n }
}
function Money($n){ '$' + ('{0:N2}' -f [double]$n) }
function Fmt-Ago($mtimeUtc){
    if($null -eq $mtimeUtc){ return 'Updated just now' }
    $s = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$mtimeUtc).TotalSeconds
    if($s -lt 0){ $s = 0 }
    if($s -lt 60){ 'Updated ' + [int]$s + 's ago' }
    elseif($s -lt 3600){ 'Updated ' + [int]($s/60) + 'm ago' }
    else { 'Updated ' + [int]($s/3600) + 'h ago' }
}
# --- render ---------------------------------------------------------------
# Claude Cloud families with usage today, in fixed display order ('Local' is
# excluded here - it gets its own per-exact-model breakdown below, not a
# single aggregate family row).
function Active-CloudFamilies($bm){
    $r=@(); foreach($f in $FamOrder){ if($f -ne 'Local' -and $bm.ContainsKey($f)){ $r += $f } }
    ,$r
}
# The last N distinct local models used today, most-recently-used first
# (ties broken by insertion order via Sort-Object's stable sort).
function Get-RecentLocalModels($byLocalModel, $capN){
    $list = @()
    foreach($mk in $byLocalModel.Keys){ $list += ,@{ model=$mk; tok=$byLocalModel[$mk].tok; last=$byLocalModel[$mk].last } }
    # NOTE: -Property 'last' (a bare string) mis-sorts arrays of hashtables in
    # PS 5.1 - only the scriptblock form actually invokes the dot-into-hashtable
    # accessor Sort-Object needs here. Confirmed by a standalone repro; do not
    # "simplify" this back to a string property name.
    $sorted = @($list | Sort-Object -Property {$_.last} -Descending)
    if($sorted.Count -gt $capN){ $sorted = $sorted[0..($capN-1)] }
    ,$sorted
}
# Reposition model rows (Claude Cloud group + Local group) + recent-chats
# section + the bottom block (All Time Usage / turns-sessions / updated), and
# resize the form. Called only when a row count changes (folded into the
# layout key), not every tick.
function Relayout($cloudFams,$localModels,$nSess,$nSessLocal,$hasLocalAllTime){
    $nCloud = $cloudFams.Count
    if($nCloud -gt 0){
        $lblCloudHdr.Top = $rowsTop; $lblCloudHdr.Visible=$true
        for($k=0;$k -lt $MaxCloudFamilyRows;$k++){
            if($k -lt $nCloud){
                $y = $rowsTop + 18 + $k*$rowH
                $rowName[$k].Top=$y; $rowCost[$k].Top=$y; $rowOut[$k].Top=$y+1
                $rowName[$k].ForeColor = $FamColor[$cloudFams[$k]]
                $rowName[$k].Visible=$true; $rowCost[$k].Visible=$true; $rowOut[$k].Visible=$true
            } else {
                $rowName[$k].Visible=$false; $rowCost[$k].Visible=$false; $rowOut[$k].Visible=$false
            }
        }
        $afterCloud = $rowsTop + 18 + $nCloud*$rowH
    } else {
        $lblCloudHdr.Visible=$false
        for($k=0;$k -lt $MaxCloudFamilyRows;$k++){ $rowName[$k].Visible=$false; $rowCost[$k].Visible=$false; $rowOut[$k].Visible=$false }
        $afterCloud = $rowsTop
    }

    $nLocalM = $localModels.Count
    if($nLocalM -gt 0){
        $lmY0 = $afterCloud + $(if($nCloud -gt 0){6}else{0})
        $lblLocalModelsHdr.Top = $lmY0; $lblLocalModelsHdr.Visible=$true
        for($k=0;$k -lt $MaxLocalModelRows;$k++){
            if($k -lt $nLocalM){
                $y = $lmY0 + 18 + $k*$rowH
                $lmName[$k].Top=$y; $lmOut[$k].Top=$y+1
                $lmName[$k].Visible=$true; $lmOut[$k].Visible=$true
            } else {
                $lmName[$k].Visible=$false; $lmOut[$k].Visible=$false
            }
        }
        $afterModels = $lmY0 + 18 + $nLocalM*$rowH
    } else {
        $lblLocalModelsHdr.Visible=$false
        for($k=0;$k -lt $MaxLocalModelRows;$k++){ $lmName[$k].Visible=$false; $lmOut[$k].Visible=$false }
        $afterModels = $afterCloud
    }

    $dY = $afterModels + 6
    $div2.Top = $dY; $div2.Visible=$true          # divider between models and recent chats
    $bottom = $dY + 6

    # recent-chats section (header always shown when there are chats; the rows
    # collapse away when $script:sessCollapsed, leaving just the clickable header)
    if($nSess -gt 0){
        $s0 = $bottom + 2
        $lblCtxUsedHdr.Top = $s0; $lblCtxUsedHdr.Visible=$true
        $lblRecentChatsHdr.Top = $s0; $lblRecentChatsHdr.Visible=$true
        $lblChevronHdr.Top = $s0; $lblChevronHdr.Visible=$true
        $rowsShown = if($script:sessCollapsed){ 0 } else { $nSess }
        $sTop = $s0 + 18
        for($k=0;$k -lt $MaxSessionsCap;$k++){
            if($k -lt $rowsShown){
                $y = $sTop + $k*$sRowH
                $sName[$k].Top=$y
                $sTrack[$k].Top=$y+5
                $sPct[$k].Top=$y
                $sSep[$k].Top=$y+3
                $sTok[$k].Top=$y
                $sName[$k].Visible=$true; $sTrack[$k].Visible=$true; $sPct[$k].Visible=$true; $sSep[$k].Visible=$true; $sTok[$k].Visible=$true
            } else {
                $sName[$k].Visible=$false; $sTrack[$k].Visible=$false; $sPct[$k].Visible=$false; $sSep[$k].Visible=$false; $sTok[$k].Visible=$false
            }
        }
        $bottom = if($rowsShown -gt 0){ $sTop + $rowsShown*$sRowH + 6 } else { $s0 + 18 }
    } else {
        $lblCtxUsedHdr.Visible=$false; $lblRecentChatsHdr.Visible=$false; $lblChevronHdr.Visible=$false
        for($k=0;$k -lt $MaxSessionsCap;$k++){ $sName[$k].Visible=$false; $sTrack[$k].Visible=$false; $sPct[$k].Visible=$false; $sSep[$k].Visible=$false; $sTok[$k].Visible=$false }
    }

    # LOCAL recent-chats section - mirrors the cloud block above exactly, just
    # sourced from $nSessLocal/$script:sessCollapsedLocal/$l* control arrays.
    # Fully hidden (including its own divider) when there are no local chats.
    if($nSessLocal -gt 0){
        $div3b.Top = $bottom + 2; $div3b.Visible=$true
        $ls0 = $div3b.Top + 8
        $lblLocalCtxUsedHdr.Top = $ls0; $lblLocalCtxUsedHdr.Visible=$true
        $lblLocalRecentChatsHdr.Top = $ls0; $lblLocalRecentChatsHdr.Visible=$true
        $lblLocalChevronHdr.Top = $ls0; $lblLocalChevronHdr.Visible=$true
        $lRowsShown = if($script:sessCollapsedLocal){ 0 } else { $nSessLocal }
        $lTop = $ls0 + 18
        for($k=0;$k -lt $MaxLocalSessionsCap;$k++){
            if($k -lt $lRowsShown){
                $y = $lTop + $k*$sRowH
                $lName[$k].Top=$y
                $lTrack[$k].Top=$y+5
                $lPct[$k].Top=$y
                $lSep[$k].Top=$y+3
                $lTok[$k].Top=$y
                $lName[$k].Visible=$true; $lTrack[$k].Visible=$true; $lPct[$k].Visible=$true; $lSep[$k].Visible=$true; $lTok[$k].Visible=$true
            } else {
                $lName[$k].Visible=$false; $lTrack[$k].Visible=$false; $lPct[$k].Visible=$false; $lSep[$k].Visible=$false; $lTok[$k].Visible=$false
            }
        }
        $bottom = if($lRowsShown -gt 0){ $lTop + $lRowsShown*$sRowH + 6 } else { $ls0 + 18 }
    } else {
        $div3b.Visible=$false
        $lblLocalCtxUsedHdr.Visible=$false; $lblLocalRecentChatsHdr.Visible=$false; $lblLocalChevronHdr.Visible=$false
        for($k=0;$k -lt $MaxLocalSessionsCap;$k++){ $lName[$k].Visible=$false; $lTrack[$k].Visible=$false; $lPct[$k].Visible=$false; $lSep[$k].Visible=$false; $lTok[$k].Visible=$false }
    }

    # bottom block: divider -> All Time Usage (2 lines) -> turns/sessions (left)
    # -> updated (right, the very bottom line)
    $div3.Top = $bottom + 2; $div3.Visible=$true
    $b0 = $div3.Top + 8
    # "All Time Usage:" headline gets more breathing room below it (6px), then
    # the cost/turns/updated detail lines read as one tight block (2px each) -
    # Jacob's feedback 2026-07-06: rows 1-2 had too little space, rows 2-3 had
    # too much; row 3-4 was already right.
    $lblTick1a.Top = $b0;      $lblTick1a.Visible=$true     # All Time Usage: (left)
    $lblTick1b.Top = $b0;      $lblTick1b.Visible=$true     # X tokens (right)
    $lblTick2a.Top = $b0 + 20; $lblTick2a.Visible=$true     # $X cached (left)
    $lblTick2Sep.Top = $b0 + 20; $lblTick2Sep.Visible=$true # · marker
    $lblTick2b.Top = $b0 + 20; $lblTick2b.Visible=$true     # $Y per token (right)
    # Local All-Time row only exists once local usage has ever been recorded -
    # everything below shifts down 16px (matching the existing row rhythm) when
    # it's shown, and sits exactly where it always did when it's not.
    if($hasLocalAllTime){
        $lblTickLa.Top = $b0 + 36; $lblTickLa.Visible=$true
        $lblTickLb.Top = $b0 + 36; $lblTickLb.Visible=$true
        $footTop = $b0 + 52
    } else {
        $lblTickLa.Visible=$false; $lblTickLb.Visible=$false
        $footTop = $b0 + 36
    }
    $lblFoot1a.Top = $footTop; $lblFoot1a.Visible=$true     # output (left)
    $lblFoot1Sep1.Top = $footTop; $lblFoot1Sep1.Visible=$true  # · marker
    $lblFoot1b.Top = $footTop; $lblFoot1b.Visible=$true     # turns (center)
    $lblFoot1Sep2.Top = $footTop; $lblFoot1Sep2.Visible=$true  # · marker
    $lblFoot1c.Top = $footTop; $lblFoot1c.Visible=$true     # sessions (right)
    $lblFoot2.Top = $footTop + 17;  $lblFoot2.Visible=$true # Updated Xs ago (right)
    $divT.Visible=$false                                    # (old ticker divider, unused now)
    $bottom = $footTop + 17 + 22

    $newH = $bottom
    if($form.Height -ne $newH){
        $form.Height = $newH
        Set-Region $newH
    }
    if($form.Top + $newH -gt $wa.Bottom - 4){ $form.Top = $wa.Bottom - $newH - 8 }
    if($form.Top -lt $wa.Top){ $form.Top = $wa.Top + 8 }
}
function Repaint($d,$cloudFams,$localModels,$stamp){
    Set-T $lblHero (Money $d.cost)
    Set-T $lblRawVal (Money $d.raw)
    $bm = $d.by
    for($k=0;$k -lt $cloudFams.Count;$k++){
        $f=$cloudFams[$k]
        Set-T $rowName[$k] $f
        Set-T $rowCost[$k] (Money $bm[$f].cost)
        Set-T $rowOut[$k]  (Fmt-Tok $bm[$f].tok)   # total tokens this model used today
    }
    for($k=0;$k -lt $localModels.Count;$k++){
        $lm = $localModels[$k]
        Set-T $lmName[$k] $lm.model
        Set-T $lmOut[$k] (Fmt-Tok $lm.tok)         # total tokens this exact local model used today
        $tip.SetToolTip($lmName[$k], $lm.model + "`n" + (Fmt-Tok $lm.tok) + ' tokens today  ' + $dotChar + '  ' + (Fmt-Ago $lm.last))
    }
    $arrow = [string][char]0x2193
    $sx = if($d.sessions -eq 1){'session'}else{'sessions'}
    Set-T $lblFoot1a ($arrow + ' ' + (Fmt-Tok $d.out) + ' output')
    Set-T $lblFoot1b ($d.turns.ToString() + ' turns')
    Set-T $lblFoot1c ($d.sessions.ToString() + ' ' + $sx)
    Set-T $lblFoot2 (Fmt-Ago $stamp)
}
# Paint the per-chat context rows: name (as in the app), a fill bar coloured by
# how full the context is, the percentage, and a hover tooltip with exact tokens.
# Paints a set of session rows into the given control arrays (used for BOTH
# the Cloud and Local recent-chats sections - same rendering, different data
# and different target controls/cap).
function Repaint-Sessions($sessions, $names, $tracks, $fills, $pcts, $seps, $toks, $cap){
    $dot=[string][char]0x00B7
    $m=[Math]::Min($sessions.Count,$cap)
    for($k=0;$k -lt $m;$k++){
        $s=$sessions[$k]
        Set-T $names[$k] $s.title
        $p=[double]$s.pct; $pc=$p; if($pc -gt 100){ $pc=100 }
        $w=[int]($sTrackW*$pc/100.0)
        if($fills[$k].Width -ne $w){ $fills[$k].Width=$w }
        $col=Hue $p
        $fills[$k].BackColor=$col
        Set-T $pcts[$k] (('{0:0}' -f $p) + '%')
        $pcts[$k].ForeColor=$col
        Set-T $toks[$k] (Fmt-Tok $s.ctx)          # absolute context tokens (the number behind the %)
        $detail = $s.title + "`n" + (Fmt-Tok $s.ctx) + ' / ' + (Fmt-Tok $s.win) + ' context tokens  ' + $dot + '  ' + ('{0:0}' -f $p) + '% used' + "`n" + (Family $s.model) + '  ' + $dot + '  ' + (Fmt-Ago $s.tstamp) + "`n" + 'right-click to archive'
        $tip.SetToolTip($names[$k], $detail)
        $tip.SetToolTip($tracks[$k], $detail)
        $tip.SetToolTip($toks[$k], $detail)
        # stamp the session id on every control in the row for the per-chat menu
        $names[$k].Tag=$s.id; $tracks[$k].Tag=$s.id; $fills[$k].Tag=$s.id; $pcts[$k].Tag=$s.id; $seps[$k].Tag=$s.id; $toks[$k].Tag=$s.id
    }
}
# All-time totals, summed from the persistent per-day history store (cheap; the
# same store the calendar uses). Throttled - all-time changes slowly. Reflects
# recorded history (grows as you use it; a calendar open fills in any old days).
function Get-AllTime {
    $now=[DateTime]::UtcNow
    if($script:allTime -and $script:allTimeAt -and ($now-$script:allTimeAt).TotalSeconds -lt 30){ return $script:allTime }
    $tok=0.0; $tokLocal=0.0; $cost=0.0; $raw=0.0
    try { $h=Load-History; foreach($k in $h.Keys){ $x=$h[$k]; $tok+=[double]$x.tok; $tokLocal+=[double]$x.tokLocal; $cost+=[double]$x.cost; $raw+=[double]$x.raw } } catch {}
    # Local (e.g. Ollama) tokens are never priced (always $0, see Get-Price/Family) and
    # use a different tokenizer than Claude's, so they're kept OUT of the Cloud/Claude
    # figures below - never blended into one mixed-unit number. Local's own total is
    # only shown in the calendar (Usage Windows page), where there's room to do it justice.
    $tokCloud = $tok - $tokLocal
    $script:allTime=@{ tok=$tok; tokLocal=$tokLocal; tokCloud=$tokCloud; cost=$cost; raw=$raw }; $script:allTimeAt=$now
    return $script:allTime
}
# Paint the bottom "All Time Usage:" lines (Claude/Cloud tokens + both cost
# estimates - Local/Ollama usage is tracked separately, never mixed in here)
# plus the Local All-Time row, once any local usage has ever been recorded.
function Repaint-Ticker {
    $a=Get-AllTime
    Set-T $lblTick1b ((Fmt-Tok $a.tokCloud) + ' tokens')
    Set-T $lblTick2a ((Money $a.cost) + ' cached')
    Set-T $lblTick2b ((Money $a.raw) + ' per token')
    if($a.tokLocal -gt 0){ Set-T $lblTickLb ((Fmt-Tok $a.tokLocal) + ' tokens') }
}
function Update-Widget {
    $r = Aggregate-Today
    $d = $r.agg
    $sess = @{ cloud=@(); local=@() }; try { $sess = Get-Sessions } catch {}
    $sessions=@($sess.cloud); $sessionsLocal=@($sess.local)
    $nSess = $sessions.Count; $nSessLocal = $sessionsLocal.Count
    $hasDaily = ($d.turns -gt 0)
    $allTime = Get-AllTime
    $hasLocalAllTime = ($allTime.tokLocal -gt 0)

    $cloudFams = if($hasDaily){ Active-CloudFamilies $d.by } else { @() }
    $localModels = if($hasDaily){ Get-RecentLocalModels $d.byLocalModel $MaxLocalModelRows } else { @() }
    $localModelKey = (($localModels | ForEach-Object { $_.model }) -join ',')
    $key = ($cloudFams -join ',') + '|' + $localModelKey + '|' + $nSess + '|' + $nSessLocal + '|' + [int]$script:sessCollapsed + '|' + [int]$script:sessCollapsedLocal + '|' + [int]$hasLocalAllTime
    if($key -ne $script:layoutKey){ Relayout $cloudFams $localModels $nSess $nSessLocal $hasLocalAllTime; $script:layoutKey=$key }

    if($hasDaily){
        Repaint $d $cloudFams $localModels $r.stamp
    } else {
        Set-T $lblHero '$0.00'; Set-T $lblRawVal '$0.00'
        Set-T $lblFoot1a 'no Claude usage yet today'
        Set-T $lblFoot1b ''; Set-T $lblFoot1c ''
        Set-T $lblFoot2 ''
    }
    if($nSess -gt 0){
        # header doubles as a collapse toggle: chevron + (count when collapsed).
        # "Context Used" only shows expanded; "Recent Cloud Chats" always shows,
        # right-justified, with the chevron to ITS right (the last thing in the row).
        $chev = if($script:sessCollapsed){ [string][char]0x25B8 } else { [string][char]0x25BE }   # > / v
        Set-T $lblChevronHdr $chev
        if($script:sessCollapsed){
            Set-T $lblCtxUsedHdr ''
            Set-T $lblRecentChatsHdr ('Recent Cloud Chats  (' + $nSess + ')')
        } else {
            Set-T $lblCtxUsedHdr 'Context Used'
            Set-T $lblRecentChatsHdr 'Recent Cloud Chats'
        }
        if(-not $script:sessCollapsed){ try { Repaint-Sessions $sessions $sName $sTrack $sFill $sPct $sSep $sTok $MaxSessions } catch {} }
    }
    if($nSessLocal -gt 0){
        $chevL = if($script:sessCollapsedLocal){ [string][char]0x25B8 } else { [string][char]0x25BE }
        Set-T $lblLocalChevronHdr $chevL
        if($script:sessCollapsedLocal){
            Set-T $lblLocalCtxUsedHdr ''
            Set-T $lblLocalRecentChatsHdr ('Recent Local Chats  (' + $nSessLocal + ')')
        } else {
            Set-T $lblLocalCtxUsedHdr 'Context Used'
            Set-T $lblLocalRecentChatsHdr 'Recent Local Chats'
        }
        if(-not $script:sessCollapsedLocal){ try { Repaint-Sessions $sessionsLocal $lName $lTrack $lFill $lPct $lSep $lTok $script:MaxLocalSessions } catch {} }
    }
    try { Repaint-Ticker } catch {}

    # keep today's total in the persistent history store (throttled to ~60s)
    if($hasDaily){
        $script:data = $d
        $now = [DateTime]::UtcNow
        if($null -eq $script:lastPersist -or ($now - $script:lastPersist).TotalSeconds -ge 60){
            Persist-Today $d; $script:lastPersist = $now
        }
    }
}

# --- history calendar -----------------------------------------------------
# Full deduped scan of EVERY transcript, bucketed by local day. Slower than the
# live path (reads all history once, ~a few seconds), so it runs only on demand.
function Scan-AllHistory {
    $files = @(Get-ChildItem (Join-Path $ProjRoot '*\*.jsonl') -ErrorAction SilentlyContinue) +
             @(Get-ChildItem (Join-Path $ProjRoot '*\*\subagents\*.jsonl') -ErrorAction SilentlyContinue)
    $seen=@{}; $byDay=@{}; $meta=@{}; $bySession=@{}
    # all-time exact-model breakdown for LOCAL usage only (Cloud stays family-
    # level everywhere else - see byModel above - since exact Claude model ids
    # aren't interesting the way distinct local/Ollama tags are).
    $byLocalModel=@{}
    # rolling windows as of scan time (last 5h / 7d / Fable-7d)
    $roll=@{ h5=@{tok=0.0;cost=0.0}; d7=@{tok=0.0;cost=0.0}; f7=@{tok=0.0;cost=0.0} }
    $rnow=Get-Date; $rc5=$rnow.AddHours(-$Roll5hHours); $rc7=$rnow.AddDays(-$Roll7dDays)
    foreach($f in $files){
        $isSub = (Split-Path $f.DirectoryName -Leaf) -eq 'subagents'
        if($isSub){ $sid = Split-Path (Split-Path $f.DirectoryName -Parent) -Leaf }
        else      { $sid = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
        if(-not $meta.ContainsKey($sid)){ $meta[$sid]=@{ label=$null; cwd=$null; custom=$null; ai=$null } }
        $fs=$null; $sr=$null
        try { $fs=New-Object System.IO.FileStream($f.FullName,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite); $sr=New-Object System.IO.StreamReader($fs) } catch { continue }
        try {
            while($null -ne ($line=$sr.ReadLine())){
                # label a session by its first real user prompt (top-level files only)
                if((-not $isSub) -and (-not $meta[$sid].label) -and $line.IndexOf('"user"') -ge 0){
                    try { $uo=$line|ConvertFrom-Json } catch { $uo=$null }
                    if($uo -and $uo.type -eq 'user' -and $uo.message){
                        $c=$uo.message.content; $txt=$null
                        if($c -is [string]){ $txt=$c } elseif($c){ $tb=($c | Where-Object { $_.type -eq 'text' } | Select-Object -First 1); if($tb){ $txt=$tb.text } }
                        if($txt){
                            $txt=($txt -replace '\s+',' ').Trim()
                            if($txt -and $txt -notmatch '^(This session is being continued|Caveat:|<command-|<local-command|\[Request interrupted)'){
                                if($txt.Length -gt 80){ $txt=$txt.Substring(0,80)+[char]0x2026 }
                                $meta[$sid].label=$txt
                            }
                        }
                    }
                }
                # capture the chat's app title (desktop-app format); keep the latest.
                # Title records are tiny, so skip big content lines that merely mention it.
                if((-not $isSub) -and $line.Length -lt 500){
                    if($line.IndexOf('"custom-title"') -ge 0){ try { $ct=($line|ConvertFrom-Json).customTitle; if(-not [string]::IsNullOrWhiteSpace($ct)){ $meta[$sid].custom=[string]$ct } } catch {} }
                    elseif($line.IndexOf('"ai-title"') -ge 0){ try { $at=($line|ConvertFrom-Json).aiTitle; if(-not [string]::IsNullOrWhiteSpace($at)){ $meta[$sid].ai=[string]$at } } catch {} }
                }
                if($line.IndexOf('output_tokens') -lt 0){ continue }
                try { $o=$line|ConvertFrom-Json } catch { continue }
                if($o.type -ne 'assistant'){ continue }
                $u=$o.message.usage; if($null -eq $u){ continue }
                $k="$($o.message.id)|$($o.requestId)"; if($k -eq '|'){ $k=$o.uuid }
                if($seen.ContainsKey($k)){ continue }; $seen[$k]=1
                try { $dt=([datetimeoffset]::Parse([string]$o.timestamp)).LocalDateTime } catch { continue }
                $day=$dt.ToString('yyyy-MM-dd'); $hh=$dt.Hour; $hm=$dt.ToString('HH:mm')
                if(-not $meta[$sid].cwd -and $o.cwd){ $meta[$sid].cwd = Split-Path ([string]$o.cwd) -Leaf }
                $i=[double]$u.input_tokens; $ou=[double]$u.output_tokens; $cr=[double]$u.cache_read_input_tokens; $cc=[double]$u.cache_creation_input_tokens
                $e5=0.0; $e1=0.0; if($u.cache_creation){ $e5=[double]$u.cache_creation.ephemeral_5m_input_tokens; $e1=[double]$u.cache_creation.ephemeral_1h_input_tokens } else { $e5=$cc }
                $pr=Get-Price $o.message.model; $bi=$pr.In/1e6; $bo=$pr.Out/1e6
                $tc=$i*$bi+$ou*$bo+$cr*($bi*0.1)+$e5*($bi*1.25)+$e1*($bi*2.0); $tr=($i+$cr+$cc)*$bi+$ou*$bo; $tkn=$i+$ou+$cr+$cc
                $fam=Family $o.message.model
                if(-not $byDay.ContainsKey($day)){ $byDay[$day]=@{cost=0.0;raw=0.0;tok=0.0;out=0.0;turns=0;byModel=@{};hours=(New-Object 'double[]' 24);sessions=@{}} }
                $d=$byDay[$day]; $d.cost+=$tc; $d.raw+=$tr; $d.tok+=$tkn; $d.out+=$ou; $d.turns++
                if($hh -ge 0 -and $hh -lt 24){ $d.hours[$hh]+=$tkn }
                if(-not $d.byModel.ContainsKey($fam)){ $d.byModel[$fam]=@{cost=0.0;raw=0.0;out=0.0;tok=0.0;turns=0} }
                $fm=$d.byModel[$fam]; $fm.cost+=$tc; $fm.raw+=$tr; $fm.out+=$ou; $fm.tok+=$tkn; $fm.turns++
                if(-not $d.sessions.ContainsKey($sid)){ $d.sessions[$sid]=@{cost=0.0;raw=0.0;tok=0.0;out=0.0;turns=0;byModel=@{};start=$hm;end=$hm} }
                $s=$d.sessions[$sid]; $s.cost+=$tc; $s.raw+=$tr; $s.tok+=$tkn; $s.out+=$ou; $s.turns++
                if($hm -lt $s.start){ $s.start=$hm }; if($hm -gt $s.end){ $s.end=$hm }
                if(-not $s.byModel.ContainsKey($fam)){ $s.byModel[$fam]=0.0 }; $s.byModel[$fam]+=$tkn
                # all-time per-chat rollup (subagent turns fold into the parent sid)
                if(-not $bySession.ContainsKey($sid)){ $bySession[$sid]=@{cost=0.0;raw=0.0;tok=0.0;out=0.0;turns=0;byModel=@{};first=$day;last=$day;days=@{}} }
                $g=$bySession[$sid]; $g.cost+=$tc; $g.raw+=$tr; $g.tok+=$tkn; $g.out+=$ou; $g.turns++
                if($day -lt $g.first){ $g.first=$day }; if($day -gt $g.last){ $g.last=$day }; $g.days[$day]=1
                if(-not $g.byModel.ContainsKey($fam)){ $g.byModel[$fam]=@{cost=0.0;tok=0.0;raw=0.0;out=0.0;turns=0} }
                $g.byModel[$fam].cost+=$tc; $g.byModel[$fam].tok+=$tkn; $g.byModel[$fam].raw+=$tr; $g.byModel[$fam].out+=$ou; $g.byModel[$fam].turns++
                if($fam -eq 'Local'){
                    $mkey=[string]$o.message.model; if([string]::IsNullOrWhiteSpace($mkey)){ $mkey='(unknown local model)' }
                    if(-not $byLocalModel.ContainsKey($mkey)){ $byLocalModel[$mkey]=@{ tok=0.0; turns=0; last=$dt } }
                    $lm=$byLocalModel[$mkey]; $lm.tok+=$tkn; $lm.turns++; if($dt -gt $lm.last){ $lm.last=$dt }
                }
                # rolling windows (as of scan time)
                if($dt -ge $rc7){
                    $roll.d7.tok+=$tkn; $roll.d7.cost+=$tc
                    if($fam -eq 'Fable'){ $roll.f7.tok+=$tkn; $roll.f7.cost+=$tc }
                    if($dt -ge $rc5){ $roll.h5.tok+=$tkn; $roll.h5.cost+=$tc }
                }
            }
        } catch { } finally { if($sr){ $sr.Close() }; if($fs){ $fs.Close() } }
    }
    return @{ byDay=$byDay; meta=$meta; bySession=$bySession; roll=$roll; byLocalModel=$byLocalModel }
}
# Persistent per-day store, so history survives Claude Code pruning old transcripts.
function Load-History {
    $h=@{}
    if(Test-Path $HistPath){
        try {
            $o = Get-Content $HistPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($p in $o.PSObject.Properties){ $v=$p.Value; $h[$p.Name]=@{cost=[double]$v.cost;raw=[double]$v.raw;tok=[double]$v.tok;tokLocal=[double]$v.tokLocal;out=[double]$v.out;turns=[int]$v.turns} }
        } catch { }
    }
    return $h
}
function Save-History($h){
    $clean=[ordered]@{}
    foreach($k in ($h.Keys | Sort-Object)){ $d=$h[$k]; $tl=if($d.tokLocal){$d.tokLocal}else{0}; $clean[$k]=[ordered]@{cost=[math]::Round($d.cost,2);raw=[math]::Round($d.raw,2);tok=[math]::Round($d.tok);tokLocal=[math]::Round($tl);out=[math]::Round($d.out);turns=$d.turns} }
    try { ($clean | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $HistPath -Encoding UTF8 } catch { }
    return $clean
}
# Continuously fold TODAY's live total into the persistent store, so long-term
# history accrues even if the calendar is never opened (and survives pruning).
# Guarded so a just-started widget that hasn't caught up can't shrink the day.
function Persist-Today($d){
    if($null -eq $d -or $d.turns -le 0){ return }
    try {
        $hist  = Load-History
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $tokLocal = if($d.by.ContainsKey('Local')){ $d.by['Local'].tok } else { 0.0 }
        if(-not $hist.ContainsKey($today) -or $d.turns -ge $hist[$today].turns){
            $hist[$today] = @{ cost=$d.cost; raw=$d.raw; tok=$d.tok; tokLocal=$tokLocal; out=$d.out; turns=$d.turns }
            [void](Save-History $hist)
        }
    } catch { }
}
# Scan -> merge into the store (keep the fuller record per day) -> generate the
# calendar from the template -> open it in the browser.
function Open-History {
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $scan = Scan-AllHistory
        # persist the simple per-day TOTALS (pruning-proof; drives heatmap for old days)
        $hist = Load-History
        foreach($k in $scan.byDay.Keys){
            $sd=$scan.byDay[$k]
            if(-not $hist.ContainsKey($k) -or $sd.turns -ge $hist[$k].turns){
                $tokLocal = if($sd.byModel.ContainsKey('Local')){ $sd.byModel['Local'].tok } else { 0.0 }
                $hist[$k]=@{ cost=$sd.cost; raw=$sd.raw; tok=$sd.tok; tokLocal=$tokLocal; out=$sd.out; turns=$sd.turns }
            }
        }
        [void](Save-History $hist)
        if(-not (Test-Path $CalTpl)){ $lblFoot2.Text='calendar-template.html missing'; return }

        # build the rich embedded data: every day (scanned + pruned-but-stored),
        # with per-model, hourly, and per-session detail where transcripts still exist
        $embed=[ordered]@{}
        foreach($day in ($hist.Keys | Sort-Object)){
            $t=$hist[$day]
            $tlv = if($t.tokLocal){ $t.tokLocal } else { 0 }
            $entry=[ordered]@{ cost=[math]::Round($t.cost,2); raw=[math]::Round($t.raw,2); tok=[math]::Round($t.tok); tokLocal=[math]::Round($tlv); out=[math]::Round($t.out); turns=$t.turns; byModel=[ordered]@{}; hours=@(); sessions=@() }
            $rich=$scan.byDay[$day]
            if($rich){
                foreach($fam in ($rich.byModel.Keys | Sort-Object { $rich.byModel[$_].tok } -Descending)){
                    $x=$rich.byModel[$fam]; $entry.byModel[$fam]=[ordered]@{ cost=[math]::Round($x.cost,2); raw=[math]::Round($x.raw,2); out=[math]::Round($x.out); tok=[math]::Round($x.tok); turns=$x.turns }
                }
                $entry.hours=@($rich.hours | ForEach-Object { [math]::Round($_) })
                $sess=@()
                foreach($sid in ($rich.sessions.Keys | Sort-Object { $rich.sessions[$_].tok } -Descending)){
                    if($script:archived -and $script:archived.ContainsKey($sid)){ continue }   # archived: keep in totals, drop from the list
                    $s=$rich.sessions[$sid]; $m=$scan.meta[$sid]
                    $topFam=''; $topTok=-1.0; foreach($fam in $s.byModel.Keys){ if($s.byModel[$fam] -gt $topTok){ $topTok=$s.byModel[$fam]; $topFam=$fam } }
                    $lbl = if($m -and $m.custom){ $m.custom } elseif($m -and $m.ai){ $m.ai } elseif($m -and $m.label){ $m.label } else { '(no prompt captured)' }
                    $cw  = if($m -and $m.cwd){ $m.cwd } else { '' }
                    $sess += ,([ordered]@{ id=$sid.Substring(0,8); label=$lbl; cwd=$cw; start=$s.start; end=$s.end; turns=$s.turns; tok=[math]::Round($s.tok); cost=[math]::Round($s.cost,2); raw=[math]::Round($s.raw,2); out=[math]::Round($s.out); model=$topFam })
                }
                $entry.sessions=$sess
            }
            $embed[$day]=$entry
        }
        $json = $embed | ConvertTo-Json -Depth 12 -Compress
        if($null -eq $json -or $json.Trim() -eq '' ){ $json='{}' }

        # all-time per-chat catalog (every session we still have logs for), for the
        # zebra "All chats" list on the calendar's main view.
        $allSess=@()
        foreach($sid in $scan.bySession.Keys){
            if($script:archived -and $script:archived.ContainsKey($sid)){ continue }   # archived: keep in totals, drop from the catalog
            $g=$scan.bySession[$sid]; $m=$scan.meta[$sid]
            $name = if($m -and $m.custom){ $m.custom } elseif($m -and $m.ai){ $m.ai } elseif($m -and $m.label){ $m.label } else { '(untitled chat)' }
            $cw   = if($m -and $m.cwd){ $m.cwd } else { '' }
            $bmodel=@()
            foreach($fam in ($g.byModel.Keys | Sort-Object { $g.byModel[$_].tok } -Descending)){
                $x=$g.byModel[$fam]
                $bmodel += ,([ordered]@{ model=$fam; tok=[math]::Round($x.tok); cost=[math]::Round($x.cost,2); raw=[math]::Round($x.raw,2); out=[math]::Round($x.out); turns=$x.turns })
            }
            $allSess += ,([ordered]@{ id=$sid.Substring(0,8); name=$name; cwd=$cw; tok=[math]::Round($g.tok); cost=[math]::Round($g.cost,2); raw=[math]::Round($g.raw,2); out=[math]::Round($g.out); turns=$g.turns; first=$g.first; last=$g.last; days=$g.days.Count; byModel=$bmodel })
        }
        $sessJson = if($allSess.Count -eq 0){ '[]' } elseif($allSess.Count -eq 1){ '[' + ($allSess[0] | ConvertTo-Json -Depth 8 -Compress) + ']' } else { $allSess | ConvertTo-Json -Depth 8 -Compress }

        # all-time distinct local models (e.g. different Ollama tags), ranked by
        # total tokens - the Local Usage page's breakdown (an all-time view, so
        # ranked by volume rather than the widget's "last 5 used" recency view).
        $localModels=@()
        foreach($mk in ($scan.byLocalModel.Keys | Sort-Object { $scan.byLocalModel[$_].tok } -Descending)){
            $x=$scan.byLocalModel[$mk]
            $localModels += ,([ordered]@{ model=$mk; tok=[math]::Round($x.tok); turns=$x.turns; last=$x.last.ToString('o') })
        }
        $localModelsJson = if($localModels.Count -eq 0){ '[]' } elseif($localModels.Count -eq 1){ '[' + ($localModels[0] | ConvertTo-Json -Depth 5 -Compress) + ']' } else { $localModels | ConvertTo-Json -Depth 5 -Compress }

        # rolling usage windows (last 5h / 7d / Fable-7d) as of the scan
        $rl = $scan.roll
        $rollJson = ([ordered]@{
            h5=[ordered]@{ tok=[math]::Round($rl.h5.tok); cost=[math]::Round($rl.h5.cost,2) }
            d7=[ordered]@{ tok=[math]::Round($rl.d7.tok); cost=[math]::Round($rl.d7.cost,2) }
            f7=[ordered]@{ tok=[math]::Round($rl.f7.tok); cost=[math]::Round($rl.f7.cost,2) }
        } | ConvertTo-Json -Depth 5 -Compress)

        $tpl  = Get-Content $CalTpl -Raw -Encoding UTF8
        $gen  = (Get-Date).ToString('MMM d, yyyy h:mm tt')
        $html = $tpl.Replace('__USAGE_DATA__',$json).Replace('__ALL_SESSIONS__',$sessJson).Replace('__ROLLING__',$rollJson).Replace('__LOCAL_MODELS__',$localModelsJson).Replace('__GENERATED__',$gen)
        [System.IO.File]::WriteAllText($CalOut,$html,(New-Object System.Text.UTF8Encoding($false)))
        Start-Process $CalOut
    } catch { } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

# --- timer + run ----------------------------------------------------------
$script:archived = Load-Archived  # restore the user's archived-chats list
Load-Settings                     # restore the recent-chats count (if changed from the calendar before)
Start-SettingsServer              # start listening for the calendar's settings panel
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Update-Widget; Poll-SettingsServer })
# Paint the placeholder layout first (DoEvents), THEN run the first scan - which
# can take a few seconds when it reads the whole day from cold - so the window
# appears immediately instead of as a frozen blank rectangle.
$form.Add_Shown({
    [System.Windows.Forms.Application]::DoEvents()
    Update-Widget
    $timer.Start()
})

[void]$form.ShowDialog()
if($script:singleInstance){ try { $script:singleInstance.ReleaseMutex() } catch {} }
