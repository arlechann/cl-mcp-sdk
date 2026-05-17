#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

ip_address=${1:-127.0.0.1}
port=${2:-6274}

HOST=${ip_address} ALLOWED_ORIGINS=http://${ip_address}:${port} npx @modelcontextprotocol/inspector sbcl --noinform --disable-debugger --load "${script_dir}/run-echo-server.lisp"
