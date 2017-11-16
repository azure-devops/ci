#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "$SCRIPT_DIR"
SCRIPT_NAME="$(basename $0)"
source "$SCRIPT_DIR/lib.sh"

print_usage() {
    cat <<EOF
Command
    $0
Arguments
    --command|-c               [Required]: Jenkins cli command to run
    --command_input_file|-cif            : File path containing the input to the CLI command
    --jenkins_url|-j                     : Jenkins URL, defaulted to "http://localhost:8080/"
    --jenkins_username|-ju               : Jenkins user name, defaulted to "admin"
    --jenkins_password|-jp               : Jenkins password. If not specified and the user name is "admin", the initialAdminPassword will be used
EOF
}

#set defaults
jenkins_url=$(get_env JENKINS_URL "http://localhost:8080/")
jenkins_username=$(get_env JENKINS_USERNAME "admin")

while [[ $# > 0 ]]; do
    key="$1"
    shift
    case $key in
        --command|-c)
            command="$1"
            shift
        ;;
        --command_input_file|-cif)
            command_input_file="$1"
            shift
        ;;
        --jenkins_url|-j)
            jenkins_url="$1"
            shift
        ;;
        --jenkins_username|-ju)
            jenkins_username="$1"
            shift
        ;;
        --jenkins_password|-jp)
            jenkins_password="$1"
            shift
        ;;
        --help|-help|-h)
            print_usage
            exit 13
        ;;
        *)
            log_error "ERROR: Unknown argument '$key' to script '$0'"
            exit -1
    esac
done

throw_if_empty jenkins_username $jenkins_username
if [ "$jenkins_username" != "admin" ]; then
    throw_if_empty jenkins_password $jenkins_password
fi

if [ ! -e jenkins-cli.jar ]; then
    log_info "Downloading Jenkins CLI..."
    retry_until_successful wget "${jenkins_url}jnlpJars/jenkins-cli.jar" -O jenkins-cli.jar
fi

#if [ -z "$jenkins_password" ]; then
    # NOTE: Intentionally setting this after the first retry_until_successful to ensure the initialAdminPassword file exists
    #jenkins_password=`sudo cat /var/lib/jenkins/secrets/initialAdminPassword`
#fi

log_info "Running \"${command}\"..."
if [ -z "$command_input_file" ]; then
    #retry_until_successful java -jar jenkins-cli.jar -s "${jenkins_url}" -auth "${jenkins_username}":"${jenkins_password}" $command
    retry_until_successful java -jar jenkins-cli.jar -s "${jenkins_url}" $command
else
    #retry_until_successful cat "$command_input_file" | java -jar jenkins-cli.jar -s "${jenkins_url}" -auth "${jenkins_username}":"${jenkins_password}" $command
    retry_until_successful cat "$command_input_file" | java -jar jenkins-cli.jar -s "${jenkins_url}" $command
fi
