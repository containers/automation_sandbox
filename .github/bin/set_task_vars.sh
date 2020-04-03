

# This file is intended for sourcing by the cirrus-ci_retrospective workflow
# It should not be used under any other context.

# Consume the output JSON from running the cirrus-ci_retrospective container.
prn=$(jq --raw-output '.[] | select(.name == "${MONITOR_TASK}") | .build.pullRequest' "$ccirjson")
tid=$(jq --raw-output '.[] | select(.name == "${ACTION_TASK}") | .id' "$ccirjson")
sha=$(jq --raw-output '.[] | select(.name == "${MONITOR_TASK}") | .build.changeIdInRepo' "$ccirjson")
tst=$(jq --raw-output '.[] | select(.name == "${ACTION_TASK}") | .status' "$ccirjson")

was_pr='false'
do_intg='false'
if [[ -n "$prn" ]] && [[ "$prn" != "null" ]] && [[ $prn -gt 0 ]]; then
    was_pr='true'
    if [[ -n "$tst" ]] && [[ "$tst" == "paused" ]]; then
        do_intg='true'
    fi
fi
