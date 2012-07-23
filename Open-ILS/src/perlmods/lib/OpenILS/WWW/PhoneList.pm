# ---------------------------------------------------------------
# Copyright (C) 2011 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::WWW::PhoneList;
use strict;
use warnings;
use bytes;

use Apache2::Log;
use Apache2::Const -compile => qw(OK FORBIDDEN HTTP_NO_CONTENT :log);
use APR::Const    -compile => qw(:error SUCCESS);
use APR::Table;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;

use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;

use Text::CSV; # Still only support CSV output.

# Our submodules.
use OpenILS::WWW::PhoneList::Holds;
use OpenILS::WWW::PhoneList::Overdues;

my $U = 'OpenILS::Application::AppUtils';

my $bootstrap;

sub import {
    my $self = shift;
    $bootstrap = shift;
}

sub child_init {
    OpenSRF::System->bootstrap_client(config_file => $bootstrap);
    my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
    Fieldmapper->import(IDL => $idl);
    OpenILS::Utils::CStoreEditor->init;
    return Apache2::Const::OK;
}

sub handler {
    my $r = shift;
    my $cgi = new CGI;
    my $authid = $cgi->cookie('ses') || $cgi->param('ses');
    my $user = $U->simplereq('open-ils.auth', 'open-ils.auth.session.retrieve', $authid);
    if (!$user || (ref($user) eq 'HASH' && $user->{ilsevent} == 1001)) {
        return Apache2::Const::FORBIDDEN;
    }

    my $ou_id = $cgi->cookie("ws_ou") || $cgi->param("ws_ou") || $user->home_ou;

    # Look for optional addcount parameter. If it is present add a
    # count column to the end of the csv ouput with a count of the
    # patron's hold items.
    my $addcount = defined($cgi->param('addcount'));

    # Member staff asked for the option to ignore a patron's
    # preference to receive both a phone and email notice, and skip
    # them if it looks like they will get an email notice, too.
    # So we made it an option on the query string.
    my $skipemail = defined($cgi->param('skipemail'));

    # Build the args hashref to initialize our functional submodule:
    my $args = {
                'authtoken' => $authid,
                'user' => $user->id,
                'work_ou' => $ou_id,
               };

    # Default module to load is Holds.
    my $module = 'OpenILS::WWW::PhoneList::Holds';

    # If the overdue parameter is specified, we us the Overdues module
    # and get the number of days from the due date. If no number of
    # days is given, or if the argument to overdue is not a number,
    # then we use a default of 14.
    if (defined($cgi->param('overdue'))) {
        $module = 'OpenILS::WWW::PhoneList::Overdues';
        $args->{'days'} =
            ($cgi->param('overdue') =~ /^[0-9]+$/) ? $cgi->param('overdue')
                : 14;
        $args->{'skipemail'} = $skipemail;
    } else {
        $args->{'addcount'} = $addcount;
        $args->{'skipemail'} = $skipemail;
    }

    # Load the module.
    my $source = $module->new($args);

    # check for user permissions:
    return Apache2::Const::FORBIDDEN unless($source->checkperms);

    # Tell the source to run its query.
    if ($source->query()) {
        my $csv = Text::CSV->new();
        $r->headers_out->set("Content-Disposition" => "attachment; filename=phone.csv");
        $r->content_type("text/plain");
        # Print the columns
        if ($csv->combine(@{$source->columns})) {
            $r->print($csv->string . "\n");
        }
        # Print the results
        $r->print($csv->string . "\n") while ($csv->combine(@{$source->next}));
    }
    else {
        # Query failed, so we'll return no content error.
        return Apache2::Const::HTTP_NO_CONTENT;
    }

    return Apache2::Const::OK;
}

1;
