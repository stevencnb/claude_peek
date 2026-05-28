#!/usr/bin/env bash
#
# Unit tests for peek-guard.sh — no subagent required.
#
# Each case pipes a simulated PreToolUse hook payload into the guard and checks the
# emitted permissionDecision (or no output, for the main-session no-op). Dangerous
# command strings are kept LITERAL (single-quoted, or backticks injected via $BT) so
# nothing actually runs here.
#
# Usage:  bash plugins/peek/tests/test-peek-guard.sh
# Requires: bash, jq. Exits non-zero if any case fails.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/../scripts/peek-guard.sh"
BT=$(printf '\140')   # a literal backtick, injected safely

command -v jq >/dev/null 2>&1 || { echo "jq is required to run these tests"; exit 2; }
[ -f "$GUARD" ] || { echo "guard not found at $GUARD"; exit 2; }

pass=0; fail=0; fails=""

run() {
  at="$1"; cmd="$2"; want="$3"
  if [ "$at" = "-" ]; then
    json=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -n --arg c "$cmd" --arg a "$at" '{tool_name:"Bash",tool_input:{command:$c},agent_type:$a}')
  fi
  out=$(printf '%s' "$json" | bash "$GUARD" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then got="deny"            # hard floor: exit 2 blocks the call
  elif [ -n "$out" ]; then
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
    [ -z "$got" ] && got="bad-json"
  else got="noop"; fi                            # exit 0 + no stdout = main-session no-op
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf 'PASS  %-14s want=%-5s  %s\n' "$at" "$want" "$cmd"
  else
    fail=$((fail+1)); printf 'FAIL  %-14s want=%-5s got=%-5s  %s\n' "$at" "$want" "$got" "$cmd"
    fails="$fails\n  [$at] $cmd (want $want, got $got)"
  fi
}

echo "---- main session must be untouched (no-op) ----"
run - "rm -rf /" noop
run - "git commit -m x" noop
run - "anything at all" noop

echo "---- inside inspector: ALLOW (read-only) ----"
run peek-inspector "git status" allow
run peek-inspector "git log -5" allow
run peek-inspector "git log --oneline -5" allow
run peek-inspector "git diff -- src/a.js" allow
run peek-inspector "git diff --staged" allow
run peek-inspector "git show HEAD~2" allow
run peek-inspector "git branch -a" allow
run peek-inspector "git branch" allow
run peek-inspector "git remote -v" allow
run peek-inspector "git config --get user.name" allow
run peek-inspector "git stash list" allow
run peek-inspector "git ls-files" allow
run peek-inspector "git -C sub status" allow
run peek-inspector "git --no-pager log -3" allow
run peek-inspector "tree -L 2" allow
run peek-inspector "cat README.md" allow
run peek-inspector "ls -la" allow
run peek-inspector "head -n 20 file.txt" allow
run peek-inspector "find . -name '*.js'" allow
run peek-inspector "git log | head" allow
run peek-inspector "cat a && cat b" allow

echo "---- inside inspector: DENY (mutating / escape) ----"
run peek-inspector "git commit -m x" deny
run peek-inspector "git push" deny
run peek-inspector "git push origin main" deny
run peek-inspector "git checkout main" deny
run peek-inspector "git switch main" deny
run peek-inspector "git reset --hard" deny
run peek-inspector "git restore f" deny
run peek-inspector "git clean -fd" deny
run peek-inspector "git stash" deny
run peek-inspector "git stash pop" deny
run peek-inspector "git branch -d feature" deny
run peek-inspector "git branch -D feature" deny
run peek-inspector "git remote add origin url" deny
run peek-inspector "git rebase main" deny
run peek-inspector "git merge dev" deny
run peek-inspector "rm file" deny
run peek-inspector "mv a b" deny
run peek-inspector "cp a b" deny
run peek-inspector "mkdir x" deny
run peek-inspector "touch x" deny
run peek-inspector "cat f > out" deny
run peek-inspector "echo hi > /tmp/x" deny
run peek-inspector "cat a >> b" deny
run peek-inspector "ls && rm x" deny
run peek-inspector "ls; rm x" deny
# shellcheck disable=SC2016  # literal $(...) is the test input; it must NOT expand here
run peek-inspector 'echo $(rm x)' deny
run peek-inspector "cat ${BT}ls${BT}" deny
run peek-inspector "find . -name '*.js' -delete" deny
run peek-inspector "find . -exec rm {} ;" deny
run peek-inspector "python -c 'import os'" deny
run peek-inspector "bash -c 'rm x'" deny
run peek-inspector "sudo ls" deny
run peek-inspector "npm test" deny
run peek-inspector "sed -i s/a/b/ f" deny
run peek-inspector "awk '{print}' f" deny
run peek-inspector "git -c alias.x='!rm' x" deny
run peek-inspector "git -c core.pager=touch log" deny

echo "---- inside inspector: wrappers hiding a mutator must DENY ----"
run peek-inspector "ls | xargs rm" deny
run peek-inspector "env FOO=1 rm x" deny
run peek-inspector "timeout 5 rm x" deny
run peek-inspector "nohup rm x" deny
run peek-inspector "nice -n 10 rm x" deny

echo "---- inside inspector: write-capable options on read subcommands must DENY ----"
run peek-inspector "git diff --output=/tmp/x" deny
run peek-inspector "git diff --output /tmp/x" deny
run peek-inspector "git show --output=/tmp/x HEAD" deny
run peek-inspector "git log --output=/tmp/x -1" deny
run peek-inspector "git format-patch --output-directory /tmp HEAD~1" deny
run peek-inspector "git diff --output-indicator-new=x" allow

echo "---- inside inspector: weird chars don't break deny (exit 2) or ask/allow JSON ----"
TAB=$(printf '\t')
run peek-inspector "rm${TAB}x" deny
run peek-inspector 'rm "a b"' deny
run peek-inspector 'weird"tool x' ask

echo "---- inside inspector: dangerous env overrides must DENY ----"
run peek-inspector "GIT_PAGER=evil git -p log" deny
run peek-inspector "GIT_EXTERNAL_DIFF=evil git diff" deny
run peek-inspector "LD_PRELOAD=/tmp/x.so ls" deny
run peek-inspector "PATH=/tmp git status" deny
run peek-inspector "FOO=1 git status" allow
run peek-inspector "TZ=UTC git log -1" allow

echo "---- inside inspector: find exec/ok variants must DENY ----"
run peek-inspector "find . -execdir rm {} ;" deny
run peek-inspector "find . -ok rm {} ;" deny
run peek-inspector "find . -okdir rm {} ;" deny

echo "---- inside inspector: git config reads allow, writes deny ----"
run peek-inspector "git config user.email" allow
run peek-inspector "git config --global user.name" allow
run peek-inspector "git config --unset user.name" deny
run peek-inspector "git config --add core.x y" deny
run peek-inspector "git config user.email newval" ask

echo "---- inside inspector: ASK (grey zone) ----"
run peek-inspector "psql -c whatever" ask
run peek-inspector "git branch newbranch" ask
run peek-inspector "some-unknown-tool --flag" ask
run peek-inspector "git frobnicate" ask
run peek-inspector "docker ps" ask
run peek-inspector "xargs grep foo" ask
run peek-inspector "nice -n 10 ls" ask

echo "---- deny is a hard block: guard exits 2 (blocks in every permission mode) ----"
rc_of() {  # exit code of the guard for agent ($1) / command ($2)
  if [ "$1" = "-" ]; then j=$(jq -n --arg c "$2" '{tool_input:{command:$c}}')
  else j=$(jq -n --arg c "$2" --arg a "$1" '{tool_input:{command:$c},agent_type:$a}'); fi
  printf '%s' "$j" | bash "$GUARD" >/dev/null 2>&1; echo "$?"
}
check_rc() {
  got=$(rc_of "$1" "$2")
  if [ "$got" = "$3" ]; then pass=$((pass+1)); printf 'PASS  exit=%-3s %s\n' "$got" "$2"
  else fail=$((fail+1)); printf 'FAIL  want-exit=%-3s got-exit=%-3s %s\n' "$3" "$got" "$2"; fails="$fails\n  exit[$1] $2 (want $3 got $got)"; fi
}
check_rc peek-inspector "rm file" 2
check_rc peek-inspector "git commit -m x" 2
check_rc peek-inspector "cat f > out" 2
check_rc peek-inspector "git status" 0
check_rc peek-inspector "docker ps" 0
check_rc - "rm -rf /" 0

echo ""
echo "================ RESULT: $pass passed, $fail failed ================"
if [ "$fail" -gt 0 ]; then printf 'FAILURES:%b\n' "$fails"; exit 1; fi
exit 0
