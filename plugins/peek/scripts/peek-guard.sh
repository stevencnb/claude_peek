#!/usr/bin/env bash
# shellcheck disable=SC2086
#   ^ This guard deliberately relies on word-splitting (with `set -f` disabling globbing,
#     below) to tokenize commands and scan the space-separated PROG/ENV tables; unquoted
#     $vars are intentional throughout, so SC2086 ("double quote to prevent splitting")
#     is expected file-wide and would break the logic if "fixed".
#
# peek-guard.sh — PreToolUse Bash guard for the `peek-inspector` subagent.
#
# Behavior:
#   * Outside peek-inspector (your main session / any other agent): NO-OP.
#     Exits 0 with no output, so nothing you do normally is affected.
#   * Inside peek-inspector: classifies the Bash command three ways and emits a
#     PreToolUse permission decision on stdout:
#         deny  — destructive / escape / mutating commands (the hard floor)
#         allow — explicit read-only inspection commands (so /peek is smooth)
#         ask   — anything else (your config / a prompt decides)
#     Fails CLOSED inside the inspector (uncertain -> ask or deny); never elsewhere.
#
# Design notes:
#   * The scope gate is jq-free, so the main session never depends on jq.
#   * jq is used only to extract the command *inside* the inspector. If jq is
#     missing, the inspector denies with an install hint (main session unaffected).
#   * Targets bash 3.2 (macOS default): no associative arrays, no ${var,,}.
#   * Reference: docs confirm PreToolUse hooks receive `agent_type` (the agent's
#     frontmatter name) and that decisions compose with the user's own
#     allow/ask/deny rules (deny always wins).

set -u
set -f          # disable globbing; the guard must never expand pathnames

AGENT_NAME="peek-inspector"

input="$(cat)"

# ---------------------------------------------------------------------------
# 1) Scope gate (jq-free). Act ONLY inside the peek-inspector subagent.
#    On the main thread `agent_type` is absent, so this never matches.
# ---------------------------------------------------------------------------
if ! printf '%s' "$input" \
  | grep -Eq '"agent_type"[[:space:]]*:[[:space:]]*"'"$AGENT_NAME"'"'; then
  exit 0
fi

# ---------------------------------------------------------------------------
# emit DECISION REASON  — print a PreToolUse decision and exit.
# ---------------------------------------------------------------------------
emit() {
  # Escape backslash/quote, then neutralize ALL control chars (tab, newline, CR, …)
  # to spaces so the embedded command can never produce invalid JSON (which could
  # drop a deny decision and fail open).
  reason=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\000-\037' ' ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
  exit 0
}

# ---------------------------------------------------------------------------
# 2) Extract the command (jq). Fail closed inside the inspector if jq missing.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  emit deny "peek-inspector guard requires 'jq' to evaluate commands. Install jq (e.g. 'brew install jq') and retry."
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && emit allow "no command to run"

# ---------------------------------------------------------------------------
# 3a) Whole-string danger checks: redirection & command/process substitution.
#     Denied even if they appear inside quotes (acceptable for read-only use).
# ---------------------------------------------------------------------------
case "$cmd" in
  *'>'*)  emit deny "Output redirection ('>') is blocked in the read-only inspector." ;;
esac
case "$cmd" in
  *'`'*)  emit deny "Command substitution (backticks) is blocked in the read-only inspector." ;;
esac
# shellcheck disable=SC2016  # the literal '$(' is the match target, not an expansion
case "$cmd" in
  *'$('*) emit deny "Command substitution \$(...) is blocked in the read-only inspector." ;;
esac
case "$cmd" in
  *'<('*) emit deny "Process substitution <(...) is blocked in the read-only inspector." ;;
esac

# ---------------------------------------------------------------------------
# Program classification tables.
# ---------------------------------------------------------------------------
# Clearly read-only programs (besides git, find — handled specially).
RO_PROGS="ls tree cat head tail wc stat file pwd echo which basename dirname realpath readlink nl du hexdump xxd strings grep egrep fgrep"
# Hard mutators / interpreters / network / process control -> deny.
MUT_PROGS="rm rmdir mv cp ln dd tee truncate shred chmod chown chgrp install rsync mkfifo mknod sed gsed awk gawk nawk perl python python2 python3 ruby node deno bun php lua Rscript sh bash zsh ksh dash fish csh tcsh eval exec source apt apt-get yum dnf brew port pacman npm pnpm yarn pip pip3 pipx gem cargo go make cmake gcc cc clang curl wget scp sftp ssh nc ncat telnet kill pkill killall mount umount systemctl service launchctl crontab git-receive-pack patch tar unzip zip gzip gunzip bzip2 xz touch mkdir"
# Privilege escalation -> deny.
PRIV_PROGS="sudo doas su runas pkexec"
# Environment overrides that can turn a read command into code execution / library
# injection (git runs PAGER/EXTERNAL_DIFF/SSH/EDITOR via the shell; loaders honor LD_*/DYLD_*).
DANGER_ENV="GIT_PAGER PAGER GIT_EXTERNAL_DIFF GIT_DIFF_OPTS GIT_SSH GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_ASKPASS SSH_ASKPASS GIT_EDITOR GIT_SEQUENCE_EDITOR EDITOR VISUAL GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM LESSOPEN LESSCLOSE LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH BASH_ENV ENV SHELL IFS PATH PROMPT_COMMAND"

is_word_in() {  # $1=needle, rest=haystack words; 0 if found
  needle="$1"; shift
  for w in "$@"; do [ "$w" = "$needle" ] && return 0; done
  return 1
}

# classify_git_dual SUB ARGS  -> sets seg_dec / seg_reason for dual git subcommands
classify_git_dual() {
  gsub="$1"; gargs="$2"
  case "$gsub" in
    branch)
      case " $gargs " in
        *" -d "*|*" -D "*|*" -m "*|*" -M "*|*" -f "*|*" --delete "*|*" --move "*|*" --copy "*|*" --force "*|*" --edit-description "*|*" --set-upstream-to "*|*" --unset-upstream "*|*" -u "*)
          seg_dec="deny"; seg_reason="git branch delete/rename/force modifies refs"; return ;;
      esac
      for a in $gargs; do
        case "$a" in -*) ;; *) seg_dec="ask"; seg_reason="git branch with an argument may create/move a branch"; return ;; esac
      done
      seg_dec="allow"; return ;;
    tag)
      case " $gargs " in
        *" -d "*|*" --delete "*|*" -a "*|*" --annotate "*|*" -s "*|*" --sign "*|*" -m "*|*" -F "*|*" -f "*|*" --force "*)
          seg_dec="deny"; seg_reason="git tag create/delete modifies refs"; return ;;
      esac
      for a in $gargs; do
        case "$a" in -*) ;; *) seg_dec="ask"; seg_reason="git tag with an argument may create a tag"; return ;; esac
      done
      seg_dec="allow"; return ;;
    remote)
      set -- $gargs
      if [ "$#" -eq 0 ]; then seg_dec="allow"; return; fi
      case "$1" in
        -v|-vv|--verbose|show|get-url) seg_dec="allow"; return ;;
        *) seg_dec="deny"; seg_reason="git remote $1 modifies remotes"; return ;;
      esac ;;
    config)
      # explicit read flags -> allow
      case " $gargs " in
        *" --get "*|*" --get-all "*|*" --get-regexp "*|*" --get-urlmatch "*|*" --get-color "*|*" --get-colorbool "*|*" --list "*|*" -l "*)
          seg_dec="allow"; return ;;
      esac
      # write flags modify config even with a single key arg -> deny
      case " $gargs " in
        *" --add "*|*" --unset "*|*" --unset-all "*|*" --replace-all "*|*" --remove-section "*|*" --rename-section "*|*" --edit "*|*" -e "*)
          seg_dec="deny"; seg_reason="git config write flag modifies config"; return ;;
      esac
      # a single bare key with no value is a read (e.g. `git config user.email`);
      # `git config key value` (>=2 non-option args) is a set -> ask (user decides)
      n=0
      for a in $gargs; do case "$a" in -*) ;; *) n=$((n+1)) ;; esac; done
      if [ "$n" -eq 1 ]; then seg_dec="allow"; return; fi
      seg_dec="ask"; seg_reason="git config without --get/--list may set a value"; return ;;
    stash)
      set -- $gargs
      if [ "$#" -eq 0 ]; then seg_dec="deny"; seg_reason="bare 'git stash' saves a stash"; return; fi
      case "$1" in
        list|show) seg_dec="allow"; return ;;
        *) seg_dec="deny"; seg_reason="git stash $1 modifies stashes/working tree"; return ;;
      esac ;;
    worktree)
      set -- $gargs
      if [ "$#" -eq 0 ]; then seg_dec="ask"; seg_reason="git worktree needs a subcommand"; return; fi
      case "$1" in
        list) seg_dec="allow"; return ;;
        *) seg_dec="deny"; seg_reason="git worktree $1 modifies worktrees"; return ;;
      esac ;;
    reflog)
      set -- $gargs
      if [ "$#" -eq 0 ]; then seg_dec="allow"; return; fi
      case "$1" in
        expire|delete) seg_dec="deny"; seg_reason="git reflog $1 rewrites reflogs"; return ;;
        *) seg_dec="allow"; return ;;
      esac ;;
    symbolic-ref)
      n=0; for a in $gargs; do case "$a" in -*) ;; *) n=$((n+1)) ;; esac; done
      if [ "$n" -ge 2 ]; then seg_dec="deny"; seg_reason="git symbolic-ref set (write)"; return; fi
      seg_dec="allow"; return ;;
    notes)
      set -- $gargs
      if [ "$#" -eq 0 ]; then seg_dec="allow"; return; fi
      case "$1" in
        list|show|get-ref) seg_dec="allow"; return ;;
        *) seg_dec="deny"; seg_reason="git notes $1 modifies notes"; return ;;
      esac ;;
    *) seg_dec="ask"; seg_reason="git $gsub"; return ;;
  esac
}

# classify_git ARGS...  ($1 == "git")  -> sets seg_dec / seg_reason
classify_git() {
  shift   # drop 'git'
  # config/exec override flags enable alias/command injection -> deny
  case " $* " in
    *" -c "*|*" --exec-path"*|*" --upload-pack"*|*" --receive-pack"*)
      seg_dec="deny"; seg_reason="git -c/--exec-path overrides are not allowed"; return ;;
  esac
  # --output/--output-directory write a file (redirection by another name); any
  # subcommand that accepts them (diff/show/log/format-patch/…) could clobber a path.
  # Matched as whole tokens so read-only flags like --output-indicator-new are unaffected.
  case " $* " in
    *" --output "*|*" --output="*|*" --output-directory "*|*" --output-directory="*)
      seg_dec="deny"; seg_reason="git --output writes to a file and is not read-only"; return ;;
  esac
  # skip benign global options to reach the subcommand
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C) shift; [ "$#" -gt 0 ] && shift; continue ;;
      --git-dir=*|--work-tree=*|--namespace=*) shift; continue ;;
      -p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs) shift; continue ;;
      --) shift; break ;;
      -*) shift; continue ;;
      *) break ;;
    esac
  done
  if [ "$#" -eq 0 ]; then seg_dec="allow"; return; fi   # bare 'git' -> usage (read-only)
  sub="$1"; shift
  rest="$*"
  case "$sub" in
    status|log|diff|show|rev-parse|ls-files|ls-tree|cat-file|blame|shortlog|describe|show-ref|for-each-ref|name-rev|whatchanged|grep|rev-list|diff-tree|diff-index|count-objects|version|help|var|cherry|merge-base|verify-commit|verify-tag)
      seg_dec="allow"; return ;;
    add|commit|push|pull|fetch|merge|rebase|reset|restore|checkout|switch|clean|rm|mv|init|clone|am|apply|cherry-pick|revert|gc|prune|repack|submodule|update-index|update-ref|write-tree|commit-tree|hash-object|mktag|mktree|fast-import|filter-branch|maintenance|pack-objects|index-pack|replace|fsck|stage|unstage)
      seg_dec="deny"; seg_reason="git $sub modifies the repository"; return ;;
    branch|tag|remote|config|stash|worktree|reflog|symbolic-ref|notes)
      classify_git_dual "$sub" "$rest"; return ;;
    *) seg_dec="ask"; seg_reason="unrecognized git subcommand '$sub'"; return ;;
  esac
}

# classify SEGMENT  -> sets seg_dec / seg_reason
classify() {
  s="$1"
  set -- $s
  # skip leading VAR=val environment assignments; deny ones that can alter execution
  while [ "$#" -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*)
        env_var="${1%%=*}"
        if is_word_in "$env_var" $DANGER_ENV; then
          seg_dec="deny"; seg_reason="environment override '$env_var' can change how commands execute"; return
        fi
        shift ;;
      *) break ;;
    esac
  done
  if [ "$#" -eq 0 ]; then seg_dec="allow"; return; fi
  prog="$1"
  prog="${prog#\\}"        # strip a leading backslash (alias bypass)
  prog="${prog##*/}"       # strip leading path

  if is_word_in "$prog" $PRIV_PROGS; then
    seg_dec="deny"; seg_reason="privilege escalation ('$prog') is not allowed"; return
  fi
  if is_word_in "$prog" $MUT_PROGS; then
    seg_dec="deny"; seg_reason="'$prog' can modify the filesystem and is blocked"; return
  fi
  if [ "$prog" = "git" ]; then
    classify_git "$@"; return
  fi
  if [ "$prog" = "find" ]; then
    # -exec also covers -execdir, and -ok covers -okdir (matched here as prefixes).
    case " $s " in
      *" -delete"*|*" -exec"*|*" -ok"*|*" -fprintf"*|*" -fprint "*|*" -fprint0"*|*" -fls"*)
        seg_dec="deny"; seg_reason="find with -delete/-exec writes or executes"; return ;;
    esac
    seg_dec="allow"; return
  fi
  if is_word_in "$prog" $RO_PROGS; then
    seg_dec="allow"; return
  fi
  # Unrecognized program (this also covers command-runner wrappers like xargs, env,
  # timeout, nohup, nice, watch, flock, parallel). If any token invokes a known
  # mutator or privilege command, hard-deny; otherwise surface it as ask.
  for tok in $s; do
    t="${tok#\\}"; t="${t##*/}"
    if is_word_in "$t" $PRIV_PROGS; then
      seg_dec="deny"; seg_reason="privilege escalation ('$t') is not allowed"; return
    fi
    if is_word_in "$t" $MUT_PROGS; then
      seg_dec="deny"; seg_reason="'$t' (a mutating command) appears in this command"; return
    fi
  done
  seg_dec="ask"; seg_reason="'$prog' is not a recognized read-only command"
}

# ---------------------------------------------------------------------------
# 3b) Split on shell separators ( ; | & and thus && || |& ) plus newlines,
#     then classify every segment. deny wins over ask wins over allow.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2020  # mapping each of ; | & to a newline; tr interprets \n, three given for portability
segments="$(printf '%s' "$cmd" | tr ';|&' '\n\n\n')"

overall="allow"
ask_reason="approval required"

while IFS= read -r seg || [ -n "$seg" ]; do
  seg="$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$seg" ] && continue
  seg_dec="allow"; seg_reason=""
  classify "$seg"
  case "$seg_dec" in
    deny) emit deny "$seg_reason. (command: $seg)" ;;
    ask)  overall="ask"; ask_reason="$seg_reason" ;;
  esac
done <<EOF
$segments
EOF

if [ "$overall" = "ask" ]; then
  emit ask "peek-inspector: $ask_reason. Approve to run this read-only-intended command, or deny."
fi

emit allow "read-only inspection command"
