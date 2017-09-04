#!groovy
import com.microsoft.azure.devops.ci.utils

def call(nodeLabel) {
    def ciUtils = new com.microsoft.azure.devops.ci.utils()
    node(nodeLabel) {
        echo 'works'
    }
}