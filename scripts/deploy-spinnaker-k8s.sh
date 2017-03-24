#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --scenario_name|-sn     [Required]: Scenario name
  --client_id|-ci         [Required]: Service principal client id
  --client_secret|-cs     [Required]: Service principal client secret
  --tenant_id|-ti                   : Tenant id, defaulted to the Microsoft tenant id
  --user_name|-un                   : User name
  --region|-r                       : Region
  --keep_alive_hours|-kah           : The max number of hours to keep this deployment, defaulted to 48
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
user_name="spinuser"
region="eastus"
keep_alive_hours="48"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --scenario_name|-sn)
      scenario_name="$1"
      shift
      ;;
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
    --user_name|-un)
      user_name="$1"
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
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
done

throw_if_empty --scenario_name $scenario_name
throw_if_empty --client_id $client_id
throw_if_empty --client_secret $client_secret
throw_if_empty --tenant_id $tenant_id
throw_if_empty --user_name $user_name
throw_if_empty --region $region
throw_if_empty --keep_alive_hours $keep_alive_hours

# Create ssh key
mkdir $scenario_name
temp_key_path=$scenario_name/temp_key
ssh-keygen -t rsa -N "" -f $temp_key_path -V "+1d"
temp_pub_key=$(cat ${temp_key_path}.pub)

parameters=$(cat <<EOF 
{
    "adminUsername": {
        "value": "$user_name"
    },
    "sshPublicKey": {
        "value": "$temp_pub_key"
    },
    "spinnakerDnsLabelPrefix": {
        "value": "$scenario_name"
    },
    "servicePrincipalClientId": {
        "value": "$client_id"
    },
    "servicePrincipalClientSecret": {
        "value": "$client_secret"
    }
}
EOF
)

az login --service-principal -u $client_id -p $client_secret --tenant $tenant_id
az group create -n $scenario_name -l $region --tags "CleanTime=$(date -d "+${keep_alive_hours} hours" +%s)"
deployment_data=$(az group deployment create -g $scenario_name --template-uri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/spinnaker-vm-to-kubernetes/azuredeploy.json --parameters "$parameters")

provisioningState=$(echo "$deployment_data" | python -c "import json, sys; data=json.load(sys.stdin);print data['properties']['provisioningState']")
if [ "$provisioningState" != "Succeeded" ]; then
    echo "Deployment failed." 1>&2
    exit -1
fi

az acs kubernetes get-credentials --resource-group=$scenario_name --name=containerservice-$scenario_name --ssh-key-file=$temp_key_path

fqdn=$(echo "$deployment_data" | python -c "import json, sys;data=json.load(sys.stdin);print data['properties']['outputs']['spinnakerFQDN']['value']")

# Setup ssh port forwarding
temp_ctl=$scenario_name/tunnel.ctl
cat <<EOF >"$scenario_name/ssh_config"
Host tunnel-start
  HostName $fqdn
  IdentityFile $temp_key_path
  ControlMaster yes
  ControlPath $temp_ctl
  RequestTTY no
  # Spinnaker/gate
  LocalForward 8084 127.0.0.1:8084
  User $user_name
  StrictHostKeyChecking no

Host tunnel-stop
  HostName $fqdn
  IdentityFile $temp_key_path
  ControlPath $temp_ctl
  RequestTTY no
EOF