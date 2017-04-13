node('quickstart-template') {
    try {
        properties([
            pipelineTriggers([cron('@daily'), pollSCM('* * * * *')])
        ])

        checkout([
            $class: 'GitSCM',
            branches: [[name: '*/master']],
            doGenerateSubmoduleConfigurations: false,
            extensions: [[$class: 'PathRestriction', excludedRegions: '', includedRegions: '''test-quickstart-template.groovy
scripts/deploy-quickstart-template.sh''']],
            submoduleCfg: [],
            userRemoteConfigs: [[url: 'https://github.com/azure-devops/ci.git']]
        ])

        // We're not using this repo for anything other than the triggers. TODO(erijiz): Modify the deploy script to use these files rather than downloading them
        dir('azure-quickstart-templates') {
            checkout([
                $class: 'GitSCM',
                branches: [[name: '*/master']],
                doGenerateSubmoduleConfigurations: false,
                extensions: [[$class: 'PathRestriction', excludedRegions: '''.*.md
.*metadata.json''', includedRegions: (env.JOB_BASE_NAME + '/.*')]],
                submoduleCfg: [],
                userRemoteConfigs: [[url: 'https://github.com/Azure/azure-quickstart-templates.git']]
            ])
        }

        def run_basic_spinnaker_test = env.JOB_BASE_NAME.contains("spinnaker")
        def run_spinnaker_k8s_test = env.JOB_BASE_NAME.contains("spinnaker") && env.JOB_BASE_NAME.contains("k8s")

        def scenario_name = "qstest" + UUID.randomUUID().toString().replaceAll("-", "")

        stage('Deploy Quickstart Template') {
            def script_path = 'scripts/deploy-quickstart-template.sh'
            sh 'sudo chmod +x ' + script_path
            withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
                sh script_path + ' -tn ' + env.JOB_BASE_NAME + ' -sn ' + scenario_name + ' -ai ' + env.app_id + ' -ak ' + env.app_key
            }
        }

        sh 'ssh -F ' + scenario_name + '/ssh_config -f -N tunnel-start'

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
                    git poll: false, url: 'https://github.com/google/citest.git'
                    sh activate_venv + 'pip install -r requirements.txt'
                }

                dir('spinnaker-k8s-test') {
                    git poll: false, url: 'https://github.com/spinnaker/spinnaker.git'

                    dir('testing/citest') {
                        sh activate_venv + 'pip install -r requirements.txt;PYTHONPATH=.:spinnaker python tests/kube_smoke_test.py --native_host=localhost --spinnaker_kubernetes_account=my-kubernetes-account'
                    }
                }
            }
        }

        sh 'ssh -O "exit" -F ' + scenario_name + '/ssh_config tunnel-stop'

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