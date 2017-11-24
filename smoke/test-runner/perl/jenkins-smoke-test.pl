#!/usr/bin/env perl
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

use strict;
use warnings FATAL => 'all';

package main;

use FindBin qw($Bin);
use lib "$Bin/../../lib/perl";
use Getopt::Long qw(:config gnu_getopt no_ignore_case auto_version auto_help);
use Helpers qw(:log :shell throw_if_empty random_string process_file);
use Cwd qw(abs_path);
use File::Basename;
use File::Copy;
use File::Find;
use File::Glob qw(:bsd_glob);
use File::Path qw(make_path remove_tree);
use File::Spec;
use IO::Select;
use IPC::Open3 qw(open3);
use JenkinsMonitor;
use Pod::Usage;
use POSIX qw(strftime);
use Provisioner;
use sigtrap qw(die normal-signals);
use Symbol;

use Data::Dumper;

our $VERSION = 0.1.0;

my $task_start_time = time();

our %options = (
    subscriptionId => $ENV{AZURE_SUBSCRIPTION_ID},
    clientId => $ENV{AZURE_CLIENT_ID},
    clientSecret => $ENV{AZURE_CLIENT_SECRET},
    tenantId => $ENV{AZURE_TENANT_ID},
    adminUser => 'azureuser',
    suffix => strftime("%m%d", localtime()) . Helpers::random_string(4),
    location => 'Southeast Asia',
    nsgAllowHost => [],
    skipExt => [qw(md jar pl pm)],
    timeout => 3600,
    clean => 1,
    verbose => 1,
);

GetOptions(\%options,
    'subscriptionId|subscription-id|s=s',
    'clientId|client-id|u=s',
    'clientSecret|client-secret|p=s',
    'tenantId|tenant-id|t=s',
    'image|i=s',
    'location|l=s',
    'adminUser|admin-user=s',
    'publicKeyFile|public-key-file=s',
    'privateKeyFile|private-key-file=s',
    # common resource name suffix
    'suffix=s',
    # options for ACS resources
    'acsResourceGroup|acs-resource-group=s',
    'acsK8sName|acs-k8s-name=s',
    # options for ACR
    'acrResourceGroup|acr-resource-group=s',
    'acrName|acr-name=s',
    # options for Azure WebApp (Linux)
    'webappResourceGroup|webapp-resource-group=s',
    'webappPlan|webapp-plan=s',
    'webappName|webapp-name=s',
    # options for Azure WebApp (Win)
    'webappwinResourceGroup|webappwin-resource-group=s',
    'webappwinPlan|webappwin-plan=s',
    'webappwinName|webappwin-name=s',
    # options for Azure Function
    'funcResourceGroup|func-resource-group=s',
    'funcStorageAccount|func-storage-account=s',
    'funcName|func-name=s',
    # options for VM Agents
    'vmResourceGroup|vm-resource-group=s',
    'vmNsg|vm-nsg=s',
    'targetDir|target-dir=s',
    'artifactsDir|artifacts-dir=s',
    'nsgAllowHost|nsg-allow-host=s@',
    'skipExt|skip-ext=s@',
    'exposePort|expose-port=i',
    'timeout=i',
    'clean!',
    'verbose!',
) or pod2usage(2);

sub normalize {
    my ($key, $prefix) = @_;
    $options{$key} ||= $prefix . $options{suffix};
}

sub check_timeout {
    if (time() - $task_start_time > $options{timeout}) {
        die "Timeout ($options{timeout}s)";
    }
}

#######################################################################################################################
# Check and Normalize Command Line Arguments
#######################################################################################################################

if (exists $options{exposePort} and $options{exposePort} <= 0) {
    die "Argument exposePort=$options{exposePort} is invalid\n";
}

# Options for ACS resources
normalize('acsResourceGroup', 'jksmoke-acs-');
normalize('acsK8sName', 'containerservice-jksmoke-acs-');
normalize('acsK8sDns', 'acsk8s');

# Options for ACR
normalize('acrResourceGroup', 'jksmoke-acr-');
normalize('acrName', 'jksmokeacr');

# Options for Azure WebApp (Linux)
normalize('webappResourceGroup', 'jksmoke-webapp-');
normalize('webappPlan', 'plan-');
normalize('webappName', 'webapp-');

# Options for Azure WebApp (Win)
normalize('webappwinResourceGroup', 'jksmoke-webappwin-');
normalize('webappwinPlan', 'planwin-');
normalize('webappwinName', 'webappwin-');

# Options for Azure Function
normalize('funcResourceGroup', 'jksmoke-func-');
normalize('funcStorageAccount', 'funcstorage');
normalize('funcName', 'func-');

# Options for VM Agents
normalize('vmResourceGroup', 'jksmoke-vm-');
normalize('vmNsg', 'jksmoke-vm-nsg-');

if (not $options{targetDir}) {
    $options{targetDir} = File::Spec->catfile(abs_path("$Bin/.."), ".target");
    log_info("Remove all contents in $options{targetDir}");
    remove_tree($options{targetDir});
}

if (not $options{artifactsDir}) {
    $options{artifactsDir} = File::Spec->catfile(abs_path("$Bin/.."), ".artifacts");
    remove_tree($options{artifactsDir});
}

make_path($options{targetDir});
make_path($options{artifactsDir});

{
    # dump the options, hiding the service principal secret
    my $secret = delete $options{clientSecret};
    print Data::Dumper->Dump([\%options], ["options"]);
    $options{clientSecret} = $secret;
}

our $verbose = $options{verbose};

check_tool('Azure CLI', 'which az');
check_tool('Docker', 'which docker && docker ps');
check_tool('ssh-keygen', 'which ssh-keygen');

throw_if_empty('Azure subscription ID', $options{subscriptionId});
throw_if_empty('Azure client ID', $options{clientId});
throw_if_empty('Azure client secret', $options{clientSecret});
throw_if_empty('Azure tenant ID', $options{tenantId});
throw_if_empty('VM admin user', $options{adminUser});
throw_if_empty('Jenkins image', $options{image});

if (length($options{acrName}) < 5) {
    die "ACR name must have length greater than 5: $options{acrName}";
}

@{$options{nsgAllowHost}} = split(/,/, join(',', @{$options{nsgAllowHost}}));
@{$options{skipExt}} = split(/,/, join(',', @{$options{skipExt}}));

if (not checked_output(qw(docker images -q), $options{image})) {
    die "Image '$options{image}' was not found.";
}

my $generated_key = 0;
if (not exists $options{publicKeyFile} or not exists $options{privateKeyFile}) {
    $options{privateKeyFile} = File::Spec->catfile(abs_path($options{targetDir}), ".ssh/id_rsa");
    $options{publicKeyFile} = $options{privateKeyFile} . '.pub';
    log_info("Generate SSH key at $options{privateKeyFile}");
    make_path(dirname($options{publicKeyFile}));
    my $command = list2cmdline(qw(ssh-keygen -q -t rsa -N), '', '-f', $options{privateKeyFile});
    $command = 'yes | ' . $command;
    log_info($command);
    system('/bin/bash', '-c', $command);
    if ($? != 0) {
        die "Failed to generate SSH key pairs";
    }
    $generated_key = 1;
}

-e $options{publicKeyFile} or die "SSH public key file $options{publicKeyFile} does not exist.";
-e $options{privateKeyFile} or die "SSH private key file $options{privateKeyFile} does not exist.";

$options{publicKey} = Helpers::read_file($options{publicKeyFile}, 1);
$options{privateKey} = Helpers::read_file($options{privateKeyFile}, 1);
if ($generated_key) {
    log_info("Generated SSH private key:");
    print $options{privateKey}, "\n";
    log_info("Generated SSH public key:");
    print $options{publicKey}, "\n";
}

#######################################################################################################################
# Provision Azure Resources
#######################################################################################################################

{
    local $main::verbose;
    checked_run(qw(az login --service-principal -u), $options{clientId}, '-p', $options{clientSecret}, '-t',
        $options{tenantId});
}
checked_run(qw(az account set --subscription), $options{subscriptionId});

check_timeout();

# Prepare ACS
Provisioner::ensure_resource_group($options{acsResourceGroup}, $options{location});
my $conf_dir = File::Spec->catfile($options{targetDir}, 'conf');
process_file("$Bin/../conf/acs.parameters.json", $conf_dir , \%options);
$options{'k8sMasterHost'} = Provisioner::ensure_acs($options{acsResourceGroup}, $options{acsK8sName}, File::Spec->catfile($conf_dir, 'acs.parameters.json'));
throw_if_empty('K8s master host', $options{'k8sMasterHost'});
Provisioner::add_k8s_nsg_rule($options{acsResourceGroup}, @{$options{nsgAllowHost}});

check_timeout();

# Prepare ACR
Provisioner::ensure_resource_group($options{acrResourceGroup}, $options{location});
($options{acrHost}, $options{acrPassword}) = Provisioner::ensure_acr($options{acrResourceGroup}, $options{acrName});
{
    local $main::verbose;
    checked_run(qw(docker login -u), $options{acrName}, '-p', $options{acrPassword}, $options{acrHost});
}
$options{acrPrivateImageName} = $options{acrHost} . '/nginx-private';
checked_run(qw(docker pull nginx));
checked_run(qw(docker tag nginx), $options{acrPrivateImageName});
checked_run(qw(docker push), $options{acrPrivateImageName});

check_timeout();

# Prepare WebApp
Provisioner::ensure_resource_group($options{webappResourceGroup}, $options{location});
Provisioner::ensure_webapp($options{webappResourceGroup}, $options{webappPlan}, $options{webappName}, 'linux');

check_timeout();

Provisioner::ensure_resource_group($options{webappwinResourceGroup}, $options{location});
Provisioner::ensure_webapp($options{webappwinResourceGroup}, $options{webappwinPlan}, $options{webappwinName});

check_timeout();

# Prepare Function
Provisioner::ensure_resource_group($options{funcResourceGroup}, $options{location});
Provisioner::ensure_function($options{funcResourceGroup}, $options{funcStorageAccount}, $options{funcName});

check_timeout();

# VM Agents
Provisioner::ensure_resource_group($options{vmResourceGroup}, $options{location});
Provisioner::ensure_nsg($options{vmResourceGroup}, $options{vmNsg});
Provisioner::ensure_nsg_access($options{vmResourceGroup}, $options{vmNsg}, @{$options{nsgAllowHost}});

check_timeout();

#######################################################################################################################
# Replace Variables in Source Files
#######################################################################################################################

my %skip_ext = map { ($_, 1) } @{$options{skipExt}};
find(sub {
    if (-d $_) {
        return;
    }
    my $file = abs_path($File::Find::name);
    my ($extension) = /\.([^\.]+)$/;
    if (defined $extension and exists $skip_ext{$extension}) {
        return;
    }
    if ($file =~ /^\Q$options{targetDir}\E/ || $file =~ qr{/\.target\b}
        || $file =~ /^\Q$options{artifactsDir}\E/ || $file =~ qr{/\.artifacts\b}) {
        return;
    }
    my $rel = File::Spec->abs2rel($File::Find::name, "$Bin/..");
    my $target_dir = File::Spec->catfile($options{targetDir}, dirname($rel));
    process_file($file, $target_dir, \%options);
}, "$Bin/..");
chdir $options{targetDir};

#######################################################################################################################
# Start Jenkins Docker Container with init.groovy Applied and Monitor the Job Build Status
#######################################################################################################################

my $jenkins_home = File::Spec->catfile($options{targetDir}, "jenkins_home");
remove_tree($jenkins_home);
make_path($jenkins_home);

# collect the current user's <uid>:<gid>
# we need to run the Jenkins container with "-u <uid>:<gid>" so that the files written to the volume position
# /var/jenkins_home will be owned by the current running user and group, i.e., jenkins:jenkins if running in Jenkins.
# If not specified, 1000:1000 will be used and we may have permission issue when we tried to delete the volume files
# in later runs.
my $uid_gid = join(':', (getpwuid($<))[2, 3]);

$options{dockerProcessName} = 'smoke-' . Helpers::random_string();
my @commands = (qw(docker run -i),
    '-v', "$jenkins_home:/var/jenkins_home",
    '-v', "$options{targetDir}:/opt",
    '-u', $uid_gid,
    '--name', $options{dockerProcessName});
if (exists $options{exposePort}) {
    push @commands, '-p', "$options{exposePort}:8080";
}
push @commands, $options{image};

my @jobs = map { basename($_, '.xml') } bsd_glob 'jobs/*.xml';
my $monitor = JenkinsMonitor->new($jenkins_home, $options{artifactsDir}, File::Spec->catfile($options{targetDir}, "groovy/init.groovy"));
$monitor->start(@commands);
log_info("Jenkins docker container process name: $options{dockerProcessName}");
$monitor->monitor(\&check_timeout, \@jobs);
$monitor->terminate();
undef $monitor;

#######################################################################################################################
# Clean Up Tasks Running Before the Program Terminates
#######################################################################################################################

sub END {
    log_info("Teardown...");

    return if not $options{clean};

    for my $group (@Provisioner::created_resource_groups) {
        log_info("Clean up resource group $group");
        run_shell(qw(az group delete -y --no-wait -n), $group);
    }
}

__END__

=head1 NAME

jenkins-smoke-test.pl - Script to bootstrap and run the smoke tests for Azure Jenkins plugins.

=head1 SYNOPSIS

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

=cut
