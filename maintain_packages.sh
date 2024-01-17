#!/bin/bash

# This script is intended to be used by humans or automation to maintain both
# the `BASE_TAG` build-arg in the `Containerfile`, and update the list of
# packages to install when building the container image.  It should be executed:
#   - Any time there is a new (officialy) supported Fedora release.
#   - Following changes to either of the `INST_PKGS` or `EXCL_PKGS`
#     `Containerfile` values.
#   - To update nvra.txt to include the latest available updates.
#
# This script may also be run with the `--check` argument.  In that case
# it will simply exit zero if `Containerfile` reflects the most recent
# supported Fedora release.  Non-zero otherwise.
#
# Any changes to `Containerfile` or `nvra.txt` made by this script are
# intended to be checked into verstion-control, such that container-image
# build automation will pick them up.

set -eo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

declare -a INST_PKGS EXCL_PKGS
# Case-insensitive regex matching package name/version lines in `dnf install` output
TMPD=$(mktemp -d -p '' "$(basename "${BASH_SOURCE[0]}")_XXXXX.tmp")
# Expand $TMPD now, not later
# shellcheck disable=SC2064
trap "rm -rf '$TMPD'" EXIT

declare -a DNFARGS
DNFARGS=( --assumeyes --setopt=keepcache=True --nodocs --noplugins --noplugins )

msg() { echo -en "${1:-No message provided}" >> /dev/stderr; }
die() { msg "${1:-No error message provided}\n" >> /dev/stderr; exit 1; }

cleanup(){
  ret=$?
  set +e

  (
    podman kill -s 9 "$CNTR_NAME"
    podman rm --ignore --force "$CNTR_NAME"
  ) >> /dev/null

  if ((ret)); then
    msg "\nNon-zero exit, preserving '$TMPD' for inspection/debugging.\n"
  else
    rm -rf "$TMPD"
  fi
}

# Given the name of a build-arg, print its value defined in Containerfile
get_bld_arg_val() {
  local value

  [[ -n "$1" ]] || \
    die "${FUNCNAME[0]}() must be called with the name of a build-arg."

  if ! grep -E -q "^ARG $1=.+" ./Containerfile; then
    die "Can't find build-arg definition for '$1' in Containerfile"
  fi

  # Filter-out in-line comments and quotes + show value to stderr
  value=$(grep -E -m 1 "^ARG $1=" ./Containerfile | sed -r -e "s/^ARG $1=\"(.+)\".*/\1/")
  msg "    Using $1: $value\n"

  echo -n "$value"
}

# These live in Containerfile so it may be the single source of truth.
msg "Loading build-args from Containerfile:\n"
# Avoid needing to define these values in more than one place.
for arg_name in BASE_REGISTRY BASE_NAMESPACE BASE_IMGNAME BASE_TAG; do
  declare $arg_name="$(get_bld_arg_val $arg_name | tr -d '[:blank:]')"
  [[ -n "${!arg_name}" ]] || \
    die "Failed to retrieve value for $arg_name from ./Containerfile build-arg"
done

for arg_name in INST_PKGS EXCL_PKGS; do
  declare -a $arg_name
  readarray -t $arg_name <<<"$(get_bld_arg_val $arg_name | tr -s ' ' '\n')"
  if [[ -z "${arg_name[*]}" ]] || [[ "${#arg_name[@]}" -eq 0 ]]; then
    die "Failed to retrieve $arg_name (space-separated values) from ./Containerfile build-arg"
  fi
done

msg "Confirming $BASE_TAG is the latest supported Fedora release.\n"
# The fedora container image workflow tags rawhide builds with it's target
# release number.  That complicates automatic management of the `BASE_TAG`
# build-arg.  Fortunately, it can be looked up from the `latest` tagged
# fedora container image.
fqin="${BASE_REGISTRY}${BASE_NAMESPACE}${BASE_IMGNAME}:latest"
podman run --rm "$fqin" cat /etc/os-release > "$TMPD/os-release"
# No need to shellcheck this
# shellcheck disable=SC1091
_base_tag=$(source "$TMPD/os-release" && echo -n "$VERSION_ID")
expr "$_base_tag" : '[0-9]' >> /dev/null || \
  die "VERSION_ID from os-release file ($_base_tag) in latest fedora image isn't a number"

if [[ $_base_tag -ne $BASE_TAG ]]; then
  if [[ "$1" == "--check" ]]; then
    die "Containerfile BASE_TAG is '$BASE_TAG', but needs updating to '$_base_tag'."
  fi

  msg "Updating Containerfile's base Fedora release:\n"
  # Value needs to live here for building the image at some future time.
  sed -i -r \
    -e "s/^(ARG BASE_TAG=)[ \"']?[[:digit:]]+[ \"']?(.*)/\1\"${_base_tag}\"\2/" \
    Containerfile

  BASE_TAG="$(get_bld_arg_val BASE_TAG)"  # Validates `sed` didn't screw it up
elif [[ "$1" == "--check" ]]; then
  exit 0
fi

# Assist developers of this script
podman volume exists "dnfcache$BASE_TAG" || \
  podman volume create "dnfcache$BASE_TAG"

# From this point forward, the container also needs to be removed
fqin="${BASE_REGISTRY}${BASE_NAMESPACE}${BASE_IMGNAME}:${BASE_TAG}"
CNTR_NAME=$(basename "$TMPD")
trap cleanup EXIT
(
  set -x
  podman run -d --rm --name "${CNTR_NAME}" -v "dnfcache$BASE_TAG:/var/cache/dnf:U,Z" "$fqin" sleep 1h
)

msg "Updating the base container image.\n"
(
  set -x
  podman exec "${CNTR_NAME}" dnf "${DNFARGS[@]}" update
) | while read -r junk; do msg "."; done
msg ".\n"

msg "Obtaining base-image package set.\n"
(
  set -x
  podman exec "${CNTR_NAME}" rpm -qa --qf '%{N}\n'
) | sort | tee "$TMPD/initial_rpms.txt" | while read -r junk; do msg "."; done
declare -a initial_rpms
readarray -t initial_rpms < "$TMPD/initial_rpms.txt"
msg ".\n"

declare -a _dnfinstall
# Using readarray/mapfile would be inconvenient in this case
# shellcheck disable=SC2207
_dnfinstall=( dnf install "${DNFARGS[@]}" "${INST_PKGS[@]}"
              $(for xclded in "${EXCL_PKGS[@]}"; do echo "-x $xclded"; done) )

msg "Installing packages and dependencies.\n"
(
  set -x
  podman exec "${CNTR_NAME}" "${_dnfinstall[@]}"
) | while read -r junk; do msg "."; done
msg ".\n"

# This is the cleanest way of obtaining ${INST_PKGS[@]} + dependencies
# without relying on scraping the potentially unreliable dnf install output.
msg "Obtaining target packages & dependencies.\n"
(
  set -x
  podman exec "${CNTR_NAME}" rpm -qa --qf '%{N}\n'
) | sort | while read -r name junk; do
  if ! echo "${initial_rpms[@]}" | grep -F -q -w "$name"; then
    echo "$name"
    msg "*"
  else
    msg "."
  fi
done > "$TMPD/target_rpms.txt"
declare -a target_rpms
readarray -t target_rpms < "$TMPD/target_rpms.txt"
msg ".\n"

msg "Extracting all package names, versions, releases, and architectures.\n"
# The `nvra.txt file has two purposes:
#  - Renovate scans it and opens update PRs periodically when new
#    versions of select packages become available.
#  - The Containerfile uses it when installing packages
(
  echo "# DO NOT MAKE MANUAL MODIFICATIONS TO THIS FILE"
  echo "#"
  echo "# It should be maintained by re-running $(basename ${BASH_SOURCE[0]})."
  echo "# The list below was produced on $(date -u -Iseconds) using the"
  echo "# script from git commit $(git rev-parse --short HEAD) along with"
  echo "# the container image $fqin"
  echo "# having a digest of $(podman image inspect --format='{{.Digest}}' $fqin)."
  echo "# Installing : ${INST_PKGS[*]}"
  echo "# But excluding: ${EXCL_PKGS[*]}"
  echo "#"
  echo "# DO NOT MAKE MANUAL MODIFICATIONS TO THIS FILE"

  declare -a everything
  readarray -t everything <<<"$(podman exec "${CNTR_NAME}" rpm -qa --qf '%{N} - %{V} - %{R} . %{ARCH} .rpm\n' | sort)"
  for nvra in "${everything[@]}"; do
    read -r name junk <<<"$nvra"

    if echo "${target_rpms[@]}" | grep -F -q -w "$name"; then
      # Annotate package NVRA with magic string for Renovate's regex+repology manager
      # Ref: https://docs.renovatebot.com/modules/datasource/repology/
      echo "# renovate: depName=fedora_$BASE_TAG/$name"
      msg "*"
    else
      msg "."
    fi

    # List the package NVRA so build from `Containerfile` installs it
    echo "$nvra"
  done

  msg ".\n"
) > "$TMPD/nvra.txt"
nvra_total=$(wc -l < "$TMPD/nvra.txt")

# Show what's happening, but ignore if file doesn't exist.
set +e
mv --backup=simple "$TMPD/nvra.txt" ./nvra.txt |& grep -v 'cannot stat'

msg "Created/updated nvra.txt tracking ${#target_rpms[@]} target NVRA(s) out of $nvra_total total packages.\n"
