#!/usr/bin/env bash
# dcm - Development Containers Manager
# Manage Devcontainers from the terminal, identified by their local folder.
# Requires: devcontainer CLI, jq, docker or podman. Works with bash 3.2+.

set -euo pipefail

CONFIG_FILE="$HOME/.devcontainer/dcm-config.json"
LABEL="devcontainer.local_folder"

# Defaults, overridden by the config file
ENGINE="docker"
DOTFILES_REPO=""
DOTFILES_PATH=""
SHELL_CMD="bash"
EDITOR_DEFAULT=""

CONTAINER_ID=""
REMOTE_FOLDER=""
PATH_LABEL="" # target folder as shown in messages (~ for $HOME)

ok() { printf '[DCM] ✅ %s %s\n' "${1:0:12}" "$2"; }
info() { printf '[DCM] ℹ️ %s\n' "$*" >&2; }
warn() { printf '[DCM] ⚠️ %s\n' "$*" >&2; }
error() { printf '[DCM] ❌ %s\n' "$*" >&2; }
die() { printf '[DCM] ❌ %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
dcm - Development Containers Manager

Usage: dcm <command> [path]

  run      [path]            Start the devcontainer (create it if needed)
  recreate [path]            Remove and rebuild the container
  exec     [path] -- <cmd>   Run a command inside the container
  attach   [path]            Open an interactive shell inside the container
  editor   [--name=zed|vscode] [path]
                             Open the project in an editor, inside the container
  stop     [path]            Stop the container
  rm       [path]            Stop and delete the container
  --help                     Show this help

[path] defaults to the current directory. It must contain a devcontainer
definition. exec, attach and editor start the container if it is not running.

Config: ~/.devcontainer/dcm-config.json
  { "containerEngine": "docker|podman", "dotfiles": { "repo": "<url>", "path": "<target>" }, "shell": "bash",
    "editor": { "name": "zed|vscode" } }
EOF
}

# replace the home directory prefix with ~ for display
tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

require_tool() { # tool, install hint
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found in PATH. $2"
}

load_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  require_tool jq "Install it with your package manager, e.g. 'brew install jq' or 'apt install jq'."
  jq -e . "$CONFIG_FILE" >/dev/null 2>&1 || die "Invalid JSON in $CONFIG_FILE"
  ENGINE=$(jq -r '.containerEngine // "docker"' "$CONFIG_FILE") || die "Cannot read $CONFIG_FILE"
  DOTFILES_REPO=$(jq -r '(.dotfiles.repo? // "")' "$CONFIG_FILE") || die "Cannot read $CONFIG_FILE"
  DOTFILES_PATH=$(jq -r '(.dotfiles.path? // "")' "$CONFIG_FILE") || die "Cannot read $CONFIG_FILE"
  SHELL_CMD=$(jq -r '.shell // "bash"' "$CONFIG_FILE") || die "Cannot read $CONFIG_FILE"
  EDITOR_DEFAULT=$(jq -r '(.editor.name? // "")' "$CONFIG_FILE") || die "Cannot read $CONFIG_FILE"
  case "$ENGINE" in
    docker | podman) ;;
    *) die "Invalid containerEngine '$ENGINE' in $CONFIG_FILE (use docker or podman)" ;;
  esac
}

resolve_path() { # [path] -> physical absolute path
  local p="${1:-.}"
  [ -d "$p" ] || die "Not a directory: $p"
  (cd "$p" && pwd -P)
}

check_definition() {
  [ -f "$1/.devcontainer/devcontainer.json" ] || [ -f "$1/.devcontainer.json" ] ||
    die "No devcontainer definition in $1 (looked for .devcontainer/devcontainer.json and .devcontainer.json)"
}

# Container IDs (one per line) labelled with the given folder.
# Running containers only, unless the second argument is "all".
find_ids() { # path [all]
  local flag="-q"
  if [ "${2:-}" = "all" ]; then flag="-aq"; fi
  "$ENGINE" ps "$flag" --filter "label=$LABEL=$1"
}

query_ids() { # path [all]
  find_ids "$@" || die "Could not query $ENGINE (is it installed and running?)"
}

warn_if_many() { # ids
  local n
  n=$(printf '%s\n' "$1" | wc -l | tr -d ' ')
  if [ "$n" -gt 1 ]; then warn "$n containers match $PATH_LABEL"; fi
}

# Run 'devcontainer up' and set CONTAINER_ID and REMOTE_FOLDER.
# The CLI's own progress output (stderr) is passed through, so long builds are visible.
start_container() { # path
  local path="$1" out="" rc=0 msg=""
  local args=(up --workspace-folder "$path" --docker-path "$ENGINE")
  if [ -n "$DOTFILES_REPO" ]; then
    args+=(--dotfiles-repository "$DOTFILES_REPO")
  fi
  if [ -n "$DOTFILES_PATH" ]; then
    args+=(--dotfiles-target-path "$DOTFILES_PATH")
  fi

  require_tool jq "Install it with your package manager, e.g. 'brew install jq' or 'apt install jq'."

  out=$(devcontainer "${args[@]}") || rc=$?

  if [ "$rc" -ne 0 ]; then
    msg=$(printf '%s' "$out" | jq -r '.message // empty' 2>/dev/null | sed -n '1p') || true
    die "Could not start devcontainer in $PATH_LABEL${msg:+: $msg} (devcontainer up exit code $rc)"
  fi

  CONTAINER_ID=$(printf '%s' "$out" | jq -r '.containerId // empty' 2>/dev/null | sed -n '1p') || true
  [ -n "$CONTAINER_ID" ] || die "devcontainer up returned no container ID for $PATH_LABEL"
  REMOTE_FOLDER=$(printf '%s' "$out" | jq -r '.remoteWorkspaceFolder // empty' 2>/dev/null | sed -n '1p') || true
}

ensure_running() { # path
  local ids
  ids=$(query_ids "$1")
  if [ -z "$ids" ]; then
    info "Starting devcontainer: $PATH_LABEL"
    start_container "$1"
  fi
}

# Stop and delete every container labelled with the folder. Idempotent.
remove_containers() { # path [quiet]
  local ids id
  ids=$(query_ids "$1" all)
  if [ -z "$ids" ]; then
    if [ "${2:-}" != "quiet" ]; then info "No container for $PATH_LABEL, nothing to remove"; fi
    return 0
  fi
  warn_if_many "$ids"
  while IFS= read -r id; do
    "$ENGINE" stop "$id" >/dev/null 2>&1 || true
    "$ENGINE" rm "$id" >/dev/null || die "Could not remove container ${id:0:12}"
    ok "$id" "removed $PATH_LABEL"
  done <<<"$ids"
}

cmd_run() {
  local ids
  ids=$(query_ids "$1")
  if [ -n "$ids" ]; then
    warn_if_many "$ids"
    ok "${ids%%$'\n'*}" "already running $PATH_LABEL"
    return 0
  fi
  info "Starting devcontainer: $PATH_LABEL"
  start_container "$1"
  ok "$CONTAINER_ID" "started $PATH_LABEL"
}

cmd_recreate() {
  remove_containers "$1" quiet
  info "Starting devcontainer: $PATH_LABEL"
  start_container "$1"
  ok "$CONTAINER_ID" "recreated $PATH_LABEL"
}

cmd_exec() { # path -- command...
  local path="$1"
  shift
  ensure_running "$path"
  exec devcontainer exec --workspace-folder "$path" --docker-path "$ENGINE" "$@"
}

cmd_attach() {
  local path="$1" rc=0
  ensure_running "$path"
  SECONDS=0
  devcontainer exec --workspace-folder "$path" --docker-path "$ENGINE" "$SHELL_CMD" -l || rc=$?
  # An interactive shell exits with the status of its last command, so only blame
  # the shell when it fails right away.
  if { [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; } && [ "$SECONDS" -lt 2 ]; then
    error "Could not start '$SHELL_CMD' in the container. Is it installed? Check \"shell\" in $CONFIG_FILE"
  fi
  return "$rc"
}

# Open the project in an editor, inside the devcontainer.
cmd_editor() { # path editor
  local path="$1" editor="$2" ids hex uri
  case "$editor" in
    zed)
      if [ "$ENGINE" = "podman" ]; then warn "Zed's dev container support may require Docker"; fi
      ensure_running "$path"
      info "Opening $PATH_LABEL in Zed"
      exec zed --dev-container "$path"
      ;;
    vscode)
      ids=$(query_ids "$path")
      if [ -z "$ids" ]; then info "Starting devcontainer: $PATH_LABEL"; fi
      start_container "$path"
      [ -n "$REMOTE_FOLDER" ] || die "devcontainer up returned no remoteWorkspaceFolder for $PATH_LABEL"
      hex=$(printf '%s' "$path" | od -A n -t x1 | tr -d ' \n')
      uri="vscode-remote://dev-container+${hex}${REMOTE_FOLDER}"
      info "Opening $PATH_LABEL in VS Code"
      exec code --folder-uri "$uri"
      ;;
  esac
}

cmd_stop() {
  local ids id
  ids=$(query_ids "$1")
  if [ -z "$ids" ]; then
    info "No running container for $PATH_LABEL, nothing to stop"
    return 0
  fi
  warn_if_many "$ids"
  while IFS= read -r id; do
    "$ENGINE" stop "$id" >/dev/null || die "Could not stop container ${id:0:12}"
    ok "$id" "stopped $PATH_LABEL"
  done <<<"$ids"
}

cmd_rm() {
  remove_containers "$1"
}

main() {
  if [ $# -eq 0 ]; then
    usage >&2
    exit 2
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    --help)
      usage
      exit 0
      ;;
    run | recreate | exec | attach | editor | stop | rm) ;;
    *)
      usage >&2
      die "Unknown command '$cmd'"
      ;;
  esac

  local path_arg="" path_count=0 found_sep=0 editor_arg="" editor=""
  if [ "$cmd" = "exec" ]; then
    while [ $# -gt 0 ]; do
      if [ "$1" = "--" ]; then
        found_sep=1
        shift
        break
      fi
      path_arg="$1"
      path_count=$((path_count + 1))
      shift
    done
    [ "$found_sep" -eq 1 ] || die "exec needs '--' before the command: dcm exec [path] -- <command...>"
    [ "$path_count" -le 1 ] || die "exec takes at most one path before '--'"
    [ $# -gt 0 ] || die "exec needs a command after '--'"
  elif [ "$cmd" = "editor" ]; then
    while [ $# -gt 0 ]; do
      case "$1" in
        --name=*) editor_arg="${1#--name=}" ;;
        --name)
          [ $# -ge 2 ] || die "--name needs a value (zed or vscode)"
          editor_arg="$2"
          shift
          ;;
        -*) die "Unknown option '$1' for editor" ;;
        *)
          path_arg="$1"
          path_count=$((path_count + 1))
          ;;
      esac
      shift
    done
    [ "$path_count" -le 1 ] || die "editor takes at most one path"
  else
    [ $# -le 1 ] || die "$cmd takes at most one path"
    path_arg="${1:-}"
  fi

  load_config
  if [ "$cmd" = "editor" ]; then
    editor="${editor_arg:-$EDITOR_DEFAULT}"
    [ -n "$editor" ] || die "No editor specified. Use --name=zed|vscode or set editor.name in $CONFIG_FILE"
    case "$editor" in
      zed | vscode) ;;
      *) die "Unsupported editor '$editor' (use zed or vscode)" ;;
    esac
  fi
  require_tool "$ENGINE" "It is set as containerEngine in $CONFIG_FILE (default: docker)."
  case "$cmd" in
    run | recreate | exec | attach | editor)
      require_tool devcontainer "Install it with 'brew install devcontainer' or 'npm install -g @devcontainers/cli'."
      ;;
  esac
  case "$editor" in
    zed) require_tool zed "Install Zed (v0.232 or newer, for --dev-container) and make its CLI available." ;;
    vscode) require_tool code "In VS Code run 'Shell Command: Install code command in PATH' and install the Dev Containers extension." ;;
  esac

  local path
  path=$(resolve_path "$path_arg")
  check_definition "$path"
  PATH_LABEL=$(tilde "$path")

  case "$cmd" in
    run) cmd_run "$path" ;;
    recreate) cmd_recreate "$path" ;;
    exec) cmd_exec "$path" "$@" ;;
    attach) cmd_attach "$path" ;;
    editor) cmd_editor "$path" "$editor" ;;
    stop) cmd_stop "$path" ;;
    rm) cmd_rm "$path" ;;
  esac
}

main "$@"
