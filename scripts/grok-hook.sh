#!/usr/bin/env bash
# grok PreToolUse hook: gate agent file edits behind a Neovim diff review.
# Outside a Neovim terminal (no $NVIM) this exits without a decision, so
# grok's normal permission flow applies and plain-terminal use is unchanged.
set -u

[ -n "${NVIM:-}" ] || exit 0
command -v nvim >/dev/null 2>&1 || exit 0

b64=$(base64 -w0 2>/dev/null || base64)
[ -n "$b64" ] || exit 0

id=$(nvim --server "$NVIM" --remote-expr "v:lua.require'grok.review'._rpc('$b64')" 2>/dev/null) || exit 0
[ -n "$id" ] || exit 0

deadline=$(($(date +%s) + ${GROK_NVIM_REVIEW_TIMEOUT:-240} + 10))
while [ "$(date +%s)" -lt "$deadline" ]; do
  status=$(nvim --server "$NVIM" --remote-expr "v:lua.require'grok.review'._status($id)" 2>/dev/null) || exit 0
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
      exit 0
      ;;
  esac
done

echo '{"decision": "deny", "reason": "Neovim diff review timed out"}'
exit 2
