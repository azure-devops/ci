node('quickstart-template') {
    try {
        properties([
            pipelineTriggers([cron('@daily')]),
            buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '14', numToKeepStr: '')),
            parameters([
             string(defaultValue: 'Azure', description: '', name: 'template_fork'),
             string(defaultValue: 'master', description: '', name: 'template_branch')
            ])
        ])

        checkout scm

        withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
          sh 'az login --service-principal -u ' + env.app_id + ' -p ' + env.app_key + ' --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47'
        }

        dir('scripts/deploy-dev-ops') {
          stage('Download script') {
            sh './download-deploy-dev-ops.sh -f ' + params.template_fork + ' -b ' + params.template_branch
          }

          stage('Deploy target test') {
            sh './deploy-target.exp'
          }
          stage('Username test') {
            sh './username.exp'
          }
          stage('Dns prefix test') {
            sh './dns-prefix.exp'
          }
          stage('Location test') {
            sh './location.exp'
          }
          stage('Service Principal test') {
            sh './service-principal.exp'
          }
          stage('SSH key test') {
            sh './ssh-key.exp'
          }
          stage('Password test') {
            sh './password.exp'
          }
          stage('Vmss test') {
            sh './vmss.exp'
          }
          stage('K8s test') {
            sh './k8s.exp'
          }
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
    } finally {
      sh 'rm -f scripts/deploy-dev-ops/deploy-dev-ops.sh'
      sh 'az logout'
    }
}