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

package OpenILS::Application::EbookAPI::OneClickdigital;

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
use Data::Dumper;

sub new {
    my( $class, $args ) = @_;
    $class = ref $class || $class;
    return bless $args, $class;
}

sub ou {
    my $self = shift;
    return $self->{ou};
}

sub vendor {
    my $self = shift;
    return $self->{vendor};
}

sub session_id {
    my $self = shift;
    return $self->{session_id};
}

sub base_uri {
    my $self = shift;
    return $self->{base_uri};
}

sub library_id {
    my $self = shift;
    return $self->{library_id};
}

sub basic_token {
    my $self = shift;
    return $self->{basic_token};
}

sub patron_id {
    my $self = shift;
    return $self->{patron_id};
}

sub initialize {
    my $self = shift;
    my $ou = $self->{ou};

    my $base_uri = 'https://api.oneclickdigital.com/v1';
    $self->{base_uri} = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.oneclickdigital.base_uri') || $base_uri;

    my $library_id = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.oneclickdigital.library_id');
    if ($library_id) {
        $self->{library_id} = $library_id;
    } else {
        $logger->error("EbookAPI: no OneClickdigital library ID found for org unit $ou");
        return;
    }

    my $basic_token = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.oneclickdigital.basic_token');
    if ($basic_token) {
        $self->{basic_token} = $basic_token;
    } else {
        $logger->error("EbookAPI: no OneClickdigital basic token found for org unit $ou");
        return;
    }

    return $self;

}

# OneClickdigital API does not require separate client auth;
# we just need to include our basic auth token in requests
sub do_client_auth {
    my $self = shift;
    return;
}

# retrieve OneClickdigital patron ID (if any) based on patron barcode
# GET http://api.oneclickdigital.us/v1/rpc/libraries/{libraryID}/patrons/{barcode}
sub do_patron_auth {
    my ($self, $barcode) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'GET',
        uri    => "$base_uri/rpc/libraries/$library_id/patrons/$barcode"
    };
    my $res = $self->request($req, $session_id);
    # TODO distinguish between unregistered patrons and patron auth failure
    if (defined ($res) && $res->{content}->{patronId}) {
        return $res->{content}->{patronId};
    }
    $logger->error("EbookAPI: no OneClickdigital patron ID found for barcode $barcode");
    return;
}

# get basic metadata for an item (title, author, cover image if any)
# GET http://api.oneclickdigital.us/v1/libraries/{libraryId}/media/{isbn}
sub get_title_info {
    my ($self, $isbn) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'GET',
        uri    => "$base_uri/libraries/$library_id/media/$isbn"
    };
    my $res = $self->request($req, $session_id);
    if (defined ($res)) {
        return {
            title  => $res->{content}->{title},
            author => $res->{content}->{authors}
        };
    } else {
        $logger->error("EbookAPI: could not retrieve OneClickdigital title details for ISBN $isbn");
        return;
    }
}

# does this title have available "copies"? y/n
# GET http://api.oneclickdigital.us/v1/libraries/{libraryID}/media/{isbn}/availability
sub do_availability_lookup {
    my ($self, $isbn) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'GET',
        uri    => "$base_uri/libraries/$library_id/media/$isbn/availability"
    };
    my $res = $self->request($req, $session_id);
    if (defined ($res)) {
        $logger->info("EbookAPI: received availability response for ISBN $isbn: " . Dumper $res);
        return $res->{content}->{availability};
    } else {
        $logger->error("EbookAPI: could not retrieve OneClickdigital availability for ISBN $isbn");
        return;
    }
}

# OneClickdigital API does not support detailed holdings lookup,
# so we return basic availability information.
sub do_holdings_lookup {
    my ($self, $isbn) = @_;
    my $avail = $self->do_availability_lookup($isbn);
    return { available => $avail };
}

# checkout an item to a patron
# item is identified by ISBN, patron ID is their barcode
# POST //api.{domain}/v1/libraries/{libraryId}/patrons/{patronId}/checkouts/{isbn}
sub checkout {
    my ($self, $isbn, $patron_id) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'POST',
        uri    => "$base_uri/libraries/$library_id/patrons/$patron_id/checkouts/$isbn",
        headers => { "Content-Length" => "0" }
    };
    my $res = $self->request($req, $session_id);

    # TODO: more sophisticated response handling
    # HTTP 200 response indicates success, HTTP 409 indicates checkout limit reached
    if (defined ($res)) {
        if ($res->{is_success}) {
            return {
                xact_id => $res->{content}->{transactionId},
                due_date => $res->{content}->{expiration}
            };
        } else {
            $logger->error("EbookAPI: checkout failed for OneClickdigital title $isbn");
            return { error_msg => $res->{content} };
        }
    } else {
        $logger->error("EbookAPI: no response received from OneClickdigital server");
        return;
    }
}

# renew a checked-out item
# item id = ISBN, patron id = barcode
# PUT //api.{domain}/v1/libraries/{libraryId}/patrons/{patronId}/checkouts/{isbn}
sub renew {
    my ($self, $isbn, $patron_id) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'PUT',
        uri    => "$base_uri/libraries/$library_id/patrons/$patron_id/checkouts/$isbn",
        headers => { "Content-Length" => "0" }
    };
    my $res = $self->request($req, $session_id);

    # TODO: more sophisticated response handling
    # HTTP 200 response indicates success
    if (defined ($res)) {
        if ($res->{is_success}) {
            return {
                xact_id => $res->{content}->{transactionId},
                due_date => $res->{content}->{expiration}
            };
        } else {
            $logger->error("EbookAPI: renewal failed for OneClickdigital title $isbn");
            return { error_msg => $res->{content} };
        }
    } else {
        $logger->error("EbookAPI: no response received from OneClickdigital server");
        return;
    }
}

# checkin a checked-out item
# item id = ISBN, patron id = barcode
# XXX API docs indicate that a bearer token is required!
# DELETE //api.{domain}/v1/libraries/{libraryId}/patrons/{patronId}/checkouts/{isbn}
sub checkin {
}

sub place_hold {
}

sub cancel_hold {
}

# GET //api.{domain}/v1/libraries/{libraryId}/patrons/{patronId}/checkouts/all
sub get_patron_checkouts {
    my ($self, $patron_id) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'GET',
        uri    => "$base_uri/libraries/$library_id/patrons/$patron_id/checkouts/all"
    };
    my $res = $self->request($req, $session_id);

    my $checkouts = [];
    if (defined ($res)) {
        $logger->info("EbookAPI: received response for OneClickdigital checkouts: " . Dumper $res);
        foreach my $checkout (@{$res->{content}}) {
            push @$checkouts, {
                xact_id => $checkout->{transactionId},
                title_id => $checkout->{isbn},
                due_date => $checkout->{expiration},
                download_url => $checkout->{downloadUrl},
                title => $checkout->{title},
                author => $checkout->{authors}
            };
        };
        $logger->info("EbookAPI: retrieved " . scalar(@$checkouts) . " OneClickdigital checkouts for patron $patron_id");
        $self->{checkouts} = $checkouts;
        return $self->{checkouts};
    } else {
        $logger->error("EbookAPI: failed to retrieve OneClickdigital checkouts for patron $patron_id");
        return;
    }
}

# GET //api.{domain}/v1/libraries/{libraryId}/patrons/{patronId}/holds/all
sub get_patron_holds {
    my ($self, $patron_id) = @_;
    my $base_uri = $self->{base_uri};
    my $library_id = $self->{library_id};
    my $session_id = $self->{session_id};
    my $req = {
        method => 'GET',
        uri    => "$base_uri/libraries/$library_id/patrons/$patron_id/holds/all"
    };
    my $res = $self->request($req, $session_id);

    my $holds = [];
    if (defined ($res)) {
        $logger->info("EbookAPI: received response for OneClickdigital holds: " . Dumper $res);
        foreach my $hold (@{$res->{content}}) {
            push @$holds, {
                xact_id => $hold->{transactionId},
                title_id => $hold->{isbn},
                expire_date => $hold->{expiration},
                title => $hold->{title},
                author => $hold->{authors},
                # XXX queue position/size and pending vs ready info not available via API
                queue_position => '-',
                queue_size => '-',
                is_ready => 0
            };
        };
        $logger->info("EbookAPI: retrieved " . scalar(@$holds) . " OneClickdigital holds for patron $patron_id");
        $self->{holds} = $holds;
        return $self->{holds};
    } else {
        $logger->error("EbookAPI: failed to retrieve OneClickdigital holds for patron $patron_id");
        return;
    }
}

1;
