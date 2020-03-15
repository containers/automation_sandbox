

# A Library of contextual console output-related operations.
# Intended for use by other scripts, not to be executed directly.

# helper, not intended for use outside this file
_ctx() {
    # Caller's caller details
    echo "${BASH_SOURCE[3]}:${BASH_LINENO[2]} in ${FUNCNAME[3]}()"
}

# helper, not intended for use outside this file.
_fmt_ctx() {
    local stars="************************************************"
    local prefix="${1:-no prefix given}"
    local message="${2:-no message given}"
    echo "$stars"
    echo "$prefix  ($(_ctx))"
    echo "$stars"
}

# Print a highly-visible message to stderr.  Usage: warn <msg>
warn() {
    _fmt_ctx "WARNING: ${1:-no warning message given}" > /dev/stderr
}

# Same as warn() but exit non-zero or with given exit code
# usage: die <msg> [exit-code]
die() {
    _fmt_ctx "ERROR: ${1:-no error message given}" > /dev/stderr
    exit ${2:-1}
}

dbg() {
    if ((DEBUG)); then
        echo "DEBUG: ${1:-No debugging message given} $(_ctx)}" > /dev/stderr
    fi
}
