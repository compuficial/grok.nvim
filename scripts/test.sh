#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${1:-tests/}"
nvim --headless -u "$ROOT/tests/minimal_init.lua" \
  -c "lua if vim.fn.exists(':PlenaryBustedDirectory') == 0 then vim.api.nvim_err_writeln('plenary.nvim not found (set PLENARY_DIR or clone into deps/plenary.nvim)') vim.cmd('cquit 1') end" \
  -c "PlenaryBustedDirectory $ROOT/$SPEC {minimal_init='$ROOT/tests/minimal_init.lua'}" \
  +qa
