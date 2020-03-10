#!/bin/bash

set -eo pipefail

# Execute inside a github action, using a completed check_suite event's JSON file
# as input.  Querries details about the concluded Cirrus-CI build, tasks, artifacts,
# execution environment, and associated repository state.

# GH GraphQL General Reference: https://developer.github.com/v4/object/
# GH CheckSuite Object Reference: https://developer.github.com/v4/object/checksuite
GHQL_URL="https://api.github.com/graphql"
# Cirrus-CI GrqphQL Reference: https://cirrus-ci.org/api/
CCI_URL="https://api.cirrus-ci.com/graphql"
DEBUG=${DEBUG}
JQ=${JQ:-$(type -P jq)}
CURL=${CURL:-$(type -P curl)}
SCRIPT_FILENAME=$(basename $0)
TMPDIR=$(mktemp -p '' -d ".tmp_${SCRIPT_FILENAME}_XXXXXXXX")


die() {
    echo "Error: ${1:-No error mesage given}" &> /dev/stderr
    exit 1
}

dbg() {
    [[ -z "$DEBUG" ]] || \
        echo -e "${1:-No debugging message given} (${FUNCNAME[1]}() @ ${BASH_SOURCE[1]}:${BASH_LINENO[0]})" > /dev/stderr
}

# Given a GraphQL Query JSON, encode it as a GraphQL query string
encode_query() {
    # Validate JSON, then embed as escaped string.
    # Assume strict-mode JSON where strings quoted with " only
    local json_string=$(echo "$1" | tr -s '\n\t\v ' ' ' | sed -r -e 's/"/\\"/g')
    local result=$(pretty_json "{\"query\": \"$json_string\"}")
    dbg "### GraphQL Query formatted into JSON: '$result'"
    echo "$result"
}

# Get a temporary file named with the calling-function's name
# Optionally, if the first argument is non-empty, use it as the file extension
tmpfile() {
    [[ -n "${FUNCNAME[1]}" ]] || \
        die "tmpfile() function bug that should never happen, did."
    [[ -n "$1" ]] || \
        local ext=".$1"
    mktemp -p "$TMPDIR" ".tmp_${FUNCNAME[1]}_XXXXXXXX${ext}"
}


# Given a URL Data and optionally a token, validate then print formatted JSON string
curl_post() {
    local url="$1"
    local data="$2"
    local token=$GITHUB_TOKEN
    local ret="0"
    local auth=""
    [[ -n "$url" ]] || \
        die "Expecting non-empty url argument"
    [[ -n "$data" ]] || \
        die "Expecting non-empty data argument"
    dbg "### Querying endpoint '$url' with"
    [[ -n "$token" ]] || \
        dbg "### Warning: \$GITHUB_TOKEN is empty, performing unauthenticated query of '$url'" > /dev/stderr
    # Don't expose secrets on any command-line
    local headers_tmpf
    headers_tmpf=$(tmpfile)
    cat << EOF > "$headers_tmpf"
accept: application/vnd.github.antiope-preview+json
content-type: application/json
${token:+authorization: Bearer $token}
EOF
    $CURL --silent --request POST \
      --url "$url" \
      --header "@$headers_tmpf" \
      --data "$data" || ret=$?
    rm -f "$headers_tmpf" &> /dev/null
    dbg "### query exit code '$ret'"
    return $ret
}

# Format JSON suitable for human consumption
pretty_json() {
    local json="$1"
    [[ -n "$json" ]] || \
        die "Expecting non-empty json argument"
    dbg "#### Beatifying some JSON for humans"
    echo "$json" | $JQ --indent 4 . || \
        die "Problem parsing JSON:\n$json"
    #dbg "### $json "
}

# Apply filter to json and print raw output or die with a helpful error
filter_json() {
    local filter="$1"
    local json="$2"
    [[ -n "$filter" ]] || die "Expected non-empty jq filter string"
    [[ -n "$json" ]] || die "Expected non-empty JSON"
    dbg "### Filtering JSON through '$filter'"
    json=$(pretty_json "$json")
    echo "$json" | $JQ --slurp --compact-output --raw-output "$filter" || \
        die "filtering JSON with '$filter': \n$json"
}

# Name suggests parameter order
filter_verify_query() {
    local query_url="$1"
    local filter="$2"
    local test_args="$3"  # optional; sub @@@@ w/ filtered output
    local query_json="$4"
    [[ -n "$query_url" ]] || \
        die "Expecting non-empty query_url argument"
    [[ -n "$filter" ]] || \
        die "Expecting non-empty filter argument"
    [[ -n "$query_json" ]] || \
        die "Expecting non-empty query_json argument"
    dbg "## Submitting GraphQL Query, filtering and verifying the result"
    local encoded_query=$(encode_query "$query_json")
    local result_json=$(curl_post "$query_url" "$encoded_query")
    if [[ "$result_json" =~ "error" ]]; then
        die "Returned from remote endpoint: '$result_json'"
    fi

    local filtered_result=$(filter_json "$filter" "$result_json")
    if [[ -n "$test_args" ]]; then
        # make safe for embedding into bash-string
        dbg "### Escaping filtered json result for testing"
        local _filtered_result=$(echo "$filtered_result" | tr -d '\n\t\v ' | sed -r -e 's/"/\\"/g')
        dbg "### Substututing escaped result into test arguments"
        # FIXME: sed does not work well for all possible values of $_filtered_result/g
        local _test_args=$(echo "$test_args" | sed -r -e "s/@@@@/$_filtered_result/g")
        dbg "## Testing filtered result with 'test $_test_args'"
        local _result_json=$(pretty_json "$result_json")
        if ! test $_test_args; then
            die "GraphQL query result:\n$_result_json\nfiltered to:\n$filtered_result\nfailed verification test:\n$test_args="
        fi
    fi
    dbg "## Filtered and verified result: '$result_json'"
    echo "$filtered_result"
}

##### MAIN #####

if [[ -z "$DEBUG" ]]; then
    trap "rm -rf $TMPDIR" EXIT
else
    dbg "# Warning: Debug mode enabled:  NOT cleaning up '$TMPDIR' upon exit."
fi

[[ "$GITHUB_ACTIONS" == "true" ]] || \
    die "Expecting to be running inside a Github Action"

[[ "$GITHUB_EVENT_NAME" = "check_suite" ]] || \
    die "Expecting \$GITHUB_EVENT_NAME to be 'check_suite'"

[[ -r "$GITHUB_EVENT_PATH" ]] || \
    die "Unable to read github action event file '$GITHUB_EVENT_PATH'"

[[ -n "$GITHUB_TOKEN" ]] || \
    die "Expecting non-empty \$GITHUB_TOKEN"

[[ -d "$GITHUB_WORKSPACE" ]] || \
    die "Expecting to find \$GITHUB_WORKSPACE '$GITHUB_WORKSPACE' as a directory"

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
