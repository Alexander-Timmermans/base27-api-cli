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
            quit
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

    echo "token and expiration saved to $expiration_file"
}

function check_token_validity {
    local current_time=$(date +%s)
    local expiration_time=$(jq -r '.expiration_time' "$expiration_file")

    if (( current_time > expiration_time )); then
        # token has expired, fetching a new one
        get_api_token
    fi
    # token is still valid
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
    echo "HTTP status: $http_status"
    echo "$1"
    exit 1
}

function do_endpoint {
    do_init
    local method="${1^^}"
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
        # POST and PUT should offer a request body, and possible Form-encoding
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

    if [[ -n "$@" ]]; then
        echo "${method} ${endpoint}, $@:"
    else
        echo "${method} ${endpoint}:"
    fi

    case $http_status in
        400)
            print_status_exit "Error: bad request"
            ;;
        401)
            print_status_exit "Error: invalid access"
            ;;
        403)
            print_status_exit "Error: forbidden"
            ;;
        404)
            print_status_exit "Error: not found"
            ;;
        405)
            print_status_exit "Error: method '$method' not allowed on '$2'"
            ;;
        500)
            print_status_exit "Error: internal server error, contact your system administrator"
            ;;
        200)
            if echo "$response" | grep -q 'VAADI'; then
                echo "Not a valid API response"
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
                        #echo "$body_content" | jq '.' || echo "$body_content"
                        echo "$body_content" | jq -r ".[].$filter"
                    fi
                else
                    echo "$body_content" | jq '.' || echo "$body_content"
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
    local width1="42"
    local width2="30"
    printf "  %-${width1}s %-${width2}s %s\n" "$1" "$2" "$3"
}

print_sub() {
    local width1="14"
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
                echo ""
            else
                flag_form_encoding=true
            fi
            ;&
        -g | --get | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-g | --get" "<endpoint>" "[key=value ...]")" "GET an endpoint" "JSON"
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
                print_format "$(print_sub "-d | --delete" "<endpoint>" "[key=value ...]")" "DELETE to an endpoint" "JSON"
                echo ""
            else
                shift
                do_http "DELETE" "$@"
            fi
            ;&
        -e | --entity | "")
            if [[ -z "$f1" ]]; then
                print_format "$(print_sub "-e | --entity" "'<name>'")" "List contents of entity name" "JSON"
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
                print_format "$(print_sub "-s | --service" "'<name>'")" "List contents of service name" "JSON"
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
                print_format "$(print_sub "-f | --file" "'<id>'")" "List contents of file id" "JSON"
                echo ""
            else
                if [[ -z "$2" ]]; then
                    echo "Error, --file requires an additional argument"
                    exit 1
                fi
                do_endpoint "GET" "files/${2}"
                exit
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
            else
                do_endpoint "GET" "services" "name"
                exit
            fi
            ;&
        --list-userinfo | "")
            if [[ -z "$f1" ]]; then
                print_format "--list-userinfo" "List userinfo" "text"
                echo ""
            else
                do_endpoint "GET" "userInfo"            
                exit
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
