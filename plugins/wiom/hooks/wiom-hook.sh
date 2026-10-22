#!/bin/sh
# Wiom Builder hook (macOS / Linux / Git Bash). Usage: wiom-hook.sh <expansion|prompt|stop|posttool|sessionstart|sessionend>
#
# Privacy rule: nothing leaves this machine unless the session ran a /wiom:* command.
# Such sessions are flagged in $DATA/sessions/<session_id>; every other session exits immediately.
# Must never block Claude Code: all failures exit 0. Only "expansion" and "sessionstart" print model context;
# "posttool" may print a systemMessage (shown to the builder, not the model) after writing a brief file.

EVENT="$1"
VERSION="0.2.1"
# The service address is built in (no install-time field to get wrong). WIOM_BUILDER_URL overrides it for testing only.
URL="${WIOM_BUILDER_URL:-https://wiom-builder-production.up.railway.app}"
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

state_write() { # state_write <transcript_path> <offset>  (also records the upload time for throttling)
  tmp="$FLAG.tmp.$$"
  printf 'path=%s\noffset=%s\nlast=%s\n' "$1" "$2" "$(date +%s)" > "$tmp" && mv "$tmp" "$FLAG"
}

# Write the latest saved brief of <case> to <cwd>/wiom-briefs/<case>.md and tell the builder.
write_brief() {
  c=$(printf '%s' "$1" | sed -e 's/^[pP][dD]-/PD-/' -e 's/^[cC][dD]-/CD-/')
  c="${c%-*}-$(printf '%s' "${c##*-}" | tr 'A-F' 'a-f')"
  case "$c" in PD-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]|CD-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;; *) return 0 ;; esac
  dir=$(field cwd); [ -n "$dir" ] && [ -d "$dir" ] || dir="$HOME"
  dir="$dir/wiom-briefs"
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$c.md.$$"
  if api "/hooks/brief?case_id=$c" -o "$tmp" 2>/dev/null; then
    mv "$tmp" "$dir/$c.md" && printf '{"systemMessage":"Wiom Builder: brief saved to %s"}\n' "wiom-briefs/$c.md"
  else
    rm -f "$tmp"
  fi
  return 0
}

# Some stages run from a local copy of their agent folder (scripts, templates, sub-agent files).
# The service says which folder and commit; it is extracted under <cwd>/wiom-builder-agents/ once per
# commit. Never blocks the session: on any failure the agent is told the folder is missing by the service text.
checkout() {
  dir=$(field cwd); [ -n "$dir" ] && [ -d "$dir" ] || return 0
  tmp="$DATA/checkout.$$.tgz"; hdr="$DATA/checkout.$$.hdr"
  api "/hooks/checkout?session_id=$SID" --max-time 120 -D "$hdr" -o "$tmp" 2>/dev/null || { rm -f "$tmp" "$hdr"; return 0; }
  hv() { sed -n "s/^$1: *//Ip" "$hdr" | head -n 1 | tr -d '\r'; }
  sub=$(hv x-checkout-dir); folders=$(hv x-checkout-folder); stage=$(hv x-checkout-id); sha=$(hv x-commit-sha)
  rm -f "$hdr"
  if [ -z "$sub" ] || [ -z "$folders" ] || [ -z "$sha" ] || ! [ -s "$tmp" ]; then rm -f "$tmp"; return 0; fi
  target="$dir/$sub"; marker="$target/.wiom-${stage:-stage}.commit"
  if [ "$(cat "$marker" 2>/dev/null)" = "$sha" ]; then rm -f "$tmp"; return 0; fi
  mkdir -p "$target" 2>/dev/null || { rm -f "$tmp"; return 0; }
  # Folder names are separated by "|" (they may contain spaces). Each is replaced whole.
  oldifs=$IFS; IFS='|'
  for f in $folders; do [ -n "$f" ] && rm -rf "$target/$f"; done
  IFS=$oldifs
  tar -xzf "$tmp" -C "$target" 2>/dev/null && printf '%s\n' "$sha" > "$marker"
  rm -f "$tmp"
  return 0
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
      checkout
      printf '%s\n' "$RESP"
    else
      inject UserPromptExpansion "The Wiom Builder service could not be reached or rejected the token. This session is not recorded and the case was not created. Tell the builder to check their internet connection and token, and to contact Mukul if it keeps failing."
    fi
    ;;
  prompt|stop)
    [ -f "$FLAG" ] && upload >/dev/null 2>&1
    ;;
  posttool)
    [ -f "$FLAG" ] || exit 0
    TOOL=$(field tool_name)
    case "$TOOL" in
      *wiom__save_brief|*wiom__submit_brief)
        upload >/dev/null 2>&1
        write_brief "$(field case_id)"
        ;;
      *)
        # During long turns, upload at most every 15 seconds so the console stays near real time.
        now=$(date +%s); last=$(state_get last)
        case "$last" in ""|*[!0-9]*) last=0 ;; esac
        [ $((now - last)) -ge 15 ] && upload >/dev/null 2>&1
        ;;
    esac
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
