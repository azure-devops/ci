#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --app_id|-ai               [Required]: Service principal app id
  --app_key|-ak              [Required]: Service principal app key
  --account_name|-an         [Required]: Storage account name
  --resource_group|-rg       [Required]: Resource group name
  --tenant_id|-ti                   : Tenant id, defaulted to the Microsoft tenant id
  --region|-r                       : Region
  --storage_sku|-sk                 : Storage SKU
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
storage_sku="Standard_LRS"
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
    --account_name|-an)
      account_name="$1"
      shift
      ;;
    --resource_group|-rg)
      resource_group="$1"
      shift
      ;;
    --storage_sku|-sk)
      storage_sku="$1"
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
throw_if_empty --account_name $account_name
throw_if_empty --resource_group $resource_group
throw_if_empty --tenant_id $tenant_id
throw_if_empty --storage_sku $storage_sku
throw_if_empty --region $region
throw_if_empty --keep_alive_hours $keep_alive_hours

>&2 az login --service-principal -u $app_id -p $app_key --tenant $tenant_id
>&2 echo "Creating resource group '$resource_group'..."
>&2 az group create -n $resource_group -l $region --tags "CleanTime=$(date -d "+${keep_alive_hours} hours" +%s)"
>&2 echo "Creating storage account '$account_name'..."
deployment_data=$(az storage account create -n $account_name -g $resource_group -l $region --sku $storage_sku)
>&2 echo "$deployment_data"

provisioning_state=$(echo "$deployment_data" | python -c "import json, sys; data=json.load(sys.stdin);print data['provisioningState']")
if [ "$provisioning_state" != "Succeeded" ]; then
    >&2 echo "Deployment failed."
    exit -1
fi