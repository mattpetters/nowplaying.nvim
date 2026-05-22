#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="${GOBIN:-}"

if [[ -z "$install_dir" ]]; then
  go_path="$(go env GOPATH)"
  install_dir="$go_path/bin"
fi

mkdir -p "$install_dir"

echo "building nowplaying binaries into $install_dir"
go build -o "$install_dir/nowplayingd" "$repo_root/cmd/nowplayingd"
go build -o "$install_dir/nowplaying" "$repo_root/cmd/nowplaying"

ln -sfn "nowplaying" "$install_dir/np"
ln -sfn "nowplaying" "$install_dir/nplay"

echo "installed:"
echo "  $install_dir/nowplaying"
echo "  $install_dir/nowplayingd"
echo "  $install_dir/np -> nowplaying"
echo "  $install_dir/nplay -> nowplaying"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo
    echo "warning: $install_dir is not on PATH"
    echo "add it to PATH to run np or nplay globally"
    ;;
esac
