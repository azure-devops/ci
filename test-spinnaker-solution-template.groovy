#!/usr/bin/env groovy
properties([
    pipelineTriggers([cron('@daily')]),
    buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '14', numToKeepStr: '')),
    parameters([
        string(defaultValue: 'Azure', description: '', name: 'template_fork'),
        string(defaultValue: 'master', description: '', name: 'template_branch')])
])

def DeploySpinnakerSolutionTemplate(scenario_name, options) {
    checkout scm

    def template_base_url = "https://raw.githubusercontent.com/" + params.template_fork + "/azure-devops-utils/"+ params.template_branch + "/"
    def template_url = template_base_url + "/solution_template/spinnaker/mainTemplate.json"
    def ssh_command = ""

    def params = [:]
    params['_artifactsLocation'] = ['value' : template_base_url]
    params['_artifactsLocationSasToken'] = ['value' : '']
    params['publicIPResourceGroup'] = ['value' : scenario_name]
    params['storageAccountResourceGroup'] = ['value' : scenario_name]
    params['vmName'] = ['value' : (UUID.randomUUID().toString().replaceAll('-', '') + UUID.randomUUID().toString().replaceAll('-', '')).replaceAll('-', '').take(54) ]
    params['adminUserName'] = ['value' : 'testuser']
    params['adminPassword'] = ['value' : '']
    params['adminSSHPublicKey'] = ['value' : '']
    params['vmSize'] = ['value' : 'Standard_DS1_v2']
    params['storageAccountName'] = ['value' : 'jnktst' + UUID.randomUUID().toString().replaceAll('-', '').take(18)]
    params['storageAccountType'] = ['value' : options.storageType]
    params['publicIPName'] = ['value' : 'jnktst' + UUID.randomUUID().toString().replaceAll('-', '')]
    params['dnsPrefix'] = ['value' : 'jnktst' + UUID.randomUUID().toString().replaceAll('-', '')]

    if (options.useSSHPublicKey) {
        params['authenticationType'] = ['value' : 'sshPublicKey']
    } else {
        params['authenticationType'] = ['value' : 'password']
        withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestPassword', passwordVariable: 'admin_password', usernameVariable: 'admin_user_ignore')]) {
            params['adminPassword'] = ['value' : env.admin_password]
        }
    }

    if (options.useExistingStorage) {
        params['storageAccountNewOrExisting'] = ['value' : 'existing']
        def deploy_storage_script_path = 'scripts/deploy-storage-account.sh'
        sh 'sudo chmod +x ' + deploy_storage_script_path
        withCredentials([azureServicePrincipal(clientIdVariable: 'app_id', clientSecretVariable: 'app_key', credentialsId: 'DevOpsTesting')]) {
            sh deploy_storage_script_path + ' -an ' + params['storageAccountName']['value'] + ' -rg ' + scenario_name + ' -sk ' + params['storageAccountType']['value'] + ' -ai ' + env.app_id + ' -ak ' + env.app_key
        }
    } else {
        params['storageAccountNewOrExisting'] = ['value' : 'new']
    }

    if (options.useExistingPublicIP) {
        params['publicIPNewOrExisting'] = ['value' : 'existing']
        def deploy_ip_script_path = 'scripts/deploy-public-ip.sh'
        sh 'sudo chmod +x ' + deploy_ip_script_path
        withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
            sh deploy_ip_script_path + ' -ip ' + params['publicIPName']['value'] + ' -rg ' + scenario_name + ' -dp ' + params['dnsPrefix']['value'] + ' -ai ' + env.app_id + ' -ak ' + env.app_key
        }
    } else {
        params['publicIPNewOrExisting'] = ['value' : 'new']
    }

    def paramsJSON = readJSON text: '{}'
    paramsJSON['parameters'] = params
    writeJSON file: scenario_name + '.json', json: paramsJSON

    def script_path = 'scripts/deploy-arm-template.sh'
    sh 'sudo chmod +x ' + script_path

    withCredentials([usernamePassword(credentialsId: 'AzDevOpsTestingSP', passwordVariable: 'app_key', usernameVariable: 'app_id')]) {
        ssh_command = sh(returnStdout: true, script: script_path + ' -rps yes -tu ' + template_url + ' -vm ' + params['vmName']['value'] + ' -tp ' + scenario_name +'.json -sn ' + scenario_name + ' -ai ' + env.app_id + ' -ak ' + env.app_key).trim()
    }
    return ssh_command
}

def RunSolutionTemplateTests(options) {
    def scenario_name = "st-test" + UUID.randomUUID().toString().replaceAll("-", "")
    def socket = scenario_name + "/ssh-socket"
    node('quickstart-template') {
        try {
            def ssh_command = DeploySpinnakerSolutionTemplate(scenario_name, options)

            sh ssh_command + ' -S ' + socket + ' -fNTM -o "StrictHostKeyChecking=no"'

            try {
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
            } catch(e) {
            } finally {
                sh ssh_command + ' -S ' + socket + ' -O exit'
            }

            // Only clean up the resource group if all previous stages passed (just in case we want to debug a failure)
            // The clean-deployments job will delete it after 2 days
            sh 'az group delete -n ' + scenario_name + ' --yes'
        } catch (e) {
            print e
            throw e
        } finally {
            sh 'az logout'
            sh 'rm -rf ' + scenario_name
            sh 'rm ' + scenario_name + ".json"
        }
    }
}

try {
    stage('Run Solution Template Tests') {
        Map tasks = [failFast: false]
        def options = []
        for (publicKey in [true, false]) {
            for (existingStorage in [true, false]) {
                for (storageTypeStr in ['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS']) {
                    //no need to verify the template for all existing storage account types
                    if (existingStorage == false || storageTypeStr == 'Standard_LRS') {
                        for (existingPublicIP in [true, false]) {
                            if (existingPublicIP == false || storageTypeStr == 'Standard_LRS') {
                                options.push([
                                    name: 'SSH: ' + publicKey + ' Existing Storage: ' + existingStorage + ' Storage Type: ' + storageTypeStr + ' Existing Public IP: ' + existingPublicIP,
                                    useSSHPublicKey: publicKey,
                                    useExistingStorage: existingStorage,
                                    storageType: storageTypeStr,
                                    useExistingPublicIP: existingPublicIP
                                ])
                            }
                        }
                    }
                }
            }
        }

        //must iterate like this, the 'a in b' idiom is not supported by the cps plugin
        for (int i = 0; i < options.size(); ++i) {
            def opt = options[i]
            tasks[opt.name] = {
                RunSolutionTemplateTests(opt)
            }
        }

        timeout(60) {
            parallel(tasks)
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
