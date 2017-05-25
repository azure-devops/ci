#!/usr/bin/env groovy

def call(Map options = [:]) {
    stage('Spinnaker CI Test') {
        def venv_name= env.JOB_BASE_NAME + '-venv'
        def activate_venv = '. "' + env.WORKSPACE + '/' + venv_name + '/bin/activate";'
        sh 'virtualenv ' + venv_name

        dir('citestpackage') {
            // Eventually this repo will be its own python package and we won't have to install it separately
            git 'https://github.com/google/citest.git'
            sh activate_venv + 'pip install -r requirements.txt'
        }

        dir('spinnaker-ci-test') {
            git 'https://github.com/spinnaker/spinnaker.git'

            dir('testing/citest') {
                try {
                  sh activate_venv + 'pip install -r requirements.txt;PYTHONPATH=.:spinnaker python tests/' + options.testName + '.py --native_host=localhost ' + options.testArgs
                } finally {
                  archiveArtifacts options.testName + '.*'
                }
            }
        }
    }
}