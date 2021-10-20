#!/bin/sh

ROM_PATH="${ROM_PATH:-uxnyap.rom}"
ZIG_BUILD_ARGS=${ZIG_BUILD_ARGS:-}

REQ_PIPE="${REQ_PIPE:-reqs.fifo}"
RES_PIPE="${RES_PIPE:-resps.fifo}"

rm -rf "${REQ_PIPE}" "${RES_PIPE}" "${ROM_PATH}"
mkfifo "${REQ_PIPE}"
mkfifo "${RES_PIPE}"

uxnasm client.tal "${ROM_PATH}"

# shellcheck disable=SC2086
{
	zig build $ZIG_BUILD_ARGS
}

(uxncli "${ROM_PATH}" < "${RES_PIPE}" | cat > "${REQ_PIPE}") &
./zig-out/bin/uxnyap
