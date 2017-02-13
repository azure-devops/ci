def linux_build(nname) {
    stage('Basic Linux Verification - '+nname) {
        sh 'echo "works"'
    }
}
def windows_build(nname) {
    stage('Basic Windows Verification - '+nname) {
        bat 'echo \'works\''
    }
}

parallel 'Custom Ubuntu without init script': {
    node('s-cust-no-init-ubuntu') {
        linux_build('Custom Ubuntu, no init script')
    }
},
/*'Custom Ubuntu with init script': {
    node('s-cust-init-ubuntu') {
        linux_build('Custom Ubuntu, init script')
    }
},*/
'Reference Ubuntu with init script': {
    node('s-ref-ubuntu') {
        linux_build('Reference Ubuntu, init script')
    }
},
'Custom Windows with init script': {
    node('s-cust-windows') {
        windows_build('Custom Windows, init script')
    }
},
'Reference Windows with init script': {
    node('s-ref-windows') {
        windows_build('Reference Windows, init script')
    }
},
failFast: true
