# load-lastpass-export-into-bitwarden

Load items exported using [lastpass-export](https://github.com/ErinsMatthew/lastpass-export)
into [Bitwarden](https://bitwarden.com/).

## Overview

This script will load items exported from LastPass using
[lastpass-export](https://github.com/ErinsMatthew/lastpass-export) into a
Bitwarden vault using the [Bitwarden CLI](https://bitwarden.com/help/cli/).

## Execution

To execute this script, run the following commands once the
dependencies are installed:

```sh
# list possible options and help
$ load.sh -h

# load encrypted LastPass items in /tmp/lpass directory into Bitwarden
$ load.sh -d -p passphrase.txt /tmp/lpass
```

## Dependencies

- `bw` - Bitwarden CLI; install using [Homebrew](https://formulae.brew.sh/formula/bitwarden-cli), another package manager, or [manually](https://bitwarden.com/help/cli/).
- `cat` - pre-installed with macOS and most Linux distributions.
- `echo` - pre-installed with macOS and most Linux distributions.
- `find` - pre-installed with macOS and most Linux distributions.
- `gpg` - optional; GNU Privacy Guard; install using [Homebrew](https://formulae.brew.sh/formula/gnupg), another package manager, or [manually](https://gnupg.org/).
- `jq` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/jq), another package manager, or [manually](https://stedolan.github.io/jq/).
- `realpath` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `xargs` - pre-installed with macOS and most Linux distributions.

## Platform Support

This script was tested on macOS Monterey (12.6) using GNU Bash 5.2.15,
but should work on any GNU/Linux system that supports the dependencies
above.
