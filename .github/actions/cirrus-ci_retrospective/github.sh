#!/bin/bash

set -eo pipefail

# Intended to be executed from a github action workflow step

# Keep files to save separated from everything else
mkdir -p artifacts

# Fail if there is no event file, otherwise preserve it for debugging.
cp "$GITHUB_EVENT_PATH" artifacts/

# Verify script is running against a check_suite event
[[ $(jq --exit-status 'has("check_suite")' < "$GITHUB_EVENT_PATH") == "true" ]]

# Verify the check_suite has completed
_act_typ=$(jq --compact-output --raw-output '.action' < "$GITHUB_EVENT_PATH")
[[ "$_act_typ" == "completed" ]]

# Verify the check_suite is managed by Cirrus-CI
_filt='.check_suite.app.id'
cirrus_app_id=$(jq --compact-output --raw-output "$_filt" < "$GITHUB_EVENT_PATH")
[[ "$cirrus_app_id" == "3232" ]]

# Shortcut to looking up the repository
_filt='.repository.node_id'
repo_node_id=$(jq --compact-output --raw-output "$_filt" < "$GITHUB_EVENT_PATH")

# Commit ID of code used by the check_suite
_filt='.check_suite.head_sha'
head_sha=$(jq --compact-output --raw-output "$_filt" < "$GITHUB_EVENT_PATH")

# Validate both query input variables are non-empty
[[ -n "$repo_node_id" ]] && [[ -n "$head_sha" ]] && \
[[ "$repo_node_id" != "null" ]] && [[ "$head_sha" != "null" ]]

# Encode query into a file to avoid shell interaction and quoting complexity
echo -n '{"query":"' > ./artifacts/query_raw.json
cat $(dirname $0)/check_runs_by_sha.graphql >> ./artifacts/query_raw.json
echo -n '", "variables": ' >> ./artifacts/query_raw.json
sed -r -e "s/@@repo_node_id@@/$repo_node_id/g" $(dirname $0)/check_runs_by_sha.variables | \
    sed -r -e "s/@@head_sha@@/$head_sha/g" >> ./artifacts/query_raw.json
echo '}' >> ./artifacts/query_raw.json
echo "Formatting query JSON for submission"
tr -d '\n' < ./artifacts/query_raw.json | tr -s ' ' | tee ./artifacts/query.json | \
    jq --indent 4 --color-output .

# Obtain all check_runs and their important details
echo "Posting query"
curl --request POST \
  --silent \
  --location \
  --url https://api.github.com/graphql \
  --header 'accept: application/vnd.github.antiope-preview+json' \
  --header "authorization: Bearer $GITHUB_TOKEN" \
  --header 'content-type: application/json' \
  --data @./artifacts/query.json -o ./artifacts/reply.json

# Colorized output to help in debugging
echo "Formatting reply JSON"
jq --indent 4 --color-output . <./artifacts/reply.json

echo "Examining reply for any 'error'"
grep -qi 'error' ./artifacts/reply.json || exit 0
exit 1
