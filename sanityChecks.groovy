#!groovy
pipeline {
    agent none
    options {
        timeout(time: 60, unit: 'MINUTES')
    }
    stages {
        stage('Verify VMAgents templates') {
            steps {
                 parallel ( failFast: true,
                    'Custom Ubuntu without init script (public IP)': {
                        runSanityChecks('s-cust-no-init-ubuntu-public')
                    },
                    /* Temporarily disable 'Custom Ubuntu with init script (public IP)' because the vm agent template is not configured correctly.
                    'Custom Ubuntu with init script': {
                        runSanityChecks('s-cust-init-ubuntu-public')
                    },*/
                    'Reference Ubuntu with init script (public IP)': {
                        runSanityChecks('s-ref-ubuntu-public')
                    },
                    'Custom Windows with init script (public IP)': {
                        runSanityChecks('s-cust-windows-public')
                    },
                    'Reference Windows with init script (public IP)': {
                        runSanityChecks('s-ref-windows-public')
                    },
                    'Custom Ubuntu without init script (private IP)': {
                        runSanityChecks('s-cust-no-init-ubuntu-private')
                    },
                    'Reference Ubuntu with init script (private IP)': {
                        runSanityChecks('s-ref-ubuntu-private')
                    },
                    'Custom Windows with init script (private IP)': {
                        runSanityChecks('s-cust-windows-private')
                    },
                    'Reference Windows with init script (private IP)': {
                        runSanityChecks('s-ref-windows-private')
                    },
                    'Custom Ubuntu without init script (public IP - with NSG)': {
                        runSanityChecks('s-cust-no-init-ubuntu-public-nsg')
                    },
                    'Reference Ubuntu with init script (public IP - with NSG)': {
                        runSanityChecks('s-ref-ubuntu-public-nsg')
                    },
                    'Custom Windows with init script (public IP - with NSG)': {
                        runSanityChecks('s-cust-windows-public-nsg')
                    },
                    'Reference Windows with init script (public IP - with NSG)': {
                        runSanityChecks('s-ref-windows-public-nsg')
                    },
                    'Custom Ubuntu without init script (private IP - with NSG)': {
                        runSanityChecks('s-cust-no-init-ubuntu-private-nsg')
                    },
                    'Reference Ubuntu with init script (private IP - with NSG)': {
                        runSanityChecks('s-ref-ubuntu-private-nsg')
                    },
                    'Custom Windows with init script (private IP - with NSG)': {
                        runSanityChecks('s-cust-windows-private-nsg')
                    },
                    'Reference Windows with init script (private IP - with NSG)': {
                        runSanityChecks('s-ref-windows-private-nsg')
                    })
            }
        }
    }
}