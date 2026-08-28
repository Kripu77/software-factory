#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT

fail() { echo "FAIL: $*" >&2; exit 1; }

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

command -v python3 >/dev/null 2>&1 || fail "python3 required for setup TTY tests"

run_notty() {
  local code=0
  set +e
  (cd "$WS/widgets" && FACTORY_WORKSPACE="$WS" NO_COLOR=1 TERM=dumb "$FACTORY" setup "$@") \
    </dev/null >"$TMP/out" 2>"$TMP/err"
  code=$?
  set -e
  return "$code"
}

pty_setup() {
  local answers="$1" cwd="$2"
  shift 2
  NO_COLOR=1 TERM=xterm-256color FACTORY_WORKSPACE="$WS" python3 - "$FACTORY" "$answers" "$cwd" "$@" << 'PY'
import fcntl, os, pty, signal, struct, sys, termios, time

factory, answers_path, cwd, *rest = sys.argv[1:]
answers = open(answers_path, "rb").read()
if answers and not answers.endswith(b"\n"):
    answers += b"\n"
winsize = struct.pack("HHHH", 24, 80, 0, 0)

def on_alarm(signum, frame):
    raise TimeoutError("setup PTY timed out")

signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(12)

pid, fd = pty.fork()
if pid == 0:
    os.chdir(cwd)
    fcntl.ioctl(1, termios.TIOCSWINSZ, winsize)
    os.execve(factory, [factory, "setup", *rest], os.environ)

fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
time.sleep(0.2)
os.write(fd, answers)

try:
    while True:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
finally:
    signal.alarm(0)
    try:
        os.close(fd)
    except OSError:
        pass

status = None
try:
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == 0:
        os.kill(pid, signal.SIGTERM)
        _, status = os.waitpid(pid, 0)
except OSError:
    sys.exit(99)
if status is None:
    sys.exit(99)

code = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else (
    os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
)
sys.exit(code)
PY
}

answers_file() {
  printf '%s' "$1" >"$TMP/answers"
}

# No TTY: do not hang, do not write, mention a terminal
run_notty && fail "setup without a TTY must fail"
grep -qi "terminal" "$TMP/err" "$TMP/out" || fail "no-TTY should mention a terminal, got out=$(cat "$TMP/out") err=$(cat "$TMP/err")"
[[ ! -e "$WS/widgets/.factory/config" ]] || fail "no-TTY must not write .factory/config"
[[ ! -e "$WS/widgets/.factory/conventions" ]] || fail "no-TTY must not write conventions"

# Piped stdin is still not a TTY and must not write
set +e
printf 'u\ngithub\n\ny\n' | (cd "$WS/widgets" && FACTORY_WORKSPACE="$WS" "$FACTORY" setup) >"$TMP/pipe-out" 2>"$TMP/pipe-err"
pipe_code=$?
set -e
[[ "$pipe_code" -ne 0 ]] || fail "piped setup must fail"
[[ ! -e "$WS/widgets/.factory/config" ]] || fail "piped setup must not write config"

# --yes is for workers, not the wizard
set +e
(cd "$WS/widgets" && FACTORY_WORKSPACE="$WS" "$FACTORY" setup --yes) >"$TMP/yes-out" 2>"$TMP/yes-err"
yes_code=$?
set -e
[[ "$yes_code" -ne 0 ]] || fail "setup --yes must fail"
grep -qi "config" "$TMP/yes-err" "$TMP/yes-out" || fail "setup --yes should point at factory.sh config, got $(cat "$TMP/yes-err")$(cat "$TMP/yes-out")"
[[ ! -e "$WS/widgets/.factory/config" ]] || fail "setup --yes must not write"

# Detect existing config and keep it
mkdir -p "$WS/widgets/.factory"
printf 'tracker=linear\nteam=KEEP\n' >"$WS/widgets/.factory/config"
printf 'euc-go: Go services\n' >"$WS/widgets/.factory/conventions"
before_cfg="$(cat "$WS/widgets/.factory/config")"
before_conv="$(cat "$WS/widgets/.factory/conventions")"
answers_file $'k\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/keep-out" 2>"$TMP/keep-err"
keep_code=$?
set -e
[[ "$keep_code" -eq 0 ]] || fail "keep should exit 0, err=$(cat "$TMP/keep-err") out=$(cat "$TMP/keep-out")"
grep -qi "existing" "$TMP/keep-out" || fail "detect should mention existing config, got $(cat "$TMP/keep-out")"
grep -qi "keep" "$TMP/keep-out" || fail "detect should offer keep, got $(cat "$TMP/keep-out")"
[[ "$(cat "$WS/widgets/.factory/config")" == "$before_cfg" ]] || fail "keep must not change config"
[[ "$(cat "$WS/widgets/.factory/conventions")" == "$before_conv" ]] || fail "keep must not change conventions"

# Cancel at review leaves files unchanged
answers_file $'u\nskip\n\nn\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/cancel-out" 2>"$TMP/cancel-err"
cancel_code=$?
set -e
[[ "$cancel_code" -ne 0 ]] || fail "cancel should be a non-zero exit"
[[ "$(cat "$WS/widgets/.factory/config")" == "$before_cfg" ]] || fail "cancel must not change config"
[[ "$(cat "$WS/widgets/.factory/conventions")" == "$before_conv" ]] || fail "cancel must not change conventions"
grep -qi "review" "$TMP/cancel-out" || fail "cancel path should reach review, got $(cat "$TMP/cancel-out")"

# Skip optional sections, write github default through config writers
rm -rf "$WS/widgets/.factory"
answers_file $'skip\n\ny\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/skip-out" 2>"$TMP/skip-err"
skip_code=$?
set -e
[[ "$skip_code" -eq 0 ]] || fail "skip+confirm should succeed, err=$(cat "$TMP/skip-err") out=$(cat "$TMP/skip-out")"
[[ -f "$WS/widgets/.factory/config" ]] || fail "skip+confirm should write tracker via config"
grep -qxF "tracker=github" "$WS/widgets/.factory/config" || fail "skip tracker should land github default, got $(cat "$WS/widgets/.factory/config")"
[[ ! -e "$WS/widgets/.factory/conventions" ]] || fail "skip skills should not write conventions"
grep -qxF ".factory/" "$WS/widgets/.git/info/exclude" || fail "setup write should exclude .factory/"
grep -q $'⠋' "$TMP/skip-out" && fail "NO_COLOR must not animate a spinner"

# Write-through-config: tracker linear + skill and convention lines in the #35 format
rm -rf "$WS/widgets/.factory"
answers_file $'linear\nABC\ntdd: features and bug fixes\nnever add jest tests\n\ny\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/write-out" 2>"$TMP/write-err"
write_code=$?
set -e
[[ "$write_code" -eq 0 ]] || fail "write should succeed, err=$(cat "$TMP/write-err") out=$(cat "$TMP/write-out")"
grep -qxF "tracker=linear" "$WS/widgets/.factory/config" || fail "linear tracker missing, got $(cat "$WS/widgets/.factory/config")"
grep -qxF "team=ABC" "$WS/widgets/.factory/config" || fail "linear team missing, got $(cat "$WS/widgets/.factory/config")"
grep -qxF "tdd: features and bug fixes" "$WS/widgets/.factory/conventions" || fail "skill line missing, got $(cat "$WS/widgets/.factory/conventions")"
grep -qxF "never add jest tests" "$WS/widgets/.factory/conventions" || fail "convention line missing, got $(cat "$WS/widgets/.factory/conventions")"
out="$(FACTORY_WORKSPACE="$WS" "$FACTORY" config --repo widgets)"
grep -q "tracker linear" <<< "$out" || fail "config should show what setup wrote, got: $out"
grep -q "tdd: features and bug fixes" <<< "$out" || fail "config should list the skill setup wrote, got: $out"
SETUP_LIB="$ROOT/lib/setup.sh"
[[ -f "$SETUP_LIB" ]] || fail "TTY wizard must live in lib/setup.sh"
grep -q 'lib/setup.sh' "$FACTORY" || fail "factory.sh must source lib/setup.sh"
if grep -q '^setup_run()' "$FACTORY"; then
  fail "setup_run must not be defined in factory.sh"
fi
if grep -q '^setup_init_ui()' "$FACTORY"; then
  fail "TTY paint must not live in factory.sh"
fi
awk '
  /^setup_write\(\)/ {on=1}
  on {print}
  on && /^}$/ {exit}
' "$SETUP_LIB" | grep -q "config_tracker" || fail "setup_write must call config_tracker"
awk '
  /^setup_write\(\)/ {on=1}
  on {print}
  on && /^}$/ {exit}
' "$SETUP_LIB" | grep -q "config_write_conventions" || fail "setup_write must call config_write_conventions"
awk '
  /^config_show\(\)/ {on=1}
  on {print}
  on && /^}$/ {exit}
' "$FACTORY" | grep -q "config_read" || fail "config_show must use config_read"
grep -q 'config_read' "$SETUP_LIB" || fail "wizard must read existing config through config_read"

# Confirm writes in place; write is not another numbered stage
grep -E '5/5[[:space:]]+Write' "$TMP/skip-out" && fail "write must not be its own stage, got $(cat "$TMP/skip-out")"
grep -qi "wrote factory config" "$TMP/skip-out" || fail "confirm should write on the review screen, got $(cat "$TMP/skip-out")"

# Existing config, update tracker, skip skills (leave conventions)
printf 'tracker=github\n' >"$WS/widgets/.factory/config"
printf 'euc-go: Go services\n' >"$WS/widgets/.factory/conventions"
answers_file $'u\nlinear\nZZZ\n\ny\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/upd-out" 2>"$TMP/upd-err"
upd_code=$?
set -e
[[ "$upd_code" -eq 0 ]] || fail "update should succeed, err=$(cat "$TMP/upd-err") out=$(cat "$TMP/upd-out")"
grep -qxF "tracker=linear" "$WS/widgets/.factory/config" || fail "update should change tracker"
grep -qxF "euc-go: Go services" "$WS/widgets/.factory/conventions" || fail "skip skills should keep existing conventions"
grep -qi "current" "$TMP/upd-out" || fail "skills stage should show existing lines, got $(cat "$TMP/upd-out")"
grep -q "euc-go: Go services" "$TMP/upd-out" || fail "skills stage should list current conventions, got $(cat "$TMP/upd-out")"

# Typed skill lines replace the list after showing current
printf 'tracker=github\n' >"$WS/widgets/.factory/config"
printf 'euc-go: Go services\n' >"$WS/widgets/.factory/conventions"
answers_file $'u\nskip\ntdd: features and bug fixes\n\ny\n'
set +e
pty_setup "$TMP/answers" "$WS/widgets" >"$TMP/repl-out" 2>"$TMP/repl-err"
repl_code=$?
set -e
[[ "$repl_code" -eq 0 ]] || fail "replace skills should succeed, err=$(cat "$TMP/repl-err") out=$(cat "$TMP/repl-out")"
grep -qi "current" "$TMP/repl-out" || fail "replace path should show existing lines first, got $(cat "$TMP/repl-out")"
grep -qxF "tdd: features and bug fixes" "$WS/widgets/.factory/conventions" || fail "typed skills should replace conventions"
grep -q "euc-go" "$WS/widgets/.factory/conventions" && fail "typed skills must not keep old conventions"

# --repo still targets the named checkout
mkdir -p "$WS/other"
git -C "$WS/other" init -q
git -C "$WS/other" remote add origin "https://github.com/acme/other.git"
rm -rf "$WS/widgets/.factory"
answers_file $'skip\n\ny\n'
set +e
pty_setup "$TMP/answers" "$WS/other" --repo widgets >"$TMP/repo-out" 2>"$TMP/repo-err"
repo_code=$?
set -e
[[ "$repo_code" -eq 0 ]] || fail "--repo setup failed, err=$(cat "$TMP/repo-err") out=$(cat "$TMP/repo-out")"
[[ ! -e "$WS/other/.factory/config" ]] || fail "setup --repo widgets must not write the cwd checkout"
grep -qxF "tracker=github" "$WS/widgets/.factory/config" || fail "setup --repo widgets must write widgets"

# README documents factory setup; install.sh is still the plugin install
grep -q "factory setup" "$ROOT/README.md" || fail "README missing factory setup"
grep -q "factory.sh config" "$ROOT/README.md" || fail "README should still document factory.sh config"
if grep -E '\$FACTORY setup|factory\.sh setup' "$ROOT/install.sh"; then
  fail "install.sh must not run the setup wizard"
fi
grep -q "factory setup" "$ROOT/install.sh" || fail "install.sh should point at factory setup after plugin install"
grep -Eq 'Next:.*factory setup.*(grok|claude)' "$ROOT/install.sh" || fail "install next step should keep the runner after factory setup"
grep -q "factory.sh setup" "$FACTORY" || fail "usage should list factory.sh setup"

# install.sh <checkout> still does not write factory config
hid="$TMP/bin"
mkdir -p "$hid"
for cmd in bash mkdir ln rm echo grep command cat cp dirname pwd; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
prod="$TMP/product"
mkdir -p "$prod"
HOME="$TMP/home" PATH="$hid" "$ROOT/install.sh" "$prod" >/dev/null
[[ ! -e "$prod/.factory/config" ]] || fail "install.sh must not write .factory/config"
[[ ! -e "$prod/.factory/conventions" ]] || fail "install.sh must not write conventions"

# The PATH command from install.sh is a symlink at ~/.local/bin/factory
factory_cli="$TMP/home/.local/bin/factory"
[[ -L "$factory_cli" ]] || fail "install should leave a factory symlink"
rm -rf "$WS/widgets/.factory"
set +e
(cd "$WS/widgets" && PATH="$(dirname "$factory_cli"):$PATH" FACTORY_WORKSPACE="$WS" NO_COLOR=1 TERM=dumb factory setup) \
  </dev/null >"$TMP/sym-out" 2>"$TMP/sym-err"
sym_code=$?
set -e
[[ "$sym_code" -ne 0 ]] || fail "factory setup via the install symlink without a TTY must fail"
grep -qi "terminal" "$TMP/sym-err" "$TMP/sym-out" || fail "symlink factory setup should mention a terminal, got out=$(cat "$TMP/sym-out") err=$(cat "$TMP/sym-err")"
[[ ! -e "$WS/widgets/.factory/config" ]] || fail "symlink factory setup without a TTY must not write"

echo "ok setup"
