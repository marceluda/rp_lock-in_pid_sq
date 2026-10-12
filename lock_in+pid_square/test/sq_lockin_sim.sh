#!/bin/bash
# Simulates the square generator (lock/gen_mod_sq.v) and the square lock-in of fpga/prj/v0.94/rtl/lock.v
# with test/sq_lockin_tb.v in Vivado 2020.1 xsim (lock_in+pid_square v2.0.0).
# Usage: test/sq_lockin_sim.sh [work_dir]     (default: a temporary directory, removed at the end)
# Exit status 0 if the testbench prints "TB RESULT: PASS".
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PRJ="$HERE/../fpga/prj/v0.94/rtl"
TB="$HERE/sq_lockin_tb.v"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/Vivado/2020.1/settings64.sh}"
WORK="${1:-$(mktemp -d)}"
mkdir -p "$WORK"
# lock/abs_val.v is not used by lock.v (and has a trailing comma that xvlog rejects): not compiled
env -i HOME="$HOME" PATH=/usr/local/bin:/usr/bin:/bin LANG=C LC_ALL=C bash -c "
  . '$VIVADO_SETTINGS' > /dev/null &&
  cd '$WORK' &&
  xvlog '$PRJ/lock.v' \$(ls '$PRJ'/lock/*.v | grep -v '/abs_val.v\$') '$TB' &&
  xvlog \$XILINX_VIVADO/data/verilog/src/glbl.v &&
  xelab -debug typical --timescale 1ns/1ps -L unisims_ver sq_lockin_tb glbl -s sq_lockin_tb_sim &&
  xsim sq_lockin_tb_sim -R
" 2>&1 | tee "$WORK/sq_lockin_sim.log"
RC=1
grep -q "TB RESULT: PASS" "$WORK/sq_lockin_sim.log" && RC=0
[ -z "$1" ] && rm -rf "$WORK"
exit $RC
