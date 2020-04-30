#!/bin/bash

# This script is intended to be executed from a github actions workflow.  It should
# not be run directly unless you know what you're doing.

set -ex

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

# Query stored in GitHub Gist to permit easy modifications/updates
BASE_URL='https://gist.githubusercontent.com/cevich/165f6477745cc2e9ec048f169155fd83/raw'
# Encode query into a file to avoid shell interaction and quoting complexity
echo -n '{"query":"' > ./artifacts/query_raw.json
curl --silent --location --url "$BASE_URL/check_runs_by_sha.graphql" >> ./artifacts/query_raw.json
echo -n '", "variables": ' >> ./artifacts/query_raw.json
curl --silent --location --url "$BASE_URL/variables.json" | \
    sed -r -e "s/@@repo_node_id@@/$repo_node_id/g" | \
    sed -r -e "s/@@head_sha@@/$head_sha/g" >> ./artifacts/query_raw.json
echo '}' >> ./artifacts/query_raw.json
tr -d '[:space:]' < ./artifacts/query_raw.json > ./artifacts/query.json

# Obtain all check_runs and their important details
curl --request POST \
  --silent \
  --location \
  --url https://api.github.com/graphql \
  --header 'accept: application/vnd.github.antiope-preview+json' \
  --header 'authorization: Bearer ${{ github.token }}' \
  --header 'content-type: application/json' \
  --data @./artifacts/query.json -o ./artifacts/reply.json

# Colorized output to help in debugging
jq --indent 4 --color-output . <./artifacts/reply.json
