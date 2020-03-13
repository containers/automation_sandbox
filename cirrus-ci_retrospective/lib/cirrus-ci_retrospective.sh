
# Library of constants and functions for the cirrus-ci_retrospective script
# Not intended to be executed directly.

source $(dirname "${BASH_SOURCE[0]}")/common.sh

# GH GraphQL General Reference: https://developer.github.com/v4/object/
# GH CheckSuite Object Reference: https://developer.github.com/v4/object/checksuite
GHQL_URL="https://api.github.com/graphql"
# Cirrus-CI GrqphQL Reference: https://cirrus-ci.org/api/
CCI_URL="https://api.cirrus-ci.com/graphql"
TMPDIR=$(mktemp -p '' -d "$MKTEMP_FORMAT")
# Support easier unit-testing
CURL=${CURL:-$(type -P curl)}


# Given a GraphQL Query JSON, encode it as a GraphQL query string
encode_query() {
    dbg "#### Encoding GraphQL Query into JSON string"
    [[ -n "$1" ]] || \
        die "Expecting JSON string as first argument"
    # Embed GraphQL as escaped string into JSON
    # Assume strict-mode JSON where strings quoted with "
    local json_string
    json_string=$(sed -r -e 's/"/\\"/g' <<<"$1")
    pretty_json "{\"query\": \"$json_string\"}"  # Handles it's own errors
}

# Get a temporary file named with the calling-function's name
# Optionally, if the first argument is non-empty, use it as the file extension
tmpfile() {
    [[ -n "${FUNCNAME[1]}" ]] || \
        die "tmpfile() function bug that should never happen, did."
    [[ -z "$1" ]] || \
        local ext=".$1"
    mktemp -p "$TMPDIR" "$MKTEMP_FORMAT${ext}"
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
    local headers_tmpf=$(tmpfile headers)
    local data_tmpf=$(tmpfile data)
    echo "$data" > "$data_tmpf"
    cat << EOF > "$headers_tmpf"
accept: application/vnd.github.antiope-preview+json
content-type: application/json
${token:+authorization: Bearer $token}
EOF
    $CURL --silent --request POST \
      --url "$url" \
      --header "@$headers_tmpf" \
      --data "@$data_tmpf" || ret=$?
    # Don't leave secrets lying around in files
    rm -f "$headers_tmpf" &> /dev/null
    dbg "### curl exit code '$ret'"
    return $ret
}

# Format JSON suitable for human consumption
# N/B: If output consumed in a sub-shell, it must be examined for 'parse error'
pretty_json() {
    local json="$1"
    [[ -n "$json" ]] || \
        die "Expecting non-empty json argument"
    dbg "#### Formatting JSON for possible human consumption"
    jq --indent 4 . <<<"$json" || die "Call to pretty_json with invalid JSON: '$json'"
}

# Apply filter to json and print raw output or die with a helpful error
filter_json() {
    local filter="$1"
    local json="$2"
    [[ -n "$filter" ]] || die "Expected non-empty jq filter string"
    [[ -n "$json" ]] || die "Expected non-empty JSON"
    dbg "### Filtering JSON through '$filter'"
    json=$(pretty_json "$json")
    jq --compact-output --raw-output "$filter" <<<"$json" || \
        die "Error filtering JSON with '$filter': \n$json"
}

# Name suggests parameter order
url_query_filter_test() {
    local url="$1"
    local query_json="$2"
    local filter="$3"
    shift 3
    local test_args
    test_args="$@"
    [[ -n "$url" ]] || \
        die "Expecting non-empty url argument"
    [[ -n "$filter" ]] || \
        die "Expecting non-empty filter argument"
    [[ -n "$query_json" ]] || \
        die "Expecting non-empty query_json argument"
    dbg "## Submitting GraphQL Query, filtering and verifying the result"
    local encoded_query=$(encode_query "$query_json")
    local result_json
    local ret

    local curl_output
    local curl_outputf=$(tmpfile)
    ret=0
    curl_post "$url" "$encoded_query" > $curl_outputf || ret=$?
    dbg "## Curl command exited $ret" > /tmp/test
    curl_output="$(<$curl_outputf)"

    if [[ "$ret" -ne "0" ]]; then
        die "Curl command exited $ret with output: $curl_output)"
    elif grep -q "error" $curl_outputf; then
        die "Found 'error' in output from curl: $curl_output"
    fi

    dbg "## Running filter on curl output"
    local filtered_result=$(filter_json "$filter" "$curl_output")
    if [[ -n "$test_args" ]]; then
        result_tmpf=$(tmpfile)
        # make result safe for embedding as string into test command
        printf '%q' "$filtered_result" | tr -d '[:space:]'  > "$result_tmpf"
        local _test_args=$(echo "test $test_args" | sed -r -e "s/@@@@/'$(<$result_tmpf)'/g")
        dbg "## Testing filtered result with '$test_args'"
        ( eval "$_test_args" ) || \
            die "GraphQL query filtered with $filter failed verification test $test_args: $(<$result_tmpf)"
    fi
    dbg "## Filtered and verified result: '$result_json'"
    echo "$filtered_result"
}

verify_env_vars() {
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
}
