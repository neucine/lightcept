#!/bin/sh
set -eu
if [ "$#" -eq 2 ] && [ "$1" = "-V" ] && [ "$2" = "/?" ]; then
    echo "LLVM Resource Converter (Zig wrapper)"
    exit 0
fi
exec zig rc "$@"
