

# This file is intended for sourcing by the cirrus-ci_retrospective workflow
# It should not be used under any other context.

# Consume the output JSON from running the cirrus-ci_retrospective container.
prn=$(jq --raw-output '.[] | select(.name == "${MONITOR_TASK}") | .build.pullRequest' ./cirrus-ci_retrospective.json)
tid=$(jq --raw-output '.[] | select(.name == "${ACTION_TASK}") | .id' ./cirrus-ci_retrospective.json)
sha=$(jq --raw-output '.[] | select(.name == "${MONITOR_TASK}") | .build.changeIdInRepo' ./cirrus-ci_retrospective.json)
tst=$(jq --raw-output '.[] | select(.name == "${ACTION_TASK}") | .status' ./cirrus-ci_retrospective.json)

was_pr='false'
do_intg='false'
if [[ -n "$prn" ]] && [[ "$prn" != "null" ]] && [[ $prn -gt 0 ]]; then
    was_pr='true'
    if [[ -n "$tst" ]] && [[ "$tst" == "paused" ]]; then
        do_intg='true'
    fi
fi
