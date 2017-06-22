set -x

#Install Java 8
sudo DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:openjdk-r/ppa -y
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install openjdk-8-jre openjdk-8-jre-headless openjdk-8-jdk -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -y update --fix-missing

# Install git
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git

#Install Maven
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y maven

#make sure we can build Jenkins plugins
mkdir ~/.m2
wget https://raw.githubusercontent.com/azure-devops/ci/master/resources/jenkins-settings.xml -O ~/.m2/settings.xml