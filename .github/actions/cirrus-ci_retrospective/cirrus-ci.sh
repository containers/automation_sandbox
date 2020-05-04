#!/bin/bash

set -eo pipefail

# Intended to be executed from a github action workflow step

# Verify we have reply JSON from prior github query
[[ -r "reply.json" ]]

# Keep files to save separated from everything else
mkdir -p artifacts

_filt='.data.node.object.checkSuites.nodes[].checkRuns.nodes[].externalId'
# Verify reply JSON is valid, and extract the task IDs as a newline separated list
task_ids=$(jq --compact-output --raw-output $_filt < ./reply.json)

# Encode query into a file to avoid shell interaction and quoting complexity
curl --silent --location --url "$GIST_SCRIPTS_URL/build_task_by_id.tmpl" --remote-name
(
    # Start of raw/unprocessed JSON
    echo -n '{"query":"'
    # Start of query string
    echo 'query {'
    for task_id in $task_ids; do
        echo "Formatting query for $task_id from template" > /dev/stderr
        sed -r -e "s/@@task_id@@/$task_id/g" ./build_task_by_id.tmpl
    done
    # End of query string
    echo '}"'
    # End of JSON
    echo '}'
) >> ./artifacts/query_raw.json

echo "Formatting JSON for submission"
# Embedded newlines make GraphQL Barf, cull extranious spaces, compact JSON
tr -d '\n' < ./artifacts/query_raw.json | tr -s ' ' | jq --compact-output . | \
    tee ./artifacts/query.json | jq --indent 4 --color-output .

echo "Posting query"
curl --request POST \
    --silent \
    --location \
    --url https://api.cirrus-ci.com/graphql \
    --header 'content-type: application/json' \
    --data @./artifacts/query.json -o ./artifacts/reply.json

echo "Formatting reply"
jq --indent 4 --color-output . < ./artifacts/reply.json

echo "Examining reply for any 'error'"
grep -qi 'error' ./artifacts/reply.json || exit 0
exit 1
