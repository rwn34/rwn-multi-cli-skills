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
