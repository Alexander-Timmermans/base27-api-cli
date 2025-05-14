#!/bin/bash

# Base27 API (CUBA Platform / Jmix naming convention)
# third party CLI tool, based on the online documentation:
# https://community.base27.eu/doc/rest/


api_name="base27_api"
api_base="rest/v2"

expiration_file="./.${api_name}_token.json"
config_file="./${api_name}_conf.env"

readonly REQUIREMENTS=(\
    awk \
    bash \
    cat \
    chmod \
    file \
    grep \
    jq \
    printf \
    sed \
)

function requires() {
    for i in "$@"; do
        if ! hash "$i" &>/dev/null; then
            echo "Error: this program requires '$i', please install it"
            exit 1
        fi
    done
}

function generate_config_file {
    if [[ ! -f "$config_file" ]]; then
        cat <<EOF > "$config_file"
base_url="https://"
username=""
password=""
client_id=""
client_secret=""
EOF
        chmod 600 "$config_file"
        echo "config file created at $config_file. Please fill in your credentials."
        exit
    fi
}

function do_config {
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        echo "Missing config file: $config_file"
        generate_config_file
        exit 1
    fi

    local missing_vars=()
    if [[ -z "$base_url" || "$base_url" == "https://" ]]; then
        echo "base_url is not set correctly. Please update $config_file"
        exit 1
    fi
    [[ -z "$username" ]] && missing_vars+=("username")
    [[ -z "$password" ]] && missing_vars+=("password")
    [[ -z "$client_id" ]] && missing_vars+=("client_id")
    [[ -z "$client_secret" ]] && missing_vars+=("client_secret")

    if [[ ${#missing_vars[@]} -ne 0 ]]; then
        echo "Missing required variables: ${missing_vars[*]}"
        echo "Please fill in $config_file"
        exit 1
    fi
    if [[ $1 == "validate" ]]; then
        echo "$config_file is valid"
    fi
}

function get_api_token {
    local basic_auth=$(echo -n "$client_id:$client_secret" | base64)

    local response=$(curl --silent --location "${base_url}/${api_base}/oauth/token" \
        --header "Content-Type: application/x-www-form-urlencoded" \
        --header "Authorization: Basic $basic_auth" \
        --data-urlencode 'grant_type=password' \
        --data-urlencode "username=$username" \
        --data-urlencode "password=$password")

    local timestamp=$(date +%s)
    local expires_in=$(echo "$response" | jq -r '.expires_in')
    local expiration_time=$((timestamp + expires_in))

    echo "$response" | jq --argjson timestamp "$timestamp" --argjson expiration_time "$expiration_time" \
        '. + {timestamp: $timestamp, expiration_time: $expiration_time}' > "$expiration_file"
}

function check_token_validity {
    local current_time=$(date +%s)
    local expiration_time=$(jq -r '.expiration_time' "$expiration_file")

    if (( current_time > expiration_time )); then
        # token has expired, fetching a new one
        get_api_token
    fi
    # "token is still valid.."
}

function get_access_token {
    local access_token=$(jq -r '.access_token' "$expiration_file")
    echo "$access_token"
}

function do_init {
    requires "${REQUIREMENTS[@]}"
    do_config
    flag_form_encoding=false
    if [ ! -f "$expiration_file" ]; then
        # no token file found, fetching new token
        get_api_token
    else
        check_token_validity
    fi

    access_token=$(get_access_token)
}

function print_status_exit {
    if [[ -n "$2" ]]; then
        echo "${method} ${endpoint}, $2"
    else
        echo "${method} ${endpoint}"
    fi

    echo "HTTP status: $http_status"
    echo "$1"
    exit 1
}

function do_endpoint {
    do_init

    local method
    local method_full
    method_full="$1"
    case "$1" in
        GET_MANDATORY)
            method="GET"
            ;;
        GET_WRITEABLE)
            method="GET"
            ;;
        GET_FULL)
            method="GET"
            ;;
        *)
            method="${1^^}"
            method_full=""
            ;;
    esac

    local endpoint="$2"
    shift 2

    local url="${base_url}/${api_base}/${endpoint}"

    local flag_filter_query=false
    local filter=""

    local headers=(-H "Authorization: Bearer $access_token")
    local data_option=()

    if [[ $# -gt 0 ]]; then
        filter="$(IFS='&'; echo "$*")"
    fi
        
    if [[ "$filter" == *"="* ]]; then
        flag_filter_query=true
    fi

    # all HTTP request types:
    # OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, CONNECT, PATCH
    # Base27 only supports GET, POST, PUT, DELETE

    # GET and DELETE don’t require a request body
    if [[ "$method" == "GET" || "$method" == "DELETE" ]]; then
        if $flag_filter_query; then
            if $flag_form_encoding; then
                curl_method_args=(-G)
                for pair in "$@"; do
                    data_option+=(--data-urlencode "$pair")
                done
            else
                if [[ -n "$filter" ]]; then
                    url="${url}?${filter}"
                fi
            fi
        # else: nothing to do
        fi
    else
        # POST, PUT (PATCH) should offer a request body, and possible form-encoding
        if [[ "$method" == "POST" || "$method" == "PUT" ]]; then
            if $flag_form_encoding; then
                headers+=(-H "Content-Type: application/x-www-form-urlencoded")

                if $flag_filter_query; then
                    IFS=' ' read -r -a pairs <<< "$filter"
                    for pair in "${pairs[@]}"; do
                        data_option+=(--data-urlencode "$pair")
                    done
                else
                    data_option+=(--data-urlencode "$filter")
                fi
            else
                headers+=(-H "Content-Type: application/json")

                if $flag_filter_query; then
                    IFS=' ' read -r -a pairs <<< "$filter"
                    local json_payload="{"
                    for pair in "${pairs[@]}"; do
                        key="${pair%%=*}"
                        val="${pair#*=}"
                        json_payload+="\"$key\":\"$val\","
                    done
                    json_payload="${json_payload%,}}"  # Remove trailing comma + close
                    data_option=(--data-raw "$json_payload")
                else
                    data_option=(--data-raw '{}')  
                fi
            fi
        else
            echo "Error: do_endpoint needs a valid method (get, put, post or delete)"
            exit 1
        fi
    fi

    local curl_method_args=()

    # GET doesn't need -X
    case "$method" in
        DELETE) curl_method_args=(-X DELETE) ;;
        POST)   curl_method_args=(-X POST) ;;
        PUT)    curl_method_args=(-X PUT) ;;
    esac

    local response=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" --location "$url" \
        "${headers[@]}" "${data_option[@]}" "${curl_method_args[@]}")

    #http_status=$(echo "$response" | sed -e 's/.*HTTPSTATUS://')
    # rewrite without sed
    http_status="${response##*HTTPSTATUS:}"

    #body_content=$(echo "$response" | sed -e 's/HTTPSTATUS:.*//')
    # rewrite without sed
    body_content="${response%HTTPSTATUS:*}"

    case $http_status in
        400)
            print_status_exit "Error: bad request" "$@"
            ;;
        401)
            print_status_exit "Error: invalid access" "$@"
            ;;
        403)
            print_status_exit "Error: forbidden" "$@"
            ;;
        404)
            print_status_exit "Error: not found" "$@"
            ;;
        405)
            print_status_exit "Error: method '$method' not allowed on '$2'" "$@"
            ;;
        500)
            print_status_exit "Error: internal server error, contact your system administrator" "$@"
            ;;
        200)
            if echo "$response" | grep -q 'VAADI'; then
                echo "Not a valid API response"
            else
                if [[ "$endpoint" == "metadata/entities" && "$method_full" == "GET_MANDATORY" ]]; then
                    # Mandatory + not ReadOnly → Must be in POST request.
                    # 1. Must include fields that are:
                    #    - mandatory == true
                    #    - readOnly == false

                    # Not mandatory + not ReadOnly → Optional in POST.
                    # 2. Should include optional, non-readOnly fields, but ideally prefilled ("" or null) or commented in output as optional.

                    # ReadOnly → Do not send. These are likely system-managed (id, version, timestamps, etc.).
                    # 3. Exclude readOnly fields — they are system-managed (e.g., id, version, timestamps, audit fields).

                    # Associations or Compositions → You might need to provide a related entity or a reference (like an id or nested object).
                    # 4. Handle associations/compositions:
                    #    - If it's a reference (MANY_TO_ONE, ONE_TO_MANY), it often expects an object with at least an id.
                    #    - Optional: provide examples or stubs for these.
                    
                    # No default value → Even optional fields may break functionality if left blank — these are the "functional musts" you discovered via the UI.
                    # 5. Fields without default values (and not mandatory) might still be required for business logic — but only detectable by POST testing or UI behavior.

                    echo "$body_content" | jq -n --argjson props "$(
                      ./base27_api.sh -g metadata/entities/'base$DataSubjectRequest' \
                      | jq '.properties // [] | map(select(.mandatory == true and .readOnly == false))'
                    )" '
                    reduce $props[] as $prop ({}; 
                      .[$prop.name] = 
                        if $prop.name == "version" then 1
                        elif $prop.type == "int" then 0
                        elif $prop.type == "boolean" then false
                        elif $prop.attributeType == "ASSOCIATION" or $prop.attributeType == "COMPOSITION" then { id: "" }
                        else "" 
                        end
                    )'
                elif [[ "$endpoint" == "metadata/entities" && "$method_full" == "GET_WRITEABLE" ]]; then
                    echo "$body_content" | jq -r '
                      .[] | select(.entityName == "'$2'") | 
                      {
                        (.entityName): (
                          reduce (.properties // [])[] as $prop ({}; 
                            # Step 1: Mandatory and not ReadOnly (always include in POST with default values)
                            if ($prop.mandatory == true and $prop.readOnly == false) then
                              .[$prop.name] = (
                                if $prop.name == "version" then 1
                                elif $prop.type == "int" then 0
                                elif $prop.type == "boolean" then false
                                elif $prop.type == "string" then ""
                                else null end
                              )
                            # Step 2: Not mandatory, not ReadOnly (optional, with default values or commented)
                            elif ($prop.mandatory == false and $prop.readOnly == false) then
                              .[$prop.name] = (
                                if $prop.name == "version" then 1
                                elif $prop.type == "int" then 0
                                elif $prop.type == "boolean" then false
                                elif $prop.type == "string" then ""
                                else null end
                              )
                            # Step 3: ReadOnly fields (do not include in POST)
                            else . end
                          )
                        )
                      }
                    '
                elif [[ "$endpoint" == "metadata/entities" && "$method_full" == "GET_FULL" ]]; then
                    echo "$body_content" | jq -r '
                      .[] | select(.entityName == "'$2'") |
                      {
                        (.entityName): (
                          reduce (.properties // [])[] as $prop ({};
                            if ($prop.readOnly != true) then
                              .[$prop.name] = (
                                if $prop.attributeType == "ASSOCIATION" then
                                  if $prop.cardinality == "MANY_TO_ONE" then { "id": "" }
                                  elif $prop.cardinality == "MANY_TO_MANY" or $prop.cardinality == "ONE_TO_MANY" then [ { "id": "" } ]
                                  else null end
                                elif $prop.name == "version" then 1
                                elif $prop.type == "int" then 0
                                elif $prop.type == "boolean" then false
                                elif $prop.type == "string" then ""
                                else null end
                              )
                            else . end
                          )
                        )
                      }
                    '
                else
                    if [[ -n $filter ]]; then
                        if $flag_filter_query; then
                            if [[ "$filter" == *"&"* ]]; then
                                echo "$body_content" | jq '.' || echo "$body_content"
                            else
                                if [[ "$filter" == *"[]"* ]]; then
                                    echo "$body_content" | jq -r "$filter"
                                else
                                    echo "$body_content" | jq -r ".[].$filter"
                                fi
                            fi
                        else
                            if [[ "$filter" == *"$"* ]]; then
                                # this should always be about an entity
                                if [[ "$endpoint" == "metadata/entities" ]]; then
                                    echo "$body_content" | jq ".[] | select(.entityName == \"$filter\")"
                                else
                                    echo "$body_content" | jq ".[] | select(._entityName == \"$filter\")"
                                fi
                            else
                                echo "$body_content" | jq -r ".[].$filter"
                            fi
                        fi
                    else
                        echo "$body_content" | jq '.' || echo "$body_content"
                    fi
                fi
            fi
            ;;
        *)
            echo "response:$response"
            ;;
    esac
}

endpoints=(
    "Lists:"
    ""
    "GET    metadata/entities"
    "GET    metadata/enums"
    "GET    metadata/datatypes"
    "GET    messages/entities"
    "GET    messages/enums"
    "GET    services"
    "GET    userInfo"
    ""
    "Objects:"
    ""
    "GET    entities/{entityName}"
    "POST   entities/{entityName}"
    "GET    entities/{entityName}/{entityId}"
    "PUT    entities/{entityName}/{entityId}"
    "DELETE entities/{entityName}/{entityId}"
    "GET    entities/{entityName}/search"
    "POST   entities/{entityName}/search"
    ""
    "GET    services/{serviceName}"
    "GET    services/{serviceName}/{methodName}"
    "POST   services/{serviceName}/{methodName}"
    ""
    "POST   files"
    "GET    files/{id}"
    ""
    "GET    metadata/entities/{entityName}"
    "GET    metadata/entities/{entityName}/views"
    "GET    metadata/entities/{entityName}/views/{viewName}"
    "GET    metadata/enums/{enumName]"
    ""
    "GET    messages/entities/{entityName}"
    "GET    messages/enums/{enumName}"
)


print_format() {
    local width1="58"
    local width2="37"
    printf "  %-${width1}s %-${width2}s %s\n" "$1" "$2" "$3"
}

print_sub() {
    local width1="30"
    local width2="10"
    printf "%-${width1}s %-${width2}s %s\n" "$1" "$2" "$3"
}

function do_http {
    local method="$1"
    local endpoint="$2"
    shift 2  # shift past method and endpoint

    if [[ -z "$endpoint" ]]; then
        echo "Error: $method requires an endpoint."
        exit 1
    fi

    local query_params=()
    for arg in "$@"; do
        query_params+=("$arg")
    done

    do_endpoint "$method" "$endpoint" "${query_params[@]}"
    exit
}

function do_case {
    local f1=""
    if [[ "$1" != "--help" ]]; then
        f1="$1"
    fi
    case "$f1" in
        --help | "")
            if [[ $script_arg_count -lt 1 ]]; then
                echo "Base27 API CLI tool"
                echo "Usage: $0 [options]"
            fi
            print_format "Options:" "Description:" "Output-type:"
            ;&
        --validate-config | "")
            if [[ -z "$f1" ]]; then 
                print_format "-c" "Generate / validate config" ""
            else
                do_config "validate"
                exit
            fi
            ;&
        --use-form-encoding | "")
            if [[ -z "$f1" ]]; then 
                print_format "-u" "Use form encoding" ""
                echo 
            else
                flag_form_encoding=true
            fi
            ;&
        --list-endpoints | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-endpoints" "List all API endpoints" "text"
            else
                for ep in "${endpoints[@]}"; do
                    echo "  $ep"
                done
                exit
            fi
            ;&
        --list-metadata-entities | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-metadata-entities" "List all metadata/entities" "text"
            else
                do_endpoint "GET" "metadata/entities" "entityName"
                exit
            fi
            ;&
        --list-metadata-enums | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-metadata-enums" "List all metadata/enums" "text"
            else
                do_endpoint "GET" "metadata/enums" "name"
                exit
            fi
            ;&
        --list-metadata-datatypes | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-metadata-datatypes" "List all metadata/datatypes" "text"
            else
                do_endpoint "GET" "metadata/datatypes" "name"
                exit
            fi
            ;&
        --list-messages-entities | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-messages-entities" "List all messages/entities" "text"
            else
                do_endpoint "GET" "messages/entities" "keys[]"
                exit
            fi
            ;&
        --list-messages-enums | "")
            if [[ -z "$f1" ]]; then 
                print_format "--list-messages-enums" "List all messages/enums" "text"
            else
                do_endpoint "GET" "messages/enums"  "keys[]"
                exit
            fi
            ;&
        --list-services | "")
            if [[ -z "$f1" ]]; then
                print_format "--list-services" "List all services" "text"
                echo
            else
                do_endpoint "GET" "services" "name"
                exit
            fi
            ;&
        # does not work properly in Base27?
        #--list-userinfo | "")
        #    if [[ -z "$f1" ]]; then
        #        print_format "--list-userinfo" "List userinfo" "text"
        #        echo 
        #    else
        #        do_endpoint "GET" "userInfo"            
        #        exit
        #    fi
        #    ;&
        -me | --get-entity | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-me | --get-entity" "'<name>'")" "GET metadata of an entity" "JSON"
            else
                if [[ -z "$2" ]]; then
                    echo "Error, --entity requires an additional argument"
                    exit 1
                fi
                do_endpoint "GET" "metadata/entities/${2}"
                exit
            fi
            ;&
        -mn | --get-enum | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-mn | --get-enum" "'<name>'")" "GET metadata of an enum" "JSON"
                echo
            else
                if [[ -z "$2" ]]; then
                    echo "Error: requires a name"
                    exit 1
                fi
                do_endpoint "GET" "metadata/enums/${2}"
                exit
            fi
            ;&
        -jem | --json-entity-mandatory | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-jem | --json-entity-mandatory" "'<name>'")" "Generate a mandatory entity template" "JSON"
            else
                if [[ -z "$2" ]]; then
                    echo "Error: requires an <entity>"
                    exit 1
                fi
                do_endpoint "GET_MANDATORY" "metadata/entities" "entityName" "$2"
                exit
            fi
            ;&
        -jew | --json-entity-writeable | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-jew | --json-entity-writeable" "'<name>'")" "Generate a writable entity template" "JSON"
            else
                if [[ -z "$2" ]]; then
                    echo "Error: requires an <entity>"
                    exit 1
                fi
                do_endpoint "GET_WRITEABLE" "metadata/entities" "entityName" "$2"
                exit
            fi
            ;&
        -jef | --json-entity-full)
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-jef | --json-entity-full" "'<name>'")" "Generate a full entity template" "JSON"
                echo
            else
                if [[ -z "$2" ]]; then
                    echo "Error: requires an <entity>"
                    exit 1
                fi
                do_endpoint "GET_FULL" "metadata/entities" "entityName" "$2"
                exit
            fi
            ;&
        -e | --entity | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-e | --entity" "'<name>'")" "Inspect an entity name" "JSON"
            else
                if [[ -z "$2" ]]; then
                    echo "Error, --entity requires an additional argument"
                    exit 1
                fi
                do_endpoint "GET" "entities/${2}"
                exit
            fi
            ;&
        -s | --service | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-s | --service" "'<name>'")" "Inspect a service name" "JSON"
            else
                if [[ -z "$2" ]]; then
                    echo "Error: requires a name"
                    exit 1
                fi
                do_endpoint "GET" "services/${2}"
                exit
            fi
            ;&
        -f | --file | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-f | --file" "'<id>'")" "Inspect a file id" "JSON"
                echo 
            else
                if [[ -z "$2" ]]; then
                    echo "Error, --file requires an additional argument"
                    exit 1
                fi
                do_endpoint "GET" "files/${2}"
                exit
            fi
            ;&
        -g | --get | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-g | --get" "<endpoint>")" "GET an endpoint" "JSON"
            else
                shift  
                do_http "GET" "$@"
            fi
            ;&
        -p | --post | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-p | --post" "<endpoint>" "[key=value ...]")" "POST to an endpoint" "JSON"
            else
                shift
                do_http "POST" "$@"
            fi
            ;&
        -t | --put | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-t | --put" "<endpoint>" "[key=value ...]")" "PUT to an endpoint" "JSON"
            else
                shift
                do_http "PUT" "$@"
            fi
            ;&
        -d | --delete | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-d | --delete" "<endpoint>")" "DELETE to an endpoint" "JSON"
            else
                shift
                do_http "DELETE" "$@"
            fi
            ;;
        *)
            echo -e "Error: unknown option: $1\n"
            do_case
            ;&
    esac
}

script_arg_count=$#

while [[ "$1" == -* ]]; do
    case "$1" in
        -c)
            do_case --validate-config
            exit
            ;;
        -u)
            do_case --use-form-encoding
            shift
            ;;
        -h|--help)
            do_case --help
            exit
            ;;
        --) # end of options
            shift
            break
            ;;
        *)
            break # pass remaining args to do_case
            ;;
    esac
done

do_case "$@"
