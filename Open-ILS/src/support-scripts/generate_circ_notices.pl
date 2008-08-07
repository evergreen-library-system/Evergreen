#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service
# Bill Erickson <erickson@esilibrary.com>
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
#  ---------------------------------------------------------------
use strict; use warnings;
require 'oils_header.pl';
use vars qw/$logger/;
use DateTime;
use Template;
use Data::Dumper;
use Email::Send;
use Getopt::Long;
use Unicode::Normalize;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::AppSession;
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use OpenILS::Const qw/:const/;
my $U = 'OpenILS::Application::AppUtils';

my $settings = undef;
my $e = OpenILS::Utils::CStoreEditor->new;

my ($osrf_config, $send_email, $gen_day_intervals, $days_back) = 
    ('/openils/conf/opensrf_core.xml', 1, 0, 0); 

GetOptions(
    'osrf_osrf_config=s' => \$osrf_config,
    'send-emails' => \$send_email,
    'generate-day-intervals' => \$gen_day_intervals,
    'days-back=s' => \$days_back,
);

sub help {
    print <<HELP;
        --config <config_file>
        
        --send-emails If set, generate email notices

        --generate-day-intervals If set, notices which have a notify_interval of >= 1 day will be processed.

        --days-back <days_back_comma_separted>  This is used to set the effective run date of the script.
            This is useful if you don't want to generate notices on certain days.  For example, if you don't 
            generate notices on the weekend, you would run this script on weekdays and set --days-back to 
            0,1,2 when it's run on Monday to capture any notices from Saturday and Sunday. 
HELP
}


sub main {
    osrf_connect($osrf_config);
    $settings = OpenSRF::Utils::SettingsClient->new;

    my $smtp_server = $settings->config_value(notifications => 'smtp_server');
    my $sender_address = $settings->config_value(notifications => 'sender_address');
    my $od_sender_addr = $settings->config_value(notifications => overdue => 'sender_address') || $sender_address;
    my $pd_sender_addr = $settings->config_value(notifications => predue => 'sender_address') || $sender_address;
    my $overdue_notices = $settings->config_value(notifications => overdue => 'notice');
    my $predue_notices = $settings->config_value(notifications => predue => 'notice');

    $overdue_notices = [$overdue_notices] unless ref $overdue_notices eq 'ARRAY'; 
    $predue_notices = [$predue_notices] unless ref $predue_notices eq 'ARRAY'; 

    my @overdues = sort { 
        OpenSRF::Utils->interval_to_seconds($a->{notify_interval}) <=> 
        OpenSRF::Utils->interval_to_seconds($b->{notify_interval}) } @$overdue_notices;

    my @predues = sort { 
        OpenSRF::Utils->interval_to_seconds($a->{notify_interval}) <=> 
        OpenSRF::Utils->interval_to_seconds($b->{notify_interval}) } @$predue_notices;

    generate_notice_set($_, 'overdue') for @overdues;
    generate_notice_set($_, 'predue') for @predues;
}


sub generate_notice_set {
    my($notice, $type) = @_;

    my $notify_interval = OpenSRF::Utils->interval_to_seconds($notice->{notify_interval});
    $notify_interval = -$notify_interval if $type eq 'overdue';

    my ($start_date, $end_date) = make_date_range(-$days_back + $notify_interval);

    $logger->info("notice: retrieving circs with due date in range $start_date -> $end_date");

    my $QUERY = {
        select => {
            circ => ['id']
        }, 
        from => 'circ', 
        where => {
            '+circ' => {
                checkin_time => undef, 
                '-or' => [
                    {stop_fines => ["LOST","LONGOVERDUE","CLAIMSRETURNED"]},
                    {stop_fines => undef}
                ],
				due_date => {between => [$start_date, $end_date]},
            }
        }
    };

    # if a circ duration is defined for this type of notice
    if(my $durs = $settings->{circ_duration_range}) {
        $QUERY->{where}->{'+circ'}->{duration} = {between => [$durs->{from}, $durs->{to}]};
    }

    my $circs = $e->json_query($QUERY, {timeout => 18000, substream => 1});
    process_circs($notice, $type, map {$_->{id}} @$circs);
}


sub process_circs {
    my $notice = shift;
    my $type = shift;
    my @circs = @_;

	return unless @circs;

	$logger->info("notice: processing $type notices with notify interval ". 
        $notice->{notify_interval}."  and ".scalar(@circs)." circs");

	my $org; 
	my $patron;
	my @current;

	my $x = 0;
	for my $circ (@circs) {
		$circ = $e->retrieve_action_circulation($circ);

		if( !defined $org or 
				$circ->circ_lib != $org  or $circ->usr ne $patron ) {
			$org = $circ->circ_lib;
			$patron = $circ->usr;
			generate_notice($notice, $type, @current) if @current;
			@current = ();
		}

		push(@current, $circ);
		$x++;
	}

	$logger->info("notice: processed $x circs");
	generate_notice($notice, $type, @current);
}

my %ORG_CACHE;

sub generate_notice {
    my $notice = shift;
    my $type = shift;
    my @circs = @_;
    my $circ_list = fetch_circ_data(@circs);
    my $tt = Template->new({
        ABSOLUTE => 1,
    });

    my $sender = $settings->config_value(
        notifications => $type => 'sender_address') || 
        $settings->config_value(notifications => 'sender_address');

    $tt->process(
        $notice->{template}, 
        {   circ_list => $circ_list,
            smtp_sender => $sender,
            smtp_repley => $sender # XXX
        },
        \&handle_template_output
    ) or $logger->error('notice: Template error '.$tt->error);
}

sub handle_template_output {
    my $str = shift;
    print "$str\n";
}



sub fetch_circ_data {
    my @circs = @_;

	my $circ_lib_id = $circs[0]->circ_lib;
	my $usr_id = $circs[0]->usr;
	$logger->debug("notice: printing user:$usr_id circ_lib:$circ_lib_id");

    my $usr = $e->retrieve_actor_user([
        $usr_id,
        {   flesh => 1,
            flesh_fields => {
                au => [qw/card billing_address mailing_address/] 
            }
        }
    ]);

    my $circ_lib = $ORG_CACHE{$circ_lib_id} ||
        $e->retrieve_actor_org_unit([
            $circ_lib_id,
            {   flesh => 1,
                flesh_fields => {
                    aou => [qw/billing_address mailing_address/],
                }
            }
        ]);
    $ORG_CACHE{$circ_lib_id} = $circ_lib;

    my $circ_objs = $e->search_action_circulation([
        {id => [map {$_->id} @circs]},
        {   flesh => 2,
            flesh_fields => {
                circ => [q/target_copy/],
                acp => ['call_number'],
                acn => ['record'],
            }
        }
    ]);

    $_->circ_lib($circ_lib) for @$circ_objs;
    $_->usr($usr) for @$circ_objs;

    return $circ_objs
}

=head
	if( $circ->copy->call_number->id == OILS_PRECAT_CALL_NUMBER ) {
		$data->{title} = $copy->dummy_title || '';
		$data->{author} = $copy->dummy_author || '';
    } else {
        $data->{mvr} = $U->record_to_mvr($copy->call_number->record);
		$data->{title} = $data->{mvr}->title || '';
		$data->{author} = $data->{mvr}->author || '';
    }
=cut

sub make_date_range {
	my $offset = shift;
    #my $is_day_precision = shift; # window?

	my $epoch = CORE::time + $offset;
	my $date = DateTime->from_epoch(epoch => $epoch, time_zone => 'local');

	$date->set_hour(0);
	$date->set_minute(0);
	$date->set_second(0);
	my $start = "$date";
	
	$date->set_hour(23);
	$date->set_minute(59);
	$date->set_second(59);

	return ($start, "$date");
}

main();
