#!/usr/bin/env bash
# Builds the offline server bundle for one release (plan 6):
#   tool/server-bundle.sh <version> <output folder>
# -> <output folder>/nebula-vpn-v<version>-server-linux-amd64.tar.gz, holding
#   nebula/          the source at this commit (install.sh runs from here)
#   nebula/bundle/   images.tar (api, worker, admin, postgres, redis, AdGuard
#                    Home), the pinned Xray, Hysteria2 and dnsproxy downloads,
#                    the agent's wheels, and manifest.txt
# The release script signs it with every other file (SHA256SUMS.txt.sig), and
# `install.sh --bundle` installs from it without Docker Hub, GitHub or PyPI.
# ponytail: amd64 only; an arm64 server still installs online.
set -euo pipefail

version=${1:?usage: tool/server-bundle.sh <version> <output folder>}
out=$(mkdir -p "${2:?output folder}" && cd "$2" && pwd)
root=$(git rev-parse --show-toplevel)
cd "$root"
project=nebula-production
compose=infrastructure/compose/production.yaml

eval "$(grep -E '^(XRAY_VERSION|HYSTERIA_VERSION|DNSPROXY_VERSION)=' install.sh)"
xray_sha=$(sed -n '/^declare -A XRAY_SHA=(/,/^)/s/^  \[amd64\]=//p' install.sh)
hysteria_sha=$(sed -n '/^declare -A HYSTERIA_SHA=(/,/^)/s/^  \[amd64\]=//p' install.sh)
dnsproxy_sha=$(sed -n '/^declare -A DNSPROXY_SHA=(/,/^)/s/^  \[amd64\]=//p' install.sh)
images=$(sed -n 's/^ *image: //p' "$compose")
dns_image=$(sed -n 's/^ *image: \${NEBULA_DNS_IMAGE:-\(.*\)}$/\1/p' "$compose")
[ -n "$dns_image" ] || { echo "the dns service's image is not in the form the bundle expects"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/nebula"
git archive HEAD | tar -x -C "$work/nebula"
payload=$work/nebula/bundle
mkdir -p "$payload/wheels"

echo "== images"
docker build -q -t $project-api services/api >/dev/null
docker build -q -t $project-worker services/worker >/dev/null
# No public origin baked in: on 443 (every new install) the panel's own check
# passes without one.
docker build -q -t $project-admin --build-arg NEBULA_API_INTERNAL_URL=http://api:8000 apps/admin >/dev/null
third=()
for image in $images; do
  case $image in
    \$\{NEBULA_DNS_IMAGE*) docker pull -q "$dns_image" >/dev/null
      docker tag "$dns_image" adguard/adguardhome:nebula-bundle
      third+=(adguard/adguardhome:nebula-bundle) ;;
    *) docker pull -q "$image" >/dev/null; third+=("$image") ;;
  esac
done
docker save -o "$payload/images.tar" $project-api $project-worker $project-admin "${third[@]}"

echo "== binaries"
curl -fsSL --retry 3 -o "$payload/Xray-linux-64.zip" \
  "https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip"
echo "$xray_sha  $payload/Xray-linux-64.zip" | sha256sum -c --quiet
curl -fsSL --retry 3 -o "$payload/hysteria-linux-amd64" \
  "https://github.com/apernet/hysteria/releases/download/app/v$HYSTERIA_VERSION/hysteria-linux-amd64"
echo "$hysteria_sha  $payload/hysteria-linux-amd64" | sha256sum -c --quiet
dnsproxy=dnsproxy-linux-amd64-v$DNSPROXY_VERSION.tar.gz
curl -fsSL --retry 3 -o "$payload/$dnsproxy" \
  "https://github.com/AdguardTeam/dnsproxy/releases/download/v$DNSPROXY_VERSION/$dnsproxy"
echo "$dnsproxy_sha  $payload/$dnsproxy" | sha256sum -c --quiet

echo "== agent wheels (Python 3.12, as on Ubuntu 24.04)"
python3 -m pip download -q --require-hashes --no-deps --only-binary=:all: \
  --python-version 3.12 --implementation cp --abi cp312 \
  --platform manylinux_2_17_x86_64 --platform manylinux2014_x86_64 --platform any \
  -r services/vpn-agent/requirements.lock -d "$payload/wheels"

{
  echo "version=$version"
  echo "commit=$(git rev-parse HEAD)"
  echo "xray=$XRAY_VERSION hysteria=$HYSTERIA_VERSION dnsproxy=$DNSPROXY_VERSION"
  echo "images=$project-api $project-worker $project-admin ${third[*]}"
} > "$payload/manifest.txt"

file=$out/nebula-vpn-v$version-server-linux-amd64.tar.gz
tar -C "$work" -czf "$file" nebula
ls -la "$file"
