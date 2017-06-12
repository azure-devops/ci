set -x

#Install Java
sudo DEBIAN_FRONTEND=noninteractive apt-get -y update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y default-jdk
sudo DEBIAN_FRONTEND=noninteractive apt-get -y update --fix-missing

# Install git
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git

#Install Maven
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y maven

#make sure we can build Jenkins plugins
mkdir ~/.m2
wget https://raw.githubusercontent.com/azure-devops/ci/master/resources/jenkins-settings.xml -O ~/.m2/settings.xml