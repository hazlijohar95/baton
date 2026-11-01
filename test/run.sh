#!/bin/bash
# End-to-end tests for bin/baton with stub claude, rex and acc in a throwaway HOME. Runs under bash 3.2.
# shellcheck disable=SC1010,SC2155  # `$BATON done` is a subcommand, not the loop keyword; PATH export is test setup.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BATON="/bin/bash $ROOT/skills/baton/scripts/baton"
pass=0 fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [[ -n ${2:-} ]] && printf '     %s\n' "$2"; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
expect_fail() { local name=$1 pattern=$2; shift 2; local out; if out=$("$@" 2>&1); then bad "$name" "succeeded: $out"; elif grep -q "$pattern" <<<"$out"; then ok "$name"; else bad "$name" "$out"; fi; }

setup() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/baton-test.XXXXXX")
  export HOME=$T/home LOG=$T/log STUB=$T/stub
  mkdir -p "$HOME" "$STUB" "$T/bin" "$HOME/.claude-a" "$HOME/.claude-b" "$HOME/.claude-c"
  : >"$LOG"
  unset TMUX BATON_BACKEND BATON_WORKER BATON_MODEL BATON_PERMISSION_MODE BATON_ACCOUNTS_FILE
  export REX_SESSION=sess REX_BLOCK=main-block BATON_POLL=0.2
  export CLAUDE_CONFIG_DIR=$HOME/.claude-a
  export PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v jq)")"
  write_stubs
  git init -q -b main "$T/repo" && cd "$T/repo" || exit 1
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git config user.name t && git config user.email t@t
}

write_stubs() {
  cat >"$T/bin/claude" <<'EOF'
#!/bin/bash
printf 'claude %s\n' "$*" >>"$LOG"
printf '%s\n' "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR-unset} BATON_WORKER=${BATON_WORKER-} PWD=$PWD" >>"$LOG"
settings="" prompt=""
while (( $# )); do case $1 in --settings) settings=$2; shift 2 ;; -n|--append-system-prompt|--model|--permission-mode) shift 2 ;; *) prompt=$1; shift ;; esac; done
hook() { jq -r ".hooks.$1[0].hooks[0].command" "$settings"; }
echo '{"session_id":"sess-1","hook_event_name":"SessionStart"}' | eval "$(hook SessionStart)"
if [[ -n ${FAKE_COMMIT:-} ]]; then echo work >"work-$RANDOM.txt"; git add -A && git commit -qm "worker change"; fi
[[ -n ${FAKE_DIRTY:-} ]] && echo dirty >dirty.txt
sleep "${FAKE_WORK:-0}"
jq -n --arg m "finished: $prompt" '{session_id: "sess-1", hook_event_name: "Stop", last_assistant_message: $m}' | eval "$(hook Stop)"
EOF
  cat >"$T/bin/rex" <<'EOF'
#!/bin/bash
printf 'rex %s\n' "$*" >>"$LOG"
case $1 in
  split)
    cwd="" ; while (( $# )) && [[ $1 != -- ]]; do [[ $1 == -c ]] && cwd=$2; shift; done; shift
    id=blk-$RANDOM; touch "$STUB/$id"
    ( cd "$cwd" && "$@" >>"$LOG" 2>&1; rm -f "$STUB/$id" ) </dev/null >/dev/null 2>&1 &
    printf '{"block_ids":["%s"]}\n' "$id" ;;
  block)
    case $2 in inspect) [[ -e $STUB/$3 ]] ;; close) rm -f "$STUB/$3" ;; esac ;;
  send|send-key) : ;;
esac
EOF
  cat >"$T/bin/acc" <<EOF
#!/bin/bash
[[ \$1 == ls ]] || exit 1
cat <<'JSON'
{"accounts":[
 {"id":"a","tool":"claude","configDir":"~/.claude-a","configDirPath":"$HOME/.claude-a","rank":1,"usage":{"load":10,"capped":false}},
 {"id":"b","tool":"claude","configDir":"~/.claude-b","configDirPath":"$HOME/.claude-b","rank":2,"usage":{"load":40,"capped":false}},
 {"id":"c","tool":"claude","configDir":"~/.claude-c","configDirPath":"$HOME/.claude-c","rank":3,"usage":{"load":100,"capped":true}},
 {"id":"d","tool":"claude","configDirPath":"$HOME/.claude","rank":4,"usage":{"load":50,"capped":false}},
 {"id":"x","tool":"codex","rank":1}
],"roomiest":{"claude":"a"}}
JSON
EOF
  chmod +x "$T/bin/"*
}

teardown() { cd / && rm -rf "$T"; }

brief() { printf '%s\n' "$1" >"$T/$2.md"; printf '%s' "$T/$2.md"; }

# --- accounts ---
setup
out=$($BATON accounts --json)
check "accounts come from acc, ranked, claude only" test "$(jq -r 'map(.id) | join(",")' <<<"$out")" = "a,b,c,d"
check "capped account is marked" test "$(jq -r '.[2].capped' <<<"$out")" = true
printf 'one %s/.claude-b\n# comment\ntwo\n' "$HOME" >"$HOME/acc-file"
out=$(BATON_ACCOUNTS_FILE=$HOME/acc-file $BATON accounts --json)
check "an accounts file wins over acc" test "$(jq -r 'map(.id) | join(",")' <<<"$out")" = "one,two"
check "a file line with no folder means the default account" test "$(jq -r '.[1].configDir' <<<"$out")" = null
rm "$T/bin/acc"
out=$($BATON accounts --json)
check "without acc or a file, the current account is the only one" test "$(jq -r '.[0].id + " " + .[0].configDir' <<<"$out")" = "default $HOME/.claude-a"
teardown

# --- spawn, wait, status, done ---
setup
FAKE_COMMIT=1 $BATON spawn api "$(brief 'add the endpoint' api)" >/dev/null
check "spawn makes the branch" git show-ref --verify --quiet refs/heads/baton/api
check "spawn makes the worktree" test -d .baton/worktrees/api
check "worktrees stay out of git status" test -z "$(git status --porcelain)"
check "spawn skips the busy main account for the roomiest free one" grep -q "\"account\": \"b\"" "$(git rev-parse --git-common-dir)/baton/api/state.json"
$BATON wait api --timeout 10 >/dev/null
check "the worker ran on its account's folder, marked as a worker" grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude-b BATON_WORKER=1 PWD=.*/.baton/worktrees/api" "$LOG"
check "the worker got the brief as its prompt" grep -q "add the endpoint" "$LOG"
check "the pane opened beside the main session, unfocused" grep -q "rex split --split=right --focus=false --label baton:api .*-s sess -b main-block" "$LOG"
st=$($BATON status api --json)
check "status: stopped after the Stop hook" test "$(jq -r '.[0].state' <<<"$st")" = stopped
check "status: session id from SessionStart" test "$(jq -r '.[0].sessionId' <<<"$st")" = sess-1
check "status: last message from Stop" test "$(jq -r '.[0].lastMessage' <<<"$st")" = "finished: add the endpoint"
check "status: one commit ahead" test "$(jq -r '.[0].commits' <<<"$st")" = 1
expect_fail "done refuses to drop unmerged commits" "not in main" $BATON done api
git merge -q --no-edit baton/api
$BATON done api >/dev/null
check "done after merge removes the worktree" test ! -d .baton/worktrees/api
check "done after merge deletes the branch" test -z "$(git branch --list 'baton/api')"
check "done forgets the worker" test -z "$($BATON status --json | jq -r '.[]')"
teardown

setup
FAKE_WORK=30 $BATON spawn one "$(brief 'first' one)" >/dev/null
$BATON spawn two "$(brief 'second' two)" >/dev/null
check "a second worker spreads to the next free account" grep -q "\"account\": \"d\"" "$(git rev-parse --git-common-dir)/baton/two/state.json"
check "a second worker stacks below the first" grep -q "rex split --split=below .* -b blk-" "$LOG"
check "status shows a running worker as working" test "$($BATON status one --json | jq -r '.[0].state')" = working
expect_fail "wait times out on a running worker" "still working" $BATON wait one --timeout 1
$BATON tell one "also add tests" >/dev/null
check "tell types into the worker's pane" grep -q "rex send -b blk-.* also add tests" "$LOG"
$BATON done one --force >/dev/null
$BATON wait two --timeout 10 >/dev/null
rm -f "$STUB"/blk-*
expect_fail "tell refuses a worker whose pane is gone" "has exited" $BATON tell two "hello?"
check "done --force closes a running worker" test ! -d .baton/worktrees/one
$BATON wait two --timeout 10 >/dev/null; $BATON done two >/dev/null
teardown

setup
$BATON spawn deflt "$(brief x deflt)" --account d >/dev/null; $BATON wait deflt --timeout 10 >/dev/null
check "the default account's worker runs with CLAUDE_CONFIG_DIR unset, as its login needs" grep -q "CLAUDE_CONFIG_DIR=unset BATON_WORKER=1" "$LOG"
$BATON spawn tilde "$(brief x tilde)" --account a >/dev/null; $BATON wait tilde --timeout 10 >/dev/null
check "a ~ folder from acc is expanded" grep -q "CLAUDE_CONFIG_DIR=$HOME/.claude-a BATON_WORKER=1" "$LOG"
teardown

# --- guards ---
setup
expect_fail "task names are checked" "lowercase" $BATON spawn "Bad Name" /dev/null
$BATON spawn dup "$(brief x dup)" >/dev/null
expect_fail "a task name can't be reused" "exists" $BATON spawn dup "$(brief x dup2)"
expect_fail "workers can't start workers" "don't start workers" env BATON_WORKER=1 $BATON spawn sub "$(brief x sub)"
expect_fail "an unknown account is refused" "no account 'zz'" $BATON spawn acct "$(brief x acct)" --account zz
mkdir -p .baton && printf '#!/bin/bash\nexit 3\n' >.baton/setup && chmod +x .baton/setup
expect_fail "a failing .baton/setup is reported" "setup failed" $BATON spawn setupfail "$(brief x sf)"
check "a failing .baton/setup leaves no worktree" test ! -d .baton/worktrees/setupfail
check "a failing .baton/setup leaves no branch" test -z "$(git branch --list 'baton/setupfail')"
printf '#!/bin/bash\necho "$BATON_TASK from $BATON_MAIN" > setup-ran\n' >.baton/setup
$BATON spawn setupok "$(brief x so)" >/dev/null
check ".baton/setup runs in the new worktree" grep -q "setupok from $(pwd -P)" .baton/worktrees/setupok/setup-ran
$BATON wait --timeout 10 >/dev/null
FAKE_DIRTY=1 $BATON spawn dirty "$(brief x d)" >/dev/null; $BATON wait dirty --timeout 10 >/dev/null
expect_fail "done refuses uncommitted work" "uncommitted" $BATON done dirty
teardown

setup
cat >"$T/bin/acc" <<'EOF'
#!/bin/bash
echo '{"accounts":[{"id":"a","tool":"claude","rank":1,"usage":{"load":95,"capped":false}}]}'
EOF
expect_fail "no account with room is an error" "no account has room" $BATON spawn full "$(brief x full)"
teardown

setup
unset REX_SESSION
BATON_BACKEND=manual $BATON spawn hand "$(brief 'by hand' hand)" >"$T/out"
check "without Rex or tmux it prints the command to run" grep -q "bash .*/baton/hand/run.sh" "$T/out"
bash "$(git rev-parse --git-common-dir)/baton/hand/run.sh" >/dev/null 2>&1
check "the printed command runs the worker" test "$($BATON status hand --json | jq -r '.[0].state')" = stopped
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
