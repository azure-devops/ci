Set-ExecutionPolicy Unrestricted
$jenkinsserverurl = $args[0]
$vmname = $args[1]
$secret = $args[2]


$wc = New-Object System.Net.WebClient

# disable the git credential manager
git config --system --unset credential.helper

#make sure we can build Jenkins plugins
mkdir c:\.m2
$wc.DownloadFile("https://raw.githubusercontent.com/azure-devops/ci/master/resources/jenkins-settings.xml", "c:\.m2\settings.xml")

Set-Location d:\

# Download the file to a specific location
Write-Output "Downloading zulu SDK "
$source = "http://cdn.azul.com/zulu/bin/zulu8.21.0.1-jdk8.0.131-win_x64.zip"
mkdir d:\azurecsdir
$destination = "d:\azurecsdir\zuluJDK.zip"
$wc.DownloadFile($source, $destination)

Write-Output "Unzipping JDK "
# Unzip the file to specified location
$shell_app = new-object -com shell.application
$zip_file = $shell_app.namespace($destination)
mkdir d:\java
$destination = $shell_app.namespace("d:\java")
$destination.Copyhere($zip_file.items(), 0x14)
Write-Output "Successfully downloaded and extracted JDK "

# Downloading jenkins slaves jar
Write-Output "Downloading jenkins slave jar "
mkdir d:\jenkins
$slaveSource = $jenkinsserverurl + "jnlpJars/slave.jar"
$destSource = "d:\jenkins\slave.jar"
$wc.DownloadFile($slaveSource, $destSource)

# Download the service wrapper
$wrapperExec = "d:\jenkins\jenkins-slave.exe"
$configFile = "d:\jenkins\jenkins-slave.xml"
$wc.DownloadFile("https://github.com/kohsuke/winsw/releases/download/winsw-v2.1.2/WinSW.NET2.exe", $wrapperExec)
$wc.DownloadFile("https://raw.githubusercontent.com/azure-devops/ci/master/resources/jenkins-slave.exe.config", "d:\jenkins\jenkins-slave.exe.config")
$wc.DownloadFile("https://raw.githubusercontent.com/azure-devops/ci/master/resources/jenkins-slave.xml", $configFile)

# Prepare config
Write-Output "Executing agent process "
$configExec = "d:\java\zulu8.21.0.1-jdk8.0.131-win_x64\bin\java.exe"
$configArgs = "-jnlpUrl `"${jenkinsserverurl}/computer/${vmname}/slave-agent.jnlp`" -noReconnect"
if ($secret) {
    $configArgs += " -secret `"$secret`""
}
(Get-Content $configFile).replace('@JAVA@', $configExec) | Set-Content $configFile
(Get-Content $configFile).replace('@ARGS@', $configArgs) | Set-Content $configFile
(Get-Content $configFile).replace('@SLAVE_JAR_URL', $slaveSource) | Set-Content $configFile

# Install the service
& $wrapperExec install
#sc.exe config "Service Name" obj= "DOMAIN\User" password= "password"
& $wrapperExec start