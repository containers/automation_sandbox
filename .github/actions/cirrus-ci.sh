#!/bin/bash

# This script is intended to be executed from a github actions workflow.  It should
# not be run directly unless you know what you're doing.

set -ex

# Keep files to save separated from everything else
mkdir -p artifacts

# Verify we have reply JSON from prior github query
[[ -r "reply.json" ]]

_filt=.data.node.object.checkSuites.nodes[].checkRuns.nodes[].externalId
# Verify reply JSON is valid, and extract the task IDs as a newline separated list
task_ids=$(jq --compact-output --raw-output $filt <./reply.json)

for task_id in $task_ids; do
    echo "Working on $task_id"
done
