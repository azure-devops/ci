#!/bin/bash 
#===============================================================================
#          FILE: bootstrap-jenkins.sh
# 
#   DESCRIPTION: setup jenkins instance for plugin smoke testing.  
# 
#       CREATED: 11/14/2017 06:39:48 AM UTC
#===============================================================================

set -x

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
    mailer \
    azure-commons \
    azure-credentials \
    kubernetes-cd \
    azure-acs \
    windows-azure-storage \
    azure-container-agents \
    azure-vm-agents \
    azure-app-service \
    azure-function

