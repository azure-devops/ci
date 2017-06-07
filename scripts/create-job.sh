#!/bin/bash
function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --plugin_name|-p         [Required]: Plugin name
  --fork_name|-f           [Required]: Fork name
  --git_url|-g             [Required]: Git url
  --jenkins_url|-j         [Required]: Jenkins url
  --private_key|-i                   : SSH private key file (if omitted, the script will use this env variable: REMOTE_JENKINS_PEM)
  --job_description|-d               : Job description (by default it's 'Building <fork_name> for <plugin_name> plugin')
  --job_display_name|-n              : Job display name (by default it's '<fork_name>')
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
    --plugin_name|-p)
      plugin_name="$1"
      shift
      ;;
    --fork_name|-f)
      fork_name="$1"
      shift
      ;;
    --git_url|-g)
      git_url="$1"
      shift
      ;;
    --jenkins_url|-j)
      jenkins_url="$1"
      shift
      ;;
    --private_key|-i)
      REMOTE_JENKINS_PEM="$1"
      shift
      ;;
    --job_description|-d)
      job_description="$1"
      shift
      ;;
    --job_display_name|-n)
      job_display_name="$1"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument '$key'" 1>&2
      exit -1
  esac
done

throw_if_empty --plugin_name $plugin_name
throw_if_empty --fork_name $fork_name
throw_if_empty --git_url $git_url
throw_if_empty --jenkins_url $jenkins_url
throw_if_empty --private_key $REMOTE_JENKINS_PEM

job_name="${plugin_name}/${fork_name}"
if [ -z "$job_display_name" ]
then
    job_display_name="${fork_name}"
fi

if [ -z "$job_description" ]
then
    job_description="Building ${fork_name} for ${plugin_name} plugin"
fi

job_template=$(curl -s ${artifacts_location}/scripts/fork_template.xml)

job_xml=$(echo "${job_template}" | sed -e "s|{job-description}|${job_description}|" -e "s|{job-display-name}|${job_display_name}|" -e "s|{git-url}|${git_url}|")

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

echo "${job_xml}" | java -jar jenkins-cli.jar -remoting -s "${jenkins_url}" -i "${REMOTE_JENKINS_PEM}" create-job "${job_name}"

rm jenkins-cli.jar