#!/usr/bin/env bash
set -euo pipefail

main() {
  local name="dcm"
  local ref="${DCM_VERSION:-main}"
  local dir="${DCM_INSTALL_DIR:-$HOME/.local/bin}"
  local url="https://raw.githubusercontent.com/marcelfrey29/development-containers-manager/$ref/$name"

  mkdir -p "$dir"
  curl -fsSL "$url" -o "$dir/$name.tmp"
  chmod +x "$dir/$name.tmp"
  mv "$dir/$name.tmp" "$dir/$name"

  echo "Installed $name to $dir/$name"
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "Add it to your PATH: export PATH=\"$dir:\$PATH\"" ;;
  esac
}

main "$@"
