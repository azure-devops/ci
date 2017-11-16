FROM jenkins/jenkins:$$jenkins-version$$

WORKDIR /var/jenkins_home

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    PLUGIN_DIR=/usr/share/jenkins/ref/plugins/

RUN set -x && \
    /usr/local/bin/install-plugins.sh \
	    cloudbees-folder \
    	antisamy-markup-formatter \
	    build-timeout \
        credentials-binding \
        timestamper \
        ws-cleanup \
        ant \
        gradle \
        workflow-aggregator \
        github-branch-source \
        pipeline-github-lib \
        pipeline-stage-view \
        git \
        subversion \
        ssh-slaves \
        matrix-auth \
        pam-auth \
        ldap \
        email-ext \
        mailer $$all-plugins-list$$

$$docker-copy-jpi$$

COPY resolve-dependencies.sh /usr/local/bin/
RUN /usr/local/bin/resolve-dependencies.sh $$built-plugins$$

WORKDIR /var/jenkins_home
 
