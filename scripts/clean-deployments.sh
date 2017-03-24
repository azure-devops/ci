#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --client_id|-ci         [Required]: Service principal client id
  --client_secret|-cs     [Required]: Service principal client secret
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
    --client_id|-ci)
      client_id="$1"
      shift
      ;;
    --client_secret|-cs)
      client_secret="$1"
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

throw_if_empty --client_id $client_id
throw_if_empty --client_secret $client_secret
throw_if_empty --tenant_id $tenant_id

az login --service-principal -u $client_id -p $client_secret --tenant $tenant_id

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
 
az logout