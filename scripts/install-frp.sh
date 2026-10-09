#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$EUID" -ne 0 ]]; then echo 'Run with sudo/root' >&2; exit 1; fi
version='0.71.0'
case "$(uname -m)" in
  x86_64|amd64) arch=amd64; sha='84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716' ;;
  aarch64|arm64) arch=arm64; sha='f33c293c275d8fc68c654b6fba10b2551d6463d09a9fc9cffb7227eae82266' ;;
  *) echo 'Only Linux amd64 and arm64 are supported by this installer' >&2; exit 1;;
esac
command -v curl >/dev/null || { echo 'Install curl first'; exit 1; }
command -v tar >/dev/null || { echo 'Install tar first'; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
archive="frp_${version}_linux_${arch}.tar.gz"
url="https://github.com/fatedier/frp/releases/download/v${version}/${archive}"
echo "Downloading verified upstream frp v${version} (${arch})..."
curl --fail --location --retry 3 --connect-timeout 15 -o "$work/$archive" "$url"
printf '%s  %s\n' "$sha" "$work/$archive" | sha256sum --check --status || { echo 'SHA256 verification failed'; exit 1; }
mkdir "$work/out"
tar -xzf "$work/$archive" --strip-components=1 -C "$work/out"
install -m 0755 "$work/out/frps" /usr/local/bin/frps
install -m 0755 "$work/out/frpc" /usr/local/bin/frpc
/usr/local/bin/frps --version
/usr/local/bin/frpc --version
echo 'FRP installed and SHA256 verified.'
