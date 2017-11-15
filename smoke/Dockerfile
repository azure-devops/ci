FROM jenkins/jenkins:lts

WORKDIR /var/jenkins_home

ENV JAVA_OPTS -Djenkins.install.runSetupWizard=false

COPY . /opt

RUN /opt/bash/bootstrap-jenkins.sh

COPY groovy/init.groovy /usr/share/jenkins/ref/

