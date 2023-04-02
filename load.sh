#!/usr/bin/env bash

set -o nounset

# enable extended pattern matching features
shopt -s extglob

usage() {
    cat << EOT 1>&2
Usage: load.sh [-dfhkq] [-a algo] [-o org] [-p fn] [-x ext] dir

OPTIONS
=======
-a algo     use 'algo' for Decryption via GnuPG; default: AES256
-d          output debug information
-f          overwrite output and index files if they already exists
-h          show help
-k          keep language code as a field
-o org      use 'org' as the organization ID
-p fn       use 'fn' for passphrase file to decrypt
-q          do not display status information
-x ext      use 'ext' as extension for encrypted files; default: enc

ARGUMENTS
=========
dir          directory to write output files

EXAMPLES
========
# load encrypted LastPass items in /tmp/lpass directory into Bitwarden
$ load.sh -d -p passphrase.txt /tmp/lpass

EOT

    exit
}

initGlobals() {
    declare -Ag GLOBALS=(
        [BE_QUIET]='false'              # -q
        [DEBUG]='false'                 # -d
        [DECRYPT_DATA]='false'          # -p
        [DECRYPTION_ALGO]=''            # -a
        [ENCRYPTED_EXTENSION]=''        # -x
        [KEEP_LANGUAGE_CODE]='false'    # -k
        [ORGANIZATION_ID]=''            # -o
        [INPUT_DIR]=''                  # dir
        [OVERWRITE_OPTION]=''           # -f
        [PASSPHRASE_FILE]=''            # -p
    )

    declare -Ag FOLDERS_HASH=()

    declare -Ag TEMPLATES=()

    declare -agr NOTE_FIELDS=(
        'Account Number'
        'Account Type'
        'Address'
        'Agent Name'
        'Agent Phone'
        'Bank Name'
        'Branch Address'
        'Branch Phone'
        'City / Town'
        'Co-pay'
        'Color'
        'Company Phone'
        'Company'
        'Country'
        'DOB'
        'Date of Birth'
        'Expiration Date'
        'Expiration'
        'Expires'
        'Group ID'
        'Height'
        'IBAN Number'
        'IMEI'
        'Issued Date'
        'Issued'
        'Issuing Authority'
        'Keyword'
        'Language'
        'License Class'
        'MAC'
        'Make'
        'Member ID'
        'Member Name'
        'Membership #'
        'Membership Number'
        'Model'
        'Name on Card'
        'Name'
        'Nationality'
        'NoteType'
        'Number'
        'Organization'
        'PIN'
        'Password'
        'Physician Address'
        'Physician Name'
        'Physician Phone'
        'Pin'
        'Policy Number'
        'Policy Type'
        'Port'
        'Purchase Date'
        'Purchase Location'
        'Purchased'
        'Rewards Number'
        'Routing Number'
        'S/N'
        'SMTP Port'
        'SMTP Server'
        'SSN'
        'SWIFT Code'
        'Security Code'
        'Serial Number'
        'Serial'
        'Server'
        'Sex'
        'Start Date'
        'State'
        'Telephone'
        'Type'
        'URL'
        'Username'
        'Website'
        'ZIP / Postal Code'
    )
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

    while getopts ":a:dfhko:p:qx:" FLAG; do
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

            k)
                GLOBALS[KEEP_LANGUAGE_CODE]='true'

                debug "Keep language code turned on."
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

    for DEPENDENCY in bw cat cut echo find gdate grep jq realpath sed tr xargs; do
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

getItemProperty() {
    printf '%s' "$1" | jq --raw-output "$2"
}

loadTemplates() {
    debug "Loading templates."

    TEMPLATES[CARD]=$(bw get template item.card)
    TEMPLATES[FIELD]=$(bw get template item.field)
    TEMPLATES[FOLDER]=$(bw get template folder)
    TEMPLATES[IDENTITY]=$(bw get template item.identity)
    TEMPLATES[ITEM]=$(bw get template item)
    TEMPLATES[LOGIN]=$(bw get template item.login | jq '.totp = null')
    TEMPLATES[NOTE]=$(bw get template item.secureNote)
    TEMPLATES[URI]=$(bw get template item.login.uri)
}

loadFolderHash() {
    local FOLDER_JSON
    local FOLDER_ID
    local FOLDER_NAME

    while read -r FOLDER_JSON; do
        FOLDER_ID=$(getItemProperty "${FOLDER_JSON}" '.id')
        FOLDER_NAME=$(getItemProperty "${FOLDER_JSON}" '.name')

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
    FOLDER_ID=$(printf '%s' "${TEMPLATES[FOLDER]}" | jq ".name = \"${FOLDER_NAME/"/\\"/}\"" | bw encode | bw create folder | jq --raw-output '.id')

    debug "Created folder '${FOLDER_NAME}' (ID: '${FOLDER_ID}')."

    FOLDERS_HASH[${FOLDER_NAME}]=${FOLDER_ID}
}

checkFolder() {
    local FOLDER_NAME

    FOLDER_NAME=$(getItemProperty "$1" '.group')

    debug "Checking for folder named '${FOLDER_NAME}'."

    # if folder name is specified and does not exist as a key, add it
    if [[ -n ${FOLDER_NAME} && -z ${FOLDERS_HASH[${FOLDER_NAME}]+_} ]]; then
        createFolder "${FOLDER_NAME}"
    fi
}

getNoteField() {
    printf '%s' "$1" | grep "^$2:" | cut -d : -f 2-

    # TODO: escape quotes?
}

getItemType() {
    local ITEM_JSON
    local ITEM_URL
    local ITEM_NOTES
    local ITEM_TYPE

    ITEM_JSON=$1

    ITEM_URL=$(getItemProperty "${ITEM_JSON}" '.url')

    if [[ ${ITEM_URL} == 'http://sn' ]]; then
        ITEM_NOTES=$(getItemProperty "${ITEM_JSON}" '.note')

        ITEM_TYPE=$(getNoteField "${ITEM_NOTES}" 'NoteType')

        if [[ -z ${ITEM_TYPE} ]]; then
            ITEM_TYPE='Secure Note'
        fi

        echo "${ITEM_TYPE}"
    else
        echo 'Password'
    fi
}

addAttachments() {
    debug "Adding attachments."
}

# Adapted from <https://stackoverflow.com/a/17841619/2647496>.
joinArray() {
    local DELIM
    local ARRAY

    DELIM=${1-}
    ARRAY=${2-}

    if shift 2; then
        printf '%s' "${ARRAY}" "${@/#/${DELIM}}"
    fi
}

removeItemNote() {
    printf '%s' "$1" | grep -v "^$2:"
}

processFile() {
    local ITEM

    debug "Processing file named '$1'."

    while read -r ITEM; do
        processItem "${ITEM}"
    done < <(decryptData "$1" | jq --compact-output '.[]')
}

trim() {
    sed -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//'
}

filterDummyUrls() {
    sed -e 's/^http{,s}:\/\/$//' \
      -e 's/^xn--https:\/\/-$//' | trim
}

upsertItem() {
    # https://bitwarden.com/help/cli/#create

    #bw encode | \
    cat
}

processItem() {
    local ITEM_JSON
    local LASTPASS_ITEM_ID
    local LASTPASS_ITEM_TYPE
    local ITEM_NOTES
    local FIELD
    local CUSTOM_FIELD
    local SUB_FILTERS_STRING
    local JQ_FILTERS_STRING
    local ITEM_TYPE_CODE
    local ITEM_URL
    local ITEM_USERNAME
    local ITEM_PASSWORD
    local URIS
    local LOGIN
    local LASTPASS_ID_FIELD
    local EXPIRATION_DATE
    local EXPIRATION_MONTH_NAME

    local -A NOTE_FIELD_VALUES=()
    local -a SUB_FILTERS=()
    local -a JQ_FILTERS=()

    ITEM_JSON=$1

    checkFolder "${ITEM_JSON}"

    LASTPASS_ITEM_ID=$(getItemProperty "${ITEM_JSON}" '.id')

    LASTPASS_ITEM_TYPE=$(getItemType "${ITEM_JSON}")

    debug "Processing item (ID: '${LASTPASS_ITEM_ID}') of type '${LASTPASS_ITEM_TYPE}'."

    ITEM_NOTES=$(getItemProperty "${ITEM_JSON}" '.note')

    for FIELD in "${NOTE_FIELDS[@]}"; do
        # TODO: Handle mutliple values with same field name.

        NOTE_FIELD_VALUES[${FIELD}]=$(getNoteField "${ITEM_NOTES}" "${FIELD}")

        ITEM_NOTES=$(removeItemNote "${ITEM_NOTES}" "${FIELD}")

        if [[ -z ${NOTE_FIELD_VALUES[${FIELD}]} ]]; then
            unset "NOTE_FIELD_VALUES[${FIELD}]"
        fi
    done

    unset "NOTE_FIELD_VALUES[NoteType]"

    if [[ ${GLOBALS[KEEP_LANGUAGE_CODE]} != 'true' ]]; then
        unset "NOTE_FIELD_VALUES[Language]"
    fi

    case "${LASTPASS_ITEM_TYPE}" in
        'Address')
            ITEM_TYPE_CODE=4    # Identity
            ;;

        "Driver's License")
            ITEM_TYPE_CODE=4    # Identity

            # NoteType:Driver's License\nNumber:\nExpiration Date:,,\nLicense Class:\nName:\nAddress:\nCity / Town:\nState:\nZIP / Postal Code:\nCountry:\nDate of Birth:\nSex:\nHeight:\nNotes:Server

            # .title = null
            # .
            ;;

        'Credit Card')
            ITEM_TYPE_CODE=3    # Card

            SUB_FILTERS=()

            local -A CARD_NOTE_FIELDS

            CARD_NOTE_FIELDS=([cardholderName]='Name on Card' [number]='Number' [code]='Security Code')

            for FIELD in "${!CARD_NOTE_FIELDS[@]}"; do
                if [[ -n ${NOTE_FIELD_VALUES[${CARD_NOTE_FIELDS[${FIELD}]}]+_} ]]; then
                    SUB_FILTERS+=(".${FIELD} = \"${NOTE_FIELD_VALUES[${CARD_NOTE_FIELDS[${FIELD}]}]/"/\\"/}\"")

                    unset "NOTE_FIELD_VALUES[${CARD_NOTE_FIELDS[${FIELD}]}]"
                else
                    SUB_FILTERS+=(".${FIELD} = null")
                fi
            done

            unset 'CARD_NOTE_FIELDS'

            if [[ -n ${NOTE_FIELD_VALUES[Expiration Date]+_} ]]; then
                EXPIRATION_DATE=${NOTE_FIELD_VALUES[Expiration Date]}
                EXPIRATION_MONTH_NAME=$(printf '%s' "${EXPIRATION_DATE}" | cut -d , -f 1)

                SUB_FILTERS+=(".expMonth = \"$(gdate --date="1 ${EXPIRATION_MONTH_NAME}" +'%m')\"")
                SUB_FILTERS+=(".expYear = \"$(printf '%s' "${EXPIRATION_DATE}" | cut -d , -f 2)\"")

                unset 'NOTE_FIELD_VALUES[Expiration Date]'
            else
                SUB_FILTERS+=(".expMonth = null")
                SUB_FILTERS+=(".expYear = null")
            fi

            if [[ -n ${NOTE_FIELD_VALUES[Type]+_} ]]; then
                SUB_FILTERS+=(".brand = \"$(printf '%s' "${NOTE_FIELD_VALUES[Type]}" | tr '[:upper:]' '[:lower:]')\"")

                unset 'NOTE_FIELD_VALUES[Type]'
            else
                SUB_FILTERS+=(".brand = null")
            fi

            SUB_FILTERS_STRING=$(joinArray ' | ' "${SUB_FILTERS[@]}")

            JQ_FILTERS+=(".card = $(printf '%s' "${TEMPLATES[CARD]}" | \
              jq "${SUB_FILTERS_STRING}")")
            ;;

        'Membership')
            ITEM_TYPE_CODE=1    # Login

            # NoteType:Membership\nOrganization:\nMembership Number:\nMember Name:\nStart Date:,,\nExpiration Date:\nWebsite:\nTelephone:\nPassword:\nNotes:
            ;;

        'Email Account' | 'Password')
            ITEM_TYPE_CODE=1    # Login

            SUB_FILTERS=()

            ITEM_USERNAME=$(getItemProperty "${ITEM_JSON}" '.username')
            ITEM_PASSWORD=$(getItemProperty "${ITEM_JSON}" '.password')

            SUB_FILTERS+=(".username = \"${ITEM_USERNAME/"/\\"/}\"")
            SUB_FILTERS+=(".password = \"${ITEM_PASSWORD/"/\\"/}\"")

            ITEM_URL=$(getItemProperty "${ITEM_JSON}" '.url' | filterDummyUrls)

            if [[ -n ${ITEM_URL} ]]; then
                URIS=$(printf '%s' "${TEMPLATES[URI]}" | jq ".uri = \"${ITEM_URL}\"")

                SUB_FILTERS+=(".uris = ${URIS}")
            fi

            SUB_FILTERS_STRING=$(joinArray ' | ' "${SUB_FILTERS[@]}")

            LOGIN=$(printf '%s' "${TEMPLATES[LOGIN]}" | \
              jq "${SUB_FILTERS_STRING}")

            JQ_FILTERS+=(".login = ${LOGIN}")
            ;;

        'Bank Account' | 'Insurance' | 'Passport' | 'Social Security' | 'Health Insurance' | 'Secure Note')
            ITEM_TYPE_CODE=2    # Secure Note
            ;;

        *)
            ITEM_TYPE_CODE=2    # Secure Note

            debug "Unknown item type; treating as Secure Note."
            ;;
    esac

    ITEM_FOLDER_NAME=$(getItemProperty "${ITEM_JSON}" '.group')

    if [[ -n ${ITEM_FOLDER_NAME} ]]; then
        JQ_FILTERS+=(".folderId = \"${FOLDERS_HASH[${ITEM_FOLDER_NAME}]}\"")
    fi

    JQ_FILTERS+=(".type = ${ITEM_TYPE_CODE}")

    ITEM_NAME=$(getItemProperty "${ITEM_JSON}" '.name')

    JQ_FILTERS+=(".name = \"${ITEM_NAME/"/\\"/}\"")

    ITEM_NOTES=$(printf '%s' "${ITEM_NOTES}" | sed -e 's/^Notes://' )

    JQ_FILTERS+=(".notes = \"${ITEM_NOTES/"/\\"/}\"")

    # add remaining notes fields
    for FIELD in "${!NOTE_FIELD_VALUES[@]}"; do
        CUSTOM_FIELD=$(printf '%s' "${TEMPLATES[FIELD]}" | jq ".name = \"${FIELD}\" | .value = \"${NOTE_FIELD_VALUES[${FIELD}]/"/\\"/}\"")

        JQ_FILTERS+=(".fields += [${CUSTOM_FIELD}]")
    done

    # add a hidden field with the LastPass ID for cross-reference
    LASTPASS_ID_FIELD=$(printf '%s' "${TEMPLATES[FIELD]}" | jq ".name = \"lastpass_id\" | .value = \"${LASTPASS_ITEM_ID}\" | .type = 1")

    JQ_FILTERS+=(".fields += [${LASTPASS_ID_FIELD}]")

    JQ_FILTERS_STRING=$(joinArray ' | ' "${JQ_FILTERS[@]}")

    printf '%s' "${TEMPLATES[ITEM]}" | \
      jq --monochrome-output "${JQ_FILTERS_STRING}" # | \
      #upsertItem

    # TODO: Attachments
    # bw create attachment --file ./path/to/file --itemid 16b15b89-65b3-4639-ad2a-95052a6d8f66
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

    loadTemplates

    loadFolderHash
}

processLastPassExport() {
    local FILE_LIST
    local NUM_ITEMS
    local COUNTER
    local FILE

    debug "Loading exported LastPass items into Bitwarden."

    # build array of file names in input directory
    mapfile -d '' FILE_LIST < <(find "${GLOBALS[INPUT_DIR]}" -type f -depth 1 -print0 | xargs -0 realpath -z)

    NUM_ITEMS=${#FILE_LIST[@]}

    if [[ ${NUM_ITEMS} -gt 0 ]]; then
        debug "Found ${NUM_ITEMS} items."

        COUNTER=0

        for FILE in "${FILE_LIST[@]}"; do
            processFile "${FILE}"

            (( COUNTER++ ))

            showProgress "${COUNTER}" "${NUM_ITEMS}"
        done
    else
        debug "No items found in '${GLOBALS[INPUT_DIR]}'."
    fi
}

performSetup "$@"

processLastPassExport
