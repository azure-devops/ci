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
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
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

# Create ssh key
mkdir $scenario_name
temp_key_path=$scenario_name/temp_key
ssh-keygen -t rsa -N "" -f $temp_key_path -V "+1d"
temp_pub_key=$(cat ${temp_key_path}.pub)

if [[ "$template_name" == *"spinnaker"* && "$template_name" == *"jenkins"* ]]; then
  vm_prefix="devops"
elif [[ "$template_name" == *"spinnaker"* ]]; then
  vm_prefix="spinnaker"
elif [[ "$template_name" == *"jenkins"* ]]; then
  vm_prefix="jenkins"
else
  echo "ERROR: Unrecognized template '$template_name'." 1>&2
  exit -1
fi

parameters=$(curl -s ${template_location}${template_name}/azuredeploy.parameters.json)
parameters=$(try_replace_parameter "$parameters" "servicePrincipalAppId" "$app_id")
parameters=$(try_replace_parameter "$parameters" "servicePrincipalAppKey" "$app_key")
parameters=$(try_replace_parameter "$parameters" "adminUsername" "$user_name")
parameters=$(try_replace_parameter "$parameters" "sshPublicKey" "$temp_pub_key")
parameters=$(try_replace_parameter "$parameters" "adminPassword" "$(uuidgen -r)")
parameters=$(try_replace_parameter "$parameters" "${vm_prefix}DnsPrefix" "$scenario_name")

az login --service-principal -u $app_id -p $app_key --tenant $tenant_id
echo "Creating resource group '$scenario_name'..."
az group create -n $scenario_name -l $region --tags "CleanTime=$(date -d "+${keep_alive_hours} hours" +%s)"
echo "Deploying template '$template_name'..."
deployment_data=$(az group deployment create -g $scenario_name --template-uri ${template_location}${template_name}/azuredeploy.json --parameters "$parameters")
echo "$deployment_data"

provisioning_state=$(echo "$deployment_data" | python -c "import json, sys; data=json.load(sys.stdin);print data['properties']['provisioningState']")
if [ "$provisioning_state" != "Succeeded" ]; then
    echo "Deployment failed." 1>&2
    exit -1
fi

# Download kubernetes config if applicable
if [[ "$template_name" == *"k8s"* ]]; then
  echo "Copying Kubernetes credentials to the agent..."
  az acs kubernetes get-credentials --resource-group=$scenario_name --name=containerservice-$scenario_name --ssh-key-file=$temp_key_path
fi

# Jenkins templates don't have the VmFQDN, we need to get it from the jenkinsURL output
if [[ "$template_name" == *"jenkins"* ]]; then
  fqdn=$(echo "$deployment_data" | python -c "import json, sys, re;data=json.load(sys.stdin);print re.findall(r'https*://(.*)' ,data['properties']['outputs']['jenkinsURL']['value'])[0]")
else
  fqdn=$(echo "$deployment_data" | python -c "import json, sys;data=json.load(sys.stdin);print data['properties']['outputs']['${vm_prefix}VmFQDN']['value']")
fi

# Setup an ssh key on the VMs if the template didn't do it by default
# (it's more secure than programatically ssh-ing with a password and let's us ssh in a consistent manner)
if [[ "$parameters" != *"sshPublicKey"* ]]; then
  echo 'Setting up ssh key access for vm...'
  az vm user reset-ssh -n "${vm_prefix}VM" -g "$scenario_name" # The azure-jenkins template fails to setup the key for some reason unless we do this first
  az vm user update -u "$user_name" --ssh-key-value "$temp_pub_key" -n "${vm_prefix}VM" -g "$scenario_name"
fi

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
  # Jenkins
  LocalForward 8080 127.0.0.1:8080
  User $user_name
  StrictHostKeyChecking no

Host tunnel-stop
  HostName $fqdn
  IdentityFile $temp_key_path
  ControlPath $temp_ctl
  RequestTTY no
EOF