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
use SSHClient;
use JenkinsCli;
use Cwd qw(abs_path);
use File::Basename;
use File::Copy;
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Spec;
use Pod::Usage;
use Socket;

use Data::Dumper;

our $VERSION = 0.1.0;

our %options = (
    verbose => 1,
    subscriptionId => $ENV{AZURE_SUBSCRIPTION_ID},
    clientId => $ENV{AZURE_CLIENT_ID},
    clientSecret => $ENV{AZURE_CLIENT_SECRET},
    tenantId => $ENV{AZURE_TENANT_ID},
    adminUser => 'azureuser',
    testConfigRepo => 'https://github.com/azure-devops/ci.git',
    testConfigBranch => 'master',
    testConfigRoot => 'smoke/test-configs',
    nsgAllowHost => [],
);

GetOptions(\%options,
    'subscriptionId|s=s',
    'clientId|u=s',
    'clientSecret|p=s',
    'tenantId|t=s',
    'image|i=s',
    'resource-group|g=s',
    'location|l=s',
    'adminUser=s',
    'publicKeyFile=s',
    'privateKeyFile=s',
    'k8sName=s',
    'acrName=s',
    'targetDir=s',
    'artifactsDir=s',
    'testConfigRepo=s',
    'testConfigRoot=s',
    'testConfigBranch=s',
    'nsgAllowHost=s@',
    'clean!',
    'verbose!',
) or pod2usage(2);

if (not $options{targetDir}) {
    $options{targetDir} = File::Spec->catfile(abs_path("$Bin/.."), ".target");
    log_info("Remove all contents in $options{targetDir}");
    remove_tree($options{targetDir});
}

if (not $options{artifactsDir}) {
    $options{artifactsDir} = File::Spec->catfile(abs_path("$Bin/.."), ".artifacts");
}

{
    # dump the options, hiding the service principal secret
    my $secret = delete $options{clientSecret};
    print Data::Dumper->Dump([\%options], ["options"]);
    $options{clientSecret} = $secret;
}

$options{testConfigRoot} =~ s/[\\\/]+$//;

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

@{$options{nsgAllowHost}} = split(/,/, join(',', @{$options{nsgAllowHost}}));

if (not checked_output(qw(docker images -q), $options{image})) {
    die "Image '$options{image}' was not found.";
}

make_path($options{targetDir});

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


{
    local $main::verbose;
    checked_run(qw(az login --service-principal -u), $options{clientId}, '-p', $options{clientSecret}, '-t',
        $options{tenantId});
}
checked_run(qw(az account set --subscription), $options{subscriptionId});

if (!$options{'resource-group'}) {
    if (not exists $options{clean}) {
        $options{clean} = 1;
    }
    $options{'resource-group'} = 'jenkins-smoke-' . Helpers::random_string();
    $options{'location'} ||= 'Southeast Asia';

    checked_run(qw(az group create -n), $options{'resource-group'}, '-l', $options{location});
} else {
    $options{'location'} = checked_output(qw(az group show --query location --output tsv -n), $options{'resource-group'});
}

sub add_nsg_rule {
    my $resource_group = shift;
    my @hosts = @_;

    die "Resource gorup is empty" if not $resource_group;
    return if not @hosts;

    my $nsg_output = checked_output(qw(az network nsg list --query [].name --output tsv --resource-group), $resource_group);
    my @master_nsgs = grep { /^k8s-master-/ } split(/\r?\n/, $nsg_output);
    if (not @master_nsgs) {
        log_warning("No Kubernetes master network security group found in resource group $resource_group.");
    } else {
        log_info("Found master network security group(s) in resource group $resource_group: " . join(', ', @master_nsgs));
        for my $host (@hosts) {
            $host =~ s/^\s+|\s+$//g;
            if ($host !~ /^\d+(\.\d+){3}$/) {
                my $ip = inet_ntoa(inet_aton($host));
                log_info("Resolved $host to ip address $ip");
                $host = $ip;
            }
            my $name = 'allow_' . join('_', $host =~ /([\w\d]+)/g) . '_' . Helpers::random_string();
            for my $nsg (@master_nsgs) {
                # chose a fixed priority 2017. it is not ideal but should be enough for the smoke test
                checked_run(qw(az network nsg rule create --priority 2017 --destination-port-ranges 22),
                    '--resource-group', $resource_group,
                    '--nsg-name', $nsg,
                    '--name', $name,
                    '--source-address-prefixes', $host);
            }
        }
    }
}

if (!$options{k8sName}) {
    $options{k8sDns} = 'a'. Helpers::random_string(10);
    $options{k8sName} = 'containerservice-' . $options{'resource-group'};
    process_file("$Bin/../conf/acs.parameters.json", File::Spec->catfile($options{targetDir}, 'conf'), \%options);
    checked_run(qw(az group deployment create --template-uri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-acs-kubernetes/azuredeploy.json),
        '--resource-group', $options{'resource-group'}, '--parameters', '@' . File::Spec->catfile($options{targetDir}, "conf/acs.parameters.json"));

    add_nsg_rule($options{'resource-group'}, @{$options{nsgAllowHost}});
    # CLI doesn't support creation with existing service principal
    #checked_run(qw(az acs create --orchestrator-type kubernetes --agent-count 1 --resource-group), $options{'resource-group'}, '--name', $options{k8sName}, '--ssh-key-value', $options{publicKeyFile});
} else {
    $options{k8sDns} = $options{k8sName};
}

$options{'k8s-master-host'} = checked_output(qw(az acs show --query masterProfile.fqdn --output tsv -g), $options{'resource-group'}, '-n', $options{k8sName});
throw_if_empty('K8s master host', $options{'k8s-master-host'});

if (!$options{acrName}) {
    $options{acrName} = 'acr' . Helpers::random_string();
    checked_run(qw(az acr create --sku Basic --admin-enabled true --resource-group), $options{'resource-group'}, '--name', $options{acrName});
}

$options{acrHost} = checked_output(qw(az acr show --query loginServer --output tsv --resource-group), $options{'resource-group'}, '--name', $options{acrName});
$options{acrPassword} = checked_output(qw(az acr credential show --query passwords[0].value --output tsv --name), $options{acrName});

{
    local $main::verbose;
    checked_run(qw(docker login -u), $options{acrName}, '-p', $options{acrPassword}, $options{acrHost});
}
$options{acrPrivateImageName} = $options{acrHost} . '/nginx-private';
checked_run(qw(docker pull nginx));
checked_run(qw(docker tag nginx), $options{acrPrivateImageName});
checked_run(qw(docker push), $options{acrPrivateImageName});

find(sub {
    if (-d $_) {
        return;
    }
    my $file = abs_path($File::Find::name);
    if ($file =~ /^\Q$options{targetDir}\E/ || $file =~ qr{/\.target\b}
        || $file =~ /^\Q$options{artifactsDir}\E/ || $file =~ qr{/\.artifacts\b}) {
        return;
    }
    my $rel = File::Spec->abs2rel($File::Find::name, "$Bin/..");
    my $target_dir = File::Spec->catfile($options{targetDir}, dirname($rel));
    process_file($file, $target_dir, \%options);
}, "$Bin/..");
chdir $options{targetDir};

$options{dockerProcessName} = 'smoke-' . Helpers::random_string();

my $jenkins_home = File::Spec->catfile($options{targetDir}, "jenkins_home");
make_path($options{artifactsDir});
remove_tree($jenkins_home);
make_path($jenkins_home);
chmod 0777, $jenkins_home;

# TODO Change to IPC::Open3
# we do not have pseudo TTY when running in Jenkins
# We cannot run with "docker -t" in Jenkins, as a result, the STDOUT of the main process will be buffered
# and output when the child process termiates, rather than interleaved.
my $jenkins_pid = fork();
if (!$jenkins_pid) {
    copy("$options{targetDir}/groovy/init.groovy", "$jenkins_home/init.groovy");
    my @commands = (qw(docker run -i -p8090:8080),
        '-v', "$jenkins_home:/var/jenkins_home",
        '-v', "$options{targetDir}:/opt",
        '--name', $options{dockerProcessName},
        $options{image});
    my $command = list2cmdline(@commands);
    print_banner("Start Jenkins in Docker");
    log_info($command);
    exec { $commands[0] } @commands;
    exit 0;
}
log_info("Jenkins process pid: $jenkins_pid, docker container process name: $options{dockerProcessName}");

my @jobs = map { basename($_, '.xml') } glob 'jobs/*.xml';
my %status_for_job;
my $remaining_job = @jobs;

sub read_link {
    my ($file) = @_;
    if (-l $file) {
        return readlink($file) || -1;
    } else {
        return -1;
    }
}

while (1) {
    print "\r\n\n";
    print_banner("Check Build Status");
    for my $job (@jobs) {
        my $job_home = File::Spec->catfile($jenkins_home, 'jobs', $job);
        if (not -e $job_home) {
            print "$job - missing\r\n";
            next;
        }
        my $builds_home = File::Spec->catfile($job_home, 'builds');
        if (not -e $builds_home) {
            print "$job - no build\r\n";
            next;
        }
        my $lastSuccessfulBuild = read_link(File::Spec->catfile($builds_home, 'lastSuccessfulBuild'));
        my $lastUnsuccessfulBuild = read_link(File::Spec->catfile($builds_home, 'lastUnsuccessfulBuild'));
        if ($lastUnsuccessfulBuild > 0) {
            print "$job - failed\r\n";
            if (not exists $status_for_job{$job}) {
                --$remaining_job;
            }
            $status_for_job{$job} = 'failed';
            copy(File::Spec->catfile($builds_home, $lastUnsuccessfulBuild, 'log'), File::Spec->catfile($options{artifactsDir}, "$job.log"));
        } elsif ($lastSuccessfulBuild > 0) {
            print "$job - successful\r\n";
            if (not exists $status_for_job{$job}) {
                --$remaining_job;
            }
            $status_for_job{$job} = 'successful';
            copy(File::Spec->catfile($builds_home, $lastSuccessfulBuild, 'log'), File::Spec->catfile($options{artifactsDir}, "$job.log"));
        } else {
            print "$job - building\r\n";
        }
    }
    print "\r\n";

    if ($remaining_job <= 0) {
        last;
    }

    sleep 20;
}

log_info("Send SIGINT to the Jenkins docker container process with pid $jenkins_pid...");
kill 'INT', $jenkins_pid;

log_info("Kill docker process $options{dockerProcessName}...");
checked_run(qw(docker kill), $options{dockerProcessName});

log_info("Wait for the process with pid $jenkins_pid to terminate...");
waitpid $jenkins_pid, 0;

my $final_result = 0;
print_banner("Build Result");
for my $job (keys %status_for_job) {
    my $status = $status_for_job{$job};
    if ($status eq 'successful') {
        log_info("$job - $status");
    } else {
        log_error("$job - $status");
        $final_result = 1;
    }
}

log_info("\r\n\r\nArtifacts copied to $options{artifactsDir}");

exit $final_result;

sub END {
    return if not $options{clean};

    if ($options{'resource-group'}) {
        run_shell(qw(az group delete -y --no-wait -n), $options{'resource-group'});
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
   --adminUser                  The user name to login to ACS cluster master or other VM
   --publicKeyFile              The public key file used to create ACS cluster or other VM resources
   --privateKeyFile             The private key file used to authenticate with ACS cluster master or other VM resources

   --resource-group             The resource group that contains all the related resources
                                It will be generated and created if not provided
   --location                   The resource location for all the resources, default "Southeast Asia"
   --k8sName                    The ACS resource name with Kubernetes orchestrator
   --acrName                    The Azure Container Registry resource name

   --targetDir                  The directory to store all the geneated resources
   --artifactDir                The directory to store the build artifacts

   --testConfigRepo             Repository URL for the test configs, default "https://github.com/azure-devops/ci.git"
   --testConfigBranch           Branch of the test configs, default "master"
   --testConfigRoot             Root directory for all the test configs, default "smoke/test-configs"

   --nsgAllowHost               Comma separated hosts that needs to be allowed for SSH access in the newly
                                created Kubernetes master network security group

 <Miscellaneous>
   --verbose                    Turn on verbose output
   --help                       Show the help documentation
   --version                    Show the script version

=cut
