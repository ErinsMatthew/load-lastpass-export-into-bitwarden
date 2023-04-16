#!/usr/bin/env bash

set -o nounset

# enable extended pattern matching features
shopt -s extglob

usage() {
    cat << EOT 1>&2
Usage: load.sh [-dfhkqz] [-a algo] [-o org] [-p fn] [-x ext] dir

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
-z          do not perform actions; dry run mode

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
        [DRY_RUN]='false'               # -z
        [ENCRYPTED_EXTENSION]=''        # -x
        [INPUT_DIR]=''                  # dir
        [KEEP_LANGUAGE_CODE]='false'    # -k
        [ORGANIZATION_ID]=''            # -o
        [OVERWRITE_OPTION]=''           # -f
        [PASSPHRASE_FILE]=''            # -p
        [TEMP_DIR]=$(mktemp -d)
    )

    declare -Ag FOLDERS_HASH=()

    declare -Ag ITEMS_HASH=()

    declare -Ag TEMPLATES=()

    declare -g LASTPASS_ID_FIELD_NAME=lastpass_id

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

    while getopts ":a:dfhko:p:qx:z" FLAG; do
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

            z)
                GLOBALS[DRY_RUN]='true'

                debug "Dry run mode turned on."
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

    for DEPENDENCY in base64 bw cat cut echo find gdate grep jq realpath sed tr xargs; do
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

getLastPassItemProperty() {
    printf '%s' "$1" | jq --raw-output "$2" | trim
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
        FOLDER_ID=$(getLastPassItemProperty "${FOLDER_JSON}" '.id')
        FOLDER_NAME=$(getLastPassItemProperty "${FOLDER_JSON}" '.name')

        # if folder does not exist in hash, add it
        if [[ -z ${FOLDERS_HASH[${FOLDER_NAME}]+_} ]]; then
            debug "Adding folder '${FOLDER_NAME}' (ID: '${FOLDER_ID}') to hash."

            FOLDERS_HASH[${FOLDER_NAME}]=${FOLDER_ID}
        else
            debug "Found a duplicate folder '${FOLDER_NAME}' (ID: '${FOLDER_ID}')."
        fi
    done < <(bw list folders | jq --compact-output '.[]')
}

loadItemHash() {
    local BITWARDEN_ITEM_JSON
    local LASTPASS_ITEM_ID

    while read -r BITWARDEN_ITEM_JSON; do
        LASTPASS_ITEM_ID=$(printf '%s' "${BITWARDEN_ITEM_JSON}" | jq --raw-output ".fields[] | select( .name == \"${LASTPASS_ID_FIELD_NAME}\" ) | .value")

        # if item does not exist in hash, add it
        if [[ -n ${LASTPASS_ITEM_ID} && -z ${ITEMS_HASH[${LASTPASS_ITEM_ID}]+_} ]]; then
            debug "Adding item '${LASTPASS_ITEM_ID}' to hash."

            ITEMS_HASH[${LASTPASS_ITEM_ID}]=${BITWARDEN_ITEM_JSON}
        fi
    done < <(bw list items | jq --compact-output ".[] | select( .fields != null ) | select( .fields[].name == \"${LASTPASS_ID_FIELD_NAME}\" )")
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

    FOLDER_NAME=$(getLastPassItemProperty "$1" '.group')

    if [[ -n ${FOLDER_NAME} ]]; then
        debug "Checking for folder named '${FOLDER_NAME}'."

        # if folder name is specified and does not exist as a key, add it
        if [[ -z ${FOLDERS_HASH[${FOLDER_NAME}]+_} ]]; then
            createFolder "${FOLDER_NAME}"
        fi
    fi
}

getLastPassNoteFieldValue() {
    printf '%s' "$1" | grep "^$2:" | cut -d : -f 2- | trim

    # TODO: escape quotes?
}

getLastPassItemType() {
    local LASTPASS_ITEM_JSON
    local ITEM_URL
    local LASTPASS_ITEM_NOTES
    local LASTPASS_ITEM_TYPE

    LASTPASS_ITEM_JSON=$1

    ITEM_URL=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.url')

    if [[ ${ITEM_URL} == 'http://sn' ]]; then
        LASTPASS_ITEM_NOTES=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.note')

        LASTPASS_ITEM_TYPE=$(getLastPassNoteFieldValue "${LASTPASS_ITEM_NOTES}" 'NoteType')

        if [[ -z ${LASTPASS_ITEM_TYPE} ]]; then
            LASTPASS_ITEM_TYPE='Secure Note'
        fi

        echo "${LASTPASS_ITEM_TYPE}"
    else
        echo 'Password'
    fi
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

removeLastPassItemNoteField() {
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
    sed -E -e 's#https?://$##' \
      -e 's#xn--https?://-$##' | trim
}

bwEditOrCreate() {
    local BITWARDEN_ITEM_ID

    BITWARDEN_ITEM_ID=${2:-0}

    if [[ ${GLOBALS[DRY_RUN]} == 'true' ]]; then
        if [[ $1 == 'edit' ]]; then
            printf '{ "id": "%s" }' "${BITWARDEN_ITEM_ID}"
        else
            base64 --decode
        fi
    else
        if [[ $1 == 'edit' ]]; then
            bw edit item "${BITWARDEN_ITEM_ID}"
        else
            bw create item
        fi
    fi
}

upsertItem() {
    local BITWARDEN_ITEM_JSON
    local ENCODED_JSON
    local BITWARDEN_ITEM_ID

    BITWARDEN_ITEM_JSON=$1

    ENCODED_JSON=$(printf '%s' "${BITWARDEN_ITEM_JSON}" | bw encode)

    BITWARDEN_ITEM_ID=$(printf '%s' "${BITWARDEN_ITEM_JSON}" | jq --raw-output '.id // ""')

    if [[ -n ${BITWARDEN_ITEM_ID} ]]; then
        printf '%s' "${ENCODED_JSON}" | \
          bwEditOrCreate 'edit' "${BITWARDEN_ITEM_ID}" | \
          jq --raw-output '.id // ""'
    else
        printf '%s' "${ENCODED_JSON}" | \
          bwEditOrCreate 'create' | \
          jq --raw-output '.id // ""'
    fi
}

processAttachments() {
    local LASTPASS_ITEM_ID

    LASTPASS_ITEM_ID=$1

    if [[ -d ${GLOBALS[INPUT_DIR]}/${LASTPASS_ITEM_ID} ]]; then
        local BITWARDEN_ITEM_ID
        local FILE_LIST
        local NUM_ITEMS
        local COUNTER
        local FILE
        local TEMP_FILE

        BITWARDEN_ITEM_ID=$2

        debug "Processing attachments for '${LASTPASS_ITEM_ID}' (Bitwarden Item ID: ${BITWARDEN_ITEM_ID})."

        # build array of attachment file names in item directory
        mapfile -d '' FILE_LIST < <(find "${GLOBALS[INPUT_DIR]}/${LASTPASS_ITEM_ID}" -type f -depth 1 -print0 | xargs -0 realpath -z)

        NUM_ITEMS=${#FILE_LIST[@]}

        if [[ ${NUM_ITEMS} -gt 0 ]]; then
            debug "Found ${NUM_ITEMS} attachments for '${LASTPASS_ITEM_ID}'."

            for FILE in "${FILE_LIST[@]}"; do
                debug "Processing attachment '${FILE}'."

                TEMP_FILE=${GLOBALS[TEMP_DIR]}/$(basename "${FILE}")

                decryptData "${FILE}" > "${TEMP_FILE}"

                # bw create attachment --file "${TEMP_FILE}" --itemid "${BITWARDEN_ITEM_ID}"

                rm -f "${TEMP_FILE}"
            done
        fi
    fi
}

getBitwardenItemJson() {
    if [[ -n ${ITEMS_HASH[$1]+_} ]]; then
        printf '%s' "${ITEMS_HASH[$1]}"
    else
        printf '%s' "${TEMPLATES[ITEM]}"
    fi
}

addField() {
    local -n JQ_FILTERS_REF
    local BITWARDEN_ITEM_JSON
    local CUSTOM_FIELD_NAME
    local CUSTOM_FIELD_VALUE
    local CUSTOM_FIELD_TYPE
    local NUM_FIELDS
    local CUSTOM_FIELD

    JQ_FILTERS_REF=$1
    BITWARDEN_ITEM_JSON=$2
    CUSTOM_FIELD_NAME=$3
    CUSTOM_FIELD_VALUE=$4
    CUSTOM_FIELD_TYPE=${5:-0}       # default to zero

    NUM_FIELDS=$(printf '%s' "${BITWARDEN_ITEM_JSON}" | \
      jq --raw-output ".fields[] | select( .name == \"${CUSTOM_FIELD_NAME}\" and .value == \"${CUSTOM_FIELD_VALUE}\" ) | length")

    if [[ ${NUM_FIELDS} -eq 0 ]]; then
        CUSTOM_FIELD=$(printf '%s' "${TEMPLATES[FIELD]}" | \
        jq ".name = \"${CUSTOM_FIELD_NAME}\" | .value = \"${CUSTOM_FIELD_VALUE}\" | .type = ${CUSTOM_FIELD_TYPE}")

        JQ_FILTERS_REF+=(".fields += [${CUSTOM_FIELD}]")
    fi
}

processLastPassNoteFields() {
    local LASTPASS_ITEM_NOTES
    local -nA NOTE_FIELD_VALUES_REF
    local FIELD

    LASTPASS_ITEM_NOTES=$1
    NOTE_FIELD_VALUES_REF=$2

    for FIELD in "${NOTE_FIELDS[@]}"; do
        # TODO: Handle mutliple values with same field name.

        NOTE_FIELD_VALUES_REF[${FIELD}]=$(getLastPassNoteFieldValue "${LASTPASS_ITEM_NOTES}" "${FIELD}")

        LASTPASS_ITEM_NOTES=$(removeLastPassItemNoteField "${LASTPASS_ITEM_NOTES}" "${FIELD}")

        if [[ -z ${NOTE_FIELD_VALUES_REF[${FIELD}]} ]]; then
            unset "NOTE_FIELD_VALUES_REF[${FIELD}]"
        fi
    done

    unset "NOTE_FIELD_VALUES_REF[NoteType]"

    if [[ ${GLOBALS[KEEP_LANGUAGE_CODE]} != 'true' ]]; then
        unset "NOTE_FIELD_VALUES_REF[Language]"
    fi

    printf '%s' "${LASTPASS_ITEM_NOTES}"
}

processItem() {
    local LASTPASS_ITEM_JSON
    local LASTPASS_ITEM_ID
    local LASTPASS_ITEM_TYPE
    local LASTPASS_ITEM_NOTES
    local FIELD
    local SUB_FILTERS_STRING
    local JQ_FILTERS_STRING
    local ITEM_TYPE_CODE
    local ITEM_URL
    local ITEM_USERNAME
    local ITEM_PASSWORD
    local URIS
    local LOGIN
    local EXPIRATION_DATE
    local EXPIRATION_MONTH_NAME
    local BITWARDEN_ITEM_JSON
    local BITWARDEN_ITEM_ID

    local -A NOTE_FIELD_VALUES=()
    local -a SUB_FILTERS=()
    local -a JQ_FILTERS=()

    LASTPASS_ITEM_JSON=$1

    checkFolder "${LASTPASS_ITEM_JSON}"

    LASTPASS_ITEM_ID=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.id')

    LASTPASS_ITEM_TYPE=$(getLastPassItemType "${LASTPASS_ITEM_JSON}")

    debug "Processing item (ID: '${LASTPASS_ITEM_ID}') of type '${LASTPASS_ITEM_TYPE}'."

    LASTPASS_ITEM_NOTES=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.note')

    LASTPASS_ITEM_NOTES=$(processLastPassNoteFields "${LASTPASS_ITEM_NOTES}" NOTE_FIELD_VALUES)

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

        'Email Account' | 'Password')
            ITEM_TYPE_CODE=1    # Login

            SUB_FILTERS=()

            ITEM_USERNAME=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.username')
            ITEM_PASSWORD=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.password')

            SUB_FILTERS+=(".username = \"${ITEM_USERNAME/"/\\"/}\"")
            SUB_FILTERS+=(".password = \"${ITEM_PASSWORD/"/\\"/}\"")

            ITEM_URL=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.url' | filterDummyUrls)

            if [[ -n ${ITEM_URL} ]]; then
                URIS=$(printf '%s' "${TEMPLATES[URI]}" | jq ".uri = \"${ITEM_URL}\"")

                SUB_FILTERS+=(".uris += [${URIS}]")
            fi

            SUB_FILTERS_STRING=$(joinArray ' | ' "${SUB_FILTERS[@]}")

            LOGIN=$(printf '%s' "${TEMPLATES[LOGIN]}" | \
              jq "${SUB_FILTERS_STRING}")

            JQ_FILTERS+=(".login = ${LOGIN}")
            ;;

        'Bank Account' | 'Insurance' | 'Membership' | 'Passport' | 'Social Security' | 'Health Insurance' | 'Secure Note')
            ITEM_TYPE_CODE=2    # Secure Note
            ;;

        *)
            ITEM_TYPE_CODE=2    # Secure Note

            debug "Unknown item type; treating as Secure Note."
            ;;
    esac

    ITEM_FOLDER_NAME=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.group')

    if [[ -n ${ITEM_FOLDER_NAME} ]]; then
        JQ_FILTERS+=(".folderId = \"${FOLDERS_HASH[${ITEM_FOLDER_NAME}]}\"")
    fi

    JQ_FILTERS+=(".type = ${ITEM_TYPE_CODE}")

    ITEM_NAME=$(getLastPassItemProperty "${LASTPASS_ITEM_JSON}" '.name')

    JQ_FILTERS+=(".name = \"${ITEM_NAME/"/\\"/}\"")

    LASTPASS_ITEM_NOTES=$(printf '%s' "${LASTPASS_ITEM_NOTES}" | sed -e 's/^Notes://' )

    JQ_FILTERS+=(".notes = \"${LASTPASS_ITEM_NOTES/"/\\"/}\"")

    BITWARDEN_ITEM_JSON=$(getBitwardenItemJson "${LASTPASS_ITEM_ID}")

    # add remaining notes fields
    for FIELD in "${!NOTE_FIELD_VALUES[@]}"; do
        addField JQ_FILTERS "${BITWARDEN_ITEM_JSON}" "${FIELD}" "${NOTE_FIELD_VALUES[${FIELD}]/"/\\"/}"
    done

    addField JQ_FILTERS "${BITWARDEN_ITEM_JSON}" "${LASTPASS_ID_FIELD_NAME}" "${LASTPASS_ITEM_ID}"

    JQ_FILTERS_STRING=$(joinArray ' | ' "${JQ_FILTERS[@]}")

    BITWARDEN_ITEM_JSON=$(printf '%s' "${BITWARDEN_ITEM_JSON}" | \
      jq "${JQ_FILTERS_STRING}")

    # TODO: if [[ changes ]]; then
    debug "Upserting item (ID: '${LASTPASS_ITEM_ID}')."

    debug "BITWARDEN_ITEM_JSON = ${BITWARDEN_ITEM_JSON}"

    BITWARDEN_ITEM_ID=$(upsertItem "${BITWARDEN_ITEM_JSON}")

    debug "BITWARDEN_ITEM_ID = ${BITWARDEN_ITEM_ID}"

    if [[ -n ${BITWARDEN_ITEM_ID} ]]; then
        processAttachments "${LASTPASS_ITEM_ID}" "${BITWARDEN_ITEM_ID}"
    fi
    # fi
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

    loadItemHash
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
