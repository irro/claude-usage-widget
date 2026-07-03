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
$Version  = '1.2.1'   # bump on each release; shown next to the title in the widget

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
        default           { return @{ In=5.0;  Out=25.0 } }   # unknown -> Opus-tier
    }
}

# Group a model id into a display family for the per-model usage rows.
function Family($m){
    switch -Wildcard ($m){
        'claude-opus-*'   { 'Opus' }
        'claude-sonnet-*' { 'Sonnet' }
        'claude-haiku-*'  { 'Haiku' }
        'claude-fable-*'  { 'Fable' }
        'claude-mythos-*' { 'Fable' }
        default           { 'Other' }
    }
}

# The daily-tokens bar measures TODAY's cumulative tokens (input + output +
# cache read + cache write, summed across every session) against this budget.
# A transcript-only widget can't read your real plan rate-limit, so this is a
# tunable "how heavy is today" gauge - set it to a ceiling meaningful to you.
# Default 2B: an ordinary day sits low-to-mid, only a marathon day fills it.
$DailyBudgetTokens = 2000000000

# --- state ----------------------------------------------------------------
$script:files     = @{}     # path -> per-file accumulator (today only)
$script:curDay    = $null   # 'yyyy-MM-dd' the accumulators belong to
$script:seenToday = @{}     # message.id|requestId -> 1 (dedup resumed/copied turns)
$script:layoutKey = $null
$script:data      = $null   # latest today aggregate (for the on-close save)
$script:lastPersist = $null # last time today's total was written to the history store

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

# Fixed family order + colour for the per-model rows. Only families with usage
# are shown, in this order. 'Other' (unknown model ids) is intentionally NOT in
# the order, so it gets no row - but its tokens/cost still count in the totals.
$FamOrder = @('Opus','Sonnet','Haiku','Fable')
$FamColor = @{ Opus=$cCyan; Sonnet=$cPurple; Haiku=$cGreen; Fable=$cAmber; Other=$cDim }

function Hue([double]$p){ if($p -ge 90){$cRed}elseif($p -ge 70){$cAmber}else{$cGreen} }

# --- layout constants -----------------------------------------------------
$W        = 300            # form width
$padL     = 12
$rowH     = 20             # per-model row height
$heroTagY = 32
$heroY    = 45             # big "spent today" number
$rawY     = 83             # "if billed per token" line
$div1Y    = 105
$barY     = 112            # daily-tokens bar row
$rowsTop  = 138            # first model row

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
    try { $p = (Get-Content $PosPath -Raw) -split ','; $form.Left=[int]$p[0]; $form.Top=[int]$p[1] }
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
$lblTitle = New-Lbl $padL 9 86 18 $cCyan 9.5 $true ; $lblTitle.Text = 'Claude usage'
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
$lblHeroTag = New-Lbl $padL $heroTagY 200 14 $cDim 8 $false ; $lblHeroTag.Text = 'spent today  ' + [string][char]0x00B7 + '  cached'
$lblHero    = New-Lbl $padL $heroY ($W-2*$padL) 34 $cCyan 20 $true ; $lblHero.Text = '$0.00' ; $lblHero.TextAlign = 'MiddleLeft'

# raw "if billed per token"
$lblRawTag = New-Lbl $padL $rawY 150 16 $cDim 8.5 $false ; $lblRawTag.Text = 'if billed per token'
$lblRawVal = New-Lbl ($W-130) $rawY (130-$padL) 16 $cAmber 9.5 $true ; $lblRawVal.TextAlign='MiddleRight'

# divider 1
$div1 = New-Object System.Windows.Forms.Panel
$div1.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div1.BackColor = $cTrack
$div1.Location = New-Object System.Drawing.Point($padL,$div1Y)
$form.Controls.Add($div1)

# daily-tokens bar
$lblBarTag = New-Lbl $padL $barY 44 16 $cDim 8.5 $false ; $lblBarTag.Text = 'tokens'
$trackBar = New-Object System.Windows.Forms.Panel
$trackBar.Location  = New-Object System.Drawing.Point(56,($barY+3))
$trackBar.Size      = New-Object System.Drawing.Size(140,9)
$trackBar.BackColor = $cTrack
$fillBar  = New-Object System.Windows.Forms.Panel
$fillBar.Location   = New-Object System.Drawing.Point(0,0)
$fillBar.Size       = New-Object System.Drawing.Size(0,9)
$fillBar.BackColor  = $cGreen
$trackBar.Controls.Add($fillBar)
$form.Controls.Add($trackBar)
$lblBarVal = New-Lbl 200 ($barY-1) ($W-200-$padL) 16 $cText 8.5 $true
$lblBarVal.TextAlign = 'MiddleRight'

# per-model rows: 5 fixed slots (name | cost | output), shown/hidden per usage
$rowName=@(); $rowCost=@(); $rowOut=@()
for($k=0;$k -lt 5;$k++){
    $y = $rowsTop + $k*$rowH
    $rn = New-Lbl $padL $y 64 17 $cText 9.5 $true
    $rc = New-Lbl 80 $y 104 17 $cText 9.5 $false
    $ro = New-Lbl 188 ($y+1) ($W-188-$padL) 15 $cDim 8.5 $false ; $ro.TextAlign = 'MiddleRight'
    $rn.Visible=$false; $rc.Visible=$false; $ro.Visible=$false
    $rowName += ,$rn ; $rowCost += ,$rc ; $rowOut += ,$ro
}

# divider 2 + footer (positioned by Relayout)
$div2 = New-Object System.Windows.Forms.Panel
$div2.Size = New-Object System.Drawing.Size(($W-2*$padL),1)
$div2.BackColor = $cTrack
$div2.Location = New-Object System.Drawing.Point($padL,180)
$form.Controls.Add($div2)

$lblFoot1 = New-Lbl $padL 188 ($W-2*$padL) 15 $cText 8 $false ; $lblFoot1.Text = 'starting...'
$lblFoot2 = New-Lbl $padL 203 ($W-2*$padL) 14 $cDim  8 $false ; $lblFoot2.Text = ''

# --- right-click menu -----------------------------------------------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miC = $menu.Items.Add('History (calendar)') ; $miC.Add_Click({ Open-History })
$miR = $menu.Items.Add('Refresh now')        ; $miR.Add_Click({ $script:curDay=$null; Update-Widget })
$miH = $menu.Items.Add('Open instructions')  ; $miH.Add_Click({ try { Start-Process (Join-Path $PSScriptRoot 'admin-instructions.html') } catch {} })
[void]$menu.Items.Add('-')
$miX = $menu.Items.Add('Exit')               ; $miX.Add_Click({ $form.Close() })
$form.ContextMenuStrip = $menu

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
$dragCtrls = @($form,$lblTitle,$lblVer,$lblHeroTag,$lblHero,$lblRawTag,$lblRawVal,$div1,$lblBarTag,$trackBar,$fillBar,$lblBarVal,$div2,$lblFoot1,$lblFoot2)
$dragCtrls += $rowName + $rowCost + $rowOut
foreach($c in $dragCtrls){ Wire-Drag $c }

function Save-Pos { try { "$($form.Left),$($form.Top)" | Set-Content -LiteralPath $PosPath -Encoding ASCII } catch {} }
$form.Add_FormClosing({ Save-Pos; if($script:data){ Persist-Today $script:data } })

# --- data: today's aggregate across all sessions --------------------------
function New-FileState { @{ off=[long]0; lw=$null; turns=0; out=0.0; tok=0.0; cost=0.0; raw=0.0; by=@{} } }

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
            $st.off=0; $st.turns=0; $st.out=0.0; $st.tok=0.0; $st.cost=0.0; $st.raw=0.0; $st.by=@{}
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
            try { if(([datetimeoffset]::Parse([string]$o.timestamp)).LocalDateTime.Date -ne $todayDate){ continue } } catch { continue }
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
            if(-not $st.by.ContainsKey($fam)){ $st.by[$fam] = @{ out=0.0; cost=0.0; raw=0.0 } }
            $st.by[$fam].out  += $ou
            $st.by[$fam].cost += $tc
            $st.by[$fam].raw  += $tr
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

    $agg = @{ turns=0; out=0.0; tok=0.0; cost=0.0; raw=0.0; by=@{}; sessions=0 }
    foreach($f in $all){
        $st = $script:files[$f.FullName]; if($null -eq $st){ continue }
        $isSub = (Split-Path $f.DirectoryName -Leaf) -eq 'subagents'
        $agg.turns += $st.turns; $agg.out += $st.out; $agg.tok += $st.tok; $agg.cost += $st.cost; $agg.raw += $st.raw
        foreach($fam in $st.by.Keys){
            if(-not $agg.by.ContainsKey($fam)){ $agg.by[$fam] = @{ out=0.0; cost=0.0; raw=0.0 } }
            $agg.by[$fam].out  += $st.by[$fam].out
            $agg.by[$fam].cost += $st.by[$fam].cost
            $agg.by[$fam].raw  += $st.by[$fam].raw
        }
        if((-not $isSub) -and $st.turns -gt 0){ $agg.sessions++ }
    }
    return @{ agg=$agg; stamp=$stamp }
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
    if($null -eq $mtimeUtc){ return 'updated just now' }
    $s = ([DateTimeOffset]::UtcNow - [DateTimeOffset]$mtimeUtc).TotalSeconds
    if($s -lt 0){ $s = 0 }
    if($s -lt 60){ 'updated ' + [int]$s + 's ago' }
    elseif($s -lt 3600){ 'updated ' + [int]($s/60) + 'm ago' }
    else { 'updated ' + [int]($s/3600) + 'h ago' }
}
function Set-Bar($tok){
    $pct = if($DailyBudgetTokens -gt 0){ 100.0*$tok/$DailyBudgetTokens } else { 0 }
    $p = $pct; if($p -lt 0){$p=0}; if($p -gt 100){$p=100}
    $w = [int](140*$p/100)
    if($fillBar.Width -ne $w){ $fillBar.Width = $w }
    $fillBar.BackColor = (Hue $pct)
    Set-T $lblBarVal ((Fmt-Tok $tok) + ' / ' + (Fmt-Tok $DailyBudgetTokens))
}

# --- render ---------------------------------------------------------------
# Families with usage, in fixed display order.
function Active-Families($bm){
    $r=@(); foreach($f in $FamOrder){ if($bm.ContainsKey($f)){ $r += $f } }
    if($r.Count -eq 0){ $r = @('Opus') }
    ,$r
}
# Reposition rows + divider + footer and resize the form for N model rows.
# Called only when the set of active families changes (not every tick).
function Relayout($fams){
    $n = $fams.Count
    for($k=0;$k -lt 5;$k++){
        if($k -lt $n){
            $y = $rowsTop + $k*$rowH
            $rowName[$k].Top=$y; $rowCost[$k].Top=$y; $rowOut[$k].Top=$y+1
            $rowName[$k].ForeColor = $FamColor[$fams[$k]]
            $rowName[$k].Visible=$true; $rowCost[$k].Visible=$true; $rowOut[$k].Visible=$true
        } else {
            $rowName[$k].Visible=$false; $rowCost[$k].Visible=$false; $rowOut[$k].Visible=$false
        }
    }
    $dY = $rowsTop + $n*$rowH + 6
    $div2.Top     = $dY
    $lblFoot1.Top = $dY + 8
    $lblFoot2.Top = $dY + 23
    $newH = $dY + 40
    if($form.Height -ne $newH){
        $form.Height = $newH
        Set-Region $newH
    }
    if($form.Top + $newH -gt $wa.Bottom - 4){ $form.Top = $wa.Bottom - $newH - 8 }
    if($form.Top -lt $wa.Top){ $form.Top = $wa.Top + 8 }
}
function Repaint($d,$fams,$stamp){
    Set-T $lblHero (Money $d.cost)
    Set-T $lblRawVal (Money $d.raw)
    Set-Bar $d.tok
    $bm = $d.by; $arrow = [string][char]0x2193
    for($k=0;$k -lt $fams.Count;$k++){
        $f=$fams[$k]
        Set-T $rowName[$k] $f
        Set-T $rowCost[$k] (Money $bm[$f].cost)
        Set-T $rowOut[$k]  ($arrow + ' ' + (Fmt-Tok $bm[$f].out))
    }
    $dot = [string][char]0x00B7
    $sx = if($d.sessions -eq 1){'session'}else{'sessions'}
    Set-T $lblFoot1 ($arrow + ' ' + (Fmt-Tok $d.out) + ' output   ' + $dot + '   ' + $d.turns + ' turns   ' + $dot + '   ' + $d.sessions + ' ' + $sx)
    Set-T $lblFoot2 (Fmt-Ago $stamp)
}
function Update-Widget {
    $r = Aggregate-Today
    $d = $r.agg
    if($d.turns -le 0){
        Set-T $lblHero '$0.00'; Set-T $lblRawVal '$0.00'
        if($fillBar.Width -ne 0){ $fillBar.Width = 0 }
        Set-T $lblBarVal ('0 / ' + (Fmt-Tok $DailyBudgetTokens))
        for($k=0;$k -lt 5;$k++){ $rowName[$k].Visible=$false; $rowCost[$k].Visible=$false; $rowOut[$k].Visible=$false }
        Set-T $lblFoot1 'no Claude usage yet today'
        Set-T $lblFoot2 ''
        $script:layoutKey = $null
        return
    }
    $fams = Active-Families $d.by
    $key = ($fams -join ',')
    if($key -ne $script:layoutKey){ Relayout $fams; $script:layoutKey=$key }
    Repaint $d $fams $r.stamp
    # keep today's total in the persistent history store (throttled to ~60s)
    $script:data = $d
    $now = [DateTime]::UtcNow
    if($null -eq $script:lastPersist -or ($now - $script:lastPersist).TotalSeconds -ge 60){
        Persist-Today $d; $script:lastPersist = $now
    }
}

# --- history calendar -----------------------------------------------------
# Full deduped scan of EVERY transcript, bucketed by local day. Slower than the
# live path (reads all history once, ~a few seconds), so it runs only on demand.
function Scan-AllHistory {
    $files = @(Get-ChildItem (Join-Path $ProjRoot '*\*.jsonl') -ErrorAction SilentlyContinue) +
             @(Get-ChildItem (Join-Path $ProjRoot '*\*\subagents\*.jsonl') -ErrorAction SilentlyContinue)
    $seen=@{}; $byDay=@{}; $meta=@{}
    foreach($f in $files){
        $isSub = (Split-Path $f.DirectoryName -Leaf) -eq 'subagents'
        if($isSub){ $sid = Split-Path (Split-Path $f.DirectoryName -Parent) -Leaf }
        else      { $sid = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
        if(-not $meta.ContainsKey($sid)){ $meta[$sid]=@{ label=$null; cwd=$null } }
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
            }
        } catch { } finally { if($sr){ $sr.Close() }; if($fs){ $fs.Close() } }
    }
    return @{ byDay=$byDay; meta=$meta }
}
# Persistent per-day store, so history survives Claude Code pruning old transcripts.
function Load-History {
    $h=@{}
    if(Test-Path $HistPath){
        try {
            $o = Get-Content $HistPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach($p in $o.PSObject.Properties){ $v=$p.Value; $h[$p.Name]=@{cost=[double]$v.cost;raw=[double]$v.raw;tok=[double]$v.tok;out=[double]$v.out;turns=[int]$v.turns} }
        } catch { }
    }
    return $h
}
function Save-History($h){
    $clean=[ordered]@{}
    foreach($k in ($h.Keys | Sort-Object)){ $d=$h[$k]; $clean[$k]=[ordered]@{cost=[math]::Round($d.cost,2);raw=[math]::Round($d.raw,2);tok=[math]::Round($d.tok);out=[math]::Round($d.out);turns=$d.turns} }
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
        if(-not $hist.ContainsKey($today) -or $d.turns -ge $hist[$today].turns){
            $hist[$today] = @{ cost=$d.cost; raw=$d.raw; tok=$d.tok; out=$d.out; turns=$d.turns }
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
                $hist[$k]=@{ cost=$sd.cost; raw=$sd.raw; tok=$sd.tok; out=$sd.out; turns=$sd.turns }
            }
        }
        [void](Save-History $hist)
        if(-not (Test-Path $CalTpl)){ $lblFoot2.Text='calendar-template.html missing'; return }

        # build the rich embedded data: every day (scanned + pruned-but-stored),
        # with per-model, hourly, and per-session detail where transcripts still exist
        $embed=[ordered]@{}
        foreach($day in ($hist.Keys | Sort-Object)){
            $t=$hist[$day]
            $entry=[ordered]@{ cost=[math]::Round($t.cost,2); raw=[math]::Round($t.raw,2); tok=[math]::Round($t.tok); out=[math]::Round($t.out); turns=$t.turns; byModel=[ordered]@{}; hours=@(); sessions=@() }
            $rich=$scan.byDay[$day]
            if($rich){
                foreach($fam in ($rich.byModel.Keys | Sort-Object { $rich.byModel[$_].tok } -Descending)){
                    $x=$rich.byModel[$fam]; $entry.byModel[$fam]=[ordered]@{ cost=[math]::Round($x.cost,2); raw=[math]::Round($x.raw,2); out=[math]::Round($x.out); tok=[math]::Round($x.tok); turns=$x.turns }
                }
                $entry.hours=@($rich.hours | ForEach-Object { [math]::Round($_) })
                $sess=@()
                foreach($sid in ($rich.sessions.Keys | Sort-Object { $rich.sessions[$_].tok } -Descending)){
                    $s=$rich.sessions[$sid]; $m=$scan.meta[$sid]
                    $topFam=''; $topTok=-1.0; foreach($fam in $s.byModel.Keys){ if($s.byModel[$fam] -gt $topTok){ $topTok=$s.byModel[$fam]; $topFam=$fam } }
                    $lbl = if($m -and $m.label){ $m.label } else { '(no prompt captured)' }
                    $cw  = if($m -and $m.cwd){ $m.cwd } else { '' }
                    $sess += ,([ordered]@{ id=$sid.Substring(0,8); label=$lbl; cwd=$cw; start=$s.start; end=$s.end; turns=$s.turns; tok=[math]::Round($s.tok); cost=[math]::Round($s.cost,2); raw=[math]::Round($s.raw,2); out=[math]::Round($s.out); model=$topFam })
                }
                $entry.sessions=$sess
            }
            $embed[$day]=$entry
        }
        $json = $embed | ConvertTo-Json -Depth 12 -Compress
        if($null -eq $json -or $json.Trim() -eq '' ){ $json='{}' }
        $tpl  = Get-Content $CalTpl -Raw -Encoding UTF8
        $gen  = (Get-Date).ToString('MMM d, yyyy h:mm tt')
        $html = $tpl.Replace('__USAGE_DATA__',$json).Replace('__GENERATED__',$gen)
        [System.IO.File]::WriteAllText($CalOut,$html,(New-Object System.Text.UTF8Encoding($false)))
        Start-Process $CalOut
    } catch { } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

# --- timer + run ----------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Update-Widget })
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
