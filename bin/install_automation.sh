#!/bin/bash

set -e

# Installs and configures common automation scripts and libraries in
# the environment where it was executed.  Intended to be downloaded
# and executed by root in the target environment.  It is assumed
# the following dependencies are already installed:
#
# bash
# core-utils
# curl
# find-utils
# git
# install
# jq
# sed

# FIXME: Should be automation, not automation_sandbox
AUTOMATION_REPO_URL=${AUTOMATION_REPO_URL:-https://github.com/containers/automation_sandbox.git}
SCRIPT_FILENAME=$(basename $0)
# The source version requested for installing
AUTOMATION_VERSION="$1"
# Sentinel value representing whatever version is present in the local repository
MAGIC_LOCAL_VERSION='0.0.0'
# Needed for unit-testing
DEFAULT_INSTALL_PREFIX=/usr/local/share
INSTALL_PREFIX="${INSTALL_PREFIX:-$DEFAULT_INSTALL_PREFIX}"
# Used internally here and in unit-testing, do not change without a really, really good reason.
_MAGIC_JUJU=${_MAGIC_JUJU:-XXXXX}
_DEFAULT_MAGIC_JUJU=d41d844b68a14ee7b9e6a6bb88385b4d

msg() { echo "${1:-No Message given}" > /dev/stderr; }

# Represents specific installer behavior, should that ever need to change
d41d844b68a14ee7b9e6a6bb88385b4d() {
    TEMPDIR=$(realpath "$(dirname $0)/../")
    trap "rm -rf $TEMPDIR" EXIT

    local actual_inst_path="$INSTALL_PREFIX/automation"
    msg "Installing common scripts/libraries version into '$actual_inst_path'"

    # Allow re-installing different versions, clean out old version if found
    if [[ -d "$actual_inst_path" ]] && [[ -r "$actual_inst_path/AUTOMATION_VERSION" ]]; then
        msg "Warning: Removing existing installed version $(cat $actual_inst_path/AUTOMATION_VERSION)"
        rm -rvf "$actual_inst_path"
    elif [[ -d "$actual_inst_path" ]]; then
        msg "Error: Unable to deal with unknown contents of '$actual_inst_path', manual removal required"
        msg "       Including any relevant lines in /etc/environment."
        exit 12
    fi

    if [[ "$DEFAULT_INSTALL_PREFIX" == "$INSTALL_PREFIX" ]]; then
        # Do a system-wide install assuming permission check passes
        local etc_env_filepath="/etc/environment"
        local inst_perm_arg="-o root -g root"
    elif [[ "$DEFAULT_INSTALL_PREFIX" != "$INSTALL_PREFIX" ]] || [[ "$UID" -ne 0 ]]; then
        # running under unit-tests or some other abnormal environment
        etc_env_filepath="$actual_inst_path/environment"
        inst_perm_arg=""
    fi

    cd "$TEMPDIR/common"
    install -v $inst_perm_arg -D -t "$actual_inst_path/bin" ./bin/*
    install -v $inst_perm_arg -D -t "$actual_inst_path/lib" ./lib/*

    msg "Configuring env. vars. \$AUTOMATION_LIB_PATH and PATH in $etc_env_filepath"
    echo "export AUTOMATION_LIB_PATH='$actual_inst_path/lib'" >> "$etc_env_filepath"
    echo "export PATH=$PATH:$actual_inst_path/bin" >> "$etc_env_filepath"

    # Last step marks a clean install
    echo "$AUTOMATION_VERSION" >> "$actual_inst_path/AUTOMATION_VERSION"
}

exec_installer() {
    if [[ -z "$TEMPDIR" ]] || [[ ! -d "$TEMPDIR" ]]; then
        msg "Error: exec_installer() expected $TEMPDIR to exist"
        exit 13
    fi

    msg "Preparing to execute automation installer for requested version '$AUTOMATION_VERSION'"

    # Special-case, use existing source repository
    if [[ "$AUTOMATION_VERSION" == "$MAGIC_LOCAL_VERSION" ]]; then
        cd $(realpath "$(dirname ${BASH_SOURCE[0]})/../")
        # Make sure it really is a git repository
        if [[ ! -r "./.git/config" ]]; then
            msg "ErrorL Must execute $SCRIPT_FILENAME from a repository clone."
            exit 6
        fi
        # Force version to be installed as the current local repository version
        AUTOMATION_VERSION=$(git describe HEAD)
        msg "Using actual installer version '$AUTOMATION_VERSION' from local repository clone"
        # Allow installer to clean-up TEMPDIR as with updated source
        cp --archive ./* ./.??* "$TEMPDIR/."
    else  # Retrieve the requested version (tag) of the source code
        msg "Refreshing remote repository '$AUTOMATION_REPO_URL'"
        git remote update
        msg "Attempting to clone branch/tag 'v$AUTOMATION_VERSION'"
        git clone --quiet --branch "v$AUTOMATION_VERSION" --depth 1 "$AUTOMATION_REPO_URL" "$TEMPDIR/."
    fi

    DOWNLOADED_INSTALLER="$TEMPDIR/bin/$SCRIPT_FILENAME"
    if [[ -x "$DOWNLOADED_INSTALLER" ]]; then
        msg "Executing install for version '$AUTOMATION_VERSION'"
        trap - EXIT  # Specific installer is now responsible for cleanup
        exec env \
            TEMPDIR="$TEMPDIR" \
            TEST_INSTALL_PREFIX="$TEST_INSTALL_PREFIX" \
            _MAGIC_JUJU="$_DEFAULT_MAGIC_JUJU" \
            "$DOWNLOADED_INSTALLER" "$AUTOMATION_VERSION"
    else
        msg "Error: '$DOWNLOADED_INSTALLER' does not exist or is not executable" > /dev/stderr
        # Allow exi
        exit 8
    fi
}

check_args() {
    if [[ -z "$AUTOMATION_VERSION" ]]; then
        msg "Error: Must specify the version number to install, as the first and only argument."
        msg "       Use version '$MAGIC_LOCAL_VERSION' to install from current source"
        exit 2
    elif ! echo "$AUTOMATION_VERSION" | egrep -q '^v?[0-9]+\.[0-9]+\.[0-9]+(-.+)?'; then
        msg "Error: '$AUTOMATION_VERSION' does not appear to be a valid version number"
        exit 4
    fi
}


##### MAIN #####

check_args

if [[ "$_MAGIC_JUJU" == "XXXXX" ]]; then
    TEMPDIR=$(mktemp -p '' -d "tmp_${SCRIPT_FILENAME}_XXXXXXXX")
    trap "rm -rf $TEMPDIR" EXIT  # version may be invalid or clone could fail or some other error
    exec_installer # Try to obtain version from source then run it
elif [[ "$_MAGIC_JUJU" == "$_DEFAULT_MAGIC_JUJU" ]]; then
    # Running from $TEMPDIR in requested version of source
    $_MAGIC_JUJU
else # Something has gone horribly wrong
    msg "Error: The executed installer script is incompatible with source version $AUTOMATION_VERSION"
    msg "Please obtain and use a newer version of $SCRIPT_FILENAME which supports ID $_MAGIC_JUJU"
    exit 10
fi
