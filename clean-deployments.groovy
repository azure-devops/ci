node('spin-k8s-test') {
    try {
        properties([
            pipelineTriggers([cron('@daily')])
        ])

        checkout scm

        stage('Delete deployments') {
            def script_path = 'scripts/clean-deployments.sh'
            sh 'sudo chmod +x ' + script_path
            withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'client_secret', usernameVariable: 'client_id')]) {
                sh script_path + ' -ci ' + env.client_id + ' -cs ' + env.client_secret
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
    }
}