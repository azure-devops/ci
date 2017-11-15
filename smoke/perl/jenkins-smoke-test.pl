#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

package main;

use FindBin qw($Bin);
use lib "$Bin/lib";
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

use Data::Dumper;

our $VERSION = 0.1.0;

our %options = (
    verbose => 1,
    subscriptionId => $ENV{AZURE_SUBSCRIPTION_ID},
    clientId => $ENV{AZURE_CLIENT_ID},
    clientSecret => $ENV{AZURE_CLIENT_SECRET},
    tenantId => $ENV{AZURE_TENANT_ID},
    adminUser => 'azureuser',
);

GetOptions(\%options,
    'subscriptionId|s=s',
    'clientId|u=s',
    'clientSecret|p=s',
    'tenantId|t=s',
    'resource-group|g=s',
    'location|l=s',
    'vmName=s',
    'adminUser=s',
    'publicKeyFile=s',
    'privateKeyFile=s',
    'k8sName=s',
    'acrName=s',
    'targetDir=s',
    'artifactsDir=s',
    'clean!',
    'verbose!',
);

if (not exists $options{targetDir}) {
    $options{targetDir} = File::Spec->catfile(abs_path("$Bin/.."), ".target-" . Helpers::random_string());
}

if (not exists $options{artifactsDir}) {
    $options{artifactsDir} = File::Spec->catfile(abs_path("$Bin/.."), ".artifacts");
}

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

my $generated_key = 0;
if (not exists $options{publicKeyFile} or not exists $options{privateKeyFile}) {
    $options{privateKeyFile} = File::Spec->catfile(abs_path("$Bin/.."), ".ssh/id_rsa");
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

log_info("Remove all contents in $options{targetDir}");
remove_tree($options{targetDir});
make_path($options{targetDir});

{
    local $main::verbose = 0;
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

if (!$options{k8sName}) {
    $options{k8sDns} = Helpers::random_string(10);
    $options{k8sName} = 'containerserivce-' . $options{k8sDns};
    process_file("$Bin/../conf/acs.parameters.json", File::Spec->catfile($options{targetDir}, 'conf'), \%options);
    checked_run(qw(az group deployment create --template-uri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-acs-kubernetes/azuredeploy.json),
        '--resource-group', $options{'resource-group'}, '--parameters', '@' . File::Spec->catfile($options{targetDir}, "conf/acs.parameters.json"));
#    checked_run(qw(az acs create --orchestrator-type kubernetes --agent-count 1 --resource-group), $options{'resource-group'}, '--name', $options{k8sName}, '--ssh-key-value', $options{publicKeyFile});
} else {
    $options{k8sDns} = $options{k8sName};
}

if (!$options{acrName}) {
    $options{acrName} = 'acr' . Helpers::random_string();
    checked_run(qw(az acr create --sku Basic --admin-enabled true --resource-group), $options{'resource-group'}, '--name', $options{acrName});
}

$options{acrHost} = checked_output(qw(az acr show --query loginServer --output tsv --resource-group), $options{'resource-group'}, '--name', $options{acrName});
$options{acrPassword} = checked_output(qw(az acr credential show --query passwords[0].value --output tsv --name), $options{acrName});

find(sub {
    if (-d $_) {
        return;
    }
    my $file = abs_path($File::Find::name);
    if ($file =~ /^\Q$options{targetDir}\E/ || $file =~ /\.target/
        || $file =~ /^\Q$options{artifactsDir}\E/ || $file =~ /\.artifacts/) {
        return;
    }
    my $rel = File::Spec->abs2rel($File::Find::name, "$Bin/..");
    my $target_dir = File::Spec->catfile($options{targetDir}, dirname($rel));
    process_file($file, $target_dir, \%options);
}, "$Bin/..");
chdir $options{targetDir};

$options{jenkinsImage} = 'smoke-' . Helpers::random_string();
$options{dockerProcessName} = 'smoke-' . Helpers::random_string();

checked_run(qw(docker build -t), $options{jenkinsImage}, '.');

my $jenkins_home = File::Spec->catfile($options{targetDir}, "jenkins_home");
make_path($options{artifactsDir});
make_path($jenkins_home);
chmod 0777, $jenkins_home;

# TODO Change to IPC::Open3
# we do not have pseudo TTY when running in Jenkins
# We cannot run with "docker -t" in Jenkins, as a result, the STDOUT of the main process will be buffered
# and output when the child process termiates, rather than interleaved.
my $jenkins_pid = fork();
if (!$jenkins_pid) {
    my @commands = (qw(docker run -i -p8090:8080 -v), "$jenkins_home:/var/jenkins_home", '--name', $options{dockerProcessName}, $options{jenkinsImage});
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
                                (Azure service principal <required>)
   --subscriptionId|-s          subscription ID
   --clientId|-u                client ID
   --clientSecret|-p            client secret
   --tenantId|-t                tenant ID

                                (Miscellaneous)
   --verbose                    Turn on verbose output
   --help                       Show the help documentation
   --version                    Show the script version

=cut
