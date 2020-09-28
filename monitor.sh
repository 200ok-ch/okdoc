#!/usr/bin/env bash

inotifywait -m . -e close_write |
  while read path action file; do
    if [[ "${file}" =~ .*pdf$ ]]; then
      make
    fi
  done
