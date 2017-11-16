#!/usr/bin/env perl
#===============================================================================
#         FILE:  build-plugin.pl
#
#  DESCRIPTION:  
#
#       AUTHOR:  ArieShout, arieshout@gmail.com
#      CREATED:  2017-11-15 08:13
#===============================================================================
use strict;
use warnings FATAL => 'all';

use FindBin qw($Bin);
use lib "$Bin/lib";
use Builder;
use Helpers qw(:log :shell throw_if_empty);
use Getopt::Long qw(:config gnu_getopt no_ignore_case);
use File::Path qw(remove_tree make_path);
use File::Spec;

my ($id, $repo);
my $branch = 'dev';

GetOptions(
    "id|p=s" => \$id,
    "repo|r=s" => \$repo,
);

throw_if_empty("Plugin ID", $id);
throw_if_empty("Plugin Repository", $repo);

my $root = "$Bin/../git";

print Builder::build('azure-commons', $root, 'https://github.com/jenkinsci/azure-commons-plugin.git'), "\n";

