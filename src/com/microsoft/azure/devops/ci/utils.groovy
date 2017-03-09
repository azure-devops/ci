#!/usr/bin/env groovy

package com.microsoft.azure.devops.ci;

def getTestResultFilePatterns() {
    return [
        surefire: 'target/surefire-reports/*.xml',
        failsafe: 'target/failsafe-reports/*.xml',
        findBugs: 'target/findbugsXml.xml'
    ];
}
/*
    Adds common job parameters and searches for an existing outlook webhook credential. If it finds one then it adds that hook to the job.
*/
def loadJobProperties() {
    def tokenizedJob = env.JOB_NAME.tokenize('/')
    def pluginName = tokenizedJob[0]
    def forkName = tokenizedJob[1]
    def branchName = tokenizedJob[2]

    def defaultShouldRunIntegrationTests = true
    def defaultShouldRunWindowsBuildStep = false // disable until we have a stable Windows node
    def defaultShouldDogfood = false

    def defaultNotifyAborted = true
    def defaultNotifyBackToNormal = true
    def defaultNotifyFailure = true
    def defaultNotifyNotBuilt = true
    def defaultNotifyRepeatedFailure = true
    def defaultNotifySuccess = true
    def defaultNotifyUnstable = true
    def defaultNotifystart = true

    if ( forkName.equalsIgnoreCase("jenkinsci") && env.BRANCH_NAME == "master" ) {
        defaultShouldDogfood = true

        defaultNotifyAborted = false
        defaultNotifyBackToNormal = false
        defaultNotifyNotBuilt = false
        defaultNotifyRepeatedFailure = false
        defaultNotifyUnstable = false
        defaultNotifystart = false
    }
    if ( pluginName.equalsIgnoreCase("azure-credentials") ) {
        defaultShouldRunIntegrationTests = false
    }

    def webhook_url = ""
    node {
        try {
        withCredentials([string(credentialsId: "notification_hook_" + pluginName + "_" + forkName, variable: 'hook_url')]) {
            webhook_url = env.hook_url
        }
        } catch (all) {
            echo "There's no notification hook defined for " + env.JOB_NAME
        }
    }

    properties([parameters([
            booleanParam(defaultValue: defaultShouldRunIntegrationTests, description: '', name: 'run_integration_tests'),
            booleanParam(defaultValue: defaultShouldRunWindowsBuildStep, description: '', name: 'run_windows_build_step'),
            booleanParam(defaultValue: defaultShouldDogfood, description: '', name: 'dogfood')
            ]),
            [$class: 'WebhookJobProperty', webhooks: [[
                notifyAborted: defaultNotifyAborted,
                notifyBackToNormal: defaultNotifyBackToNormal,
                notifyFailure: defaultNotifyFailure,
                notifyNotBuilt: defaultNotifyNotBuilt,
                notifyRepeatedFailure: defaultNotifyRepeatedFailure,
                notifySuccess: defaultNotifySuccess,
                notifyUnstable: defaultNotifyUnstable,
                startNotification: defaultNotifystart,
                timeout: 30000,
                url: webhook_url
            ]]]
        ])

}

