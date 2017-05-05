#!/bin/bash

function print_usage() {
  cat <<EOF
Command
  $0
Arguments
  --scenario_name|-sn     [Required]: Scenario name
  --template_name|-tn     [Required]: Quickstart template name
  --app_id|-ai            [Required]: Service principal app id
  --app_key|-ak           [Required]: Service principal app key
  --tenant_id|-ti                   : Tenant id, defaulted to the Microsoft tenant id
  --user_name|-un                   : User name
  --region|-r                       : Region
  --keep_alive_hours|-kah           : The max number of hours to keep this deployment, defaulted to 48
  --template_location|-tl           : The Quickstart template location
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

function try_replace_parameter() {
  local data="$1"
  local name="$2"
  local value="$3"
  echo "$data" | python -c "
import json, sys;
data=json.load(sys.stdin);
try:
  data['parameters']['$name']['value'] = '$value'
except:
  pass
print json.dumps(data)"
}

tenant_id="72f988bf-86f1-41af-91ab-2d7cd011db47"
user_name="testuser"
region="eastus"
keep_alive_hours="48"
template_location="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/"

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --scenario_name|-sn)
      scenario_name="$1"
      shift
      ;;
    --template_name|-tn)
      template_name="$1"
      shift
      ;;
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
    --template_location|-tl)
      template_location="$1"
      shift
      ;;
    *)
      >&2 echo "ERROR: Unknown argument '$key' to script '$0'"
      exit -1
  esac
done

throw_if_empty --scenario_name $scenario_name
throw_if_empty --template_name $template_name
throw_if_empty --app_id $app_id
throw_if_empty --app_key $app_key
throw_if_empty --tenant_id $tenant_id
throw_if_empty --user_name $user_name
throw_if_empty --region $region
throw_if_empty --keep_alive_hours $keep_alive_hours
throw_if_empty --template_location $template_location

# Create ssh key
mkdir $scenario_name
temp_key_path=$scenario_name/temp_key
>&2 ssh-keygen -t rsa -N "" -f $temp_key_path -V "+1d"
temp_pub_key=$(cat ${temp_key_path}.pub)

if [[ "$template_name" == *"spinnaker"* && "$template_name" == *"jenkins"* ]]; then
  vm_prefix="devops"
elif [[ "$template_name" == *"spinnaker"* ]]; then
  vm_prefix="spinnaker"
elif [[ "$template_name" == *"jenkins"* ]]; then
  vm_prefix="jenkins"
else
  >&2 echo "ERROR: Unrecognized template '$template_name'."
  exit -1
fi

parameters=$(curl -s ${template_location}${template_name}/azuredeploy.parameters.json)
parameters=$(try_replace_parameter "$parameters" "servicePrincipalAppId" "$app_id")
parameters=$(try_replace_parameter "$parameters" "servicePrincipalAppKey" "$app_key")
parameters=$(try_replace_parameter "$parameters" "adminUsername" "$user_name")
parameters=$(try_replace_parameter "$parameters" "sshPublicKey" "$temp_pub_key")
parameters=$(try_replace_parameter "$parameters" "adminPassword" "$(uuidgen -r)")
parameters=$(try_replace_parameter "$parameters" "${vm_prefix}DnsPrefix" "$scenario_name")

>&2 az login --service-principal -u $app_id -p $app_key --tenant $tenant_id
>&2 echo "Creating resource group '$scenario_name'..."
>&2 az group create -n $scenario_name -l $region --tags "CleanTime=$(date -d "+${keep_alive_hours} hours" +%s)"
>&2 echo "Deploying template '$template_name'..."
deployment_data=$(az group deployment create -g $scenario_name --template-uri ${template_location}${template_name}/azuredeploy.json --parameters "$parameters")
>&2 echo "$deployment_data"

provisioning_state=$(echo "$deployment_data" | python -c "import json, sys; data=json.load(sys.stdin);print data['properties']['provisioningState']")
if [ "$provisioning_state" != "Succeeded" ]; then
    >&2 echo "Deployment failed."
    exit -1
fi

# Download kubernetes config if applicable
if [[ "$template_name" == *"k8s"* ]]; then
  >&2 echo "Copying Kubernetes credentials to the agent..."
  >&2 az acs kubernetes get-credentials --resource-group=$scenario_name --name=containerservice-$scenario_name --ssh-key-file=$temp_key_path

  if [ ! -s "~/.kube/config" ]; then
    >&2 echo "Failed to copy kubeconfig for kubernetes cluster."
    exit -1
  fi
fi

# Setup an ssh key on the VMs if the template didn't do it by default
# (it's more secure than programatically ssh-ing with a password and let's us ssh in a consistent manner)
if [[ "$parameters" != *"sshPublicKey"* ]]; then
  >&2 echo 'Setting up ssh key access for vm...'
  >&2 az vm user reset-ssh -n "${vm_prefix}VM" -g "$scenario_name" # The azure-jenkins template fails to setup the key for some reason unless we do this first
  >&2 az vm user update -u "$user_name" --ssh-key-value "$temp_pub_key" -n "${vm_prefix}VM" -g "$scenario_name"
fi

ssh_command=$(echo "$deployment_data" | python -c "import json, sys;data=json.load(sys.stdin);print data['properties']['outputs']['ssh']['value']")
echo "$ssh_command -i $temp_key_path"