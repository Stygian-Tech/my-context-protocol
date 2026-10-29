#!/bin/sh
# Install into a shell-visible directory without changing shell startup files.
set -eu

task_install_dir=$1
task_install_version=$2
case "$task_install_dir" in
  /*) ;;
  *) printf '%s\n' 'BINDIR must be an absolute path.' >&2; exit 1 ;;
esac
case ":$PATH:" in
  *":$task_install_dir:"*) ;;
  *)
    printf 'Cannot install: %s is not on PATH.\n' "$task_install_dir" >&2
    printf '%s\n' 'Add the destination to PATH, then rerun make install.' >&2
    printf '%s\n' 'For the default destination: export PATH="$HOME/.local/bin:$PATH"' >&2
    printf '%s\n' 'Add that export to your shell startup file to keep it for future terminals.' >&2
    exit 1
    ;;
esac

mkdir -p "$task_install_dir"
task_install_tmp=$(mktemp -d "$task_install_dir/.context-install.XXXXXX")
trap 'rm -rf "$task_install_tmp"' EXIT HUP INT TERM
# Build for this machine; a cross-compiled executable would not satisfy installation.
GOOS= GOARCH= go build -trimpath -ldflags "-X main.version=$task_install_version" -o "$task_install_tmp/context" ./cmd/context
chmod 755 "$task_install_tmp/context"
mv -f "$task_install_tmp/context" "$task_install_dir/context"
printf 'Installed Context at %s/context\n' "$task_install_dir"
printf '%s\n' 'Run context help from any directory.'
