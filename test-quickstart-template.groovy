node('spin-k8s-test') {
    try {
        properties([
            pipelineTriggers([cron('@daily')])
        ])

        def venv_name= env.JOB_BASE_NAME + '-venv'
        sh 'virtualenv ' + venv_name
        def activate_venv = '. "' + env.WORKSPACE + '/' + venv_name + '/bin/activate";'

        scenario_name = sh(returnStdout: true, script: 'echo "' + env.JOB_BASE_NAME + '$(uuidgen | sed \'s/-//g\')"').trim()

        stage('Init') {
            dir('devopsci') {
                checkout scm
            }
            dir('spinnaker') {
                git 'https://github.com/spinnaker/spinnaker.git'
            }
            dir('citestpackage') {
                // Eventually this repo will be its own python package and we won't have to install it separately
                git 'https://github.com/google/citest.git'
                sh activate_venv + 'pip install -r requirements.txt'
            }
        }

        stage('Deploy Quickstart Template') {
            def script_path = 'devopsci/scripts/deploy-spinnaker-k8s.sh'
            sh 'sudo chmod +x ' + script_path
            withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
                sh script_path + ' -sn ' + scenario_name + ' -ai ' + env.app_id + ' -ak ' + env.app_key
            }
        }

        stage('Run Test') {
            sh 'ssh -F ' + scenario_name + '/ssh_config -f -N tunnel-start'
            dir('spinnaker/testing/citest') {
                sh activate_venv + 'pip install -r requirements.txt;PYTHONPATH=.:spinnaker python tests/kube_smoke_test.py --native_host=localhost'
            }
            sh 'ssh -O "exit" -F ' + scenario_name + '/ssh_config tunnel-stop'
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