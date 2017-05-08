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

    def compare_script_path = 'scripts/compare-web-pages.sh'
    sh 'sudo chmod +x ' + compare_script_path

    //we're using the login page, because http://localhost doest javascript redirect to login
    diff_result = sh(returnStatus: true, script: compare_script_path + " -f http://localhost:8080/login -s http://" + remoteURL + "/login")
    if (diff_result != 1) {
        error("The public landing page is identical with the local page!")
    }


    diff_result = sh(returnStatus: true, script: compare_script_path + " -f " + options.utilsLocation + "jenkins/jenkins-on-azure/index.html -s http://" + remoteURL + "/login -d "+ remoteURL)
    if (diff_result != 0) {
        error("The public landing page is not the same as the one in GitHub! Maybe you need to update the version (" + options.utilsLocation + "jenkins/jenkins-on-azure/index.html)")
    }

    if ( sh(returnStatus: true, script: 'command -v az >/dev/null') ) {
        error("The Azure CLI is not installed on the machine!")
    }
    if ( sh(returnStatus: true, script: 'command -v git >/dev/null') ) {
        error("Git is not installed on the machine!")
    }

    if (options.runJenkinsACRTest) {
        def jobList = null
        try {
            // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
            jobList = sh(returnStdout: true, script: 'curl --silent "' + options.utilsLocation + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "list-jobs" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
            echo "Jenkins job list: " + jobList
        } catch (e) {
        }

        def jobName = "basic-docker-build"
        if (!jobList || !jobList.contains(jobName)) {
            error("Failed to find '" + jobName + "' in Jenkins job list.")
        }
    }

    if (options.runJenkinsAptlyTest) {
        def jobList = null
        try {
            // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
            jobList = sh(returnStdout: true, script: 'curl --silent "' + options.utilsLocation + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "list-jobs" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
            echo "Jenkins job list: " + jobList
        } catch (e) {
        }

        def jobName = "hello-karyon-rxnetty"
        if (!jobList || !jobList.contains(jobName)) {
            error("Failed to find '" + jobName + "' in Jenkins job list.")
        }
    }
}