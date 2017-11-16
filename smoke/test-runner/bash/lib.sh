#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

get_env() {
    local name="$1"
    local default="$2"
    local value="${!name}"
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

throw_if_empty() {
    local name="$1"
    local value="$2"
    if [ -z "$value" ]; then
        echo "Parameter '$name' cannot be empty." 1>&2
        print_usage
        exit -1
    fi
}

check_tool() {
    local tool_name="$1"
    local test_command="$2"
    ${test_command} >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        log_error "\"${tool_name}\" not found. Please install \"${tool_name}\" before running this script."
        return 1
    fi
}

retry_until_successful() {
    local counter=0
    "$@"
    while [ $? -ne 0 ]; do
        if [[ "$counter" -gt 20 ]]; then
            exit 1
        else
            let counter++
        fi
        sleep 5
        "$@"
    done
}

log_with_color() {
    local color="$1"
    local no_color='\033[0m'
    local info="$2"
    echo -e "${color}${info}${no_color}"
}

log_info() {
    local info="$1"
    local green_color='\033[0;32m'
    log_with_color "${green_color}" "${info}"
}

log_warning() {
    local info="$1"
    local yellow_color='\033[0;33m'
    log_with_color "${yellow_color}" "[Warning] ${info}"
}

log_error() {
    local info="$1"
    local red_color='\033[0;31m'
    log_with_color "${red_color}" "[Error] ${info}"
}

print_banner() {
    local info="$1"
    log_info ''
    log_info '********************************************************************************'
    log_info "* ${info}"
    log_info '********************************************************************************'
}