# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

package JenkinsMonitor;

use strict;
use warnings FATAL => 'all';

use File::Copy;
use File::Glob qw(:bsd_glob);
use File::Path qw(make_path);
use File::Spec;
use Helpers qw(:log :shell);
use IO::Select;
use IPC::Open3;
use Symbol;

sub new {
    my $class = shift;
    my ($jenkins_home, $artifacts_dir, $init) = @_;

    my $self = {
        home => $jenkins_home,
        artifactsDir => $artifacts_dir,
        status => {},
    };

    if ($init) {
        copy($init, File::Spec->catfile($self->{home}, 'init.groovy'));
    }

    bless $self, $class;
}

sub start {
    my $self = shift;
    my @command_line = @_;

    my $command = list2cmdline(@command_line);
    print_banner("Starting Jenkins...");
    log_info($command);

    $self->{err} = gensym();
    $self->{pid} = open3($self->{in}, $self->{out}, $self->{err}, @command_line);
    close($self->{in});
    log_info("Jenkins process pid: $self->{pid}");
}

sub monitor {
    my $self = shift;
    my ($sub_check_timeout, $jobs) = @_;

    my $sel = IO::Select->new();
    $sel->add($self->{out});
    $sel->add($self->{err});

    my $buffer;
    my $last_checked_time = time();

    while (1) {
        $sub_check_timeout->();

        my @ready = $sel->can_read(5);
        for my $handle (@ready) {
            my $bytes = sysread($handle, $buffer, 4096);
            if ($bytes > 0) {
                # redirect output to STDOUT, regardless whether they come from STDOUT or STDERR of the child process
                # Jenkins will hold the STDOUT messages if it sees the STDERR messages, as a result,
                # our logging to STDOUT may not be displayed in the console page until after a period of time.
                print $buffer;
            } elsif ($bytes == 0) {
                $sel->remove($handle);
            } else {
                log_error("Error reading output of the Docker Jenkins process.");
                $sel->remove($handle);
            }
        }

        my $current_time = time();
        if ($current_time - $last_checked_time > 20) {
            my $remaining = $self->collect_job_status($jobs);
            $last_checked_time = $current_time;

            if ($remaining <= 0) {
                last;
            }
        }

        if ($sel->count() <= 0) {
            last;
        }
    }
}

sub _dump_status {
    my $self = shift;

    my $final_result = 0;
    print_banner("Build Result");
    for my $job (keys %{$self->{status}}) {
        my $status = $self->{status}{$job};
        if ($status eq 'successful') {
            log_info("$job - $status");
        } else {
            log_error("$job - $status");
            $final_result = 1;
        }
    }

    $final_result;
}

sub terminate {
    my $self = shift;

    my $pid = $self->{pid};

    log_info("Send SIGTERM to the Jenkins docker container process with pid $pid...");
    kill 'TERM', $pid;

    log_info("Wait for the process with pid $pid to terminate...");
    waitpid $pid, 0;

    $self->_dump_status();
}

sub collect_job_status {
    my $self = shift;
    my ($jobs) = @_;

    my $remaining = 0;

    print "\r\n\r\n";
    print_banner("Check Build Status");
    for my $job (@$jobs) {
        my $job_home = File::Spec->catfile($self->{home}, 'jobs', $job);
        if (not -e $job_home) {
            print "$job - missing\r\n";
            ++$remaining;
            next;
        }
        my $builds_home = File::Spec->catfile($job_home, 'builds');
        if (not -e $builds_home) {
            print "$job - no build\r\n";
            ++$remaining;
            next;
        }
        my $lastSuccessfulBuild = _read_link_number(File::Spec->catfile($builds_home, 'lastSuccessfulBuild'));
        my $lastUnsuccessfulBuild = _read_link_number(File::Spec->catfile($builds_home, 'lastUnsuccessfulBuild'));
        if ($lastUnsuccessfulBuild > 0) {
            print "$job - failed\r\n";
            if (not exists $self->{status}{$job}) {
                copy(File::Spec->catfile($builds_home, $lastUnsuccessfulBuild, 'log'), File::Spec->catfile($self->{artifactsDir}, "$job.log"));
            }
            $self->{status}{$job} = 'failed';
        } elsif ($lastSuccessfulBuild > 0) {
            print "$job - successful\r\n";
            if (not exists $self->{status}{$job}) {
                copy(File::Spec->catfile($builds_home, $lastSuccessfulBuild, 'log'), File::Spec->catfile($self->{artifactsDir}, "$job.log"));
            }
            $self->{status}{$job} = 'successful';
        } else {
            print "$job - building\r\n";
            ++$remaining;
        }
    }
    print "\r\n";

    $remaining;
}

sub _read_link_number {
    my ($file) = @_;
    if (-l $file) {
        return readlink($file) || -1;
    } else {
        return -1;
    }
}

sub DESTROY {
    my $self = shift;

    log_info("Copy slave logs to artifacts...");
    if (defined $self->{home} && -d $self->{artifactsDir}) {
        log_info("Copy out the slave logs...");
        for my $slave_log (bsd_glob(File::Spec->catfile($self->{home}, 'logs/slaves/*/slave.log'))) {
            log_info("Copy $slave_log...");
            if ($slave_log =~ qr{([^/]+)/slave\.log$}) {
                copy($slave_log, File::Spec->catfile($self->{artifactsDir}, "$1.log"));
            }
        }
    }
    log_info("\r\n\r\nArtifacts copied to $self->{artifactsDir}");
}

1;
