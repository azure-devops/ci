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

        dir('scripts/deploy-interactive') {
          stage('Target deployment test') {
            sh './target-deployment.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('Username test') {
            sh './username.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('Dns prefix test') {
            sh './dns-prefix.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('Location test') {
            sh './location.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('Service Principal test') {
            sh './service-principal.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('K8s test') {
            sh './k8s.exp ' + params.template_fork + ' ' + params.template_branch
          }
          stage('Vmss test') {
            sh './vmss.exp ' + params.template_fork + ' ' + params.template_branch
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
      sh 'az logout'
    }
}