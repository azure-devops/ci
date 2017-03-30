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
                    'Custom Ubuntu without init script': {
                        runSanityChecks('s-cust-no-init-ubuntu')
                    },
                    /* Temporarily disable 'Custom Ubuntu with init script' because the vm agent template is not configured correctly.
                    'Custom Ubuntu with init script': {
                        runSanityChecks('s-cust-init-ubuntu')
                    },*/
                    'Reference Ubuntu with init script': {
                        runSanityChecks('s-ref-ubuntu')
                    },
                    'Custom Windows with init script': {
                        runSanityChecks('s-cust-windows')
                    },
                    'Reference Windows with init script': {
                        runSanityChecks('s-ref-windows')
                    })
            }
        }
    }
}