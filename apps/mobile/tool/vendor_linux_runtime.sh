#!/usr/bin/env bash
# Fetches the engines the Linux build bundles, from their official releases,
# each checked against a pinned SHA-256: the same versions the Windows build
# ships (tool/vendor_windows_runtime.ps1). A mismatch stops the build.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
destination="$root/assets/linux_runtime"
xray_version='v26.9.30'
xray_hash='f851110beaff16e78d643f0ccfd9524b4a44dfd59bae3e34bb52bba378f7690e'
hysteria_version='v2.12.2'
hysteria_hash='6493dfffd55b5883f64c76c63880ecc32988f0c568c9ca9014907877b4d55f94'
# The DNS tunnel's engine (docs/runbooks/dns-tunnel.md): the same release Android ships.
cotten_version='v2026.11.03.161534-be99443'
cotten_hash='d40dbfb873236a772032dcaf52efde95839b38a9302e58085f7080fc760866a4'

mkdir -p "$destination"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

fetch() { # url, file, expected sha256
  curl -fsSL --retry 3 -o "$2" "$1"
  local actual
  actual="$(sha256sum "$2" | cut -d' ' -f1)"
  if [ "$actual" != "$3" ]; then
    echo "SHA-256 mismatch for $(basename "$2"): expected $3, got $actual" >&2
    exit 1
  fi
}

fetch "https://github.com/XTLS/Xray-core/releases/download/$xray_version/Xray-linux-64.zip" \
  "$temporary/xray.zip" "$xray_hash"
unzip -qo "$temporary/xray.zip" xray geoip.dat geosite.dat LICENSE -d "$destination"

fetch "https://github.com/HyNetworks/hysteria/releases/download/app/$hysteria_version/hysteria-linux-amd64" \
  "$destination/hysteria" "$hysteria_hash"

fetch "https://github.com/WhiteDNS/CottenDNS/releases/download/$cotten_version/CottenDns_Client_Linux_AMD64.tar.gz"   "$temporary/cottendns.tar.gz" "$cotten_hash"
tar -xzf "$temporary/cottendns.tar.gz" -C "$temporary" "CottenDns_Client_Linux_AMD64_$cotten_version"
mv "$temporary/CottenDns_Client_Linux_AMD64_$cotten_version" "$destination/cottendns_client"

chmod 755 "$destination/xray" "$destination/hysteria" "$destination/cottendns_client"
echo "Linux runtime ready: $(ls "$destination" | tr '\n' ' ')"
