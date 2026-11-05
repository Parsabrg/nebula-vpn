# Installing from the offline bundle

A server inside Iran may not reach Docker Hub, GitHub or PyPI. Each release
has a bundle that installs without them:
`nebula-vpn-vX-server-linux-amd64.tar.gz`, built by the Release workflow
(`tool/server-bundle.sh`) and signed with every other release file
(`SHA256SUMS.txt.sig`, the key in `docs/release-signers`).

It holds the source, the images the stack runs (api, worker, admin,
PostgreSQL, Redis, AdGuard Home), the pinned Xray, Hysteria2 and dnsproxy
downloads, and the agent's Python wheels. Still needed from the network:
the distribution's packages (`apt`, which has mirrors inside Iran) and the
certificate (Let's Encrypt, or bring your own).

The bundle is for new installs on amd64, served on port 443
(`docs/runbooks/port-443.md`). An existing server, an arm64 one, or one on
8444 installs online as before.

## Steps

On a computer that can reach GitHub, download three files of the release
into one folder: the bundle, `SHA256SUMS.txt` and `SHA256SUMS.txt.sig`. Copy
the folder to the server, then on the server:

```sh
cd <folder>
# The release key, as in docs/release-signers:
echo 'releases@nebula-vpn namespaces="nebula-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO3oob4Ghi021R3V+1+yMWxEOfNT4OQ1HwsuRsbTKdv1' > signers
ssh-keygen -Y verify -f signers -I releases@nebula-vpn -n nebula-release \
  -s SHA256SUMS.txt.sig < SHA256SUMS.txt          # "Good ... signature"
sha256sum -c --ignore-missing SHA256SUMS.txt      # the bundle: OK
tar -xzf nebula-vpn-vX-server-linux-amd64.tar.gz
sudo ./nebula/install.sh --bundle "$PWD/nebula-vpn-vX-server-linux-amd64.tar.gz"
```

`install.sh` checks the signature and the bundle's hash again, then unpacks
the images, binaries and wheels from the checked file (into
`/var/lib/nebula/bundle`), loads the images instead of building them, and
installs Docker from the distribution's packages when it is missing. A
joined server works the same way: `--bundle <file> --join <address> --token
<token>`.

Do not skip the first check: the copy you run `install.sh` from comes out of
the bundle, so only the signature tells you it is the release.

## Testing

CI (`install.yml`, job `bundle`) builds a bundle, signs it with a key made
for the run (`NEBULA_RELEASE_SIGNERS` points `install.sh` at it), refuses a
copy whose checksum list was changed, then installs with Docker Hub, GitHub
and PyPI blocked and checks that every protocol carries traffic.
