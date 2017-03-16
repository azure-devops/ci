node('linux-dev') {
  properties([parameters([
            choice(choices: 'azure-vm-agents\nazure-credentials\nwindows-azure-storage', description: 'For which plugin is the fork?', name: 'plugin_name'),
            string(defaultValue: '', description: 'Fork short name (no spaces)', name: 'fork_short_name'),
            string(defaultValue: '', description: 'Job name', name: 'job_name'),
            string(defaultValue: '', description: 'Fork\'s git url', name: 'git_url'),
            string(defaultValue: '', description: 'Outlook notification hook (optional)', name: 'hook_url')
            ])])

    checkout scm
    stage('Add Job') {
      withCredentials([file(credentialsId: 'upgrade_key_file', variable: 'key_file_path')]) {
        sh 'sudo chmod +x scripts/create-job.sh'
        sh 'scripts/create-job.sh -p ' + params.plugin_name + ' -f ' + params.fork_short_name + ' -g ' + params.git_url + ' -n \"' + params.job_name + '\" -j \"' + env.JENKINS_URL + '\" -i \"' + env.key_file_path + '\"'
      }
    }
    if ( (params.hook_url?.trim()) as boolean) {
      stage('Add Notification Hook') {
        withCredentials([file(credentialsId: 'upgrade_key_file', variable: 'key_file_path')]) {
          def cred_id = "notification_hook_" + params.plugin_name + "_" + params.fork_short_name
          def cred_description = "Notification Hook for " + params.plugin_name + " plugin (" + params.fork_short_name + " fork)"
          sh 'sudo chmod +x scripts/create-string-credentials.sh'
          sh 'scripts/create-string-credentials.sh -c ' + cred_id + ' -s ' + params.hook_url + ' -d \"' + cred_description + '\" -j \"' + env.JENKINS_URL + '\" -i \"' + env.key_file_path + '\"'
        }
      }
  }
}