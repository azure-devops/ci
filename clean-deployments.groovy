node('spin-k8s-test') {
    properties([parameters([
            string(defaultValue: '72f988bf-86f1-41af-91ab-2d7cd011db47', description: 'Tenant id', name: 'tenant_id'),
            string(defaultValue: 'AzDevOpsTestingSP', description: 'Credentials id', name: 'cred_id')
            ])])

    checkout scm

    stage('Delete deployments') {
        def script_path = 'scripts/clean-deployments.sh'
        sh 'sudo chmod +x ' + script_path
        withCredentials([usernamePassword(credentialsId: params.cred_id, passwordVariable: 'client_secret', usernameVariable: 'client_id')]) {
            sh script_path + ' -ci ' + env.client_id + ' -cs ' + env.client_secret + ' -ti ' + params.tenant_id
        }
    }
}