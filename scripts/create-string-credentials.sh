#!/bin/bash
function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --credentials_id|-c          [Required]: Credentials ID
  --credentials_secret|-s      [Required]: Secret
  --jenkins_url|-j             [Required]: Jenkins url
  --private_key|-i                       : SSH private key file (if omitted, the script will use this env variable: REMOTE_JENKINS_PEM)
  --credentials_description|-d           : Description (by default it's '<credentials_id>')
EOF
}

function throw_if_empty() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "Parameter '$name' cannot be empty." 1>&2
    print_usage
    exit -1
  fi
}

# Set defaults
artifacts_location="https://raw.githubusercontent.com/azure-devops/ci/master"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --credentials_id|-c)
      credentials_id="$1"
      shift
      ;;
    --credentials_secret|-s)
      credentials_secret="$1"
      shift
      ;;
    --credentials_description|-d)
      credentials_description="$1"
      shift
      ;;
    --private_key|-i)
      REMOTE_JENKINS_PEM="$1"
      shift
      ;;
    --jenkins_url|-j)
      jenkins_url="$1"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument '$key'" 1>&2
      exit -1
  esac
done

throw_if_empty --credentials_id $credentials_id
throw_if_empty --credentials_secret $credentials_secret
throw_if_empty --jenkins_url $jenkins_url
throw_if_empty --private_key $REMOTE_JENKINS_PEM

if [ -z "$credentials_description" ]
then
    credentials_description="${credentials_id}"
fi

credentials_template=$(curl -s ${artifacts_location}/scripts/string_credentials_template.xml)

credentials_xml=$(echo "${credentials_template}" | sed -e "s|{credentials-id}|${credentials_id}|" -e "s|{credentials-description}|${credentials_description}|" -e "s|{credentials-secret}|${credentials_secret}|")

function retry_until_successful {
    counter=0
    ${@}
    while [ $? -ne 0 ]; do
        if [[ "$counter" -gt 20 ]]; then
            exit 1
        else
            let counter++
        fi
        sleep 5
        ${@}
    done;
}

retry_until_successful wget ${jenkins_url}/jnlpJars/jenkins-cli.jar -O jenkins-cli.jar

echo "${credentials_xml}" | java -jar jenkins-cli.jar -remoting -s "${jenkins_url}" -i "${REMOTE_JENKINS_PEM}" create-credentials-by-xml SystemCredentialsProvider::SystemContextResolver::jenkins "(global)"

rm jenkins-cli.jar