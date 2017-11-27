# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

# Helper methods to provision Azure resources
package Provisioner;

use strict;
use warnings FATAL => 'all';

use Helpers qw(:log :shell);
use Socket;

use base qw(Exporter);

our @EXPORT_OK = qw(ensure_resource_group ensure_acs ensure_acr ensure_webapp ensure_function ensure_nsg ensure_nsg_access add_k8s_nsg_rule);

our @created_resource_groups;

sub ensure_resource_group {
    my ($name, $location) = @_;

    my $exists = checked_output(qw(az group exists --name), $name);
    if ($exists eq 'false') {
        checked_run(qw(az group create --name), $name, '--location', $location);
        push @created_resource_groups, $name;
    }
}

sub ensure_acs {
    my ($resource_group, $name, $parameters_file) = @_;

    my $info = checked_output(qw(az acs show --resource-group), $resource_group, '--name', $name);
    if ($info =~ /^\s*$/) {
        checked_run(qw(az group deployment create --template-uri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-acs-kubernetes/azuredeploy.json),
            '--resource-group', $resource_group, '--parameters', '@' . $parameters_file);

        # CLI doesn't support creation with existing service principal
        #checked_run(qw(az acs create --orchestrator-type kubernetes --agent-count 1 --resource-group), $options{'resource-group'}, '--name', $options{k8sName}, '--ssh-key-value', $options{publicKeyFile});
    }

    checked_output(qw(az acs show --query masterProfile.fqdn --output tsv -g), $resource_group, '-n', $name);
}

sub ensure_acr {
    my ($resource_group, $acr_name) = @_;

    my $info = checked_output(qw(az acr show --resource-group), $resource_group, '--name', $acr_name);
    if ($info =~ /^\s*$/) {
        checked_run(qw(az acr create --sku Basic --admin-enabled true),
            '--resource-group', $resource_group, '--name', $acr_name);
    }

    my $host = checked_output(qw(az acr show --query loginServer --output tsv --resource-group), $resource_group, '--name', $acr_name);
    my $password = checked_output(qw(az acr credential show --query passwords[0].value --output tsv --name), $acr_name);

    ($host, $password);
}

sub ensure_webapp {
    my ($resource_group, $plan, $webapp, $is_linux) = @_;

    my $plan_info = checked_output(qw(az appservice plan show --resource-group), $resource_group, '--name', $plan);
    if ($plan_info =~ /^\s*$/) {
        my @command_line = (qw(az appservice plan create --sku S1 --resource-group), $resource_group, '--name', $plan);
        if ($is_linux) {
            push @command_line, '--is-linux';
        }
        checked_run(@command_line);
    }

    # there's some bug with 'webapp show', we cannot use it to check the existence
    #my $webapp_missing = run_shell(qw(az webapp show --resource-group), $resource_group, '--name', $webapp);
    my $webapp_list = checked_output(qw(az webapp list --query [].name --output tsv --resource-group), $resource_group);
    if ($webapp_list !~ /^\Q$webapp\E$/sm) {
        my @command_line = (qw(az webapp create),
            '--resource-group', $resource_group,
            '--name', $webapp,
            '--plan', $plan);
        if ($is_linux) {
            push @command_line, '--deployment-container-image-name', 'nginx';
        } else {
            push @command_line, '--runtime', 'node|6.10';
        }
        checked_run(@command_line);
    }

    if (not $is_linux) {
        # create staging slot for Windows WebApp
        my $slots = checked_output(qw(az webapp deployment slot list --query [].name --output tsv),
            '--resource-group', $resource_group,
            '--name', $webapp);
        if ($slots !~ /^staging$/sm) {
            checked_run(qw(az webapp deployment slot create --slot staging),
                '--resource-group', $resource_group,
                '--name', $webapp);
        }
    }
}

sub ensure_function {
    my ($resource_group, $account, $func) = @_;

    my $location = checked_output(qw(az group show --query location --output tsv --name), $resource_group);

    my $acc_info = checked_output(qw(az storage account show --resource-group), $resource_group, '--name', $account);
    if ($acc_info =~ /^\s*$/) {
        checked_run(qw(az storage account create --sku Standard_LRS),
            '--resource-group', $resource_group, '--name', $account, '--location', $location);
    }

    my $func_missing = run_shell(qw(az functionapp show --resource-group), $resource_group, '--name', $func);
    if ($func_missing) {
        checked_run(qw(az functionapp create --deployment-source-url https://github.com/Azure-Samples/functions-quickstart),
            '--resource-group', $resource_group,
            '--name', $func,
            '--storage-account', $account,
            '--consumption-plan-location', $location);
    }
}

sub ensure_nsg {
    my ($resource_group, $nsg) = @_;

    my $nsg_info = checked_output(qw(az network nsg show --resource-group), $resource_group, '--name', $nsg);
    if ($nsg_info =~ /^\s*$/) {
        checked_run(qw(az network nsg create --resource-group), $resource_group, '--name', $nsg);
    }
}

sub next_nsg_priority {
    my ($resource_group, $nsg) = @_;

    my $priorities = checked_output(qw(az network nsg rule list --query [].priority --output tsv),
        '--resource-group', $resource_group, '--nsg-name', $nsg);
    my %used_priority = map { s/^\s+|\s+$//g; ($_, 1) } split(/\r?\n/, $priorities);

    for my $priority (100..4096) {
        if (not exists $used_priority{$priority}) {
            return $priority;
        }
    }

    die "Unable to find available priority value in NSG $resource_group/$nsg";
}

sub ensure_nsg_access {
    my ($resource_group, $nsg, @hosts) = @_;

    for my $host (@hosts) {
        $host =~ s/^\s+|\s+$//g;
        if ($host !~ /^\d+(\.\d+){3}$/) {
            my $ip = inet_ntoa(inet_aton($host));
            log_info("Resolved $host to ip address $ip");
            $host = $ip;
        }
        my $name = 'allow_' . join('_', $host =~ /([-_\w\d\.]+)/g) . '_22';
        my $rule_exists = checked_output(qw(az network nsg rule show),
            '--resource-group', $resource_group,
            '--nsg-name', $nsg,
            '--name', $name);
        if ($rule_exists !~ /^\s*$/) {
            next;
        }

        my $created = 0;
        for (1..5) {
            my $priority = next_nsg_priority($resource_group, $nsg);

            my $ret = run_shell(qw(az network nsg rule create --destination-port-ranges 22),
                '--resource-group', $resource_group,
                '--nsg-name', $nsg,
                '--name', $name,
                '--source-address-prefixes', $host,
                '--priority', $priority);

            if ($ret == 0) {
                $created = 1;
                last;
            }
            log_warning("Unable to create NSG exceptional rule for host $host in $resource_group/$nsg, retry after 5 seconds");
            sleep 5;
        }

        if (not $created) {
            die "Failed to create NSG exceptional rule for host $host in $resource_group/$nsg";
        }
    }
}

sub add_k8s_nsg_rule {
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

        for my $nsg (@master_nsgs) {
            ensure_nsg_access($resource_group, $nsg, @hosts);
        }
    }
}

1;
