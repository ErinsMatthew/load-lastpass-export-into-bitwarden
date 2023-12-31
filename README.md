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
# login, unlock, and sync Bitwarden vault
$ bw login
$ export BW_SESSION
$ bw sync

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
- `gstat` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `jq` - install using [Homebrew](https://formulae.brew.sh/formula/jq), another package manager, or [manually](https://stedolan.github.io/jq/).
- `mktemp` - pre-installed with macOS and most Linux distributions.
- `openssl` - optional; OpenSSL; older version pre-installed with macOS and most Linux distributions; install newer version using [Homebrew](https://formulae.brew.sh/formula/openssl@3), another package manager, or [manually](https://www.openssl.org/source/)
- `realpath` - install via coreutils using [Homebrew](https://formulae.brew.sh/formula/coreutils), another package manager, or [manually](https://www.gnu.org/software/coreutils/).
- `sed` - pre-installed with macOS and most Linux distributions.
- `tr` - pre-installed with macOS and most Linux distributions.
- `xargs` - pre-installed with macOS and most Linux distributions.

## Platform Support

This script was tested on macOS Monterey (12.6) using GNU Bash 5.2.15,
but should work on any GNU/Linux system that supports the dependencies
above.

## Style Guide

This script follows the [Shell Style Guide](https://google.github.io/styleguide/shellguide.html).

## Enhancements

- [ ] Allow organization per folder.
- [ ] Trim passwords, usernames, entry names, etc.?
- [ ] Process: "Start Date", "Expiration", "Expiration Date"?
- [ ] Handle multiple notes values with same key.
