#!/usr/bin/perl

# Copyright (C) 2015 BC Libraries Cooperative
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
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# ====================================================================== 
# OpenSRF requests are handled by the main OpenILS::Application::EbookAPI module,
# which determines which "handler" submodule to use based on the params of the
# OpenSRF request.  Each vendor API (OneClickdigital, OverDrive, etc.) has its
# own separate handler class, since they all work a little differently.
#
# An instance of the handler class represents an EbookAPI session -- that is, we
# instantiate a new handler object when we start a new session with the external API.
# Thus everything we need to talk to the API, like client keys or auth tokens, is
# an attribute of the handler object.
#
# API endpoints are defined in the handler class.  The handler constructs HTTP
# requests, then passes them to the the request() method of the parent class
# (OpenILS::Application::EbookAPI), which sets some default headers and manages
# the actual mechanics of sending the request and receiving the response.  It's
# up to the handler class to do something with the response.
#
# At a minimum, each handler must have the following methods, since the parent
# class presumes they exist; it may be a no-op if the API doesn't support that
# bit of functionality:
#
#   - initialize: assign values for basic attributes (e.g. library_id,
#     basic_token) based on library settings
#   - do_client_auth: authenticate client with external API (e.g. get client
#     token if needed)
#   - do_patron_auth: get a patron-specific bearer token, or just the patron ID
#   - get_title_info: get basic title details (title, author, optional cover image)
#   - do_holdings_lookup: how many total/available "copies" are there for this
#     title? (n/a for OneClickdigital)
#   - do_availability_lookup: does this title have available "copies"? y/n
#   - checkout
#   - renew
#   - checkin
#   - place_hold
#   - suspend_hold (n/a for OneClickdigital)
#   - cancel_hold
#   - get_patron_checkouts: returns an array of hashrefs representing checkouts;
#     each checkout hashref has the following keys:
#       - xact_id
#       - title_id
#       - due_date
#       - download_url
#       - title
#       - author
#   - get_patron_holds
# ====================================================================== 

package OpenILS::Application::EbookAPI::Test;

use strict;
use warnings;

use OpenILS::Application;
use OpenILS::Application::EbookAPI;
use base qw/OpenILS::Application::EbookAPI/;
use OpenSRF::AppSession;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::Utils::Cache;
use OpenILS::Application::AppUtils;
use DateTime;
use DateTime::Format::ISO8601;

my $U = 'OpenILS::Application::AppUtils';

# create new handler object
sub new {
    my( $class, $args ) = @_;

    # A new handler object represents a new API session, so we instantiate it
    # by passing it a hashref containing the following basic attributes
    # available to us when we start the session:
    #   - vendor: a string indicating the vendor whose API we're talking to
    #   - ou: org unit ID for current session
    #   - session_id: unique ID for the session represented by this object

    $class = ref $class || $class;
    return bless $args, $class;
}

# set API-specific handler attributes based on library settings
sub initialize {
    my $self = shift;

    # At a minimum, you are likely to need some kind of basic API key or token
    # to allow the client (Evergreen) to use the API.
    # Other attributes will vary depending on the API.  Consult your API
    # documentation for details.

    return $self;
}

# authorize client session against API
sub do_client_auth {
    my $self = shift;

    # Some APIs require client authorization, and may return an auth token
    # which must be included in subsequent requests.  This is where you do
    # that.  If you get an auth token, you'll want to add it as an attribute to
    # the handler object so that it's available to use in subsequent requests.
    # If your API doesn't require this step, you don't need to return anything
    # here.

    return;
}

# authenticate patron against API
sub do_patron_auth {
    my $self = shift;

    # We authenticate the patron using the barcode of their active card.
    # We may capture this on OPAC login (along with password, if required),
    # in which case it should already be an attribute of the handler object;
    # otherwise, it should be passed to this method as a parameter.
    my $barcode = shift;
    if ($barcode) {
        if (!$self->{patron_barcode}) {
            $self->{patron_barcode} = $barcode;
        } elsif ($barcode ne $self->{patron_barcode}) {
            $logger->error("EbookAPI: patron barcode in auth request does not match patron barcode for this session");
            return;
        }
    } else {
        if (!$self->{patron_barcode}) {
            $logger->error("EbookAPI: Cannot authenticate patron with unknown barcode");
        } else {
            $barcode = $self->{patron_barcode};
        }
    }

    # We really don't want to be handling the patron's unencrypted password.
    # But if we need to, it should be added to our handler object on login
    # via the open-ils.ebook_api.patron.cache_password OpenSRF API call
    # before we attempt to authenticate the patron against the external API.
    my $password;
    if ($self->{patron_password}) {
        $password = $self->{patron_password};
    }

    # return external patron ID or patron auth token

    # For testing, only barcode 99999359616 is valid.
    return 'USER001' if ($barcode eq '99999359616');

    # All other values return undef.
    return undef;
}

# get basic info (title, author, eventually a thumbnail URL) for a title
sub get_title_info {
    my $self = shift;

    # External ID for title.  Depending on the API, this could be an ISBN
    # or an identifier unique to that vendor.
    my $title_id = shift;

    # Prepare data structure to be used as return value.
    my $title_info = {
        title  => '',
        author => ''
    };

    # If title lookup fails or title is not found, our return value
    # is somewhat different.
    my $title_not_found = {
        error => 'Title not found.'
    };

    # For testing purposes, we have only three valid titles (001, 002, 003).
    # All other title IDs return an error message.
    if ($title_id eq '001') {
        $title_info->{title} = 'The Fellowship of the Ring';
        $title_info->{author} = 'J.R.R. Tolkien';
    } elsif ($title_id eq '002') {
        $title_info->{title} = 'The Two Towers';
        $title_info->{author} = 'J.R.R. Tolkien';
    } elsif ($title_id eq '003') {
        $title_info->{title} = 'The Return of the King';
        $title_info->{author} = 'J.R.R. Tolkien';
    } else {
        return $title_not_found;
    }
    return $title_info;
}

# get detailed holdings information (copy counts and formats), OR basic
# availability if detailed info is not provided by the API
sub do_holdings_lookup {
    my $self = shift;

    # External ID for title.  Depending on the API, this could be an ISBN
    # or an identifier unique to that vendor.
    my $title_id = shift;

    # Prepare data structure to be used as return value.
    # NOTE: If the external API does not provide detailed holdings info,
    # return simple availability information: { available => 1 }
    my $holdings = {
        copies_owned => 0,
        copies_available => 0,
        formats => []
    };

    # 001 and 002 are unavailable.
    if ($title_id eq '001' || $title_id eq '002') {
        $holdings->{copies_owned} = 1;
        $holdings->{copies_available} = 0;
        push @{$holdings->{formats}}, { name => 'ebook' };
    }

    # 003 is available.
    if ($title_id eq '003') {
        $holdings->{copies_owned} = 1;
        $holdings->{copies_available} = 1;
        push @{$holdings->{formats}}, { name => 'ebook' };
    }

    # All other title IDs are unknown.

    return $holdings;
}

# look up whether a title is currently available for checkout; returns a boolean value
sub do_availability_lookup {
    my $self = shift;

    # External ID for title.  Depending on the API, this could be an ISBN
    # or an identifier unique to that vendor.
    my $title_id = shift;

    # At this point, you would lookup title availability via an API request.
    # In our case, since this is a test module, we just return availability info
    # based on hard-coded values:

    # 001 and 002 are unavailable.
    return 0 if ($title_id eq '001');
    return 0 if ($title_id eq '002');

    # 003 is available.
    return 1 if ($title_id eq '003');

    # All other title IDs are unknown.
    return undef;
}

# check out a title to a patron
sub checkout {
    my $self = shift;

    # External ID of title to be checked out.
    my $title_id = shift;

    # Patron ID or patron auth token, as returned by do_patron_auth().
    my $user_token = shift;

    # Ebook format to be checked out (optional, not used here).
    my $format = shift;

    # If checkout succeeds, the response is a hashref with the following fields:
    # - due_date
    # - xact_id (optional)
    #
    # If checkout fails, the response is a hashref with the following fields:
    # - error_msg: a string containing an error message or description of why
    #   the checkout failed (e.g. "Checkout limit of (4) reached").
    #
    # If no valid response is received from the API, return undef.

    # For testing purposes, user ID USER001 is our only valid user, 
    # and title 003 is the only available title.
    if ($title_id && $user_token) {
        if ($user_token eq 'USER001' && $title_id eq '003') {
            return { due_date => DateTime->today()->add( days => 14 )->iso8601() };
        } else {
            return { msg => 'Checkout failed.' };
        }
    } else {
        return undef;
    }

}

sub renew {
    my $self = shift;

    # External ID of title to be renewed.
    my $title_id = shift;

    # Patron ID or patron auth token, as returned by do_patron_auth().
    my $user_token = shift;

    # If renewal succeeds, the response is a hashref with the following fields:
    # - due_date
    # - xact_id (optional)
    #
    # If renewal fails, the response is a hashref with the following fields:
    # - error_msg: a string containing an error message or description of why
    #   the renewal failed (e.g. "Renewal limit reached").
    #
    # If no valid response is received from the API, return undef.

    # For testing purposes, user ID USER001 is our only valid user, 
    # and title 001 is the only renewable title.
    if ($title_id && $user_token) {
        if ($user_token eq 'USER001' && $title_id eq '001') {
            return { due_date => DateTime->today()->add( days => 14 )->iso8601() };
        } else {
            return { error_msg => 'Renewal failed.' };
        }
    } else {
        return undef;
    }
}

sub checkin {
    my $self = shift;

    # External ID of title to be checked in.
    my $title_id = shift;

    # Patron ID or patron auth token, as returned by do_patron_auth().
    my $user_token = shift;

    # If checkin succeeds, return an empty hashref (actually it doesn't
    # need to be empty, it just must NOT contain "error_msg" as a key).
    #
    # If checkin fails, return a hashref with the following fields:
    # - error_msg: a string containing an error message or description of why
    #   the checkin failed (e.g. "Checkin failed").
    #
    # If no valid response is received from the API, return undef.

    # For testing purposes, user ID USER001 is our only valid user, 
    # and title 003 is the only title that can be checked in.
    if ($title_id && $user_token) {
        if ($user_token eq 'USER001' && $title_id eq '003') {
            return {};
        } else {
            return { error_msg => 'Checkin failed' };
        }
    } else {
        return undef;
    }
}

sub place_hold {
    my $self = shift;

    # External ID of title to be held.
    my $title_id = shift;

    # Patron ID or patron auth token, as returned by do_patron_auth().
    my $user_token = shift;

    # Email address of patron (optional, not used here).
    my $email = shift;

    # If hold is successfully placed, return a hashref with the following
    # fields:
    # - queue_position: this user's position in hold queue for this title
    # - queue_size: total number of holds on this title
    # - expire_date: when the hold expires
    #
    # If hold fails, return a hashref with the following fields:
    # - error_msg: a string containing an error message or description of why
    #   the hold failed (e.g. "Hold limit (4) reached").
    #
    # If no valid response is received from the API, return undef.

    # For testing purposes, we always and only allow placing a hold on title
    # 002 by user ID USER001.
    if ($title_id && $user_token) {
        if ($user_token eq 'USER001' && $title_id eq '002') {
            return {
                queue_position => 1,
                queue_size => 1,
                expire_date => DateTime->today()->add( days => 70 )->iso8601()
            };
        } else {
            return { error_msg => 'Unable to place hold' };
        }
    } else {
        return undef;
    }
}

sub cancel_hold {
    my $self = shift;

    # External ID of title.
    my $title_id = shift;

    # Patron ID or patron auth token, as returned by do_patron_auth().
    my $user_token = shift;

    # If hold is successfully canceled, return an empty hashref (actually it
    # doesn't need to be empty, it just must NOT contain "error_msg" as a key).
    #
    # If hold is NOT canceled, return a hashref with the following fields:
    # - error_msg: a string containing an error message or description of why
    #   the hold was not canceled (e.g. "Hold could not be canceled"). 
    #
    # If no valid response is received from the API, return undef.

    # For testing purposes, we always and only allow canceling a hold on title
    # 002 by user ID USER001.
    if ($title_id && $user_token) {
        if ($user_token eq 'USER001' && $title_id eq '002') {
            return {};
        } else {
            return { error_msg => 'Unable to cancel hold' };
        }
    } else {
        return undef;
    }
}

sub suspend_hold {
}

sub get_patron_checkouts {
    my $self = shift;

    # Patron ID or patron auth token.
    my $user_token = shift;

    # Return an array of hashrefs representing checkouts;
    # each hashref should have the following keys:
    #   - xact_id: unique ID for this transaction (if used by API)
    #   - title_id: unique ID for this title
    #   - due_date
    #   - download_url
    #   - title: title of item, formatted for display
    #   - author: author of item, formatted for display

    my $checkouts = [];
    # USER001 is our only valid user, so we only return checkouts for them.
    if ($user_token eq 'USER001') {
        push @$checkouts, {
            xact_id => '1',
            title_id => '001',
            due_date => DateTime->today()->add( days => 7 )->iso8601(),
            download_url => 'http://example.com/ebookapi/t/001/download',
            title => 'The Fellowship of the Ring',
            author => 'J. R. R. Tolkien'
        };
    }
    $self->{checkouts} = $checkouts;
    return $self->{checkouts};
}

sub get_patron_holds {
    my $self = shift;

    # Patron ID or patron auth token.
    my $user_token = shift;

    # Return an array of hashrefs representing holds;
    # each hashref should have the following keys:
    #   - title_id: unique ID for this title
    #   - queue_position: this user's position in hold queue for this title
    #   - queue_size: total number of holds on this title
    #   - is_ready: whether hold is currently available for checkout
    #   - is_frozen: whether hold is suspended
    #   - thaw_date: when hold suspension expires (if suspended)
    #   - create_date: when the hold was placed
    #   - expire_date: when the hold expires
    #   - title: title of item, formatted for display
    #   - author: author of item, formatted for display

    my $holds = [];
    # USER001 is our only valid user, so we only return checkouts for them.
    if ($user_token eq 'USER001') {
        push @$holds, {
            title_id => '002',
            queue_position => 1,
            queue_size => 1,
            is_ready => 0,
            is_frozen => 0,
            create_date => DateTime->today()->subtract( days => 10 )->iso8601(),
            expire_date => DateTime->today()->add( days => 60 )->iso8601(),
            title => 'The Two Towers',
            author => 'J. R. R. Tolkien'
        };
    }
    $self->{holds} = $holds;
    return $self->{holds};
}

sub do_get_download_link {
    my $self = shift;
    my $request_link = shift;

    # For some vendors (e.g. OverDrive), the workflow is as follows:
    #
    # 1. Perform a checkout.
    # 2. Checkout response contains a URL which we use to request a
    #    format-specific download link for the checked-out title.
    # 3. Submit a request to the request link.
    # 4. Response contains a (temporary/dynamic) URL which the user
    #    clicks on to download the ebook in the desired format.
    #    
    # For other vendors, the download link for a title is static and not
    # format-dependent.  In that case, we just return the original request link
    # (but ideally the UI will skip the download link request altogether, since
    # it's superfluous in that case).

    return $request_link;
}
