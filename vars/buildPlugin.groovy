#!/usr/bin/env groovy
import com.microsoft.azure.devops.ci.utils

def call() {
    def ciUtils = new com.microsoft.azure.devops.ci.utils()
    testResultFilePatterns = ciUtils.getTestResultFilePatterns()
    ciUtils.loadJobProperties()

    timeout(60) {
        parallel failFast: false,
        Windows: {
            if ( params.run_windows_build_step ) {
                node('win2016-dev') {
                    checkout scm
                    stage('Build') {
                        bat 'mvn clean install package'
                    }
                }
            }
        },
        Linux: {
            node('ubuntu') {
                checkout scm
                stage('Build') {
                    sh 'mvn clean install package'
                }
                if ( params.run_integration_tests ) {
                    stage('Integration Tests') {
                        withCredentials([file(credentialsId: 'az_test_env', variable: 'load_test_env_script_location')]) {
                            load env.load_test_env_script_location
                        }
                        sh 'mvn failsafe:integration-test package'
                    }
                }
                stage('Pack Artifacts') {
                    stash includes: testResultFilePatterns.surefire + ', ' + testResultFilePatterns.failsafe + ', ' + testResultFilePatterns.findBugs, name: 'test_results'
                    sh 'cp target/*.hpi .'
                    archiveArtifacts '*.hpi'
                }
            }
        }

        node('linux-dev') {
            stage ('Publish Test Results') {
                sh 'rm -rf *'
                unstash 'test_results'

                junit testResultFilePatterns.surefire + ', ' + testResultFilePatterns.failsafe
                step([$class: 'FindBugsPublisher', canComputeNew: false, defaultEncoding: '', excludePattern: '', healthy: '', includePattern: '', pattern: testResultFilePatterns.findBugs, unHealthy: ''])
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