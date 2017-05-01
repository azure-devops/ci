node('quickstart-template') {
    try {
        properties([
            pipelineTriggers([cron('@daily')]),
            buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '14', numToKeepStr: ''))
        ])

        def utils_location = "https://raw.githubusercontent.com/Azure/azure-devops-utils/v0.11.0/"
        def run_basic_spinnaker_test = env.JOB_BASE_NAME.contains("spinnaker")
        // The azure-jenkins template uses an old image that doesn't support the same CLI command that we run
        def run_basic_jenkins_test = env.JOB_BASE_NAME != "azure-jenkins" && env.JOB_BASE_NAME.contains("jenkins")
        def run_jenkins_acr_test = env.JOB_BASE_NAME.contains("jenkins-acr")
        def run_spinnaker_k8s_test = env.JOB_BASE_NAME.contains("spinnaker") && env.JOB_BASE_NAME.contains("k8s")

        def scenario_name = "qstest" + UUID.randomUUID().toString().replaceAll("-", "")
        def ssh_command = ""
        def jenkinsAdminPassword = "";
        def socket = scenario_name + "/ssh-socket"

        stage('Deploy Quickstart Template') {
            checkout scm

            def script_path = 'scripts/deploy-quickstart-template.sh'
            sh 'sudo chmod +x ' + script_path
            withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
                ssh_command = sh(returnStdout: true, script: script_path + ' -tn ' + env.JOB_BASE_NAME + ' -sn ' + scenario_name + ' -ai ' + env.app_id + ' -ak ' + env.app_key).trim()
            }
        }

        sh ssh_command + ' -S ' + socket + ' -fNTM -o "StrictHostKeyChecking=no"'
        try {
          if (run_basic_jenkins_test) {
              stage('Basic Jenkins Test') {
                  jenkinsAdminPassword = sh(returnStdout: true, script: ssh_command + " sudo cat /var/lib/jenkins/secrets/initialAdminPassword").trim()
                  def version = null
                  try {
                      // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
                      version = sh(returnStdout: true, script: 'curl --silent "' + utils_location + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "version" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
                      echo "Jenkins version: " + version
                  } catch (e) {
                  }
                  
                  if (!version || version == "") {
                      error("Failed to get Jenkins version.")
                  }
              }
          }

          if (run_jenkins_acr_test) {
              stage('Jenkins to ACR Test') {
                  def jobList = null
                  try {
                      // NOTE: The password will be printed out in the logs, but that's fine since you still have to ssh onto the VM to use it
                      jobList = sh(returnStdout: true, script: 'curl --silent "' + utils_location + 'jenkins/run-cli-command.sh" | sudo bash -s -- -c "list-jobs" -ju "admin" -jp ' + jenkinsAdminPassword).trim()
                      echo "Jenkins job list: " + jobList
                  } catch (e) {
                  }
                  
                  def jobName = "basic-docker-build"
                  if (!jobList || !jobList.contains(jobName)) {
                      error("Failed to find '" + jobName + "' in Jenkins job list.")
                  }
              }
          }

          if (run_basic_spinnaker_test) {
              stage('Basic Spinnaker Test') {
                  def spinnakerGateHealth = null
                  try {
                      def response = sh(returnStdout: true, script: 'curl http://localhost:8084/health').trim()
                      echo 'Spinnaker Gate Health: ' + response
                      def slurper = new groovy.json.JsonSlurper()
                      spinnakerGateHealth = slurper.parseText(response)
                  } catch (e) {
                  }
                  
                  if (spinnakerGateHealth.status != "UP") {
                      error("Spinnaker Gate service is not healthy.")
                  }
              }
          }

          if (run_spinnaker_k8s_test) {
              stage('Spinnaker Deploy to Kubernetes Test') {
                  def venv_name= env.JOB_BASE_NAME + '-venv'
                  def activate_venv = '. "' + env.WORKSPACE + '/' + venv_name + '/bin/activate";'
                  sh 'virtualenv ' + venv_name

                  dir('citestpackage') {
                      // Eventually this repo will be its own python package and we won't have to install it separately
                      git 'https://github.com/google/citest.git'
                      sh activate_venv + 'pip install -r requirements.txt'
                  }

                  dir('spinnaker-k8s-test') {
                      git 'https://github.com/spinnaker/spinnaker.git'

                      dir('testing/citest') {
                          try {
                            sh activate_venv + 'pip install -r requirements.txt;PYTHONPATH=.:spinnaker python tests/kube_smoke_test.py --native_host=localhost --spinnaker_kubernetes_account=my-kubernetes-account'
                          } finally {
                            archiveArtifacts 'kube_smoke_test.*'
                          }
                      }
                  }
              }
          }
        } finally {
          // Always close the socket so that the port is not in use on the agent
          sh ssh_command + ' -S ' + socket + ' -O exit'
        }

        stage('Clean Up') {
            sh 'rm -rf ' + scenario_name
            sh 'az group delete -n ' + scenario_name + ' --yes'
            sh 'az logout'
        }
    } catch (e) {
        def public_build_url = "$BUILD_URL".replaceAll("10.0.0.4:8080" , "devops-ci.westcentralus.cloudapp.azure.com")
        withCredentials([string(credentialsId: 'TeamEmailAddress', variable: 'email_address')]) {
            emailext (
                attachLog: true,
                subject: "Jenkins Job '$JOB_NAME' #$BUILD_NUMBER Failed",
                body: public_build_url,
                to: env.email_address
            )
        }
        throw e
    }
}