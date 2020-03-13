#!/bin/bash

source $(dirname $0)/testlib.sh || exit 1
source "$TEST_DIR"/"$SUBJ_FILENAME" || exit 2

test_message_text="This is the test text for a console_output library unit-test"

for fname in warn die; do
    exp_exit=0
    exp_word="WARNING"
    if [[ "$fname" == "die" ]]; then
        exp_exit=1
        exp_word="ERROR"
    fi

    test_cmd "At least 5-stars are shown on call to $fname function" \
        $exp_exit "\*{5}" \
        $fname "$test_message_text"

    test_cmd "The word '$exp_word' appears on call to $fname function" \
        $exp_exit "$exp_word" \
        $fname "$test_message_text"

    test_cmd "The message text appears on call to $fname message" \
        $exp_exit "$test_message_text" \
        $fname "$test_message_text"

    test_cmd "The message text includes a the file, line number and testing function reference" \
        $exp_exit "testlib.sh:[[:digit:]]+ in test_cmd()" \
        $fname "$test_message_text"
done

# script is set +e
exit_with_status
