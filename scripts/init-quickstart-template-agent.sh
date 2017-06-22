set -x

# Install Java 8
sudo DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:openjdk-r/ppa -y
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install openjdk-8-jre openjdk-8-jre-headless openjdk-8-jdk -y
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y --fix-missing

# Install git
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git

# Install expect
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y expect

if !(command -v git >/dev/null); then
  echo "Failed to install git on agent" 1>&2
  exit -1
fi

# Install python
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python-pip python-dev libffi-dev libssl-dev
sudo pip install virtualenv
sudo pip install pyparsing

# Install Azure CLI 2.0
echo "deb [arch=amd64] https://apt-mo.trafficmanager.net/repos/azure-cli/ wheezy main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver apt-mo.trafficmanager.net --recv-keys 417A0893
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
# NOTE: Using version 2.0.7 of the Azure CLI until this bug is fixed: https://github.com/Azure/azure-cli/issues/3731
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli=0.2.10-1

if !(command -v az >/dev/null); then
  echo "Failed to install az cli on agent" 1>&2
  exit -1
fi

# Install Kubernetes CLI
kubectl_file="/usr/local/bin/kubectl"
sudo curl -L -o $kubectl_file https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
sudo chmod +x $kubectl_file

if !(command -v kubectl >/dev/null); then
  echo "Failed to install kubectl on agent" 1>&2
  exit -1
fi