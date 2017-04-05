set -x

# Install Java
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-7-jdk
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y --fix-missing

# Install git
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git

# Install python
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python-pip python-dev libffi-dev libssl-dev
sudo pip install virtualenv
sudo pip install pyparsing

# Install Azure CLI 2.0
echo "deb [arch=amd64] https://apt-mo.trafficmanager.net/repos/azure-cli/ wheezy main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver apt-mo.trafficmanager.net --recv-keys 417A0893
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli

# Install Kubernetes CLI
kubectl_file="/usr/local/bin/kubectl"
sudo curl -L -o $kubectl_file https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
sudo chmod +x $kubectl_file