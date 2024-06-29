#!/usr/bin/env bash

QUERY_DIR="$(git rev-parse --show-toplevel)/tree-sitter/queries/"

function fetch_query() {
  lang=${1}
  echo "Fetching highlights query for ${lang}"
  wget https://raw.githubusercontent.com/tree-sitter/tree-sitter-${lang}/master/queries/highlights.scm \
    -O ${QUERY_DIR}highlights-${lang}.scm
}

fetch_query c
fetch_query cpp
fetch_query zig
fetch_query bash
fetch_query python
fetch_query json
fetch_query rust
fetch_query toml
