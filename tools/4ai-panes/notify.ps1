# notify.ps1 - fleet Telegram notifications for the pane-runner loop (task #26).
#
# Dot-sourceable (via $PSScriptRoot) alongside fleet-clis.ps1. Exposes
# Send-FleetNotification, which posts a short Markdown line to a Telegram topic
# when the self-driving pane-runner picks up / finishes / alerts on a handoff.
#
# Design contract:
#   - FAIL-OPEN. A notify failure must NEVER break the pane loop, so every path
#     is wrapped in try/catch and returns silently (Write-Warning at most).
#   - Feature OFF by default: if bot_token OR chat_id is unresolved from either
#     source, the function returns without sending and without erroring.
#   - Config resolution: ENV VARS FIRST (RWN_TELEGRAM_BOT_TOKEN /
#     RWN_TELEGRAM_CHAT_ID / RWN_TELEGRAM_THREAD_ID), then fall back to the
#     gitignored, outside-repo file ~/.rwn-auto/notify.json for any piece still
#     missing. The token is NEVER stored in-repo (see notify.json.example).
#   - 5s timeout on the HTTP call so a slow network can't stall the loop.
#
# ASCII-only source (Telegram emoji are built at runtime from code points via
# [char]::ConvertFromUtf32, never embedded as literal non-ASCII bytes).

# Resolve the Telegram config. Env vars win; the outside-repo notify.json fills
# any still-missing piece. Returns a pscustomobject { BotToken; ChatId; ThreadId }
# or $null when bot_token/chat_id can't be resolved (feature off). Never throws.
function Resolve-FleetNotifyConfig {
    $botToken = $env:RWN_TELEGRAM_BOT_TOKEN
    $chatId   = $env:RWN_TELEGRAM_CHAT_ID
    $threadId = $env:RWN_TELEGRAM_THREAD_ID

    $needFile = ([string]::IsNullOrWhiteSpace($botToken) -or
                 [string]::IsNullOrWhiteSpace($chatId) -or
                 [string]::IsNullOrWhiteSpace($threadId))
    if ($needFile) {
        $path = Join-Path $HOME '.rwn-auto/notify.json'
        if (Test-Path -LiteralPath $path) {
            try {
                $tg = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).telegram
                if ($tg) {
                    if ([string]::IsNullOrWhiteSpace($botToken) -and $tg.bot_token) { $botToken = [string]$tg.bot_token }
                    if ([string]::IsNullOrWhiteSpace($chatId)   -and $tg.chat_id)   { $chatId   = [string]$tg.chat_id }
                    if ([string]::IsNullOrWhiteSpace($threadId) -and $tg.thread_id) { $threadId = [string]$tg.thread_id }
                }
            } catch {
                Write-Warning "notify: could not parse ~/.rwn-auto/notify.json - $($_.Exception.Message)"
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($botToken) -or [string]::IsNullOrWhiteSpace($chatId)) { return $null }

    return [pscustomobject]@{
        BotToken = $botToken
        ChatId   = $chatId
        ThreadId = if ([string]::IsNullOrWhiteSpace($threadId)) { $null } else { $threadId }
    }
}

# Dedup / rate-throttle window (seconds). A notification identical to one already
# sent within this window (same Kind+Project+Handoff) is suppressed so a flapping
# pane loop cannot spam Telegram. Set to 0 to disable throttling entirely.
#
# The throttle is FILE-BACKED so it survives a supervised pane respawn:
# run-pane-supervised.ps1 spawns a FRESH pane-runner process on each crash, which
# would reset an in-process-only map and let a rapid crash-respawn-crash cycle emit
# one notification per respawn. The file (Kind|Project|Handoff -> last-sent UTC) is
# the cross-process source of truth; the in-process map below is only a fast path.
# State lives under the gitignored runtime area .ai/handoffs/.claims/ (ignored via
# ".ai/handoffs/.claims/*" in .gitignore) so it never enters version control.
#
# ABSOLUTE fail-open: if the file can't be read/parsed/written for ANY reason, the
# decision SENDS (never suppress-on-error, never throw) - a throttle malfunction
# must never silence a real alert. See Test-FleetNotifyThrottled.
$script:FleetNotifyThrottleSeconds = 60
$script:FleetNotifyLastSent = @{}
try {
    $script:FleetNotifyThrottlePath = [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '../../.ai/handoffs/.claims/.fleet-notify-throttle.json'))
} catch {
    $script:FleetNotifyThrottlePath = $null
}

# Decide whether a notification keyed $Key is throttled (suppress) or should send,
# recording a fresh send timestamp when it sends. File-backed (survives a respawn);
# the in-process map is a fast path that also collapses same-process dupes without
# file I/O. Returns $true = SUPPRESS, $false = SEND. FULLY fail-open: any read /
# parse / write failure returns $false (SEND). Never throws. On write it prunes
# entries older than 5 windows so the state file cannot grow unbounded. Atomic-ish
# write (temp + Move-Item -Force, BOM-less UTF-8) mirrors Write-Claim.
function Test-FleetNotifyThrottled {
    param(
        [string]$Key,
        [int]$WindowSeconds = $script:FleetNotifyThrottleSeconds,
        [string]$Path = $script:FleetNotifyThrottlePath
    )
    if ($WindowSeconds -le 0) { return $false }
    $nowUtc = (Get-Date).ToUniversalTime()

    # Fast in-process path (also collapses same-process dupes with no file I/O).
    try {
        $lastMem = $script:FleetNotifyLastSent[$Key]
        if ($lastMem -and (($nowUtc - $lastMem).TotalSeconds -lt $WindowSeconds)) { return $true }
    } catch { }

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    # File-backed cross-process check. Any failure to read/parse -> SEND (fail-open).
    $map = @{}
    try {
        if (Test-Path -LiteralPath $Path) {
            $json = Get-Content -LiteralPath $Path -Raw
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $parsed = $json | ConvertFrom-Json
                foreach ($prop in $parsed.PSObject.Properties) {
                    $when = [datetime]::MinValue
                    if ([datetime]::TryParse([string]$prop.Value, [ref]$when)) {
                        $map[$prop.Name] = $when.ToUniversalTime()
                    }
                }
            }
        }
    } catch {
        return $false
    }

    $last = $map[$Key]
    if ($last -and (($nowUtc - $last).TotalSeconds -lt $WindowSeconds)) {
        try { $script:FleetNotifyLastSent[$Key] = $last } catch { }
        return $true
    }

    # SEND: record the new timestamp, prune stale keys, write atomically. A write
    # failure here still returns $false (we already decided to send) - fail-open.
    $map[$Key] = $nowUtc
    try { $script:FleetNotifyLastSent[$Key] = $nowUtc } catch { }
    try {
        $cutoff = $nowUtc.AddSeconds(-5 * $WindowSeconds)
        $out = [ordered]@{}
        foreach ($k in ($map.Keys | Sort-Object)) {
            if ($map[$k] -ge $cutoff) { $out[$k] = $map[$k].ToString('yyyy-MM-ddTHH:mm:ssZ') }
        }
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $tmp = "$Path.tmp.$PID"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($out | ConvertTo-Json -Compress))
        [System.IO.File]::WriteAllBytes($tmp, $bytes)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } catch { }
    return $false
}

# Post a fleet event to the configured Telegram topic. Fail-open no-op if unset.
# -Kind is one of picked|done|alert; the text is built from Owner/Handoff/Project.
# Returns the Telegram API response object on send (callers pipe to Out-Null in
# the loop) or $null when the feature is off / on any error. NEVER throws.
function Send-FleetNotification {
    param(
        [ValidateSet('picked', 'done', 'alert')]
        [string]$Kind,
        [string]$Project,
        [string]$Handoff,
        [string]$Cli,
        [string]$Owner
    )
    try {
        $cfg = Resolve-FleetNotifyConfig
        if ($null -eq $cfg) { return $null }

        # Throttle: suppress an identical notification (same Kind+Project+Handoff)
        # already sent within FleetNotifyThrottleSeconds. Decided (and recorded) at
        # the send decision (not after the HTTP call), so a Telegram outage during a
        # flapping loop still can't spam. File-backed so it survives a supervised
        # respawn. Guarded so a throttle hiccup can never block a send (fail-open):
        # Test-FleetNotifyThrottled itself never throws, and any error here still
        # falls through and sends.
        if ($script:FleetNotifyThrottleSeconds -gt 0) {
            try {
                $throttleKey = "$Kind|$Project|$Handoff"
                if (Test-FleetNotifyThrottled -Key $throttleKey -WindowSeconds $script:FleetNotifyThrottleSeconds) {
                    return $null
                }
            } catch { }
        }

        # Emoji built at runtime from code points (keeps this source ASCII-only):
        #   picked = robot (U+1F916), done = check mark (U+2705), alert = warning (U+26A0)
        $emoji = switch ($Kind) {
            'picked' { [char]::ConvertFromUtf32(0x1F916) }
            'done'   { [char]::ConvertFromUtf32(0x2705) }
            'alert'  { [char]::ConvertFromUtf32(0x26A0) }
            default  { '' }
        }

        # Markdown two-line layout: the *bold* project leads on its own first
        # line (prominent + unambiguous), the owner + `code` handoff follow on
        # line 2. "`n" is the PowerShell newline inside the double-quoted string;
        # a literal backtick in the handoff code span is a doubled backtick.
        $text = switch ($Kind) {
            'picked' { "$emoji *$Project*`n$Owner picked up ``$Handoff``" }
            'done'   { "$emoji *$Project*`n$Owner finished ``$Handoff``" }
            'alert'  { "$emoji *$Project* -- needs a human`n$Owner ALERT on ``$Handoff``" }
            default  { "$emoji *$Project*`n$Owner ``$Handoff``" }
        }

        $body = @{
            chat_id    = $cfg.ChatId
            text       = $text
            parse_mode = 'Markdown'
        }
        if ($cfg.ThreadId) { $body.message_thread_id = $cfg.ThreadId }

        $uri = "https://api.telegram.org/bot$($cfg.BotToken)/sendMessage"
        return (Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 5)
    } catch {
        Write-Warning "notify: Send-FleetNotification failed - $($_.Exception.Message)"
        return $null
    }
}
