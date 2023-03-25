# convert-lastpass-export-to-bitwardenjson

Convert items exported using [lastpass-export](https://github.com/ErinsMatthew/lastpass-export)
to [Bitwarden's JSON format](https://bitwarden.com/help/condition-bitwarden-import/#condition-a-json).

## Overview

This script will convert items exported from LastPass using
[lastpass-export](https://github.com/ErinsMatthew/lastpass-export) to a
JSON format that can be used to import into Bitwarden.

## Execution

To execute this script, run the following commands once the
dependencies are installed:

```sh
# list possible options and help
$ convert.sh -h

# convert encrypted LastPass items in /tmp/lpass directory to Bitwarden JSON format
$ convert.sh -d -p passphrase.txt /tmp/lpass
```

## Dependencies

- `cat` - pre-installed with macOS and most Linux distributions
- `echo` - pre-installed with macOS and most Linux distributions
- `find` - pre-installed with macOS and most Linux distributions
- `gpg` - optional; GNU Privacy Guard; install using [Homebrew](https://formulae.brew.sh/formula/gnupg), another package manager, or [manually](https://gnupg.org/).
- `jq` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/jq), another package manager, or [manually](https://stedolan.github.io/jq/).
- `realpath` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `xargs` - pre-installed with macOS and most Linux distributions

## Platform Support

This script was tested on macOS Monterey (12.6) using GNU Bash 5.2.15,
but should work on any GNU/Linux system that supports the dependencies
above.
