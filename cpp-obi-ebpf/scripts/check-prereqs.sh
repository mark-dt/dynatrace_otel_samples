#!/usr/bin/env bash
# Verifies this host can actually run OBI, before you spend time on the rest.
#
# OBI is eBPF: it only runs on Linux. On macOS or Windows, run this sample
# inside a Linux VM (see the README).
set -uo pipefail

ok=0
fail=0
say_ok()   { echo "  [ ok ] $*"; ok=$((ok + 1)); }
say_fail() { echo "  [FAIL] $*"; fail=$((fail + 1)); }

echo "OBI prerequisites:"

# --- OS ---
if [ "$(uname -s)" != "Linux" ]; then
  say_fail "OS is $(uname -s), not Linux — eBPF instrumentation cannot run here."
  echo
  echo "Run this sample in a Linux VM. See 'Running on macOS' in the README."
  exit 1
fi
say_ok "Linux ($(uname -s))"

# --- kernel >= 5.8 ---
kver=$(uname -r)
kmaj=${kver%%.*}
krest=${kver#*.}
kmin=${krest%%.*}
if [ "$kmaj" -gt 5 ] || { [ "$kmaj" -eq 5 ] && [ "$kmin" -ge 8 ]; }; then
  say_ok "kernel $kver (needs 5.8+)"
else
  say_fail "kernel $kver is older than 5.8"
fi

# --- BTF ---
# Without BTF the probes cannot load. OBI would still start and report nothing,
# which is the most confusing failure mode of the lot — so check explicitly.
if [ -r /sys/kernel/btf/vmlinux ]; then
  say_ok "BTF present (/sys/kernel/btf/vmlinux)"
else
  say_fail "no /sys/kernel/btf/vmlinux — kernel built without BTF"
fi

# --- root ---
if [ "$(id -u)" -eq 0 ]; then
  say_ok "running as root"
elif sudo -n true 2>/dev/null; then
  say_ok "passwordless sudo available"
elif command -v sudo >/dev/null 2>&1; then
  say_ok "sudo present (will prompt for a password)"
else
  say_fail "no root and no sudo — OBI needs elevated privileges"
fi

# --- compiler ---
if command -v "${CXX:-g++}" >/dev/null 2>&1; then
  say_ok "$("${CXX:-g++}" --version | head -1)"
else
  say_fail "no C++ compiler — install g++ (apt install g++)"
fi

echo
if [ "$fail" -gt 0 ]; then
  echo "$fail check(s) failed."
  exit 1
fi
echo "All $ok checks passed."
