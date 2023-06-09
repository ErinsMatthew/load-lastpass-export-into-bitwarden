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

- `base64` - pre-installed with macOS and most Linux distributions.
- `basename` - pre-installed with macOS and most Linux distributions.
- `bw` - Bitwarden CLI; install using [Homebrew](https://formulae.brew.sh/formula/bitwarden-cli), another package manager, or [manually](https://bitwarden.com/help/cli/).
- `cat` - pre-installed with macOS and most Linux distributions.
- `cut` - pre-installed with macOS and most Linux distributions.
- `echo` - pre-installed with macOS and most Linux distributions.
- `find` - pre-installed with macOS and most Linux distributions.
- `gdate` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `gpg` - optional; GNU Privacy Guard; install using [Homebrew](https://formulae.brew.sh/formula/gnupg), another package manager, or [manually](https://gnupg.org/).
- `grep` - pre-installed with macOS and most Linux distributions.
- `jq` - install using [Homebrew](https://formulae.brew.sh/formula/jq), another package manager, or [manually](https://stedolan.github.io/jq/).
- `mktemp` - pre-installed with macOS and most Linux distributions.
- `realpath` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `sed` - pre-installed with macOS and most Linux distributions.
- `tr` - pre-installed with macOS and most Linux distributions.
- `xargs` - pre-installed with macOS and most Linux distributions.

## Platform Support

This script was tested on macOS Monterey (12.6) using GNU Bash 5.2.15,
but should work on any GNU/Linux system that supports the dependencies
above.

## Enhancements

- [ ] Allow organization per folder.
- [ ] Handle attachments.
- [x] Dry run mode.
- [ ] Trim passwords, usernames, entry names, etc.?
- [x] Ignore dummy or invalid URLs (<https://>)
- [ ] Process: "Start Date", "Expiration", "Expiration Date"?
- [ ] Handle multiple notes values with same key.
- [x] Upsert.
