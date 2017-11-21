# Smoke Test Runner for Azure Jenkins Plugins

## Prerequisites

1. A Jenkins image build with the [Image Builder](../image-builder) 
1. Azure Service Principal
1. A Jenkins instance with the following tools / support:
   * Azure Credentials plugin, with the service principal configured
   * Git
   * Azure CLI.
   * Docker. The user running Jenkins process should have permission to build and run docker images.

## How to test

1. Add Azure service principal credential to the Jenkins instance.
2. Create a new freestyle job
    * SCM: Clone the smoke test code from the Git repository
    * Tick the "Use secret text(s) or file(s)" option, specify the service principal credentials created above, 
       with all the variable names unchanged.
    * Add an "Execute shell" build step, with the following code
       
       ```
       cd smoke/test-runner
       perl perl/jenkins-smoke-test.pl --help
       perl perl/jenkins-smoke-test.pl --image <jenkins-image-name>
       ```
       
    * Add a post-build action "Archive the artifacts" with the following pattern:
    
       ```
       smoke/test-runner/.artifacts/*
       ```

## Extra Options

* To use existing Kubernetes cluster and ACR instance (required to be in the same resource group),
   specify the following arguments:
   * `--resource-group`|`-g` - Resource group containing the K8s and ACR
   * `--adminUser` - admin username for the K8s master
   * `--privateKeyFile` - private key to authenticate with the K8s master
   * `--k8sName` - name of the ACS Kubernetes cluster
   * `--acrName` - name of the ACR

* To add some hosts to the K8s network security group to allow them to access the master host via SSH:
   * `--nsgAllowHost` - comma separated hosts that needs to be added the NSG allow list

* To use different git repository for the test configs which will be loaded by the Jenkins jobs, 
   specify the test configs repository details as followed. This may help if the configs are still under
   development.
   * `--testConfigRepo` - Repository URL for the test configs, default `https://github.com/azure-devops/ci.git`
   * `--testConfigBranch` - Branch of the test configs, default `master`
   * `--testConfigRoot` - Root directory for all the test configs, default `smoke/test-configs`

## Usage Documentation

```
$ perl/jenkins-smoke-test.pl --help
Usage:
    jenkins-smoke-test.pl [options]

     Options:
     <Required>
       --subscriptionId|-s          Subscription ID
       --clientId|-u                Client ID
       --clientSecret|-p            Client secret
       --tenantId|-t                Tenant ID

       --image|-i                   The Jenkins image used to run the tests

     <Optional>
       --adminUser                  The user name to login to ACS cluster master or other VM
       --publicKeyFile              The public key file used to create ACS cluster or other VM resources
       --privateKeyFile             The private key file used to authenticate with ACS cluster master or other VM resources

       --resource-group             The resource group that contains all the related resources
                                    It will be generated and created if not provided
       --location                   The resource location for all the resources, default "Southeast Asia"
       --k8sName                    The ACS resource name with Kubernetes orchestrator
       --acrName                    The Azure Container Registry resource name

       --targetDir                  The directory to store all the geneated resources
       --artifactDir                The directory to store the build artifacts

       --testConfigRepo             Repository URL for the test configs, default "https://github.com/azure-devops/ci.git"
       --testConfigBranch           Branch of the test configs, default "master"
       --testConfigRoot             Root directory for all the test configs, default "smoke/test-configs"

       --nsgAllowHost               Comma separated hosts that needs to be allowed for SSH access in the newly
                                    created Kubernetes master network security group

     <Miscellaneous>
       --verbose                    Turn on verbose output
       --help                       Show the help documentation
       --version                    Show the script version
```
