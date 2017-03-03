def linux_build() {
    sh 'echo "works"'
}
def windows_build() {
    bat 'echo \'works\''
}
stage('Verify VMAgents templates') {
    parallel 'Custom Ubuntu without init script': {
        node('s-cust-no-init-ubuntu') {
            linux_build()
        }
    },
    /*'Custom Ubuntu with init script': {
        node('s-cust-init-ubuntu') {
            linux_build()
        }
    },*/
    'Reference Ubuntu with init script': {
        node('s-ref-ubuntu') {
            linux_build()
        }
    },
    'Custom Windows with init script': {
        node('s-cust-windows') {
            windows_build()
        }
    },
    'Reference Windows with init script': {
        node('s-ref-windows') {
            windows_build()
        }
    },
    failFast: true
}
