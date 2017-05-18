#!/usr/bin/env bash

function print_usage() {
  cat <<EOF
Command
  $0 

Arguments
  --fork|-f     : Quickstart repo fork, defaulted to 'Azure'
  --branch|-b   : Quickstart repo branch, defaulted to 'master'
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

fork="Azure"
branch="master"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --fork|-f)
      fork="$1";;
    --branch|-b)
      branch="$1";;
    --help|-help|-h)
      print_usage
      exit 13;;
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
  shift
done

throw_if_empty fork $fork
throw_if_empty branch $branch

script=$(curl -sL https://aka.ms/DeployDevOps)

old="Azure/azure-quickstart-templates/master"
new="$fork/azure-quickstart-templates/$branch"
script=${script//$old/$new}

# Just validate rather than deploying
old='az group deployment create --name "$scenario_name"'
new='az group deployment validate'
script=${script//$old/$new}

old='--query "{outputs: properties.outputs}"'
new='--query error'
script=${script//$old/$new}

# Add a tag so that resource groups get deleted as soon as the next 'Clean Deployments' job runs
old='az group create'
new='az group create --tags "CleanTime=$(date +%s)"'
script=${script//$old/$new}

script_name="deploy-dev-ops.sh"
echo "$script" > "$script_name"
chmod +x "$script_name"