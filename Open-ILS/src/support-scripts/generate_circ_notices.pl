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

my @global_overdue_circs; # all circ collections stored here go into the final global XML file

# - set up default values
my $opt_osrf_config = '/openils/conf/opensrf_core.xml';
my $opt_send_email = 0;
my $opt_gen_day_intervals = 0;
my $opt_days_back = '';
my $opt_gen_global_templates = 0;
my $opt_show_help = 0;
my $opt_append_global_email_fail;
my $opt_notice_types = '';

GetOptions(
    'osrf_opt_osrf_config=s' => \$opt_osrf_config,
    'send-email' => \$opt_send_email,
    'generate-day-intervals' => \$opt_gen_day_intervals,
    'generate-global-templates' => \$opt_gen_global_templates,
    'days-back=s' => \$opt_days_back,
    'append-global-email-fail' => \$opt_append_global_email_fail,
    'notice-types=s' => \$opt_notice_types,
    'help' => \$opt_show_help,
);

help() and exit if $opt_show_help;

sub help {
    print <<HELP;

Evergreen Circulation Notice Generator

    --config <config_file>
    
    --send-email
        If set, generate email notices

    --generate-day-intervals
        If set, notices which have a notify_interval of >= 1 day will be processed.

    --generate-global-templates
        Collect all non-emailed notices into a global set and generate templates based on that set.

    --append-global-email-fail
        If an attempt was made to send an email notice but it failed, the notice is appended
        to the global notice file set.  This will only have any bearing if --generate-global-templates
        is enabled.

    --days-back <days_back_comma_separted>  
        This is used to set the effective run date of the script.
        This is useful if you don't want to generate notices on certain days.  For example, if you don't 
        generate notices on the weekend, you would run this script on weekdays and set --days-back to 
        0,1,2 when it's run on Monday to capture any notices from Saturday and Sunday. 

    --notice-types <overdue,predue,...>
        Comma-separated list of notice types to generate for this run of the script

    --help 
        Print this help message
HELP
}


sub main {
    osrf_connect($opt_osrf_config);
    $settings = OpenSRF::Utils::SettingsClient->new;

    die "Please specify at least 1 type of notice to generate with --notice-types\n"
        unless $opt_notice_types;

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

    for my $db (($opt_days_back) ? split(',', $opt_days_back) : 0) {
        if($opt_notice_types =~ /overdue/) {
            generate_notice_set($_, 'overdue', $db) for @overdues;
        }
        if($opt_notice_types =~ /predue/) {
            generate_notice_set($_, 'predue', $db) for @predues;
        }
    }

    generate_global_overdue_file() if $opt_gen_global_templates;
}

sub generate_global_overdue_file {
    $logger->info("notice: processing ".scalar(@global_overdue_circs)." for global template");
    return unless @global_overdue_circs;

    my $tt = Template->new({ABSOLUTE => 1});

    $tt->process(
        $settings->config_value(notifications => overdue => 'combined_template'),
        {
            overdues => \@global_overdue_circs,
            get_bib_attr => \&get_bib_attr,
            parse_due_date => \&parse_due_date, # let the templates decide date format
            escape_xml => \&escape_xml,
        }, 
        \&global_overdue_output
    ) or $logger->error('notice: Template error '.$tt->error);
}

sub global_overdue_output {
    print shift();
}


sub generate_notice_set {
    my($notice, $type, $days_back) = @_;

    my $notify_interval = OpenSRF::Utils->interval_to_seconds($notice->{notify_interval});
    $notify_interval = -$notify_interval if $type eq 'overdue';

    my ($start_date, $end_date) = make_date_range($notify_interval - $days_back * 86400);

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
    if(my $durs = $notice->{circ_duration_range}) {
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
    return unless @circs;
    my $circ_list = fetch_circ_data(@circs);
    my $tt = Template->new({ABSOLUTE => 1});

    my $sender = $settings->config_value(
        notifications => $type => 'sender_address') || 
        $settings->config_value(notifications => 'sender_address');

    my $context = {   
        circ_list => $circ_list,
        get_bib_attr => \&get_bib_attr,
        parse_due_date => \&parse_due_date, # let the templates decide date format
        smtp_sender => $sender,
        smtp_repley => $sender, # XXX
        notice => $notice,
    };

    push(@global_overdue_circs, $context) if 
        $type eq 'overdue' and $notice->{file_append} =~ /always/i;

    if($opt_send_email and $notice->{email_notify} and 
            my $email = $circ_list->[0]->usr->email) {

        if(my $tmpl = $notice->{email_template}) {
            $tt->process($tmpl, $context, 
                sub { 
                    email_template_output($notice, $type, $context, $email, @_); 
                }
            ) or $logger->error('notice: Template error '.$tt->error);
        } 
    } else {
        push(@global_overdue_circs, $context) 
            if $type eq 'overdue' and $notice->{file_append} =~ /noemail/i;
    }
}

sub get_bib_attr {
    my $circ = shift;
    my $attr = shift;
    my $copy = $circ->target_copy;
    if($copy->call_number->id == OILS_PRECAT_CALL_NUMBER) {
        return $copy->dummy_title || '' if $attr eq 'title';
        return $copy->dummy_author || '' if $attr eq 'author';
    } else {
        my $mvr = $U->record_to_mvr($copy->call_number->record);
        return $mvr->title || '' if $attr eq 'title';
        return $mvr->author || '' if $attr eq 'author';
    }
}

# provides a date that Template::Plugin::Date can parse
sub parse_due_date {
    my $circ = shift;
    my $due = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($circ->due_date));
    return sprintf(
        "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
        $due->hour,
        $due->minute,
        $due->second,
        $due->day,
        $due->month,
        $due->year
    );
}

sub escape_xml {
    my $str = shift;
    $str =~ s/&/&amp;/sog;
    $str =~ s/</&lt;/sog;
    $str =~ s/>/&gt;/sog;
    return $str;
}


sub email_template_output {
    my $notice = shift;
    my $type = shift;
    my $context = shift;
    my $email = shift;
    my $msg = shift;

	my $sender = Email::Send->new({mailer => 'SMTP'});
    my $smtp_server = $settings->config_value(notifications => 'smtp_server');
    $logger->debug("notice: smtp server is $smtp_server");
	$sender->mailer_args([Host => $smtp_server]);
	my $stat = $sender->send($msg);

	if( $stat and $stat->type eq 'success' ) {
		$logger->info("notice: successfully sent $type email to $email");
	} else {
		$logger->warn("notice: unable to send $type email to $email: ".Dumper($stat));
        # if we were unable to send the email, add this notice set to the global notify set
        push(@global_overdue_circs, $context) 
            if $opt_append_global_email_fail and 
                $type eq 'overdue' and $notice->{file_append} =~ /noemail/i;
	}
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
        {   flesh => 3,
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
