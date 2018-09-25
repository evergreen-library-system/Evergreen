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

package OpenILS::Application::EbookAPI::OverDrive;

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
use OpenSRF::Utils::JSON;
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

sub account_id {
    my $self = shift;
    return $self->{account_id};
}

sub websiteid {
    my $self = shift;
    return $self->{websiteid};
}

sub authorizationname {
    my $self = shift;
    return $self->{authorizationname};
}

sub basic_token {
    my $self = shift;
    return $self->{basic_token};
}

sub bearer_token {
    my $self = shift;
    return $self->{bearer_token};
}

sub collection_token {
    my $self = shift;
    return $self->{collection_token};
}

sub granted_auth_uri {
    my $self = shift;
    return $self->{granted_auth_uri};
}

sub password_required {
    my $self = shift;
    return $self->{password_required};
}

sub patron_token {
    my $self = shift;
    return $self->{patron_token};
}

sub initialize {
    my $self = shift;
    my $ou = $self->{ou};

    my $discovery_base_uri = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.discovery_base_uri');
    $self->{discovery_base_uri} = $discovery_base_uri || 'https://api.overdrive.com/v1';
    my $circulation_base_uri = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.circulation_base_uri');
    $self->{circulation_base_uri} = $circulation_base_uri || 'https://patron.api.overdrive.com/v1';

    my $account_id = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.account_id');
    if ($account_id) {
        $self->{account_id} = $account_id;
    } else {
        $logger->error("EbookAPI: no OverDrive account ID found for org unit $ou");
        return;
    }

    my $websiteid = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.websiteid');
    if ($websiteid) {
        $self->{websiteid} = $websiteid;
    } else {
        $logger->error("EbookAPI: no OverDrive website ID found for org unit $ou");
        return;
    }

    my $authorizationname = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.authorizationname');
    if ($authorizationname) {
        $self->{authorizationname} = $authorizationname;
    } else {
        $logger->error("EbookAPI: no OverDrive authorization name found for org unit $ou");
        return;
    }

    my $basic_token = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.basic_token');
    if ($basic_token) {
        $self->{basic_token} = $basic_token;
    } else {
        $logger->error("EbookAPI: no OverDrive basic token found for org unit $ou");
        return;
    }

    my $granted_auth_uri = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.granted_auth_redirect_uri');
    if ($granted_auth_uri) {
        $self->{granted_auth_uri} = $granted_auth_uri;
    }

    my $password_required = OpenILS::Application::AppUtils->ou_ancestor_setting_value($ou, 'ebook_api.overdrive.password_required') || 0;
    $self->{password_required} = $password_required;

    return $self;

}

# Wrapper method for HTTP requests.
sub handle_http_request {
    my $self = shift;
    my $req = shift;

    # Prep our request using defaults.
    $req->{method} = 'GET' if (!$req->{method});
    $req = $self->set_http_headers($req);

    # Send the request.
    my $res = $self->request($req, $self->{session_id});

    $logger->info("EbookAPI: raw OverDrive HTTP response: " . Dumper $res);

    # A "401 Unauthorized" response means we need to re-auth our client or patron.
    if (defined ($res) && $res->{status} =~ /^401/) {
        $logger->info("EbookAPI: 401 response received from OverDrive, re-authorizing...");

        # Always re-auth client to ensure we have an up-to-date client token.
        $self->do_client_auth();

        # If we're using a Circulation API, redo patron auth too.
        my $circulation_base_uri = $self->{circulation_base_uri};
        if ($req->{uri} =~ /^$circulation_base_uri/) {
            $self->do_patron_auth();
        }

        # Now we can update our headers with our fresh client/patron tokens
        # and re-send our request.
        $req = $self->set_http_headers($req);
        return $self->request($req, $self->{session_id});
    }

    # For any non-401 response (including no response at all),
    # just return whatever response we got (if any).
    return $res;
}

# Set the correct headers for our request.
# Authorization headers are determined by which API we're using:
# - Circulation APIs use a patron access token.
# - Discovery APIs use a regular access token.
# - For other APIs, fallback to our basic token.
sub set_http_headers {
    my $self = shift;
    my $req = shift;
    $req->{headers} = {} if (!$req->{headers});
    if (!$req->{headers}->{Authorization}) {
        my $auth_type;
        my $token;
        my $circulation_base_uri = $self->{circulation_base_uri};
        my $discovery_base_uri = $self->{discovery_base_uri};
        if ($req->{uri} =~ /^$circulation_base_uri/) {
            $auth_type = 'Bearer';
            $token = $self->{patron_token};
        } elsif ($req->{uri} =~ /^$discovery_base_uri/) {
            $auth_type = 'Bearer';
            $token = $self->{bearer_token};
        } else {
            $auth_type = 'Basic';
            $token = $self->{basic_token};
        }
        if (!$token) {
            $logger->error("EbookAPI: unable to set HTTP Authorization header without token");
            $logger->error("EbookAPI: failed request: " . Dumper $req);
            return;
        } else {
            $req->{headers}->{Authorization} = "$auth_type $token";
        }
    }
    return $req;
}

# POST /token HTTP/1.1
# Host: oauth.overdrive.com
# Authorization: Basic czZCaGRSa3F0MzpnWDFmQmF0M2JW
# 
# grant_type=client_credentials
sub do_client_auth {
    my $self = shift;
    my $req = {
        method  => 'POST',
        uri     => 'https://oauth.overdrive.com/token',
        headers => {
            'Authorization' => 'Basic ' . $self->{basic_token},
            'Content-Type'  => 'application/x-www-form-urlencoded;charset=UTF-8'
        },
        content => 'grant_type=client_credentials'
    };
    my $res = $self->request($req, $self->{session_id});

    if (defined ($res)) {
        if ($res->{content}->{access_token}) {
            # save our access token for future use
            $self->{bearer_token} = $res->{content}->{access_token};
            # use access token to grab other library info (e.g. collection token)
            $self->get_library_info();
            return $res;
        } else {
            $logger->error("EbookAPI: bearer token not received from OverDrive API");
            $logger->error("EbookAPI: bad response: " . Dumper $res);
        }
    } else {
        $logger->error("EbookAPI: no client authentication response from OverDrive API");
    }
    return;
}

sub do_patron_auth {
    my $self = shift;
    my @args = @_;
    if ($self->{granted_auth_uri}) {
        return $self->do_granted_patron_auth(@args);
    } else {
        return $self->do_basic_patron_auth(@args);
    }
}

# TODO
sub do_granted_patron_auth {
}

# POST /patrontoken HTTP/1.1
# Host: oauth-patron.overdrive.com
# Authorization: Basic {Base64-encoded string}
# Content-Type: application/x-www-form-urlencoded;charset=UTF-8
# 
# grant_type=password&username=1234567890&password=1234&scope=websiteid:12345 authorizationname:default
# OR:
# grant_type=password&username=1234567890&password=[ignore]&password_required=false&scope=websiteid:12345 authorizationname:default
sub do_basic_patron_auth {
    my $self = shift;
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

    # TODO handle cached/expired tokens?
    # Making a request using an expired token will give a 401 Unauthorized error.
    # Handle this appropriately.

    # request content is an ugly url-encoded string
    my $pw = (defined $self->{patron_password}) ? $self->{patron_password} : '';
    my $content = 'grant_type=password';
    $content .= "&username=$barcode";
    if ($self->{password_required}) {
        $content .= "&password=$pw";
    } else {
        $content .= '&password=xxx&password_required=false'
    }
    $content .= '&scope=websiteid:' . $self->{websiteid} . ' authorizationname:' . $self->{authorizationname};

    my $req = {
        method  => 'POST',
        uri     => 'https://oauth-patron.overdrive.com/patrontoken',
        headers => {
            'Authorization' => 'Basic ' . $self->{basic_token},
            'Content-Type'  => 'application/x-www-form-urlencoded;charset=UTF-8'
        },
        content => $content
    };
    my $res = $self->request($req, $self->{session_id});

    if (defined ($res)) {
        if ($res->{content}->{access_token}) {
            $self->{patron_token} = $res->{content}->{access_token};
            return $self->{patron_token};
        } else {
            $logger->error("EbookAPI: patron access token not received from OverDrive API");
        }
    } else {
        $logger->error("EbookAPI: no patron authentication response from OverDrive API");
    }
    return;
}

# GET http://api.overdrive.com/v1/libraries/1225
# User-Agent: {Your application}
# Authorization: Bearer {OAuth access token}
# Host: api.overdrive.com
sub get_library_info {
    my $self = shift;
    my $library_id = $self->{account_id};
    my $req = {
        method  => 'GET',
        uri     => $self->{discovery_base_uri} . "/libraries/$library_id"
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        $self->{collection_token} = $res->{content}->{collectionToken};
        return $self->{collection_token};
    } else {
        $logger->error("EbookAPI: OverDrive Library Account API request failed");
        return;
    }
}

# GET http://api.overdrive.com/v1/collections/v1L1BYwAAAA2Q/products/76c1b7d0-17f4-4c05-8397-c66c17411584/metadata
# User-Agent: {Your application}
# Authorization: Bearer {OAuth access token}
# Host: api.overdrive.com
sub get_title_info {
    my $self = shift;
    my $title_id = shift;
    $self->do_client_auth() if (!$self->{bearer_token});
    $self->get_library_info() if (!$self->{collection_token});
    my $collection_token = $self->{collection_token};
    my $req = {
        method  => 'GET',
        uri     => $self->{discovery_base_uri} . "/collections/$collection_token/products/$title_id/metadata"
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{content}->{title}) {
            my $info = {
                title  => $res->{content}->{title},
                author => $res->{content}->{creators}[0]{name}
            };
            # Append format information (useful for checkouts).
            $info->{formats} = $self->get_formats($title_id);
            return $info;
        } else {
            $logger->error("EbookAPI: OverDrive metadata lookup failed for $title_id");
        }
    } else {
        $logger->error("EbookAPI: no metadata response from OverDrive API");
    }
    return;
}

# GET http://api.overdrive.com/v1/collections/L1BAAEAAA2i/products/76C1B7D0-17F4-4C05-8397-C66C17411584/availability
# User-Agent: {Your application}
# Authorization: Bearer {OAuth access token}
# Host: api.overdrive.com
sub do_availability_lookup {
    my $self = shift;
    my $title_id = shift;
    $self->do_client_auth() if (!$self->{bearer_token});
    $self->get_library_info() if (!$self->{collection_token});
    my $req = {
        method  => 'GET',
        uri     => $self->{discovery_base_uri} . "/collections/" . $self->{collection_token} . "/products/$title_id/availability"
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        return $res->{content}->{available};
    } else {
        $logger->error("EbookAPI: could not retrieve OverDrive availability for title $title_id");
        return;
    }
}

# Holdings lookup has two parts:
#
# 1. Copy availability: as above, but grab more details.
#
# 2. Formats:
#     GET https://api.overdrive.com/v1/collections/v1L1BYwAAAA2Q/products/76c1b7d0-17f4-4c05-8397-c66c17411584/metadata
#     User-Agent: {Your application}
#     Authorization: Bearer {OAuth access token}
#     Host: api.overdrive.com
#
sub do_holdings_lookup {
    my ($self, $title_id) = @_;
    $self->do_client_auth() if (!$self->{bearer_token});
    $self->get_library_info() if (!$self->{collection_token});
    my $collection_token = $self->{collection_token};

    # prepare data structure to be used as return value
    my $holdings = {
        copies_owned => 0,
        copies_available => 0,
        formats => []
    };

    # request copy availability totals
    my $avail_req = {
        method  => 'GET',
        uri     => $self->{discovery_base_uri} . "/collections/$collection_token/products/$title_id/availability"
    };
    if (my $avail_res = $self->handle_http_request($avail_req, $self->{session_id})) {
        $holdings->{copies_owned} = $avail_res->{content}->{copiesOwned};
        $holdings->{copies_available} = $avail_res->{content}->{copiesAvailable};
    } else {
        $logger->error("EbookAPI: failed to retrieve OverDrive holdings counts for title $title_id");
    }

    # request available formats
    $holdings->{formats} = $self->get_formats($title_id);

    return $holdings;
}

# Returns a list of available formats for a given title.
sub get_formats {
    my ($self, $title_id) = @_;
    $self->do_client_auth() if (!$self->{bearer_token});
    $self->get_library_info() if (!$self->{collection_token});
    my $collection_token = $self->{collection_token};

    my $formats = [];

    my $format_req = {
        method  => 'GET',
        uri     => $self->{discovery_base_uri} . "/collections/$collection_token/products/$title_id/metadata"
    };
    if (my $format_res = $self->handle_http_request($format_req, $self->{session_id})) {
        if ($format_res->{content}->{formats}) {
            foreach my $f (@{$format_res->{content}->{formats}}) {
                push @$formats, { id => $f->{id}, name => $f->{name} };
            }
        } else {
            $logger->info("EbookAPI: OverDrive holdings format request for title $title_id contained no format information");
        }
    } else {
        $logger->error("EbookAPI: failed to retrieve OverDrive holdings formats for title $title_id");
    }

    return $formats;
}

# POST https://patron.api.overdrive.com/v1/patrons/me/checkouts
# Authorization: Bearer {OAuth patron access token}
# Content-Type: application/json; charset=utf-8
# 
# Request content looks like this:
# {
#     "fields": [
#         {
#             "name": "reserveId",
#             "value": "76C1B7D0-17F4-4C05-8397-C66C17411584"
#         }
#     ]
# }
#
# Response looks like this:
# {
#     "reserveId": "76C1B7D0-17F4-4C05-8397-C66C17411584",
#     "expires": "10/14/2013 10:56:00 AM",
#     "isFormatLockedIn": false,
#     "formats": [
#         {
#             "reserveId": "76C1B7D0-17F4-4C05-8397-C66C17411584",
#             "formatType": "ebook-overdrive",
#             "linkTemplates": {
#                 "downloadLink": {
#                     "href": "https://patron.api.overdrive.com/v1/patrons/me/checkouts/76C1B7D0-17F4-4C05-8397-C66C17411584/formats/ebook-overdrive/downloadlink?errorpageurl={errorpageurl}&odreadauthurl={odreadauthurl}",
#                     ...
#                 },
#                 ...
#             },
#             ...
#         }
#     ],
#     ...
# }
#
# Our return value looks like this:
# {
#     due_date => "10/14/2013 10:56:00 AM",
#     formats => [
#         "ebook-overdrive" => "https://patron.api.overdrive.com/v1/patrons/me/checkouts/76C1B7D0-17F4-4C05-8397-C66C17411584/formats/ebook-overdrive/downloadlink?errorpageurl={errorpageurl}&odreadauthurl={odreadauthurl}",
#         ...
#     ]
# }
sub checkout {
    my ($self, $title_id, $patron_token, $format) = @_;
    my $request_content = {
        fields => [
            {
                name  => 'reserveId',
                value => $title_id
            }
        ]
    };
    if ($format) {
        push @{$request_content->{fields}}, { name => 'formatType', value => $format };
    }
    my $req = {
        method  => 'POST',
        uri     => $self->{circulation_base_uri} . "/patrons/me/checkouts",
        content => OpenSRF::Utils::JSON->perl2JSON($request_content)
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{content}->{expires}) {
            my $checkout = { due_date => $res->{content}->{expires} };
            if (defined $res->{content}->{formats}) {
                my $formats = {};
                foreach my $f (@{$res->{content}->{formats}}) {
                    my $ftype = $f->{formatType};
                    $formats->{$ftype} = $f->{linkTemplates}->{downloadLink}->{href};
                }
                $checkout->{formats} = $formats;
            }
            return $checkout;
        }
        $logger->error("EbookAPI: checkout failed for OverDrive title $title_id");
        return { error_msg => ( (defined $res->{content}) ? $res->{content} : 'Unknown checkout error' ) };
    }
    $logger->error("EbookAPI: no response received from OverDrive server");
    return;
}

# renew is not supported by OverDrive API
sub renew {
    $logger->error("EbookAPI: OverDrive API does not support renewals");
    return { error_msg => "Title cannot be renewed." };
}

# NB: A title cannot be checked in once a format has been locked in.
# Successful checkin returns an HTTP 204 response with no content.
# DELETE https://patron.api.overdrive.com/v1/patrons/me/checkouts/08F7D7E6-423F-45A6-9A1E-5AE9122C82E7
# Authorization: Bearer {OAuth patron access token}
# Host: patron.api.overdrive.com
sub checkin {
    my ($self, $title_id, $patron_token) = @_;
    my $req = {
        method  => 'DELETE',
        uri     => $self->{circulation_base_uri} . "/patrons/me/checkouts/$title_id"
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{status} =~ /^204/) {
            return {};
        } else {
            $logger->error("EbookAPI: checkin failed for OverDrive title $title_id");
            return { error_msg => ( (defined $res->{content}) ? $res->{content} : 'Checkin failed' ) };
        }
    }
    $logger->error("EbookAPI: no response received from OverDrive server");
    return;
}

sub place_hold {
    my ($self, $title_id, $patron_token, $email) = @_;
    my $fields = [
        {
            name  => 'reserveId',
            value => $title_id
        }
    ];
    if ($email) {
        push @$fields, { name => 'emailAddress', value => $email };
        # TODO: Use autoCheckout=true when we have a patron email?
    } else {
        push @$fields, { name => 'ignoreEmail', value => 'true' };
    }
    my $request_content = { fields => $fields };
    my $req = {
        method  => 'POST',
        uri     => $self->{circulation_base_uri} . "/patrons/me/holds",
        content => OpenSRF::Utils::JSON->perl2JSON($request_content)
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{content}->{holdPlacedDate}) {
            return {
                queue_position => $res->{content}->{holdListPosition},
                queue_size => $res->{content}->{numberOfHolds},
                expire_date => (defined $res->{content}->{holdExpires}) ? $res->{content}->{holdExpires} : undef
            };
        }
        $logger->error("EbookAPI: place hold failed for OverDrive title $title_id");
        return { error_msg => "Could not place hold." };
    }
    $logger->error("EbookAPI: no response received from OverDrive server");
    return;
}

sub cancel_hold {
    my ($self, $title_id, $patron_token) = @_;
    my $req = {
        method  => 'DELETE',
        uri     => $self->{circulation_base_uri} . "/patrons/me/holds/$title_id"
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{status} =~ /^204/) {
            return {};
        } else {
            $logger->error("EbookAPI: cancel hold failed for OverDrive title $title_id");
            return { error_msg => ( (defined $res->{content}) ? $res->{content} : 'Could not cancel hold' ) };
        }
    }
    $logger->error("EbookAPI: no response received from OverDrive server");
    return;
}

# List of patron checkouts:
# GET http://patron.api.overdrive.com/v1/patrons/me/checkouts
# User-Agent: {Your application}
# Authorization: Bearer {OAuth patron access token}
# Host: patron.api.overdrive.com
#
# Response looks like this:
# {
#     "totalItems": 4,
#     "totalCheckouts": 2,
#     "checkouts": [
#         {
#             "reserveId": "A03EAC2C-C088-46C6-B9E9-59D6C11A3596",
#             "expires": "2015-08-11T18:53:00Z",
#             ...
#         }
#     ],
#     ...
# }
#
# To get title metadata (e.g. title/author), do get_title_info(reserveId).
sub get_patron_checkouts {
    my $self = shift;
    my $patron_token = shift;
    if (my $res = $self->do_get_patron_xacts('checkouts', $patron_token)) {
        my $checkouts = [];
        foreach my $checkout (@{$res->{content}->{checkouts}}) {
            my $title_id = $checkout->{reserveId};
            my $title_info = $self->get_title_info($title_id);
            my $formats = {};
            foreach my $f (@{$checkout->{formats}}) {
                my $ftype = $f->{formatType};
                $formats->{$ftype} = $f->{linkTemplates}->{downloadLink}->{href};
            };
            push @$checkouts, {
                title_id => $title_id,
                due_date => $checkout->{expires},
                title => $title_info->{title},
                author => $title_info->{author},
                formats => $formats
            }
        };
        $self->{checkouts} = $checkouts;
        return $self->{checkouts};
    } else {
        $logger->error("EbookAPI: unable to retrieve OverDrive checkouts for patron " . $self->{patron_barcode});
        return;
    }
}

sub get_patron_holds {
    my $self = shift;
    my $patron_token = shift;
    if (my $res = $self->do_get_patron_xacts('holds', $patron_token)) {
        my $holds = [];
        foreach my $hold (@{$res->{content}->{holds}}) {
            my $title_id = $hold->{reserveId};
            my $title_info = $self->get_title_info($title_id);
            my $this_hold = {
                title_id => $title_id,
                queue_position => $hold->{holdListPosition},
                queue_size => $hold->{numberOfHolds},
                # TODO: special handling for ready-to-checkout holds
                is_ready => ( $hold->{actions}->{checkout} ) ? 1 : 0,
                is_frozen => ( $hold->{holdSuspension} ) ? 1 : 0,
                create_date => $hold->{holdPlacedDate},
                expire_date => ( $hold->{holdExpires} ) ? $hold->{holdExpires} : '-',
                title => $title_info->{title},
                author => $title_info->{author}
            };
            # TODO: hold suspensions
            push @$holds, $this_hold;
        }
        $self->{holds} = $holds;
        return $self->{holds};
    } else {
        $logger->error("EbookAPI: unable to retrieve OverDrive holds for patron " . $self->{patron_barcode});
        return;
    }
}

# generic function for retrieving patron transactions
sub do_get_patron_xacts {
    my $self = shift;
    my $xact_type = shift;
    my $patron_token = shift;
    if (!$patron_token) {
        if ($self->{patron_barcode}) {
            $self->do_client_auth() if (!$self->{bearer_token});
            $self->do_patron_auth();
        } else {
            $logger->error("EbookAPI: Cannot retrieve OverDrive $xact_type with no patron information");
        }
    }
    my $req = {
        method  => 'GET',
        uri     => $self->{circulation_base_uri} . "/patrons/me/$xact_type"
    };
    return $self->handle_http_request($req, $self->{session_id});
}

# get download URL for checked-out title
sub do_get_download_link {
    my ($self, $request_link) = @_;
    # Request links use the same domain as the circulation base URI, but they
    # are apparently always plain HTTP.  The request link still works if you
    # use HTTPS instead.  So, if our circulation base URI uses HTTPS, let's
    # force the request link to HTTPS too, for two reasons:
    # 1. A preference for HTTPS is implied by the library's circulation base
    #    URI setting.
    # 2. The base URI of the request link has to match the circulation base URI
    #    (including the same protocol) in order for the handle_http_request()
    #    method above to automatically re-authenticate the patron, if required.
    if ($self->{circulation_base_uri} =~ /^https:/) {
        $request_link =~ s/^http:/https:/;
    }
    my $req = {
        method  => 'GET',
        uri     => $request_link
    };
    if (my $res = $self->handle_http_request($req, $self->{session_id})) {
        if ($res->{content}->{links}->{contentlink}->{href}) {
            return { url => $res->{content}->{links}->{contentlink}->{href} };
        }
        return { error_msg => ( (defined $res->{content}) ? $res->{content} : 'Could not get content link' ) };
    }
    $logger->error("EbookAPI: no response received from OverDrive server");
    return;
}

1;
