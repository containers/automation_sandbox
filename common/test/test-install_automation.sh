#!/bin/bash

# Unit-tests for installation script with common scripts/libraries.
# Also verifies test script is derived from library filename

TEST_DIR=$(dirname ${BASH_SOURCE[0]})/../../bin/
source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
INSTALLER_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"
TEST_INSTALL_ROOT=$(mktemp -p '' -d tmp_${SUBJ_FILENAME}_XXXXXXXX)
trap "rm -rf $TEST_INSTALL_ROOT" EXIT

# Receives special treatment in the installer script
TEST_INSTALL_PREFIX="$TEST_INSTALL_ROOT/test/automation"

test_cmd \
    "The installer exits non-zero with a helpful message when run without a version argument" \
    2 "Error.+version.+install.+\0.\0.\0" \
    $INSTALLER_FILEPATH

test_cmd \
    "The installer detects an argument which is clearly not a symantic version number" \
    4 "Error.+not.+valid version number" \
    $INSTALLER_FILEPATH "not a version number"

test_cmd \
    "The inetaller exits non-zero with a helpful message about an non-existant version" \
    128 "fatal.+v99.99.99.*not found" \
    $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer detects incompatible future installer source version by an internal mechanism" \
    10 "Error.+incompatible.+99.99.99" \
    env _MAGIC_JUJU=TESTING$(uuidgen)TESTING $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer successfully installs and configures \$TEST_INSTALL_ROOT" \
    0 "Configuring.+$TEST_INSTALL_ROOT/automation/environment" \
    env INSTALL_PREFIX="$TEST_INSTALL_ROOT" $INSTALLER_FILEPATH 0.0.0

test_cmd \
    "The installer correctly removes/reinstalls \$TEST_INSTALL_ROOT" \
    0 "Warning: Removing existing installed version" \
    env INSTALL_PREFIX="$TEST_INSTALL_ROOT" $INSTALLER_FILEPATH 0.0.0

test_cmd \
    "The re-installed version has AUTOMATION_VERSION file matching the current version" \
    0 "$(git describe HEAD)" \
    cat "$TEST_INSTALL_ROOT/automation/AUTOMATION_VERSION"

test_cmd \
    "The non-DEFAULT_INSTALL_ROOT configured environment file defines AUTOMATION_LIB_PATH" \
    0 "^export AUTOMATION_LIB_PATH=" \
    cat $TEST_INSTALL_ROOT/automation/environment

test_cmd \
    "The installer can install the latest upstream version" \
    0 "Configuring.+$TEST_INSTALL_ROOT/automation/environment" \
    env INSTALL_PREFIX="$TEST_INSTALL_ROOT" $INSTALLER_FILEPATH latest

# Must be last call
exit_with_status
