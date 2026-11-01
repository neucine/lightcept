#!/bin/sh
set -eu

filtered=""
for argument in "$@"; do
    case "$argument" in
        --target=x86_64-pc-windows-gnu|-m64) ;;
        *) filtered="$filtered
$argument" ;;
    esac
done

set --
old_ifs=$IFS
IFS='
'
for argument in $filtered; do
    set -- "$@" "$argument"
done
IFS=$old_ifs

exec zig cc -target x86_64-windows-gnu "$@"
