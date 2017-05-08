#!/usr/bin/env groovy

package com.microsoft.azure.devops.ci;

def getTestResultFilePatterns() {
    return [
        surefire: 'target/surefire-reports/*.xml',
        failsafe: 'target/failsafe-reports/*.xml',
        findBugs: 'target/findbugsXml.xml'
    ];
}

def isWindows() {
    try {
        sh 'echo "abc"'
    } catch (all) {
        return true;
    }
    return false;
}

/**
    Adds common job parameters and searches for an existing outlook webhook credential. If it finds one then it adds that hook to the job.
*/
def loadJobProperties() {
    def tokenizedJob = env.JOB_NAME.tokenize('/')
    def pluginName = tokenizedJob[0]
    def forkName = tokenizedJob[1]
    def branchName = tokenizedJob[2]

    def defaultShouldRunIntegrationTests = false
    def defaultShouldRunWindowsBuildStep = true
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

    if ( !pluginName.equalsIgnoreCase("azure-credentials") ) {
        defaultShouldRunIntegrationTests = true
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

/**
     * Run maven 'failsafe:integration-test' step in parallel on all the provided nodes.
     * @param envList List of Map objects with these keys:
                        label - the parallel branch label
                        node_name - the node name
                        environment - the credentials id for the groovy script that sets up the environment
*/
def runIntegrationTests(envList) {
    Map tasks = [failFast: false]
    for (int i = 0; i < envList.size(); ++i) {
        String stageIdentifier = envList[i].label;
        String nodeLabel = envList[i].node_name;
        String testEnvCredentials = envList[i].environment;
        tasks[stageIdentifier] = {
            node(nodeLabel) {
                withCredentials([file(credentialsId: testEnvCredentials, variable: 'load_test_env_script_location')]) {
                    load env.load_test_env_script_location
                    checkout scm
                    //set the default integration test timeout to 20 minutes because they are very slow
                    withEnv(["_JAVA_OPTIONS=-Djenkins.test.timeout=1200"]) {
                        if ( isWindows() ) {
                            bat 'mvn install failsafe:integration-test'
                        } else {
                            sh 'mvn install failsafe:integration-test'
                        }
                    }
                    stash includes: testResultFilePatterns.failsafe, name: 'integration_test_results'
                }
            }
        }
    }
    return parallel(tasks)
}