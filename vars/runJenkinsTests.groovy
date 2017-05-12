#!/usr/bin/env groovy

def call(Map options = [:]) {
    def jenkinsAdminPassword = sh(returnStdout: true, script: options.sshCommand + " sudo cat /var/lib/jenkins/secrets/initialAdminPassword").trim()
    def version = null
    try {
        // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
        version = sh(returnStdout: true, script: 'curl --silent "' + options.utilsLocation + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "version" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
        echo "Jenkins version: " + version
    } catch (e) {
    }

    if (!version || version == "") {
        error("Failed to get Jenkins version.")
    }

    //verify that the Azure landing page works
    def remoteURL = options.sshCommand.split('@')[1].split(' ')[0]
    print remoteURL;

    //we're using the login page, because http://localhost doest javascript redirect to login
    remote_page = sh(returnStdout: true, script: "curl -s -L http://" + remoteURL + "/login")
    if (remote_page.contains("<title>Jenkins</title>")) {
        error("The login page is accessible over the public IP address, possibly exposing the user to Man in the Middle Attacks!")
    } else if (!remote_page.contains("<title>Jenkins On Azure</title>")) {
        error("The Azure landing page was not displayed over the public IP address!")
    }

    return_code = sh(returnStatus: true, script: " curl --connect-timeout 10 http://" + remoteURL + ":8080")
    if (return_code != 28) {
        error("Port 8080 is accessible over the public IP address, possibly exposing the user to Man in the Middle Attacks!")
    }

    if ( sh(returnStatus: true, script: 'command -v az >/dev/null') ) {
        error("The Azure CLI is not installed on the machine!")
    }
    if ( sh(returnStatus: true, script: 'command -v git >/dev/null') ) {
        error("Git is not installed on the machine!")
    }

    for (jobName in options.expectedJobNames) {
        def jobList = null
        try {
            // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
            jobList = sh(returnStdout: true, script: 'curl --silent "' + options.utilsLocation + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "list-jobs" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
            echo "Jenkins job list: " + jobList
        } catch (e) {
        }

        if (!jobList || !jobList.contains(jobName)) {
            error("Failed to find '" + jobName + "' in Jenkins job list.")
        }
    }
}