#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2022 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict;
use warnings;
use Getopt::Long;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Application::AppUtils;

my $U = 'OpenILS::Application::AppUtils';
$ENV{OSRF_LOG_CLIENT} = 1;

my $osrf_config = '/openils/conf/opensrf_core.xml';
my $ids_file;
my $process_as = 'admin';
my $min_id = 0;
my $max_id;
my $has_open_circ = 0;
my @included_penalties;
my $owes_more_than;
my $owes_less_than;
my $has_penalty;
my $home_ou_context;
my $no_has_penalty;
my $verbose;
my $help;
my $batch_size = 100;
my $authtoken;
my $auth_user_home;
my $e;

my $ops = GetOptions(
    'osrf-config=s'     => \$osrf_config,
    'ids-file=s'        => \$ids_file,
    'process-as=s'      => \$process_as,
    'min-id=s'          => \$min_id,
    'max-id=s'          => \$max_id,
    'has-open-circ'     => \$has_open_circ,
    'owes-more-than=s'  => \$owes_more_than,
    'owes-less-than=s'  => \$owes_less_than,
    'has-penalty=s'     => \$has_penalty,
    'no-has-penalty=s'  => \$no_has_penalty,
    'include-penalty=s' => \@included_penalties,
    'patron-home-context'   => \$home_ou_context,
    'verbose'           => \$verbose,
    'help'              => \$help
);

sub help {
    print <<HELP;

    Synopsis:
        Update patron penalties in batch with options for filtering which
        patrons to process.

    Usage:

        $0

        --osrf-config [/openils/conf/opensrf_core.xml]

        --process-as <eg-account>
            Username of an Evergreen account to use for creating the
            internal auth session.  Defaults to 'admin'.

        --patron-home-context
            Use each user's home library as the penalty calculation
            context. Otherwise the home library of the --process-as user
            is used to identify the thresholds and custom penalties to
            process.

        --has-penalty <penalty-name-or-id>
            Limit to patrons that currently have a specific penalty. If
            an id is specified, only that exact penalty is checked. If
            a name is supplied, the system will check for a custom penalty
            configured for use at the selected users' home libraries.

        --no-has-penalty <penalty-name-or-id>
            Limit to patrons that do not currently have a specific penalty.
            If an id is specified, only that exact penalty is checked. If
            a name is supplied, the system will check for a custom penalty
            configured for use at the selected users' home libraries.

        --include-penalty <penalty-name-or-id>
            Limit to a specific penalty.  Specify multiple times for
            multiple penalties. If an id is specified, only the exact
            penalties will be calculated.  Custom penalties will be looked
            up as needed if a name is supplied.

        --min-id <id>
            Lowest patron ID to process. 

        --max-id <id>
            Highest patron ID to process. 

            Together with --min-id, these are useful for running parallel
            batches of this script without overlapping and/or processing
            chunks of a controlled size.

        --has-open-circ
            Limit to patrons that have at least on open circulation.
            For simplicity, "open" in this context means null xact finish.

        --owes-more-than <amount>
            Limit to patrons who have an outstanding balance greater than
            the specified amount.

        --owes-less-than <amount>
            Limit to patrons who have an outstanding balance less than
            the specified amount.

        --verbose
            Log debug info to STDOUT.  This script logs various information
            via \$logger regardless of this option.

        --help
            Show this message.
HELP
    exit 0;
}

help() if $help or !$ops;

# $lvl should match a $logger logging function.  E.g. 'info', 'error', etc.
sub announce {
    my $lvl = shift;
	my $msg = shift;
    $logger->$lvl($msg);

    # always announce errors and warnings
    return unless $verbose || $lvl =~ /error|warn/;

    my $date_str = DateTime->now(time_zone => 'local')->strftime('%F %T');
    print "$date_str $msg\n";
}

sub get_user_ids {
    my ($limit, $offset) = @_;

    if ($ids_file) {

        open(IDS_FILE, '<', $ids_file)
            or die "Cannot open user IDs file: $ids_file: $!\n";

        my @ids = <IDS_FILE>;

        chomp @ids;

        @ids = grep { defined $_ } @ids[$offset..($offset + $limit)];

        return \@ids;
    }

    my $query = {
        select => {
            au => ['id'], 
            mus => ['balance_owed']
        },
        from => {
            au => {
                mus => {
                    type => 'left',
                    field => 'usr',
                    fkey => 'id'
                }
            }
        },
        limit => $limit,
        offset => $offset,
        order_by => [{class => 'au',  field => 'id'}]
    };

    my @where = ({'+au' => {deleted => 'f'}});

    if (defined $max_id) {

        push(@where, {
            '+au' => { # min_id defaults to 0.
                id => {between => [$min_id, $max_id]}
            }
        });

    } elsif (defined $min_id) {

        push(@where, {
            '+au' => {
                # min_id defaults to 0.
                id => {'>' => $min_id}
            }
        });
    }

    if ($has_penalty) {

        if ($has_penalty !~ /^\d+$/) { # got a penalty name, look up possible custom ones for the patron or processing user home org
            $has_penalty = {in => { union => [
                {select => { csp => ['id'] }, from => csp => where => { name => $has_penalty }},
                {select =>
                    { aous => [{column => value => transform => btrim => params => '"'}] },
                 from => 'aous',
                 where => {
                    name => 'circ.custom_penalty_override.'.$has_penalty,
                    org_unit => { in =>
                        {select => { aou => [{column => id => transform => 'actor.org_unit_ancestors' => result_field => id => alias => 'id'}]},
                         from => 'aou',
                         where => { id => ($home_ou_context ? { '+au' => 'home_ou' } : $auth_user_home) }}
                    }
                 }
                }
            ]}};
        }

        push(@where, {
            '-exists' => {
                select => {ausp => ['id']},
                from => 'ausp',
                where => {
                    usr => {'=' => {'+au' => 'id'}},
                    standing_penalty => $has_penalty,
                    '-or' => [
                        {stop_date => undef},
                        {stop_date => {'>' => 'now'}}
                    ]
                },
                limit => 1
            }
        });
    }

    if ($no_has_penalty) {

        if ($no_has_penalty !~ /^\d+$/) { # got a penalty name, look up possible custom ones for the patron or processing user home org
            $no_has_penalty = {in => { union => [
                {select => { csp => ['id'] }, from => csp => where => { name => $no_has_penalty }},
                {select =>
                    { aous => [{column => value => transform => btrim => params => '"'}] },
                 from => 'aous',
                 where => {
                    name => 'circ.custom_penalty_override.'.$no_has_penalty,
                    org_unit => { in =>
                        {select => { aou => [{column => id => transform => 'actor.org_unit_ancestors' => result_field => id => alias => 'id'}]},
                         from => 'aou',
                         where => { id => ($home_ou_context ? { '+au' => 'home_ou' } : $auth_user_home) }}
                    }
                 }
                }
            ]}};
        }

        push(@where, {
            '-not' => {
                '-exists' => {
                    select => {ausp => ['id']},
                    from => 'ausp',
                    where => {
                        usr => {'=' => {'+au' => 'id'}},
                        standing_penalty => $no_has_penalty,
                        '-or' => [
                            {stop_date => undef},
                            {stop_date => {'>' => 'now'}}
                        ]
                    },
                    limit => 1
                }
            }
        });
    }

    # For owes more / less, there is a special case because not all
    # patrons have a money.usr_summary row.  If they don't, they
    # effectively owe $0.00.

    if (defined $owes_more_than) {

        if ($owes_more_than > 0) {

            push(@where, {
                '+mus' => {
                    balance_owed => {'>' => $owes_more_than}
                }
            });

        } else {
            push(@where, {
                '-or' => [{
                    '+mus' => {
                        balance_owed => {'>' => $owes_more_than}
                    },
                }, {
                    '+mus' => {
                        usr => undef # owes $0.00
                    }
                }]
            });
        }
    }

    if (defined $owes_less_than) {

        if ($owes_less_than < 0) {
            push(@where, {
                '+mus' => {
                    balance_owed => {'<' => $owes_less_than}
                }
            }) if $owes_less_than;

        } else {

            push(@where, {
                '-or' => [{
                    '+mus' => {
                        balance_owed => {'<' => $owes_less_than}
                    },
                }, {
                    '+mus' => {
                        usr => undef # owes $0.00
                    }
                }]
            });
        }
    }

    push(@where, {
        '-exists' => {
            select => {circ => ['id']},
            from => 'circ',
            where => {
                usr => {'=' => {'+au' => 'id'}},
                xact_finish => undef
            },
            limit => 1
        }
    }) if $has_open_circ;

    $query->{where}->{'-and'} = \@where;

    my $resp = $e->json_query($query);

    return [map {$_->{id}} @$resp];
}

sub process_users {

    my $limit = $batch_size;
    my $offset = 0;
    my $counter = 0;
    my $batches = 0;
    my $method = 'open-ils.actor.user.penalties.update';
    $method .= '_at_home' if $home_ou_context;

    while (1) {
        my $user_ids = get_user_ids($limit, $offset);

        my $num = scalar(@$user_ids);

        last unless $num;

        $batches++;

        announce('debug', 
            "Processing batch $batches; count=$num; offset=$offset; ids=" .
            @$user_ids[0] . '..' . @$user_ids[$#$user_ids]);

        for my $user_id (@$user_ids) {

            $U->simplereq(
                'open-ils.actor', $method,
                $authtoken, $user_id, @included_penalties
            );

            $counter++;
        }

        $offset += $batch_size;
    }

    announce('debug', "$counter total patrons processed.");
}

sub login {

    my $auth_user = $e->search_actor_user(
        {usrname => $process_as, deleted => 'f'})->[0];

    die "No such user '$process_as' to use for authentication\n" unless $auth_user;

    my $auth_resp = $U->simplereq(
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.create',
        {user_id => $auth_user->id, login_type => 'staff'}
    );

    die "Could not create an internal auth session\n" unless (
        $auth_resp && 
        $auth_resp->{payload} && 
        ($authtoken = $auth_resp->{payload}->{authtoken}) &&
        ($auth_user_home = $auth_user->home_ou)
    );
}

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(IDL => 
    OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();
$e = OpenILS::Utils::CStoreEditor->new;

login();
process_users();

