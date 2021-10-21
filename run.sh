#!/bin/sh

ROM_PATH="${ROM_PATH:-uxnyap.rom}"
ZIG_BUILD_ARGS=${ZIG_BUILD_ARGS:-}

REQ_PIPE="${REQ_PIPE:-reqs.fifo}"
RES_PIPE="${RES_PIPE:-resps.fifo}"

rm -rf "${REQ_PIPE}" "${RES_PIPE}" "${ROM_PATH}" resp_debug
mkfifo "${REQ_PIPE}"
mkfifo "${RES_PIPE}"

uxnasm client.tal "${ROM_PATH}"

# shellcheck disable=SC2086
{
	zig build $ZIG_BUILD_ARGS
}

(cat "${RES_PIPE}" | tee resp_debug) &
(uxncli "${ROM_PATH}" | cat > "${REQ_PIPE}") &
./zig-out/bin/uxnyap
