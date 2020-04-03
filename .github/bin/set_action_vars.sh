

# This file is intended for sourcing by the cirrus-ci_retrospective workflow
# It should not be used under any other context.

source $(dirname "${BASH_SOURCE[0]}")/set_task_vars.sh
# These are special magic: https://help.github.com/en/actions/reference/workflow-commands-for-github-actions
printf "\n::set-output name=was_pr::%s\n" "$was_pr"
printf "\n::set-output name=prn::%d\n" "$prn"
printf "\n::set-output name=tid::%s\n" "$tid"
printf "\n::set-output name=sha::%s\n" "$sha"
printf "\n::set-output name=tst::%s\n" "$tst"
