#!/bin/bash

set -eo pipefail

# Execute inside a github action, using a completed check_suite event's JSON file
# as input.  Querries details about the concluded Cirrus-CI build, tasks, artifacts,
# execution environment, and associated repository state.

source $(dirname "${BASH_SOURCE[0]}")/../lib/$(basename "${BASH_SOURCE[0]}")

if ((DEBUG)); then
    trap "rm -rf $TMPDIR" EXIT
else
    dbg "# Warning: Debug mode enabled:  NOT cleaning up '$TMPDIR' upon exit."
fi

verify_env_vars

# Confirm expected triggering event
[[ "$($JQ --slurp --compact-output --raw-output '.[0].action' < $GITHUB_EVENT_PATH)" == "completed" ]] || \
    die "Expecting github action event action to be 'completed'"

cirrus_app_id=$($JQ --slurp --compact-output --raw-output '.[0].check_suite.app.id' < $GITHUB_EVENT_PATH)
dbg "# Working with Github Application ID: '$cirrus_app_id'"
[[ -n "$cirrus_app_id" ]] || \
    die "Failed to obtain Cirrus-CI's github app ID number"
[[ "$cirrus_app_id" -gt 0 ]] || \
    die "Expecting Cirrus-CI app ID to be integer greater than 0"

# Guaranteed shortcut by Github API straight to actual check_suite node
cs_node_id="$($JQ --slurp --compact-output --raw-output '.[0].check_suite.node_id' < $GITHUB_EVENT_PATH)"
dbg "# Working with github global node id '$cs_node_id'"
[[ -n "$cs_node_id" ]] || \
    die "You must provide the check_suite's node_id string as the first parameter"

#TODO: update filter_verify_query name and args
#TODO: add some missing tests args

# Validate node is really the type expected - global node ID's can point anywhere
dbg "# Checking type of object at '$cs_node_id'"
# Only verification test important, discard actual output
_=$(filter_verify_query "$GHQL_URL" \
    '.[0].data.node.__typename' \
    '"@@@@" = "CheckSuite"' \
    "{
        node(id: \"$cs_node_id\") {
            __typename
        }
    }")

dbg "# Obtaining total number of check_runs present on confirmed CheckSuite object"
cr_count=$(filter_verify_query "$GHQL_URL" \
    '.[0].data.node.checkRuns.totalCount' \
    '@@@@ -gt 0' \
    "{
        node(id: \"$cs_node_id\") {
            ... on CheckSuite {
                checkRuns {
                    totalCount
                }
            }
        }
    }")

# Unknown yet if all check_runs on check_suite are from Cirrus-CI
dbg "# Obtaining task names and id's for up to '$cr_count' check_runs max."
task_ids=$(filter_verify_query "$GHQL_URL" \
    '.[0].data.node.checkRuns.nodes[] | .name + ";" + .externalId' \
    '' \
    "{
        node(id: \"$cs_node_id\") {
          ... on CheckSuite {
            checkRuns(first: $cr_count, filterBy: {appId: $cirrus_app_id}) {
              nodes {
                externalId
                name
              }
            }
          }
        }
    }")

dbg "# Found task names;ids: $task_ids"
unset GITHUB_TOKEN  # not needed/used for cirrus-ci query
echo "$task_ids" | while IFS=';' read task_name task_id
do
    dbg "# Cross-referencing task '$task_name' ID '$task_id' in Cirrus-CI's API:"
    [[ -n "$task_id" ]] || \
        die "Expecting non-empty id for task '$task_name'"
    [[ -n "$task_name" ]] || \
        die "Expecting non-empty name for task id '$task_id'"

    output_json=$(tmpfile .json)
    dbg "# Writing task details into '$output_json' temporarily"
    filter_verify_query "$CCI_URL" \
    '.[0]' \
    '' \
    "{
      task(id: $task_id) {
        name
        status
        automaticReRun
        build {changeIdInRepo branch pullRequest status repository {
            owner name cloneUrl masterBranch
          }
        }
        artifacts {name files{path}}
      }
    }" > "$output_json"
done

dbg '# Combining and pretty-formatting all task data as JSON list'
pretty_json "$(jq --slurp '.' $TMPDIR/.*.json)" | tee "$GITHUB_WORKSPACE/${SCRIPT_FILENAME%.sh}.json"
