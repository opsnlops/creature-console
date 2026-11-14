# Creature World packages and the fleet packaging policy

Issue: [#290](https://github.com/opsnlops/creature-console/issues/290)

The fleet packaging policy is the agent-memory entry "How April distributes software". It is
canonical and written to stand alone; this file does not copy it, only records how this repo's
Swift/debhelper packages meet it. The policy was written from CMake/CPack projects, so each
rule below was checked against swift-argument-parser binaries built in `debian:trixie`.

Packages in scope: `creature-world`, `creature-house`, `creature-body`,
`creature-communicator-gateway`, `creature-agent`. `creature-cli` and `creature-mqtt` share
`debian/rules`, so the generic pieces (lintian, the Debian build image) cover them too, and since
[#291](https://github.com/opsnlops/creature-console/issues/291) they ship man pages as well:
`creature-cli(1)` (a command people run, so section 1) and `creature-mqtt(8)`. Still open from
#291: `creature-mqtt.service` runs as root.

## Audit and fixes

| Rule | Was | Fix |
|---|---|---|
| Policy §10.1: never ship under `/bin` | world, house, body, gateway shipped `./bin/<name>` | Install to `usr/bin`; units, docs and CI follow. `scripts/check_package_layout.sh` fails on any archive path under `./bin`, `./sbin` or `./lib*`, read from `dpkg-deb --contents` (an installed usr-merged filesystem hides the mistake). Upgrading from the `/bin` packages was tested on trixie: dpkg keeps the moved binary. |
| Policy §12.1: a man page covering every option and the filesystem config | none | `debian/generate-manpage`: options from swift-argument-parser's own generator, configuration from `debian/man/<pkg>.mdoc`. Section 8: they are daemons. The build fails if a page lacks OPTIONS or FILES or misses any long option. |
| lintian, report-only | absent | `scripts/report_lintian.sh` (Docker, `debian:trixie`, `--fail-on none`); CI and `build_debs.sh` print findings, CI raises a `::warning::`. |
| Build on Debian, never Ubuntu | `container:` was set in the CI matrix but never used, so packages were built on the ubuntu-24.04 runner | CI builds in `Dockerfile.debian` with `scripts/dpkg-build-in-container.sh`, the same image and recipe as `build_debs.sh`. Debug symbols are now `-dbgsym_*.deb` (Ubuntu made `.ddeb`). |
| Secrets in `/etc/default/<pkg>`, 0600 | **every** one shipped 0644, including house's `HA_TOKEN` file: `dh_fixperms` resets `/etc` to 0644, silently undoing `install -m600` | `override_dh_fixperms` restores 0600; the layout check asserts it. Existing hosts keep their edited conffile and its old mode: `chmod 600` by hand. |
| Never in packaged config | `debian/creature-agent.yaml` had an `openAiApiKey:` placeholder (a key the code no longer reads) | Removed; `OPENAI_API_KEY` in `/etc/default/creature-agent`. |
| Never root; `DynamicUser=` when possible | creature-agent and creature-agent@ ran as root | `DynamicUser=yes`. Tested on trixie systemd: a pre-existing root-owned `/var/lib/creature-agent/<i>` is migrated to `/var/lib/private`, re-owned, and stays reachable at the old path. Honeycomb shows all four live minds use exactly that path. |
| bash completion | already shipped | Nothing to change. swift-argument-parser generates bash/zsh/fish completion from the parser at build time, so even a daemon's completion cannot go stale. |

## Swift notes for the policy

**Man pages: use swift-argument-parser's generator, not help2man.** help2man runs on
swift-argument-parser `--help` output but has three snags: `OPTIONS:` becomes a `.SS` under
DESCRIPTION; an option whose text is exactly 24 columns (`--log-level <log-level>`) is followed
by a single space and merges into its description; and only one screen is documented, so a
command tree (`creature-agent run`) loses its subcommands' options. The `generate-manual` tool
in the pinned swift-argument-parser (`swift build --product generate-manual`) reads the parser
model through `--experimental-dump-help` and has none of these, at no new Build-Depends. Its
own gaps, handled by `debian/generate-manpage`: no `.Sh OPTIONS` heading, blank lines between
discussion paragraphs (groff warns; replaced with `.Pp`), and no configuration sections (spliced
in from `debian/man/<pkg>.mdoc` before EXIT STATUS). Options with a short name render as
`Fl c , -config`, which the validation accounts for.

**lintian on a Swift/debhelper package (Lintian 2.122.0, trixie, 2026-11-12).** debhelper
already covers what CPack misses (`no-changelog`, `unstripped-binary-or-object`, an empty
extended description). What remains on every Swift binary:

| sev | tag | cause | fixable? |
|---|---|---|---|
| E | `embedded-library` zlib, libyaml | `--static-swift-stdlib` links Foundation's zlib; Yams vendors libyaml | Not while the Swift runtime is linked statically (trixie has no Swift 6.4 runtime package). Override candidate. |
| E | `no-copyright-file` | no `debian/copyright` | Yes, but each binary statically links ~36 SwiftPM packages (two bundle BoringSSL); April to decide how complete. |
| W | `hardening-no-relro`, I `hardening-no-bindnow` | Swift 6.4 links with GNU ld, which emits **one RWE LOAD segment** (the whole image writable and executable) and so no `GNU_RELRO` | **Fixed** (world 0.75.3, agent 2.109.2): `debian/rules` links every product with `-Xswiftc -use-ld=lld -Xlinker -z -Xlinker relro -Xlinker -z -Xlinker now` (lld ships in the toolchain), giving W^X segments, RELRO, BIND_NOW and PIE. `scripts/check_package_layout.sh` fails on an RWE segment, a missing GNU_RELRO or missing BIND_NOW. The lld-linked World ran its migrations and served `/world/v1` against MongoDB; the gateway served its health endpoint. |
| W | `non-standard-file-perm` | `/etc/default/<pkg>` is 0600, as the policy requires | Intended. Override candidate. |
| I | `hardening-no-fortify-functions` | the prebuilt static Swift runtime is not built with `_FORTIFY_SOURCE` | No. |
| W/I | `extended-description-line-too-long`, `description-synopsis-starts-with-article`, `extended-description-is-probably-too-short`, `systemd-service-file-missing-documentation-key` | `debian/control` and unit wording | Yes, trivially. |

**debhelper, not Swift: `dh_fixperms` resets `/etc` to 0644.** Any debhelper package that wants a
0600 file must restore the mode in `override_dh_fixperms`, and check the built archive, because
nothing else notices.
