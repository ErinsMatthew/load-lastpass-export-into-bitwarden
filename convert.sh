#!/usr/bin/env bash

set -o nounset

# enable extended pattern matching features
shopt -s extglob

usage() {
    cat << EOT 1>&2
Usage: convert.sh [-dfhq] [-a algo] [-o org] [-p fn] [-x ext] dir

OPTIONS
=======
-a algo      use 'algo' for Decryption via GnuPG; default: AES256
-d           output debug information
-f           overwrite output and index files if they already exists
-h           show help
-o org       use 'org' as the organization ID
-p fn        use 'fn' for passphrase file to decrypt
-q           do not display status information
-x ext       use 'ext' as extension for encrypted files; default: enc

ARGUMENTS
=========
dir          directory to write output files

EXAMPLES
========
# convert encrypted LastPass items in /tmp/lpass directory to Bitwarden JSON format
$ convert.sh -d -p passphrase.txt /tmp/lpass

EOT

    exit
}

initGlobals() {
    declare -gA GLOBALS=(
        [BE_QUIET]='false'              # -q
        [DEBUG]='false'                 # -d
        [DECRYPT_DATA]='false'          # -p
        [DECRYPTION_ALGO]=''            # -a
        [ENCRYPTED_EXTENSION]=''        # -x
        [ORGANIZATION_ID]=''            # -o
        [INPUT_DIR]=''                  # dir
        [OVERWRITE_OPTION]=''           # -f
        [PASSPHRASE_FILE]=''            # -p
    )

    declare -gA FOLDERS_HASH=()
}

debug() {
    if [[ ${GLOBALS[DEBUG]} == 'true' ]]; then
        echo "$@"
    fi
}

processOptions() {
    local FLAG
    local OPTARG
    local OPTIND

    [[ $# -eq 0 ]] && usage

    while getopts ":a:dfho:p:qx:" FLAG; do
        case "${FLAG}" in
            a)
                GLOBALS[DECRYPTION_ALGO]=${OPTARG}

                debug "Decryption algorithm set to '${GLOBALS[DECRYPTION_ALGO]}'."
                ;;

            d)
                GLOBALS[DEBUG]='true'

                debug "Debug mode turned on."
                ;;

            f)
                GLOBALS[OVERWRITE_OPTION]='-f'

                debug "Force overwrite mode turned on."
                ;;

            o)
                GLOBALS[ORGANIZATION_ID]=${OPTARG}

                debug "Organization ID set to '${GLOBALS[ORGANIZATION_ID]}'."
                ;;

            p)
                GLOBALS[DECRYPT_DATA]='true'

                debug "Decryption turned on."

                GLOBALS[PASSPHRASE_FILE]=${OPTARG}

                debug "Decryption passphrase file set to '${GLOBALS[PASSPHRASE_FILE]}'."
                ;;

            q)
                GLOBALS[BE_QUIET]='true'

                debug "Quiet mode turned on."
                ;;

            x)
                GLOBALS[ENCRYPTED_EXTENSION]=${OPTARG}

                debug "Encrypted extension set to '${GLOBALS[ENCRYPTED_EXTENSION]}'."
                ;;

            h | *)
                usage
                ;;
        esac
    done

    shift $(( OPTIND - 1 ))

    [[ $# -eq 0 ]] && usage

    GLOBALS[INPUT_DIR]=$(realpath "$1")
}

validateInputs() {
    if [[ -z ${GLOBALS[INPUT_DIR]} ]]; then
        echo "Missing input directory." > /dev/stderr

        usage
    fi

    if [[ ! -d ${GLOBALS[INPUT_DIR]} ]]; then
        echo "Input directory is not actually a directory." > /dev/stderr

        exit
    fi

    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' && ! -s ${GLOBALS[PASSPHRASE_FILE]} ]]; then
        echo "Decryption requested, but passphrase file does not exist or is empty." > /dev/stderr

        exit
    fi
}

setDefaults() {
    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        if [[ -z ${GLOBALS[DECRYPTION_ALGO]} ]]; then
            GLOBALS[DECRYPTION_ALGO]='AES256'

            debug "Decryption algorithm set to default of '${GLOBALS[DECRYPTION_ALGO]}'."
        fi

        if [[ -z ${GLOBALS[ENCRYPTED_EXTENSION]} ]]; then
            GLOBALS[ENCRYPTED_EXTENSION]='enc'

            debug "Encrypted extension set to default of '${GLOBALS[ENCRYPTED_EXTENSION]}'."
        fi
    fi

    if [[ -z ${GLOBALS[OVERWRITE_OPTION]} ]]; then
        GLOBALS[OVERWRITE_OPTION]=''

        debug "Overwrite option set to default of '${GLOBALS[OVERWRITE_OPTION]}'."
    fi
}

checkForDependency() {
    debug "Checking for dependency '$1'."

    if ! command -v "$1" &> /dev/null; then
        echo "Dependency '$1' is missing." > /dev/stderr

        exit
    fi
}

dependencyCheck() {
    local DEPENDENCY

    for DEPENDENCY in cat echo find jq realpath xargs; do
        checkForDependency "${DEPENDENCY}"
    done

    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        checkForDependency gpg
    fi
}

decryptData() {
    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        gpg --quiet --batch --decrypt \
          --passphrase-file "${GLOBALS[PASSPHRASE_FILE]}" \
          --cipher-algo "${GLOBALS[DECRYPTION_ALGO]}" \
          "$1"
    else
        cat "$1"
    fi
}

loadFolderHash() {
    local FOLDER_JSON
    local FOLDER_ID
    local FOLDER_NAME

    while read -r FOLDER_JSON; do
        FOLDER_ID=$(printf '%s' "${FOLDER_JSON}" | jq --raw-output '.id')
        FOLDER_NAME=$(printf '%s' "${FOLDER_JSON}" | jq --raw-output '.name')

        # if folder name is specified and does not exist as a key, add it
        if [[ -z ${FOLDERS_HASH[${FOLDER_NAME}]+_} ]]; then
            debug "Adding folder '${FOLDER_NAME}' (ID: '${FOLDER_ID}')."

            FOLDERS_HASH[${FOLDER_NAME}]=${FOLDER_ID}
        else
            debug "Found a duplicate folder '${FOLDER_NAME}' (ID: '${FOLDER_ID}')."
        fi
    done < <(bw list folders | jq --compact-output '.[]')
}

createFolder() {
    local FOLDER_NAME
    local FOLDER_ID

    FOLDER_NAME=$1
    FOLDER_ID=$(printf '{"name": "%s"}' "${FOLDER_NAME}" | bw encode | bw create folder | jq --raw-output '.id')

    FOLDERS_HASH[${FOLDER_NAME}]=${FOLDER_ID}
}

checkFolder() {
    local FOLDER_NAME

    FOLDER_NAME=$(printf '%s' "$1" | jq --raw-output '.group')

    # if folder name is specified and does not exist as a key, add it
    if [[ -n ${FOLDER_NAME} && -z ${FOLDERS_HASH[${FOLDER_NAME}]+_} ]]; then
        createFolder "${FOLDER_NAME}"
    fi
}

processItem() {
    echo "$1"
}

showProgress() {
    if [[ ${GLOBALS[BE_QUIET]} != 'true' ]]; then
        debug "Processed $1 of $2."
    fi
}

performSetup() {
    initGlobals

    processOptions "$@"

    validateInputs

    setDefaults

    dependencyCheck

    loadFolderHash
}

convertAllItems() {
    local FILE_LIST
    local NUM_ITEMS
    local COUNTER
    local FILE
    local ITEM_JSON

    debug "Converting exported LastPass items to Bitwarden JSON."

    # build array of file names in input directory
    mapfile -d '' FILE_LIST < <(find "${GLOBALS[INPUT_DIR]}" -type f -depth 1 -print0 | xargs -0 realpath -z)

    NUM_ITEMS=${#FILE_LIST[@]}

    if [[ ${NUM_ITEMS} -gt 0 ]]; then
        debug "Found ${NUM_ITEMS} items."

        COUNTER=0

        for FILE in "${FILE_LIST[@]}"; do
            ITEM_JSON=$(decryptData "${FILE}" | jq --compact-output '.[0]')

            checkFolder "${ITEM_JSON}"

            # ITEMS_ARRAY+=( "$(processItem "${ITEM_JSON}")" )

            (( COUNTER++ ))

            showProgress "${COUNTER}" "${NUM_ITEMS}"
        done
    else
        debug "No items found in '${GLOBALS[INPUT_DIR]}'."
    fi
}

convertLastPassExport() {
    convertAllItems

    buildBitwardenJson
}

performSetup "$@"

convertLastPassExport
