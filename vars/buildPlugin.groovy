#!/usr/bin/env groovy
import com.microsoft.azure.devops.ci.utils

def call() {
    def ciUtils = new com.microsoft.azure.devops.ci.utils()
    ciUtils.loadJobProperties()

    timeout(60) {
        stage('Build') {
            ciUtils.buildMavenInParallel()
        }
        node('ubuntu') {
            checkout scm
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