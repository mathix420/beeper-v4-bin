# Beeper AUR packages — bump each to the latest upstream build and publish to the AUR.
#
#   just                  # upgrade + publish every package (default)
#   just all              # same as above
#   just update nightly   # upgrade + publish a single package
#   just upgrade stable   # bump pkgver + regenerate .SRCINFO only (no commit/push)
#   just publish stable   # commit + push to the AUR (assumes already upgraded)
#   just build nightly    # local makepkg test build (needs `asar`; does not install)
#   just status           # show pending changes in every repo
#
# Each PKGBUILD auto-detects the latest version from its own channel (stable /
# nightly) via its _update_version()/pkgver(), so "upgrade" only has to
# re-evaluate the PKGBUILD and write the result back.
#
# Packages (channel is baked into each repo's PKGBUILD):
#   stable  -> this directory            (beeper-v4-bin)
#   nightly -> ../beeper-nightly-bin     (beeper-nightly-bin)
# The beta channel is intentionally excluded (upstream serves a stale build there).
# To add a package: give it a *_dir variable, a case branch in `_resolve`, and a
# line in `all`.

stable_dir  := justfile_directory()
nightly_dir := justfile_directory() / ".." / "beeper-nightly-bin"

# upgrade + publish every package
default: all

all: (update "stable") (update "nightly")

# upgrade then publish one package
update pkg: (upgrade pkg) (publish pkg)

# bump pkgver to the latest upstream build and regenerate .SRCINFO (no commit/push)
upgrade pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    case '{{ pkg }}' in stable|nightly) ;; *) echo "unknown package: {{ pkg }}" >&2; exit 1 ;; esac
    dir='{{ if pkg == "nightly" { nightly_dir } else { stable_dir } }}'
    cd "$dir"
    current=$(sed -nE 's/^pkgver=(.+)/\1/p' PKGBUILD)
    # pkgver() reaches out to the channel and reports the newest version
    latest=$(makepkg --printsrcinfo | sed -nE 's/^[[:space:]]*pkgver = (.+)/\1/p')
    if [[ -z "$latest" ]]; then echo "{{ pkg }}: could not determine latest version" >&2; exit 1; fi
    if [[ "$latest" == "$current" ]]; then
      echo "{{ pkg }}: already at $current"
    else
      sed -i -E "s/^pkgver=.*/pkgver=${latest}/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
      echo "{{ pkg }}: $current -> $latest"
    fi
    # keep .SRCINFO in lockstep with the PKGBUILD
    makepkg --printsrcinfo > .SRCINFO

# commit PKGBUILD + .SRCINFO and push to the AUR (first push creates the package)
publish pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    case '{{ pkg }}' in stable|nightly) ;; *) echo "unknown package: {{ pkg }}" >&2; exit 1 ;; esac
    dir='{{ if pkg == "nightly" { nightly_dir } else { stable_dir } }}'
    cd "$dir"
    if [[ -z "$(git status --porcelain -- PKGBUILD .SRCINFO)" ]]; then
      echo "{{ pkg }}: nothing to publish"
      exit 0
    fi
    ver=$(sed -nE 's/^pkgver=(.+)/\1/p' PKGBUILD)
    git add PKGBUILD .SRCINFO
    git commit -m "new version available ($ver)"
    git push origin master
    echo "{{ pkg }}: published $ver"

# local test build (downloads the AppImage, repacks the asar); does NOT install
build pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    case '{{ pkg }}' in stable|nightly) ;; *) echo "unknown package: {{ pkg }}" >&2; exit 1 ;; esac
    dir='{{ if pkg == "nightly" { nightly_dir } else { stable_dir } }}'
    cd "$dir"
    makepkg -f

# show pending changes across every repo
status:
    #!/usr/bin/env bash
    set -euo pipefail
    for entry in "stable:{{ stable_dir }}" "nightly:{{ nightly_dir }}"; do
      name="${entry%%:*}"; dir="${entry#*:}"
      echo "== $name ($dir) =="
      git -C "$dir" status --short -- PKGBUILD .SRCINFO || echo "  (not a git repo yet)"
    done
