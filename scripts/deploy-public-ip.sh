#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --app_id|-ai               [Required]: Service principal app id
  --app_key|-ak              [Required]: Service principal app key
  --ip_name|-ip              [Required]: Public IP name
  --resource_group|-rg       [Required]: Resource group name
  --dns_prefix|-dp           [Required]: DNS perfix
  --tenant_id|-ti                   : Tenant id, defaulted to the Microsoft tenant id
  --region|-r                       : Region
  --keep_alive_hours|-kah           : The max number of hours to keep this deployment, defaulted to 48
EOF
}

function throw_if_empty() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    >&2 echo "Parameter '$name' cannot be empty."
    print_usage
    exit -1
  fi
}

tenant_id="72f988bf-86f1-41af-91ab-2d7cd011db47"
region="eastus"
keep_alive_hours="48"

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
    --ip_name|-ip)
      ip_name="$1"
      shift
      ;;
    --resource_group|-rg)
      resource_group="$1"
      shift
      ;;
    --dns_prefix|-dp)
      dns_prefix="$1"
      shift
      ;;
    --region|-r)
      region="$1"
      shift
      ;;
    --keep_alive_hours|-kah)
      keep_alive_hours="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      >&2 echo "ERROR: Unknown argument '$key' to script '$0'"
      exit -1
  esac
done

throw_if_empty --app_id $app_id
throw_if_empty --app_key $app_key
throw_if_empty --ip_name $ip_name
throw_if_empty --resource_group $resource_group
throw_if_empty --tenant_id $tenant_id
throw_if_empty --dns_prefix $dns_prefix
throw_if_empty --region $region
throw_if_empty --keep_alive_hours $keep_alive_hours

>&2 az login --service-principal -u $app_id -p $app_key --tenant $tenant_id
>&2 echo "Creating resource group '$resource_group'..."
>&2 az group create -n $resource_group -l $region --tags "CleanTime=$(date -d "+${keep_alive_hours} hours" +%s)"
>&2 echo "Creating public ip '$ip_name'..."
deployment_data=$(az network public-ip create -n $ip_name -g $resource_group -l $region --dns-name $dns_prefix)
>&2 echo "$deployment_data"

provisioning_state=$(echo "$deployment_data" | python -c "import json, sys; data=json.load(sys.stdin);print data['publicIp']['provisioningState']")
if [ "$provisioning_state" != "Succeeded" ]; then
    >&2 echo "Deployment failed."
    exit -1
fi