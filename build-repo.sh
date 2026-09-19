#!/usr/bin/env bash
# Regenerate the whole repository tree from a directory of .deb files.
# Stateless by design: the tree is a pure function of the input packages,
# so a rebuild after any release is a full rebuild, not an incremental one.
set -euo pipefail

debs_dir=${1:?usage: build-repo.sh <dir-with-debs> [output-dir]}
out=${2:-public}

suite=${SUITE:-stable}
component=main
origin=${ORIGIN:-lexfrei}
label=${LABEL:-$origin}

rm -rf "$out"
mkdir -p "$out"

shopt -s nullglob
found=("$debs_dir"/*.deb)
if [ ${#found[@]} -eq 0 ]; then
  echo "no .deb files in $debs_dir" >&2
  exit 1
fi

declare -A arch_seen=()
for deb in "${found[@]}"; do
  pkg=$(dpkg-deb --field "$deb" Package)
  arch=$(dpkg-deb --field "$deb" Architecture)
  arch_seen[$arch]=1
  dest="$out/pool/$component/${pkg:0:1}/$pkg"
  mkdir --parents "$dest"
  cp "$deb" "$dest/"
done

# "all" lands in every binary-* index rather than getting an index of its own:
# apt only fetches binary-<its own arch>, so an arch-independent package is
# invisible unless it is listed there.
arches=()
while read -r a; do
  [ -n "$a" ] && arches+=("$a")
done < <(printf '%s\n' "${!arch_seen[@]}" | grep --invert-match '^all$' | sort)
if [ ${#arches[@]} -eq 0 ]; then
  echo "input contains only Architecture: all packages, nothing to index" >&2
  exit 1
fi

cd "$out"
for arch in "${arches[@]}"; do
  dir="dists/$suite/$component/binary-$arch"
  mkdir --parents "$dir"
  dpkg-scanpackages --arch "$arch" pool > "$dir/Packages"
  gzip --keep --force --best "$dir/Packages"
done

# Written aside and moved in: a redirect would create the file before
# apt-ftparchive scans the directory, and it would hash its own output.
release_tmp=$(mktemp)
apt-ftparchive release \
  --option APT::FTPArchive::Release::Origin="$origin" \
  --option APT::FTPArchive::Release::Label="$label" \
  --option APT::FTPArchive::Release::Suite="$suite" \
  --option APT::FTPArchive::Release::Codename="$suite" \
  --option APT::FTPArchive::Release::Components="$component" \
  --option APT::FTPArchive::Release::Architectures="${arches[*]}" \
  "dists/$suite" > "$release_tmp"
mv "$release_tmp" "dists/$suite/Release"

if [ -n "${GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --no-tty --local-user "$GPG_KEY_ID" \
    --clearsign --output "dists/$suite/InRelease" "dists/$suite/Release"
  gpg --batch --yes --no-tty --local-user "$GPG_KEY_ID" \
    --detach-sign --armor --output "dists/$suite/Release.gpg" "dists/$suite/Release"
  gpg --batch --yes --no-tty --armor --export "$GPG_KEY_ID" > "$origin.asc"
fi

echo "built $out for arches: ${arches[*]}"
