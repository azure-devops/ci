#!/usr/bin/env groovy

def load_job_parms() {
    def defaultShouldRunIntegrationTests = true
    def defaultShouldRunWindowsBuildStep = true
    def defaultShouldDogfood = false

    if ( env.JOB_NAME.contains('jenkinsci') && env.BRANCH_NAME == "master" ) {
        defaultShouldDogfood = true
    }
    if ( env.JOB_NAME.contains('azure-credentials') ) {
        defaultShouldRunIntegrationTests = false
    }

    properties([parameters([
            booleanParam(defaultValue: defaultShouldRunIntegrationTests, description: '', name: 'run_integration_tests'),
            booleanParam(defaultValue: defaultShouldRunWindowsBuildStep, description: '', name: 'run_windows_build_step'),
            booleanParam(defaultValue: defaultShouldDogfood, description: '', name: 'dogfood')
            ])])
}

def build_step(node_name) {
    checkout scm
    if (node_name == "Windows") {
        bat 'mvn clean install package'
    } else {
        sh 'mvn clean install package'
    }
}

def parallel_build() {
    def nodes = [
        [name: 'Linux', label:'ubuntu']
        ]
    if ( params.run_windows_build_step ) {
        nodes.push( [name: 'Windows', label: 'win2016-dev'])
    }
    def builders = [failFast: true]
    for (x in nodes) {
        def n = x
        builders[n.name] = {
            node(n.label) {
                build_step(n.name)
            }
        }
    }
    parallel builders
}

def call() {
    load_job_parms()
    timeout(60) {
        stage('Build') {
            parallel_build()
        }
        node('ubuntu') {
            if ( params.run_integration_tests ) {
                stage('Integration Tests') {
                    withCredentials([file(credentialsId: 'az_test_env', variable: 'load_test_env_script_location')]) {
                        load env.load_test_env_script_location
                    }
                    sh 'mvn failsafe:integration-test package'
                }
            }
            stage('Pack Artifacts') {
                sh 'cp target/*.hpi .'
                archiveArtifacts '*.hpi'
            }
            stage ('Publish Test Results') {
                junit '**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml'
                step([$class: 'FindBugsPublisher', canComputeNew: false, defaultEncoding: '', excludePattern: '', healthy: '', includePattern: '', pattern: '**/target/findbugsXml.xml', unHealthy: ''])
            }
            stage('Upload Bits') {
                build job: 'Upload Bits',
                    parameters: [
                        string(name: 'parent_project', value: "${env.JOB_NAME}"),
                        string(name: 'parent_build_number', value: "${env.BUILD_NUMBER}"),
                        string(name: 'container_name', value: 'devops-jenkins'),
                        string(name: 'artifacts_pattern', value: '*.hpi'),
                        string(name: 'virtual_path', value: "${env.JOB_NAME}/${env.BUILD_NUMBER}")
                    ]
                }
        }

        if ( params.dogfood) {
            stage('Dogfood') {
                build job: 'Dogfood',
                    parameters: [
                        string(name: 'plugin_path', value: "${env.JOB_NAME}/${env.BUILD_NUMBER}"),
                        booleanParam(name: 'run', value: true),
                        string(name: 'container_name', value: 'devops-jenkins')
                    ]
            }
        }
    }
}