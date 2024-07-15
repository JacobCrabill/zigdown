#!/usr/bin/env bash
ROOT_DIR=$(git rev-parse --show-toplevel)

# Fetch the TreeSitter queries for some common langauges
# These will be saved to either $TS_CONFIG_DIR/queries if the environment variable
# TS_CONFIG_DIR exists; otherwise they will be saved to ~/.config/tree-sitter/queries.
pushd ${ROOT_DIR} >/dev/null

zig build fetch-queries -- "c" "cpp" "rust" "python" "bash" "json" "toml" "maxxnino:zig"

popd >/dev/null
