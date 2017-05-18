#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --app_id|-ai            [Required]: Service principal app id
  --app_key|-ak           [Required]: Service principal app key
  --tenant_id|-ti                   : Tenant id, defaulted to the Microsoft tenant id
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

tenant_id="72f988bf-86f1-41af-91ab-2d7cd011db47"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --app_id|-ai)
      app_id="$1"
      shift
      ;;
    --app_key|-ak)
      app_key="$1"
      shift
      ;;
    --tenant_id|-ti)
      tenant_id="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
done

throw_if_empty --app_id $app_id
throw_if_empty --app_key $app_key
throw_if_empty --tenant_id $tenant_id

az login --service-principal -u $app_id -p $app_key --tenant $tenant_id

resource_groups=($(az group list | python -c "
import json, sys;
resource_groups=[]
for group in json.load(sys.stdin):
  if group['tags']:
    if 'CleanTime' in group['tags']:
      if int('$(date +%s)') > int(group['tags']['CleanTime']): 
          resource_groups.append(group['name'])
print ' '.join(resource_groups)
"))

for name in "${resource_groups[@]}"
do
    echo "Deleting resource group '$name'."
    az group delete -n $name --yes
done