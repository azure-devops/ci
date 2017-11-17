# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

package JenkinsCli;

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";
use File::Copy;
use File::Spec;
use File::Temp qw(tempfile);
use Helpers qw(:log retry_until_successful list2cmdline);
use IO::Select qw();
use IPC::Open3 qw(open3);
use Symbol;

sub new {
    my ($class, %params) = shift;

    my $self = {
        url => 'http://localhost:8080/',
        username => 'admin',
        password => '',
    };

    (undef, $self->{jar}) = tempfile('jenkins-cli-XXXXXX', SUFFIX => '.jar', OPEN => 0);

    for my $key (keys %$self) {
        if (exists $params{$key}) {
            $self->{$key} = $params{$key};
        }
    }
    if ($self->{url} !~ qr|/$|) {
        $self->{url} .= '/';
    }

    bless $self, $class;
    $self->_fetch_cli_jar();
    $self->_initialize_password();

    return $self;
}

sub run {
    my $self = shift;
    my (@args) = @_;

    my @commands = ();
    my $input_file;
    for (my $i = 0; $i <= $#args; ++$i) {
        my $arg = $args[$i];
        if ($arg eq 'STDIN') {
            $input_file = $args[$i+1];
            last;
        } else {
            push @commands, $arg;
        }
    }

    my @command_line = (
        'java',
        '-jar',
        $self->{jar},
        '-s',
        $self->{url},
        '-auth',
        qq|$self->{username}:$self->{password}|,
        @commands
    );

    if ($main::verbose) {
        log_info(list2cmdline(@commands));
    }

    my ($in, $out, $err);
    $err = gensym();

    my $pid = open3($in, $out, $err, @command_line);
    if (defined $input_file) {
        open my $fh, '<', $input_file or die "Cannot open file $input_file.\n";
        binmode $fh;
        copy($fh, $in);
    }
    close $in;

    my $sel = IO::Select->new();
    $sel->add($out);
    $sel->add($err);

    my $data;
    while (my @ready = $sel->can_read()) {
        for my $handle (@ready) {
            my $bytes = sysread($handle, $data, 4096);
            if ($bytes > 0) {
               if (fileno($handle) == fileno($out)) {
                    print $data;
                } else {
                    print STDERR $data;
                }
            } elsif ($bytes == 0) {
                $sel->remove($handle);
            } else {
                log_error("Error reading output of command " . join(" ", @commands));
                $sel->remove($handle) if eof($handle);
            }
        }
    }
    waitpid $pid, 0;

    if ($? != 0) {
        die "$? - Failed to execute Jenkins command: " . join(' ', @commands) . "\n";
    }
}

sub install_plugin {
    my $self = shift;
    my $plugin = shift;
    my %options = @_;

    my @command = ('install-plugin', $plugin);
    if ($options{deploy}) {
        push @command, '-deploy';
    }
    if (exists $options{name}) {
        push @command, '-name', $options{name};
    }
    $self->run(@command);
}

sub _fetch_cli_jar {
    my $self = shift;

    if (-s $self->{jar}) {
        return;
    }
    
    log_info("Fetch Jenkins CLI jar file to: $self->{jar}");
    retry_until_successful('wget', "$self->{url}jnlpJars/jenkins-cli.jar", '-O', $self->{jar});
}

sub _initialize_password {
    my $self = shift;

    if (not $self->{password}) {
        my $password = qx(sudo cat /var/lib/jenkins/secrets/initialAdminPassword);
        chomp $password;
        $self->{password} = $password;
    }
}

sub DESTROY {
    my $self = shift;
    log_info("Delete Jenkins CLI jar file: $self->{jar}");
    unlink $self->{jar};
}

1;

