#!/bin/sh
# Wiom Builder hook (macOS / Linux). Usage: wiom-hook.sh <expansion|prompt|stop|sessionstart|sessionend>
#
# Privacy rule: nothing leaves this machine unless the session ran a /wiom:* command.
# Such sessions are flagged in $DATA/sessions/<session_id>; every other session exits immediately.
# Must never block Claude Code: all failures exit 0. Only "expansion" and "sessionstart" print to stdout.

EVENT="$1"
VERSION="0.1.0"
URL="${CLAUDE_PLUGIN_OPTION_SERVER_URL:-https://builder.wiom.in}"
URL="${URL%/}"
TOKEN="${CLAUDE_PLUGIN_OPTION_API_TOKEN:-}"
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.wiom-builder}"
STATE="$DATA/sessions"
MAX_CHUNK=20000000

INPUT=$(cat)

# Top-level string field from the single-line JSON Claude Code sends on stdin.
# JSON-escaped backslashes (Windows paths under Git Bash) are unescaped.
field() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -n 1 | sed 's/\\\\/\\/g'; }

SID=$(field session_id)
case "$SID" in
  ""|*[!A-Za-z0-9_-]*) exit 0 ;;
esac
FLAG="$STATE/$SID"

api() { # api <path> [curl args...]
  p="$1"; shift
  curl -sS -f --max-time 20 \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Plugin-Version: $VERSION" \
    -H "X-Client-OS: $(uname -s 2>/dev/null)" \
    "$@" "$URL$p"
}

inject() { # inject <hookEventName> <text without double quotes or backslashes>
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$2"
}

state_get() { sed -n "s/^$1=//p" "$FLAG" 2>/dev/null | head -n 1; }

state_write() { # state_write <transcript_path> <offset>
  tmp="$FLAG.tmp.$$"
  printf 'path=%s\noffset=%s\n' "$1" "$2" > "$tmp" && mv "$tmp" "$FLAG"
}

# Send transcript bytes appended since the last upload. The server stores complete lines and
# returns the next offset, so a partially written last line is simply sent again next time.
upload() {
  [ -f "$FLAG" ] || return 0
  tp=$(state_get path); off=$(state_get offset)
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  case "$off" in ""|*[!0-9]*) off=0 ;; esac
  size=$(wc -c < "$tp" | tr -d ' ')
  [ "$size" -gt "$off" ] 2>/dev/null || return 0
  resp=$(tail -c +"$((off + 1))" "$tp" | head -c "$MAX_CHUNK" | \
    api "/hooks/transcript?session_id=$SID&offset=$off" -H "Content-Type: application/octet-stream" --data-binary @-) || return 0
  next=$(printf '%s' "$resp" | sed -n 's/^next_offset=\([0-9][0-9]*\)$/\1/p')
  [ -n "$next" ] && state_write "$tp" "$next"
  return 0
}

case "$EVENT" in
  expansion)
    CMD=$(field command_name)
    case "$CMD" in wiom:*) ;; *) exit 0 ;; esac
    if [ -z "$TOKEN" ]; then
      inject UserPromptExpansion "Wiom Builder is not configured on this computer (no token). This session is not recorded. Tell the builder to run /plugin, select the wiom plugin, choose Configure, paste their Wiom Builder token, then run the command again."
      exit 0
    fi
    mkdir -p "$STATE" 2>/dev/null
    TP=$(field transcript_path)
    START=0
    [ -n "$TP" ] && [ -f "$TP" ] && START=$(wc -c < "$TP" | tr -d ' ')
    if RESP=$(printf '%s' "$INPUT" | api /hooks/start -H "Content-Type: application/json" -H "X-Start-Offset: $START" --data-binary @-); then
      state_write "$TP" "$START"
      printf '%s\n' "$RESP"
    else
      inject UserPromptExpansion "The Wiom Builder service could not be reached or rejected the token. This session is not recorded and the case was not created. Tell the builder to check their internet connection and token, and to contact Mukul if it keeps failing."
    fi
    ;;
  prompt|stop)
    [ -f "$FLAG" ] && upload >/dev/null 2>&1
    ;;
  sessionstart)
    [ -f "$FLAG" ] || exit 0
    upload >/dev/null 2>&1
    if RESP=$(printf '%s' "$INPUT" | api /hooks/resume -H "Content-Type: application/json" --data-binary @- 2>/dev/null); then
      printf '%s\n' "$RESP"
    fi
    ;;
  sessionend)
    [ -f "$FLAG" ] || exit 0
    upload >/dev/null 2>&1
    printf '%s' "$INPUT" | api /hooks/event -H "Content-Type: application/json" --data-binary @- >/dev/null 2>&1
    ;;
esac
exit 0
