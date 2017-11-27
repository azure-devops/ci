#!/usr/bin/env perl
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

#===============================================================================
#         FILE:  prepare-image.pl
#
#  DESCRIPTION:  Build Jenkins docker image with all Azure Jenkins plugins installed.
#                You may also specify some of the plugins to be built from source.
#
#      CREATED:  2017-11-15 08:46
#===============================================================================
use strict;
use warnings;

package main;

use FindBin qw($Bin);
use lib "$Bin/../../lib/perl";
use Builder;
use Getopt::Long qw(:config gnu_getopt no_ignore_case auto_version auto_help);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Helpers qw(:log :shell throw_if_empty process_file);
use Pod::Usage;

my @plugins = qw(
    azure-commons
    azure-credentials
    kubernetes-cd
    azure-acs
    windows-azure-storage
    azure-container-agents
    azure-vm-agents
    azure-app-service
    azure-function
);

my %repo_of = map { ($_, "https://github.com/jenkinsci/$_-plugin.git") } @plugins;

my %options = (
    'jenkins-version' => 'lts',
    'build-plugin' => [],
    verbose => 1,
);

GetOptions(\%options,
    'tag|t=s',
    'jenkins-version|j=s',
    'build-plugin|b=s@',
    'verbose!'
) or pod2usage(2);

our $verbose = $options{verbose};

throw_if_empty("Docker image tag", $options{tag});

@{$options{'build-plugin'}} = split(/,/, join(',', @{$options{'build-plugin'}}));
for (@{$options{'build-plugin'}}) {
    my ($id, $repo) = split(/=/, $_, 2);
    if ($repo) {
        log_info("Set repository of $id to $repo");
        $repo_of{$id} = $repo;
        # update the value in-place via the alias
        $_ = $id;
    }
}

print Data::Dumper->Dump([\%options, \%repo_of], ['options', 'repositories']);

my $docker_root = "$Bin/../.target/docker-build";
my $plugin_dir = File::Spec->catfile($docker_root, 'plugins');
my $git_root = "$Bin/../.target/git-repo";
remove_tree($docker_root, $git_root);
make_path($git_root, $plugin_dir);
for my $plugin (@{$options{'build-plugin'}}) {
    my $repo = $repo_of{$plugin};
    if (not $repo) {
        die "Cannot find repository for plugin $plugin";
    }
    my $hpi = Builder::build($plugin, $git_root, $repo);
    copy($hpi, File::Spec->catfile($plugin_dir, basename($hpi, '.hpi') . '.jpi'))
        or die "Cannot copy $hpi to $plugin_dir: $!";
}

$options{'all-plugins-list'} = list2cmdline(@plugins);
$options{'built-plugins'} = list2cmdline(@{$options{'build-plugin'}});
$options{'docker-copy-jpi'} = @{$options{'build-plugin'}} ? q{COPY plugins/*.jpi "$PLUGIN_DIR"} : "";

process_file("$Bin/../Dockerfile", $docker_root, \%options);
my $resolve_dependencies = File::Spec->catfile($docker_root, 'resolve-dependencies.sh');
copy("$Bin/../bash/resolve-dependencies.sh", $resolve_dependencies);
chmod 0755, $resolve_dependencies;

chdir $docker_root;

checked_run(qw(docker build -t), $options{tag}, '.');

__END__

=head1 NAME

prepare-image.pl - Script to build the Jenkins docker image with the Azure Jenkins plugins installed,
                   either from update center or build from source.

=head1 SYNOPSIS

prepare-image.pl [options]

 Options:
   --tag|-t                 The tag for the result image
   --jenkins-version|-j     The base Jenkins image version, default 'lts'
   --build-plugin|-b        Comma separated list of Azure Jenkins plugin IDs that needs to be build 
                            from source and installed to the result image. It can be applied multiple times.
                            The default source repository is the GitHub jenkinsci repository, which can 
                            be override with 'plugin-id=repo-url', e.g.,
                                --build-plugin azure-commons -b azure-credentials=https://my.repo.address
   
   --[no]verbose            Turn on/off the verbose output, default on
   --help                   Show the help documentation

=cut

