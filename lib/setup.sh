#!/usr/bin/env bash

SETUP_TOTAL=4
SETUP_INDEX=0
SETUP_COLOR=0
SETUP_ANIM=0
SETUP_BOLD=""
SETUP_DIM=""
SETUP_RESET=""
SETUP_CYAN=""
SETUP_GREEN=""
SETUP_YELLOW=""
SETUP_TRACKER="github"
SETUP_TEAM=""
SETUP_LINES=()
SETUP_SKILLS_CHANGED=0
SETUP_SPIN_PID=""

setup_init_ui() {
  SETUP_COLOR=0
  SETUP_ANIM=0
  SETUP_BOLD=""
  SETUP_DIM=""
  SETUP_RESET=""
  SETUP_CYAN=""
  SETUP_GREEN=""
  SETUP_YELLOW=""
  SETUP_SPIN_PID=""
  [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" && -t 1 ]] || return 0
  command -v tput >/dev/null 2>&1 || return 0
  local colors
  colors="$(tput colors 2>/dev/null || echo 0)"
  [[ "$colors" -ge 8 ]] || return 0
  SETUP_COLOR=1
  SETUP_ANIM=1
  SETUP_BOLD="$(tput bold 2>/dev/null || true)"
  SETUP_DIM="$(tput dim 2>/dev/null || true)"
  SETUP_RESET="$(tput sgr0 2>/dev/null || true)"
  SETUP_CYAN="$(tput setaf 6 2>/dev/null || true)"
  SETUP_GREEN="$(tput setaf 2 2>/dev/null || true)"
  SETUP_YELLOW="$(tput setaf 3 2>/dev/null || true)"
}

setup_need_tty() {
  local dir="$1"
  if [[ -t 0 && -t 1 ]]; then
    return 0
  fi
  echo "factory setup needs a terminal. Use factory.sh config for scripts." >&2
  config_show "$dir" >&2
  exit 1
}

setup_clear() {
  [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] || return 0
  if command -v tput >/dev/null 2>&1; then
    tput clear 2>/dev/null || printf '\033[2J\033[H'
  else
    printf '\033[2J\033[H'
  fi
}

setup_transition() {
  [[ "$SETUP_ANIM" -eq 1 ]] || return 0
  local i
  for i in 1 2 3; do
    printf '\r  %s·  %s' "$SETUP_DIM" "$SETUP_RESET"
    sleep 0.04
    printf '\r  %s·· %s' "$SETUP_DIM" "$SETUP_RESET"
    sleep 0.04
    printf '\r  %s···%s' "$SETUP_DIM" "$SETUP_RESET"
    sleep 0.04
    printf '\r     \r'
  done
}

setup_stage() {
  local name="$1"
  setup_transition
  setup_clear
  SETUP_INDEX=$((SETUP_INDEX + 1))
  printf '\n%s%s▸ %s/%s  %s%s\n\n' "$SETUP_BOLD" "$SETUP_CYAN" "$SETUP_INDEX" "$SETUP_TOTAL" "$name" "$SETUP_RESET"
}

setup_spin_stop() {
  if [[ -n "${SETUP_SPIN_PID:-}" ]]; then
    kill "$SETUP_SPIN_PID" 2>/dev/null || true
    wait "$SETUP_SPIN_PID" 2>/dev/null || true
    SETUP_SPIN_PID=""
    printf '\r\033[K'
  fi
}

setup_spin() {
  local msg="$1"
  setup_spin_stop
  if [[ "$SETUP_ANIM" -ne 1 ]]; then
    printf '  %s\n' "$msg"
    return 0
  fi
  (
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    while :; do
      printf '\r  %s%s%s %s' "$SETUP_CYAN" "${frames[i]}" "$SETUP_RESET" "$msg"
      sleep 0.04
      i=$(( (i + 1) % ${#frames[@]} ))
    done
  ) &
  SETUP_SPIN_PID=$!
}

setup_read() {
  local prompt="$1" varname="$2" default="${3:-}" input=""
  if [[ -n "$default" ]]; then
    printf '  %s%s%s [%s]: ' "$SETUP_BOLD" "$prompt" "$SETUP_RESET" "$default"
  else
    printf '  %s%s%s: ' "$SETUP_BOLD" "$prompt" "$SETUP_RESET"
  fi
  if ! IFS= read -r input; then
    echo "factory setup needs a terminal." >&2
    exit 1
  fi
  input="${input%$'\r'}"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  if [[ -z "$input" && -n "$default" ]]; then
    input="$default"
  fi
  printf -v "$varname" '%s' "$input"
}

setup_read_existing() {
  local dir="$1"
  config_read "$dir"
  SETUP_TRACKER="$CONFIG_TRACKER"
  SETUP_TEAM="$CONFIG_TEAM"
  SETUP_LINES=()
  SETUP_SKILLS_CHANGED=0
  if (( ${#CONFIG_LINES[@]} > 0 )); then
    SETUP_LINES=("${CONFIG_LINES[@]}")
  fi
}

setup_has_existing() {
  [[ "${CONFIG_EXISTS:-0}" -eq 1 ]]
}

setup_fold() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

setup_write() {
  local dir="$1"
  if [[ "$SETUP_TRACKER" == linear ]]; then
    TEAM="$SETUP_TEAM" config_tracker "$dir" linear >/dev/null
  else
    TEAM="" config_tracker "$dir" github >/dev/null
  fi
  if [[ "$SETUP_SKILLS_CHANGED" -eq 1 ]]; then
    config_write_conventions "$dir" ${SETUP_LINES[@]+"${SETUP_LINES[@]}"}
  fi
  config_show "$dir"
}

setup_run() {
  local dir="$1" choice="" tracker_in="" team_in="" line="" confirm="" skill
  setup_need_tty "$dir"
  setup_init_ui
  SETUP_TOTAL=4
  SETUP_INDEX=0

  setup_stage "Detect"
  setup_spin "Looking for factory config"
  setup_read_existing "$dir"
  setup_spin_stop
  if setup_has_existing; then
    printf '  Existing factory config:\n'
    config_show "$dir" | sed 's/^/  /'
    printf '\n'
    while true; do
      setup_read "Update or keep?" choice "update"
      case "$(setup_fold "$choice")" in
        k|keep)
          printf '\n  Kept existing config.\n'
          config_show "$dir"
          return 0
          ;;
        u|update) break ;;
        *) printf '  Type update or keep.\n' ;;
      esac
    done
  else
    printf '  No factory config yet.\n'
  fi

  setup_stage "Tracker"
  printf '  github (default) or linear, which needs a team key.\n'
  printf '  skip keeps the current tracker.\n\n'
  while true; do
    setup_read "Tracker (github, linear, skip)" tracker_in "$SETUP_TRACKER"
    case "$(setup_fold "$tracker_in")" in
      s|skip) break ;;
      github)
        SETUP_TRACKER="github"
        SETUP_TEAM=""
        break
        ;;
      linear)
        while true; do
          setup_read "Linear team key" team_in "${SETUP_TEAM}"
          if [[ -n "$team_in" ]]; then
            SETUP_TRACKER="linear"
            SETUP_TEAM="$team_in"
            break
          fi
          printf '  Linear needs a team key.\n'
        done
        break
        ;;
      *) printf '  Choose github, linear, or skip.\n' ;;
    esac
  done

  setup_stage "Skills"
  printf '  Factory skills:\n'
  for skill in "$FACTORY"/skills/*; do
    [[ -d "$skill" ]] || continue
    printf '    %s\n' "${skill##*/}"
  done
  printf '\n  One line: "<skill>: <when it applies>" or a convention.\n'
  if (( ${#SETUP_LINES[@]} > 0 )); then
    printf '  Current:\n'
    for line in "${SETUP_LINES[@]}"; do
      printf '    %s\n' "$line"
    done
    printf '  Empty line keeps these. Typed lines replace the list.\n\n'
  else
    printf '  Empty line skips or finishes.\n\n'
  fi
  local collected=()
  while true; do
    setup_read "Skill or convention" line
    [[ -n "$line" ]] || break
    collected+=("$line")
  done
  if (( ${#collected[@]} > 0 )); then
    SETUP_LINES=("${collected[@]}")
    SETUP_SKILLS_CHANGED=1
  fi

  setup_stage "Review"
  printf '  Tracker: %s\n' "$SETUP_TRACKER"
  [[ -z "$SETUP_TEAM" ]] || printf '  Team: %s\n' "$SETUP_TEAM"
  if (( ${#SETUP_LINES[@]} > 0 )); then
    printf '  Skills:\n'
    for line in "${SETUP_LINES[@]}"; do
      printf '    %s\n' "$line"
    done
  else
    printf '  Skills: none\n'
  fi
  printf '\n'
  setup_read "Write this config? [y/N]" confirm
  case "$(setup_fold "$confirm")" in
    y|yes) ;;
    *)
      printf '\n  Canceled. Nothing written.\n'
      exit 1
      ;;
  esac

  setup_write "$dir"
  printf '\n  %sWrote factory config.%s\n' "$SETUP_GREEN" "$SETUP_RESET"
}
