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
       perl perl/jenkins-smoke-test.pl
       ```
       
    * Add a post-build action "Archive the artifacts" with the following pattern:
    
       ```
       smoke/test-runner/.artifacts/*
       ```