#!/usr/bin/env bash

set -o nounset

# enable extended pattern matching features
shopt -s extglob

# remove once <https://github.com/bitwarden/clients/issues/6689> is resolved
NODE_OPTIONS="--no-deprecation"

usage() {
    cat << EOT 1>&2
Usage: load.sh [-dhlqz] [-a algo] [-e prog] [-k kdf] [-o org] [-p fn] [-x ext] dir

OPTIONS
=======
-a algo   use 'algo' for decryption; default: AES256
-d        output debug information
-e prog   use 'prog' for encryption; either 'openssl' or 'gnupg'; default: openssl
-h        show help
-k kdf    use 'kdf' for key derivation function; default: pbkdf2 (OpenSSL), N/A (GnuPG)
-l        keep language code as a field
-o org    use 'org' as the organization ID
-p fn     use 'fn' for passphrase file to decrypt
-q        do not display status information
-x ext    use 'ext' as extension for encrypted files; default: enc
-z        do not perform actions; dry run mode

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

init_globals() {
    declare -Ag GLOBALS=(
        [BE_QUIET]='false'                      # -q
        [DEBUG]='false'                         # -d
        [DECRYPT_DATA]='false'                  # -p
        [DECRYPTION_ALGO]=''                    # -a
        [DECRYPTION_KDF]=''                     # -k
        [DECRYPTION_PROG]=''                    # -e
        [DRY_RUN]='false'                       # -z
        [ENCRYPTED_EXTENSION]=''                # -x
        [INPUT_DIR]=''                          # dir
        [KEEP_LANGUAGE_CODE]='false'            # -l
        [ORGANIZATION_ID]=''                    # -o
        [PASSPHRASE_FILE]=''                    # -p
        [TEMP_DIR]=$(mktemp -d)
    )

    declare -Ag FOLDERS_HASH=()

    declare -Ag ITEMS_HASH=()

    declare -Ag TEMPLATES=()

    declare -gr BW_LASTPASS_ID_FIELD_NAME='lastpass_id'

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

process_options() {
    local flag
    local OPTARG    # set by getopts
    local OPTIND    # set by getopts

    [[ $# -eq 0 ]] && usage

    while getopts ":a:de:hk:lo:p:qx:z" flag; do
        case "${flag}" in
            a)
                GLOBALS[DECRYPTION_ALGO]=${OPTARG}

                debug "Decryption algorithm set to '${GLOBALS[DECRYPTION_ALGO]}'."
                ;;

            d)
                GLOBALS[DEBUG]='true'

                debug "Debug mode turned on."
                ;;

            e)
                GLOBALS[DECRYPTION_PROG]=${OPTARG}

                debug "Decryption program set to '${GLOBALS[DECRYPTION_PROG]}'."
                ;;

            k)
                GLOBALS[DECRYPTION_KDF]=${OPTARG}

                debug "Decryption key derivation function set to '${GLOBALS[DECRYPTION_KDF]}'."
                ;;

            l)
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

validate_inputs() {
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

set_defaults() {
    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        if [[ -z ${GLOBALS[DECRYPTION_PROG]} ]]; then
            GLOBALS[DECRYPTION_PROG]='openssl'

            debug "Decryption program set to default of '${GLOBALS[DECRYPTION_PROG]}'."
        fi

        if [[ -z ${GLOBALS[DECRYPTION_ALGO]} ]]; then
            if [[ ${GLOBALS[DECRYPTION_PROG]} == 'openssl' ]]; then
                GLOBALS[DECRYPTION_ALGO]='aes-256-cbc'
            else
                GLOBALS[DECRYPTION_ALGO]='AES256'
            fi

            debug "Decryption algorithm set to default of '${GLOBALS[DECRYPTION_ALGO]}'."
        fi

        if [[ -z ${GLOBALS[DECRYPTION_KDF]} ]]; then
            if [[ ${GLOBALS[DECRYPTION_PROG]} == 'openssl' ]]; then
                GLOBALS[DECRYPTION_KDF]='pbkdf2'
            else
                GLOBALS[DECRYPTION_KDF]=''
            fi

            debug "Decryption key derivation function set to default of '${GLOBALS[DECRYPTION_KDF]}'."
        fi

        if [[ -z ${GLOBALS[ENCRYPTED_EXTENSION]} ]]; then
            GLOBALS[ENCRYPTED_EXTENSION]='enc'

            debug "Encrypted extension set to default of '${GLOBALS[ENCRYPTED_EXTENSION]}'."
        fi
    fi
}

check_for_dependency() {
    debug "Checking for dependency '$1'."

    if ! command -v "$1" &> /dev/null; then
        printf 'Dependency %s is missing.' "$1" > /dev/stderr

        exit
    fi
}

dependency_check() {
    local dependency

    local -a dependencies=(
        'base64'
        'bw'
        'cat'
        'cut'
        'echo'
        'find'
        'gdate'
        'grep'
        'gstat'
        'jq'
        'realpath'
        'sed'
        'tr'
        'xargs'
    )

    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        if [[ ${GLOBALS[DECRYPTION_PROG]} == 'openssl' ]]; then
            dependencies+=( 'openssl' )
        else
            dependencies+=( 'gpg' )
        fi
    fi

    for dependency in "${dependencies[@]}"; do
        check_for_dependency "${dependency}"
    done
}

decrypt_data() {
    if [[ ${GLOBALS[DECRYPT_DATA]} == 'true' ]]; then
        if [[ ${GLOBALS[DECRYPTION_PROG]} == 'openssl' ]]; then
            openssl enc -d \
              -"${GLOBALS[DECRYPTION_ALGO]}" \
              -"${GLOBALS[DECRYPTION_KDF]}" \
              -pass file:"${GLOBALS[PASSPHRASE_FILE]}" \
              -in "$1"
        else
            gpg --quiet --batch --decrypt \
              --passphrase-file "${GLOBALS[PASSPHRASE_FILE]}" \
              --cipher-algo "${GLOBALS[DECRYPTION_ALGO]}" \
              "$1"
        fi
    else
        cat "$1"
    fi
}

get_lastpass_item_property() {
    local -Ar LASTPASS_FIELD_NAMES=(
        [ID]='id'
        [GROUP]='group'
        [NAME]='name'
        [NOTES]='note'
        [PASSWORD]='password'
        [URL]='url'
        [USERNAME]='username'
    )

    printf '%s' "$1" | jq --raw-output ".${LASTPASS_FIELD_NAMES[$2]}" | trim
}

load_templates() {
    debug "Loading templates."

    TEMPLATES[CARD]=$(bw get template item.card)
    TEMPLATES[FIELD]=$(bw get template item.field)
    TEMPLATES[FOLDER]=$(bw get template folder)
    TEMPLATES[IDENTITY]=$(bw get template item.identity)
    TEMPLATES[ITEM]=$(bw get template item)
    TEMPLATES[LOGIN]=$(bw get template item.login | jq '.fido2Credentials = null' | jq '.totp = null')
    TEMPLATES[NOTE]=$(bw get template item.secureNote)
    TEMPLATES[URI]=$(bw get template item.login.uri)
}

load_folder_hash() {
    local folder_json
    local folder_id
    local folder_name

    while read -r folder_json; do
        folder_id=$(get_lastpass_item_property "${folder_json}" 'ID')
        folder_name=$(get_lastpass_item_property "${folder_json}" 'NAME')

        # if folder does not exist in hash, add it
        if [[ -z ${FOLDERS_HASH[${folder_name}]+_} ]]; then
            debug "Adding folder '${folder_name}' (ID: '${folder_id}') to hash."

            FOLDERS_HASH[${folder_name}]=${folder_id}
        else
            debug "Found a duplicate folder '${folder_name}' (ID: '${folder_id}')."
        fi
    done < <(bw list folders | jq --compact-output '.[]')
}

load_item_hash() {
    local bitwarden_item_json
    local lastpass_item_id

    while read -r bitwarden_item_json; do
        # TODO: select first element in case an item has multiple fields with same name
        lastpass_item_id=$(printf '%s' "${bitwarden_item_json}" | \
          jq --raw-output \
          --arg field_name "${BW_LASTPASS_ID_FIELD_NAME}" \
          '.fields[] | select( .name == $field_name ) | .value')

        # if item does not exist in hash, add it
        if [[ -n ${lastpass_item_id} && -z ${ITEMS_HASH[${lastpass_item_id}]+_} ]]; then
            debug "Adding item '${lastpass_item_id}' to hash."

            ITEMS_HASH[${lastpass_item_id}]=${bitwarden_item_json}
        fi
    done < <(bw list items | \
      jq --compact-output \
      --arg field_name "${BW_LASTPASS_ID_FIELD_NAME}" \
      '.[] | select( .fields != null ) | select( .fields[].name == $field_name )')
}

create_folder() {
    local folder_name
    local folder_id

    folder_name=$1
    folder_id=$(printf '%s' "${TEMPLATES[FOLDER]}" | jq \
      --arg folder_name "${folder_name}" \
      '.name = $folder_name' \
      | bw encode | bw create folder | jq --raw-output '.id')

    debug "Created folder '${folder_name}' (ID: '${folder_id}')."

    FOLDERS_HASH[${folder_name}]=${folder_id}
}

check_folder() {
    local folder_name

    folder_name=$(get_lastpass_item_property "$1" 'GROUP')

    if [[ -n ${folder_name} ]]; then
        debug "Checking for folder named '${folder_name}'."

        # if folder name is specified and does not exist as a key, add it
        if [[ -z ${FOLDERS_HASH[${folder_name}]+_} ]]; then
            create_folder "${folder_name}"
        fi
    fi
}

get_lastpass_note_field_value() {
    printf '%s' "$1" | grep "^$2:" | cut -d : -f 2- | trim
}

get_lastpass_item_type() {
    local lastpass_item_json
    local item_url
    local lastpass_item_notes
    local lastpass_item_type

    lastpass_item_json=$1

    item_url=$(get_lastpass_item_property "${lastpass_item_json}" 'URL')

    if [[ ${item_url} == 'http://sn' ]]; then
        lastpass_item_notes=$(get_lastpass_item_property "${lastpass_item_json}" 'NOTES')

        lastpass_item_type=$(get_lastpass_note_field_value "${lastpass_item_notes}" 'NoteType')

        if [[ -z ${lastpass_item_type} ]]; then
            lastpass_item_type='Secure Note'
        fi

        echo "${lastpass_item_type}"
    else
        echo 'Password'
    fi
}

# Adapted from <https://stackoverflow.com/a/17841619/2647496>.
join_array() {
    local delim
    local array

    delim=${1-}
    array=${2-}

    if shift 2; then
        printf '%s' "${array}" "${@/#/${delim}}"
    fi
}

remove_lastpass_item_note_field() {
    printf '%s' "$1" | grep -v "^$2:"
}

process_file() {
    local item

    debug "Processing file named '$1'."

    while read -r item; do
        process_item "${item}"
    done < <(decrypt_data "$1" | jq --slurp --raw-input --compact-output 'fromjson? | .[]')
}

trim() {
    sed -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//'
}

filter_dummy_urls() {
    sed -E -e 's#https?://$##' \
      -e 's#xn--https?://-$##' | trim
}

bitwarden_edit_or_create() {
    local bitwarden_item_id

    bitwarden_item_id=${2:-0}

    if [[ ${GLOBALS[DRY_RUN]} == 'true' ]]; then
        if [[ $1 == 'edit' ]]; then
            printf '{ "id": "%s" }' "${bitwarden_item_id}"
        else
            cat
        fi
    else
        if [[ $1 == 'edit' ]]; then
            bw encode | bw edit item "${bitwarden_item_id}"
        else
            bw encode | bw create item
        fi
    fi
}

upsert_item() {
    local bitwarden_item_json
    local bitwarden_item_id
    local edit_or_create

    bitwarden_item_json=$1

    readonly bitwarden_item_json

    if [[ ${GLOBALS[DEBUG]} == 'true' ]]; then
        printf 'upsert_item:\n\tbitwarden_item_json = %s\n' "${bitwarden_item_json}" > /dev/stderr
    fi

    bitwarden_item_id=$(printf '%s' "${bitwarden_item_json}" | jq --raw-output '.id // ""')

    readonly bitwarden_item_id

    if [[ -n ${bitwarden_item_id} ]]; then
        edit_or_create='edit'
    else
        edit_or_create='create'
    fi

    readonly edit_or_create

    printf '%s' "${bitwarden_item_json}" | \
      bitwarden_edit_or_create "${edit_or_create}" "${bitwarden_item_id}" | \
      jq --raw-output '.id // ""'
}

get_attachment_temp_file_name() {
    local temp_file

    temp_file=${GLOBALS[TEMP_DIR]}/$(basename "${file_name}" | sed -e "s/\.${GLOBALS[ENCRYPTED_EXTENSION]}$//")

    printf '%s' "${temp_file}"
}

get_lastpass_attachment_size() {
    local file_name
    local temp_file

    file_name=$1

    readonly file_name

    temp_file=$(get_attachment_temp_file_name "${file_name}")

    decrypt_data "${file_name}" > "${temp_file}"

    gstat --printf="%s" "${temp_file}"

    rm -f "${temp_file}"
}

create_or_update_attachment() {
    local operation
    local file_name
    local bitwarden_item_id
    local bitwarden_attachment_id
    local temp_file

    operation=$1
    file_name=$2
    bitwarden_item_id=$3
    bitwarden_attachment_id=${4:-}

    readonly operation
    readonly file_name
    readonly bitwarden_item_id
    readonly bitwarden_attachment_id

    temp_file=$(get_attachment_temp_file_name "${file_name}")

    case "${operation}" in
        create)
            decrypt_data "${file_name}" > "${temp_file}"

            bw create attachment --file "${temp_file}" --itemid "${bitwarden_item_id}"

            rm -f "${temp_file}"
            ;;

        update)
            decrypt_data "${file_name}" > "${temp_file}"

            bw delete attachment "${bitwarden_attachment_id}"

            bw create attachment --file "${temp_file}" --itemid "${bitwarden_item_id}"

            rm -f "${temp_file}"
            ;;

        *)
            echo "Invalid operation: ${operation}" > /dev/stderr
            ;;
    esac
}

process_attachments() {
    local lastpass_item_id

    lastpass_item_id=$1

    readonly lastpass_item_id

    if [[ -d ${GLOBALS[INPUT_DIR]}/${lastpass_item_id} ]]; then
        local bitwarden_item_id
        local bitwarden_item_json
        local lastpass_attachments_list
        local -i num_lastpass_attachments
        local lastpass_attachment_file
        local bitwarden_attachment_json

        bitwarden_item_id=$2
        bitwarden_item_json=$3

        readonly bitwarden_item_id
        readonly bitwarden_item_json

        debug "Processing attachments for '${lastpass_item_id}' (Bitwarden Item ID: ${bitwarden_item_id})."

        # build array of attachment file names in item directory
        mapfile -d '' lastpass_attachments_list < <(find "${GLOBALS[INPUT_DIR]}/${lastpass_item_id}" -type f -depth 1 -print0 | xargs -0 realpath -z)

        num_lastpass_attachments=${#lastpass_attachments_list[@]}

        if [[ ${num_lastpass_attachments} -gt 0 ]]; then
            debug "Found ${num_lastpass_attachments} attachments for '${lastpass_item_id}'."

            for lastpass_attachment_file in "${lastpass_attachments_list[@]}"; do
                debug "Processing attachment '${lastpass_attachment_file}'."

                bitwarden_attachment_json=$(printf '%s' "${bitwarden_item_json}" | \
                  jq --raw-output \
                  --arg attachment_name "${lastpass_attachment_file}" \
                  '.attachments[]? | select( .fileName == $attachment_name )')

                if [[ -n ${bitwarden_attachment_json} ]]; then
                    local bitwarden_attachment_size
                    local lastpass_attachment_size

                    bitwarden_attachment_size=$(printf '%s' "${bitwarden_attachment_json}" | \
                      jq --raw-output \
                      '.size')

                    lastpass_attachment_size=$(get_lastpass_attachment_size "${lastpass_attachment_file}")

                    if [[ "${bitwarden_attachment_size}" != "${lastpass_attachment_size}" ]]; then
                        local bitwarden_attachment_id

                        bitwarden_attachment_id=$(printf '%s' "${bitwarden_attachment_json}" | \
                          jq --raw-output \
                          '.id')

                        create_or_update_attachment 'update' "${lastpass_attachment_file}" "${bitwarden_item_id}" "${bitwarden_attachment_id}"
                    fi
                else
                    create_or_update_attachment 'create' "${lastpass_attachment_file}" "${bitwarden_item_id}"
                fi
            done
        fi
    fi
}

get_bitwarden_item_json() {
    if [[ -n ${ITEMS_HASH[$1]+_} ]]; then
        printf '%s' "${ITEMS_HASH[$1]}"
    else
        printf '%s' "${TEMPLATES[ITEM]}"
    fi
}

add_field() {
    local -n jq_filters_ref

    local bitwarden_item_json
    local custom_field_name
    local custom_field_value
    local custom_field_type

    local -i num_fields
    local custom_field

    jq_filters_ref=$1
    bitwarden_item_json=$2
    custom_field_name=$3
    custom_field_value=$4
    custom_field_type=${5:-0}       # default to zero

    num_fields=$(printf '%s' "${bitwarden_item_json}" | \
      jq --raw-output \
      --arg field_name "${custom_field_name}" \
      --arg field_value "${custom_field_value}" \
      '.fields[] | select( .name == $field_name and .value == $field_value ) | length')

    # add field if it does not already exist
    if [[ ${num_fields} -eq 0 ]]; then
        custom_field=$(printf '%s' "${TEMPLATES[FIELD]}" |
          jq \
          --arg field_name "${custom_field_name}" \
          --arg field_value "${custom_field_value}" \
          --arg field_type "${custom_field_type}" \
          '.name = $field_name | .value = $field_value | .type = ( $field_type | tonumber )')

        jq_filters_ref+=(".fields += [${custom_field}]")
    fi
}

process_lastpass_note_fields() {
    local -n lastpass_item_notes_ref
    local -n note_field_values_ref
    local field_name

    lastpass_item_notes_ref=$1
    note_field_values_ref=$2

    for field_name in "${NOTE_FIELDS[@]}"; do
        # TODO: Handle mutliple values with same field name.

        # shellcheck disable=SC2004
        note_field_values_ref[${field_name}]=$(get_lastpass_note_field_value "${lastpass_item_notes_ref}" "${field_name}")

        lastpass_item_notes_ref=$(remove_lastpass_item_note_field "${lastpass_item_notes_ref}" "${field_name}")

        if [[ -z ${note_field_values_ref[${field_name}]} ]]; then
             unset "note_field_values_ref[${field_name}]"
        fi
    done

    unset "note_field_values_ref[NoteType]"

    if [[ ${GLOBALS[KEEP_LANGUAGE_CODE]} != 'true' ]]; then
        unset "note_field_values_ref[Language]"
    fi
}

process_item() {
    local lastpass_item_json
    local lastpass_item_id
    local lastpass_item_type
    local lastpass_item_notes
    local field
    local sub_filters_string
    local jq_filters_string
    local item_type_code
    local item_folder_name
    local item_url
    local item_username
    local item_password
    local uris
    local login
    local expiration_date
    local expiration_month_name
    local bitwarden_item_json
    local bitwarden_item_id

    local -A note_field_values=()
    local -a sub_filters=()
    local -a jq_filters=()

    lastpass_item_json=$1

    debug "lastpass_item_json = ${lastpass_item_json}"

    # make sure folder exists in Bitwarden vault
    check_folder "${lastpass_item_json}"

    lastpass_item_id=$(get_lastpass_item_property "${lastpass_item_json}" 'ID')

    lastpass_item_type=$(get_lastpass_item_type "${lastpass_item_json}")

    debug "Processing item (ID: '${lastpass_item_id}') of type '${lastpass_item_type}'."

    lastpass_item_notes=$(get_lastpass_item_property "${lastpass_item_json}" 'NOTES')

    if [[ -n ${lastpass_item_notes} ]]; then
        # store each note field value referenced in array into a hash
        process_lastpass_note_fields lastpass_item_notes note_field_values

        if [[ ${GLOBALS[DEBUG]} == 'true' ]]; then
            printf 'After calling process_lastpass_note_fields (%s):\n' "${#note_field_values[@]}" > /dev/stderr

            for field in "${!note_field_values[@]}"; do
                printf '\t%s = %s\n' "${field}" "${note_field_values[${field}]}" > /dev/stderr
            done
        fi
    fi

    case "${lastpass_item_type}" in
        'Address')
            item_type_code=4    # Identity
            ;;

        "Driver's License")
            item_type_code=4    # Identity

            # NoteType:Driver's License\nNumber:\nExpiration Date:,,\nLicense Class:\nName:\nAddress:\nCity / Town:\nState:\nZIP / Postal Code:\nCountry:\nDate of Birth:\nSex:\nHeight:\nNotes:Server

            # .title = null
            # .
            ;;

        'Credit Card')
            item_type_code=3    # Card

            sub_filters=()

            local -A card_note_fields

            card_note_fields=([cardholderName]='Name on Card' [number]='Number' [code]='Security Code')

            for field in "${!card_note_fields[@]}"; do
                if [[ -n ${note_field_values[${card_note_fields[${field}]}]+_} ]]; then
                    sub_filters+=(".${field} = \"${note_field_values[${card_note_fields[${field}]}]//"/\\"}\"")

                    unset "note_field_values[${card_note_fields[${field}]}]"
                else
                    sub_filters+=(".${field} = null")
                fi
            done

            unset 'card_note_fields'

            if [[ -n ${note_field_values[Expiration Date]+_} ]]; then
                expiration_date=${note_field_values[Expiration Date]}
                expiration_month_name=$(printf '%s' "${expiration_date}" | cut -d , -f 1)

                sub_filters+=(".expMonth = \"$(gdate --date="1 ${expiration_month_name}" +'%m')\"")
                sub_filters+=(".expYear = \"$(printf '%s' "${expiration_date}" | cut -d , -f 2)\"")

                unset 'note_field_values[Expiration Date]'
            else
                sub_filters+=(".expMonth = null")
                sub_filters+=(".expYear = null")
            fi

            if [[ -n ${note_field_values[Type]+_} ]]; then
                sub_filters+=(".brand = \"$(printf '%s' "${note_field_values[Type]}" | tr '[:upper:]' '[:lower:]')\"")

                unset 'note_field_values[Type]'
            else
                sub_filters+=(".brand = null")
            fi

            sub_filters_string=$(join_array ' | ' "${sub_filters[@]}")

            jq_filters+=(".card = $(printf '%s' "${TEMPLATES[CARD]}" | \
              jq "${sub_filters_string}")")
            ;;

        'Email Account' | 'Password')
            item_type_code=1    # Login

            sub_filters=()

            item_username=$(get_lastpass_item_property "${lastpass_item_json}" 'USERNAME')
            item_password=$(get_lastpass_item_property "${lastpass_item_json}" 'PASSWORD')

            sub_filters+=(".username = \"${item_username//"/\\"}\"")
            sub_filters+=(".password = \"${item_password//"/\\"}\"")

            item_url=$(get_lastpass_item_property "${lastpass_item_json}" 'URL' | filter_dummy_urls)

            if [[ -n ${item_url} ]]; then
                uris=$(printf '%s' "${TEMPLATES[URI]}" | jq ".uri = \"${item_url}\"")

                sub_filters+=(".uris += [${uris}]")
            fi

            sub_filters_string=$(join_array ' | ' "${sub_filters[@]}")

            login=$(printf '%s' "${TEMPLATES[LOGIN]}" | \
              jq "${sub_filters_string}")

            jq_filters+=(".login = ${login}")
            ;;

        'Bank Account' | 'Insurance' | 'Membership' | 'Passport' | 'Social Security' | 'Health Insurance' | 'Secure Note')
            item_type_code=2    # Secure Note

            jq_filters+=(".secureNote = ${TEMPLATES[NOTE]}")
            ;;

        *)
            item_type_code=2    # Secure Note

            jq_filters+=(".secureNote = ${TEMPLATES[NOTE]}")

            debug "Unknown item type; treating as Secure Note."
            ;;
    esac

    item_folder_name=$(get_lastpass_item_property "${lastpass_item_json}" 'GROUP')

    if [[ -n ${item_folder_name} ]]; then
        # shellcheck disable=SC2016
        jq_filters+=('.folderId = $folder_id')
    fi

    jq_filters+=(".type = ${item_type_code}")

    item_name=$(get_lastpass_item_property "${lastpass_item_json}" 'NAME')

    # shellcheck disable=SC2016
    jq_filters+=('.name = $item_name')

    lastpass_item_notes=$(printf '%s' "${lastpass_item_notes}" | sed -e 's/^Notes://')

    if [[ -n ${lastpass_item_notes} ]]; then
        debug "lastpass_item_notes = ${lastpass_item_notes}"
    fi

    # shellcheck disable=SC2016
    jq_filters+=('.notes = $notes')

    bitwarden_item_json=$(get_bitwarden_item_json "${lastpass_item_id}")

    # add remaining notes fields
    for field in "${!note_field_values[@]}"; do
        add_field jq_filters "${bitwarden_item_json}" "${field}" "${note_field_values[${field}]}"
    done

    add_field jq_filters "${bitwarden_item_json}" "${BW_LASTPASS_ID_FIELD_NAME}" "${lastpass_item_id}"

    jq_filters_string=$(join_array ' | ' "${jq_filters[@]}")

    bitwarden_item_json=$(printf '%s' "${bitwarden_item_json}" | jq \
      --arg item_name "${item_name}" \
      --arg folder_id "${FOLDERS_HASH[${item_folder_name}]+null}" \
      --arg notes "${lastpass_item_notes}" \
       "${jq_filters_string}")

    debug "Upserting item (ID: '${lastpass_item_id}')."

    bitwarden_item_id=$(upsert_item "${bitwarden_item_json}")

    debug "bitwarden_item_id = ${bitwarden_item_id}"

    if [[ -n ${bitwarden_item_id} ]]; then
        process_attachments "${lastpass_item_id}" "${bitwarden_item_id}" "${bitwarden_item_json}"
    fi
}

show_progress() {
    if [[ ${GLOBALS[BE_QUIET]} != 'true' ]]; then
        debug "Processed $1 of $2."
    fi
}

process_lastpass_export() {
    local file_list
    local -i num_items
    local -i counter
    local file_name

    debug "Loading exported LastPass items into Bitwarden."

    # build array of file names in input directory
    mapfile -d '' file_list < <(find "${GLOBALS[INPUT_DIR]}" -type f -depth 1 -print0 | xargs -0 realpath -z)

    num_items=${#file_list[@]}

    if [[ ${num_items} -gt 0 ]]; then
        debug "Found ${num_items} items."

        counter=1

        for file_name in "${file_list[@]}"; do
            process_file "${file_name}"

            show_progress $(( counter++ )) "${num_items}"
        done
    else
        debug "No items found in '${GLOBALS[INPUT_DIR]}'."
    fi
}

main() {
    init_globals

    process_options "$@"

    validate_inputs

    set_defaults

    dependency_check

    load_templates

    load_folder_hash

    load_item_hash

    process_lastpass_export
}

main "$@"
