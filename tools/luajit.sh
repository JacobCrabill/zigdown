#!/usr/bin/env bash
if ! command -v rlwrap >/dev/null; then
  echo "rlwrap is not installed - try 'sudo apt install rlwrap'"
  exit 1
fi
rlwrap luajit
