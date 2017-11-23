package smoke.groovy
/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 * Licensed under the MIT License. See LICENSE in the project root for license information.
 */


import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.microsoft.azure.util.AzureCredentials
import com.microsoft.azure.vmagent.AzureVMAgentTemplate
import com.microsoft.azure.vmagent.AzureVMCloud
import com.microsoft.azure.vmagent.AzureVMCloudRetensionStrategy
import groovy.json.JsonSlurper
import hudson.security.AuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.*

class Helper {
    static String randomString(int length = 8) {
        UUID.randomUUID().toString().replaceAll("-", "").substring(0, length)
    }
}

class Config {
    static String location = '$$location$$'
    static String vmResourceGroup = '$$vmResourceGroup$$'
    static Map<String, String> vmCredential = [
            id: 'vm-credential',
            username: '$$adminUser$$',
            password: 'A*1' + Helper.randomString(16)
    ]
    static Map<String, String> sshCredential = [
            id: 'ssh-credential',
            username: '$$adminUser$$',
            privateKey: '/opt/ssh/id_rsa',
            publicKey: '/opt/ssh/id_rsa.pub'
    ]

    static Map<String, String> servicePrincipal = [
            id: 'sp',
            subscriptionId: '$$subscriptionId$$',
            clientId: '$$clientId$$',
            clientSecret: '$$clientSecret$$',
            tenant: '$$tenantId$$'
    ]

    static Map<String, String> acrCredential = [
            id: 'acr',
            username: '$$acrName$$',
            password: '$$acrPassword$$'
    ]
}

static void setupSecurity() {
    Jenkins instance = Jenkins.instance
    def strategy = AuthorizationStrategy.UNSECURED
    instance.authorizationStrategy = strategy
    instance.save()
}

static void addVmCredential() {
    def credential = new UsernamePasswordCredentialsImpl(
            CredentialsScope.GLOBAL,
            Config.vmCredential.id,
            "VM Credential",
            Config.vmCredential.username,
            Config.vmCredential.password
    )
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void addAcrCredential() {
    def credential = new UsernamePasswordCredentialsImpl(
            CredentialsScope.GLOBAL,
            Config.acrCredential.id,
            'ACR Credential',
            Config.acrCredential.username,
            Config.acrCredential.password
    )
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void addSshCredential() {
    def credential = new BasicSSHUserPrivateKey(
            CredentialsScope.GLOBAL,
            Config.sshCredential.id,
            Config.sshCredential.username,
            new BasicSSHUserPrivateKey.FileOnMasterPrivateKeySource(Config.sshCredential.privateKey),
            '',
            'SSH private key credential to login to the given VM'
    )
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void addAzureCredential() {
    def credential = new AzureCredentials(
            CredentialsScope.GLOBAL,
            Config.servicePrincipal.id,
            'Service Principal for Azure resources',
            Config.servicePrincipal.subscriptionId,
            Config.servicePrincipal.clientId,
            Config.servicePrincipal.clientSecret
    )
    credential.tenant = Config.servicePrincipal.tenant
    credential.azureEnvironmentName = 'Azure'
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void setupVmCloud(String azureCredentialId) {
    String storageAccount = "storage" + Helper.randomString()
    AzureVMAgentTemplate template = new AzureVMAgentTemplate(
            "vm-cloud-template",
            "VM cloud for Jenkins plugins smoke test",
            "linux docker maven git",
            Config.location,
            "Standard_D2s_v3",
            "new",
            "Standard_LRS",
            storageAccount,
            "",
            "managed",
            "1",
            "NORMAL",
            "Ubuntu 16.04 LTS",
            true,
            true,
            true,
            "Linux",
            "basic",
            false,
            new AzureVMAgentTemplate.ImageReferenceTypeClass("", "", "", "", ""),
            "SSH",
            true,
            "",
            Config.vmCredential.id,
            "",
            "",
            "",
            false,
            "",
            "",
            "",
            new AzureVMCloudRetensionStrategy(60),
            false,
            false,
            "",
            true,
            true
    )

    AzureVMCloud cloud = new AzureVMCloud(
            "vm-cloud",
            "vm-cloud",
            azureCredentialId,
            "3",
            "1200",
            "existing",
            "",
            Config.vmResourceGroup,
            [template]
    )

    Jenkins instance = Jenkins.instance
    instance.clouds.replace(cloud)
    instance.save()
}

setupSecurity()
addVmCredential()
addSshCredential()
addAcrCredential()
addAzureCredential()
setupVmCloud(Config.servicePrincipal.id)

Thread.start {
    sleep 10000
    println '--> setting up jobs'
    def process = 'bash /opt/bash/setup-jobs.sh'.execute()
    process.waitForProcessOutput(System.out, System.err)
}
