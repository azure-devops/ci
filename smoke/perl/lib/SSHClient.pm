package SSHClient;

use strict;
use warnings FATAL => 'all';

use Helpers qw(:log :shell throw_if_empty);

sub new {
    my $class = shift;
    my ($host, $port, $user, $key) = @_;
    throw_if_empty("SSH host", $host);
    throw_if_empty("SSH user", $user);
    throw_if_empty("SSH private key file path", $key);

    my $self = {
        host => $host,
        port => $port,
        user => $user,
        key => $key,
    };

    bless $self, $class;
    $self;
}

sub run {
    my $self = shift;

    checked_run($self->base_ssh_command, @_);
}

sub output {
    my $self = shift;

    checked_output($self->base_ssh_command, @_);
}

sub copy_to {
    my $self = shift;
    my ($local, $remote) = @_;

    checked_run($self->base_scp_command, $local, $self->login_host . ':' . $remote);
}

sub copy_from {
    my $self = shift;
    my ($remote, $local) = @_;

    checked_run($self->base_scp_command, $self->login_host . ':' . $remote, $local);
}

sub login_host {
    my $self = shift;

    $self->{user} . '@' . $self->{host};
}

sub base_ssh_command {
    my $self = shift;
    'ssh', '-p', $self->{port}, '-i', $self->{key}, '-o', 'StrictHostKeyChecking=no', $self->login_host, '--';
}

sub base_scp_command {
    my $self = shift;
    'scp', '-P', $self->{port}, '-i', $self->{key}, '-o', 'StrictHostKeyChecking=no';
}

1;
