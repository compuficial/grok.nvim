#!/usr/bin/env bash
# grok PreToolUse hook: gate agent file edits behind a Neovim diff review.
#
# Without $NVIM: exit 0 with no decision so plain-terminal grok is unchanged.
# With $NVIM: fail-closed — registration/poll failures and unpresentable edits
# deny the tool (the TUI runs acceptEdits; silent fail-open would auto-apply).
set -u

deny() {
  # Reasons are static ASCII — no JSON escaping needed.
  printf '%s\n' "{\"decision\": \"deny\", \"reason\": \"$1\"}"
  exit 2
}

[ -n "${NVIM:-}" ] || exit 0
command -v nvim >/dev/null 2>&1 || exit 0

payload_file=$(mktemp "${TMPDIR:-/tmp}/grok-nvim-review.XXXXXX") || deny "Failed to create temp file for edit review"
trap 'rm -f "$payload_file"' EXIT

cat >"$payload_file" || deny "Failed to buffer PreToolUse payload"
[ -s "$payload_file" ] || deny "Empty PreToolUse payload"

# Path only on the CLI (short); payload body stays on disk — avoids ARG_MAX
# and base64 line-wrapping differences across platforms.
path_esc=${payload_file//\'/\'\\\'\'}
id=$(nvim --server "$NVIM" --remote-expr "v:lua.require'grok.review'._rpc_file('$path_esc')" 2>/dev/null) \
  || deny "Neovim RPC failed while registering edit review"

# remote-expr may quote the return value; keep digits only.
id=$(printf '%s' "$id" | tr -cd '0-9')
[ -n "$id" ] || deny "Could not present edit for review in Neovim"

deadline=$(($(date +%s) + ${GROK_NVIM_REVIEW_TIMEOUT:-240} + 10))
while [ "$(date +%s)" -lt "$deadline" ]; do
  status=$(nvim --server "$NVIM" --remote-expr "v:lua.require'grok.review'._status($id)" 2>/dev/null) \
    || deny "Neovim RPC failed while polling edit review"
  status=$(printf '%s' "$status" | tr -d "'\"[:space:]")
  case "$status" in
    allow)
      echo '{"decision": "allow"}'
      exit 0
      ;;
    deny)
      echo '{"decision": "deny", "reason": "Edit rejected by user in Neovim diff review"}'
      exit 2
      ;;
    pending)
      sleep 0.2
      ;;
    *)
      deny "Unknown review status from Neovim"
      ;;
  esac
done

deny "Neovim diff review timed out"
