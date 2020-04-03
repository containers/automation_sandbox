

# This file is intended for sourcing by the cirrus-ci_retrospective workflow
# It should not be used under any other context.

source $(dirname "${BASH_SOURCE[0]}")/set_task_vars.sh
echo "Shell variables set:"
${set_task_vars}
echo "Cirrus-CI ran on pr: $was_pr"
echo "Monitor PR Number: ${prn}"
echo "Monitor SHA: ${sha}"
echo "Action Task ID was: ${tid}"
echo "Action Task Status: ${tst}"
echo "Do integration testing: ${do_intg}"
echo ""
echo "Analyzed Cirrus-CI monitoring task:"
jq --indent 4 --color-output '.[] | select(.name == "${MONITOR_TASK}")' ./cirrus-ci_retrospective.json
echo "Analyzed Cirrus-CI action task:"
jq --indent 4 --color-output '.[] | select(.name == "${ACTION_TASK}")' ./cirrus-ci_retrospective.json
