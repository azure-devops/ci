# Smoke Test Runner for Azure Jenkins Plugins

## Prerequisites

1. A Jenkins image build with the [Image Builder](../image-builder)
1. Azure Service Principal
1. A Jenkins instance with the following tools / support:
   * Azure Credentials plugin, with the service principal configured
   * Git
   * Azure CLI.
   * Docker. The user running Jenkins process should have permission to build and run docker images.

## How to Test

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

* To test with existing Azure resources, check the following options:
   * `--suffix`: this is the common name suffix for all the generated resources. If provided
      from command line, the resource name will be constructed with this suffix. And if
      the resource already exists, it will be reused. This will be helpful to run the tests
      multiple times with the same suffix.
   * `--noclean`: by default, the script deletes all the resource groups created during the
      tests, if this option is specified, the resources will be left untouched, and can be
      reused afterwards, with the same `--suffix` option provided.
   * `--publicKeyFile`: this should be the public key used to provision the existing resources.
   * `--privateKeyFile`: this should be the private key that can be authenticate with the existing resources.

   If you already has all the resource provisioned outside of this script, you can specify
   the information of the resources from command line, again, the script will reuse the
   resource if it already exists. Check the [Full Command Line Options](#full-command-line-options)
   for all the resource options.

* To add some hosts to the K8s network security group to allow them to access the master host via SSH:
   * `--nsgAllowHost` - comma separated hosts that needs to be added the NSG allow list

## Full Command Line Options

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
       --location                   The resource location for all the resources, default "Southeast Asia"
       --adminUser                  The user name to login to ACS cluster master or other VM
       --publicKeyFile              The public key file used to create ACS cluster or other VM resources
       --privateKeyFile             The private key file used to authenticate with ACS cluster master or other VM resources

       --suffix                     The name suffix for all the related resources and groups. This will be
                                    used to generate the default value for all the followed resource group names
                                    and the resource names. If not specified, a random one will be generated.
                                    For each of the related resource, the script will check if it exists and
                                    provision the resource if absent.

       <Azure Container Service>
       --acsResourceGroup           The resource group name of the ACS clusters
       --acsK8sName                 The name of the ACS Kubernetes cluster

       <Azure Container Registry>
       --acrResourceGroup           The resource group name of the ACR
       --acrName                    The name of the ACR

       <Azure WebApp (Linux)>
       --webappResourceGroup        The resource group name of the WebApp on Linux
       --webappPlan                 The name of the WebApp on Linux plan
       --webappName                 The name of the WebApp on Linux

       <Azure WebApp (Windows)>
       --webappwinResourceGroup     The resource group name of the WebApp on Windows
       --webappwinPlan              The name of the WebApp on Windows plan
       --webappwinName              The name of the WebApp on Windows

       <Azure Function>
       --funcResourceGroup          The resource group of the Azure Function
       --funcStorageAccount         The storage account of the Azure Function
       --funcName                   The name of the Azure Function

       <VM Agents>
       --vmResourceGroup            The resource group for the VM agents provision

       --targetDir                  The directory to store all the generated resources
       --artifactDir                The directory to store the build artifacts

       --skipExt                    List of file extensions that should not be processed for the $$option$$ replacement,
                                    default md, jar, pl, pm.

       --nsgAllowHost               Comma separated hosts that needs to be allowed for SSH access in the newly
                                    created Kubernetes master network security group

       --exposePort                 Expose the port on the host running the script, which maps to the Jenkins service port
                                    running in the Docker container.

       --timeout                    Timeout for the entire task in seconds, default 3600

     <Miscellaneous>
       --[no]clean                  Whether to delete the related resource groups at the end of the script.
       --verbose                    Turn on verbose output
       --help                       Show the help documentation
       --version                    Show the script version
```

## How to Write Test Cases

To write test cases for the Azure Jenkins plugins, add configuration files in:

* `smoke/test-runner/jobs`: XML configurations to define the job, which can be copied out from
   `$JENKINS_HOME/jobs/<job-name>/config.xml`. Rename the config file to `<job-name>.xml`. They
   will be processed before the Jenkins process is started, so **the `$$<option>$$` segment
   will be replaced with the corresponding option from the start up Perl script**.
*  If the job depends on some external data source, for example, the web application source code,
   the Kubernetes deployment YAML files, or any files that's needed during the job run, you may:

   * Fetch the source from external SCM
   * Add an `Execute Shell` build step to generate the source files (or the `sh` command in pipeline).
      This is preferred as it does not have external source code dependency.

   As long as it is in the job XML definition, it will be processed by the `$$<option>$$` replacement
   and you can generate the job definition dynamically.
