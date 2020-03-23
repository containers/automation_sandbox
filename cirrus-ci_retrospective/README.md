# TODO: Better docs

# Output Decoding

The output JSON is a list of all Cirrus-CI tasks which completed after being triggered by
one of the supported mechanisms (i.e. PR push, branch push, or tag push).  At the time
this was written, CRON-based runs in Cirrus-CI do not trigger a `check_suite` in Github.
Otherwise, based on various values in the output JSON, it is possible to objectivly
determine the execution context for the build.  For example (condensed):

## After pushing to pull request number 34

```json
    {
        "data": {
            "task": {
                ...cut...
                "build": {
                    "changeIdInRepo": "679085b3f2b40797fedb60d02066b3cbc592ae4e",
                    "branch": "pull/34",
                    "pullRequest": 34,
                    ...cut...
                }
                ...cut...
            }
        }
    }
```

## After merging pull request 34 into master branch (merge commit added)

```json
    {
        "data": {
            "task": {
                ...cut...
                "build": {
                    "changeIdInRepo": "232bae5d8ffb6082393e7543e4e53f978152f98a",
                    "branch": "master",
                    "pullRequest": null,
                    ...cut...
                }
                ...cut...
            }
        }
    }
```

## After pushing the tag `v2.2.0` on former pull request 34's HEAD

```json
    {
        "data": {
            "task": {
                ...cut...
                "build": {
                    ...cut...
                    "changeIdInRepo": "679085b3f2b40797fedb60d02066b3cbc592ae4e",
                    "branch": "v2.2.0",
                    "pullRequest": null,
                    ...cut...
                    }
                }
                ...cut...
            }
        }
    }
```
