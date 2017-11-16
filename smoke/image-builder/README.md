# Docker Image Builder for Azure Jenkins Plugins Test

This tool builds a Jenkins image from the base [jenkins/jenkins](https://hub.docker.com/r/jenkins/jenkins/)
image, with all the latest Azure Jenkins plugins installed. You may also choose to build the plugins from
source, and install the SNAPSHOT version of plugins.

## Prerequisites

1. Docker

## How to build

1. Clone the source
1. Run the build

   ```bash
   cd smoke/image-builder
   perl/prepare-image.pl --help

   perl/perpare-image.pl --tag jenkins-test --jenkins-version lts --build-plugin azure-commons,azure-acs
   ```