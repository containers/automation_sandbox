

# This file is intended for sourcing by the cirrus-ci_retrospective workflow
# It should not be used under any other context.

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
testbin() {
    fp="$SCRIPT_DIR/bin/$1"
    if [[ ! -r "$fp" ]] || [[ -x "$fp" ]]; then
        echo "::error::Should be readable but not executable: $fp"
        exit 2
    fi
}

nf="$(ls -1 $SCRIPT_DIR | wc -l)"
if [[ $nf -ne 3 ]]; then
    echo "::error::Expecting exactly 3 files, found $nf"
    exit 3
fi

testbin set_task_vars.sh
testbin set_action_vars.sh
testbin debug_task_vars.sh
