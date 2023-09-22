#
# Lang. ref: https://github.com/bazelbuild/starlark/blob/master/spec.md#contents
# Impl. ref: https://cirrus-ci.org/guide/programming-tasks/
load("cirrus", "fs")

def main():
  return {
    "env": {
      "DIRECT": "ENCRYPTED[61132746e091ed6b1c275fd17ce0aeb72de05c70af12608ec1b8ce272a8358b303ef1cad07f08daacc5ab7b72b17dba7]",
      "INDIRECT": fs.read(".super_secret_file").strip()
    },
  }
