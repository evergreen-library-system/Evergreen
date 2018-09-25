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
# We define a handler class for each vendor API (OneClickdigital, OverDrive, etc.).
# See EbookAPI/Test.pm for a reference implementation with required methods,
# arguments, and return values.
# ====================================================================== 

package OpenILS::Application::EbookAPI;

use strict;
use warnings;

use Time::HiRes qw/gettimeofday/;
use Digest::MD5 qw/md5_hex/;

use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenSRF::AppSession;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::HTTPClient;

my $handler;
my $cache;
my $cache_timeout;
my $default_request_timeout;

# map EbookAPI vendor codes to corresponding packages
our %vendor_handlers = (
    'ebook_test' => 'OpenILS::Application::EbookAPI::Test',
    'oneclickdigital' => 'OpenILS::Application::EbookAPI::OneClickdigital',
    'overdrive' => 'OpenILS::Application::EbookAPI::OverDrive'
);

sub initialize {
    $cache = OpenSRF::Utils::Cache->new;

    my $sclient = OpenSRF::Utils::SettingsClient->new();
    $cache_timeout = $sclient->config_value("apps", "open-ils.ebook_api", "app_settings", "cache_timeout" ) || 300;
    $default_request_timeout = $sclient->config_value("apps", "open-ils.ebook_api", "app_settings", "request_timeout" ) || 60;
}

# returns the cached object (if successful)
sub update_cache {
    my $cache_obj = shift;
    my $overlay = shift || 0;
    my $cache_key;
    if ($cache_obj->{session_id}) {
        $cache_key = $cache_obj->{session_id};
    } else {
        $logger->error("EbookAPI: cannot update cache with unknown cache object");
        return;
    }

    # Optionally, keep old cached field values unless a new value for that
    # field is explicitly provided.  This makes it easier for asynchronous
    # requests (e.g. for circs and holds) to cache their results.
    if ($overlay) {
        if (my $orig_cache = $cache->get_cache($cache_key)) {
            $logger->info("EbookAPI: overlaying new values on existing cache object");
            foreach my $k (%$cache_obj) {
                # Add/overwrite existing cached value if a new value is defined.
                $orig_cache->{$k} = $cache_obj->{$k} if (defined $cache_obj->{$k});
            }
            # The cache object we want to save is the (updated) original one.
            $cache_obj = $orig_cache;
        }
    }

    try { # fail silently if there's no pre-existing cache to delete
        $cache->delete_cache($cache_key);
    } catch Error with {};
    if (my $success_key = $cache->put_cache($cache_key, $cache_obj, $cache_timeout)) {
        return $cache->get_cache($success_key);
    } else {
        $logger->error("EbookAPI: error when updating cache with object");
        return;
    }
}

sub retrieve_session {
    my $session_id = shift;
    unless ($session_id) {
        $logger->info("EbookAPI: no session ID provided");
        return;
    }
    my $cached_session = $cache->get_cache($session_id) || undef;
    if ($cached_session) {
        return $cached_session;
    } else {
        $logger->info("EbookAPI: could not find cached session with id $session_id");
        return;
    }
}

# prepare new handler from session
# (will retrieve cached session unless a session object is provided)
sub new_handler {
    my $session_id = shift;
    my $ses = shift || retrieve_session($session_id);
    if (!$ses) {
        $logger->error("EbookAPI: could not start handler - no cached session with ID $session_id");
        return;
    }
    my $module = ref($ses);
    $logger->info("EbookAPI: starting new $module handler from cached session $session_id...");
    $module->use;
    my $handler = $module->new($ses);
    return $handler;
}


sub check_session {
    my $self = shift;
    my $conn = shift;
    my $session_id = shift;
    my $vendor = shift;
    my $ou = shift;

    return start_session($self, $conn, $vendor, $ou) unless $session_id;

    my $cached_session = retrieve_session($session_id);
    if ($cached_session) {
        # re-authorize cached session, if applicable
        my $handler = new_handler($session_id, $cached_session);
        $handler->do_client_auth();
        if (update_cache($handler)) {
            return $session_id;
        } else {
            $logger->error("EbookAPI: error updating session cache");
            return;
        }
    } else {
        return start_session($self, $conn, $vendor, $ou);
    }
}
__PACKAGE__->register_method(
    method => 'check_session',
    api_name => 'open-ils.ebook_api.check_session',
    api_level => 1,
    argc => 2,
    signature => {
        desc => "Validate an existing EbookAPI session, or initiate a new one",
        params => [
            {
                name => 'session_id',
                desc => 'The EbookAPI session ID being checked',
                type => 'string'
            },
            {
                name => 'vendor',
                desc => 'The ebook vendor (e.g. "oneclickdigital")',
                type => 'string'
            },
            {
                name => 'ou',
                desc => 'The context org unit ID',
                type => 'number'
            }
        ],
        return => {
            desc => 'Returns an EbookAPI session ID',
            type => 'string'
        }
    }
);

sub _start_session {
    my $vendor = shift;
    my $ou = shift;
    $ou = $ou || 1; # default to top-level org unit

    my $module;
    
    # determine EbookAPI handler from vendor name
    # TODO handle API versions?
    if ($vendor_handlers{$vendor}) {
        $module = $vendor_handlers{$vendor};
    } else {
        $logger->error("EbookAPI: No handler module found for $vendor!");
        return;
    }

    # TODO cache session? reuse an existing one if available?

    # generate session ID
    my ($sec, $usec) = gettimeofday();
    my $r = rand();
    my $session_id = "ebook_api.ses." . md5_hex("$sec-$usec-$r");
    
    my $args = {
        vendor => $vendor,
        ou => $ou,
        session_id => $session_id
    };

    $module->use;
    $handler = $module->new($args);  # create new handler object
    $handler->initialize();          # set handler attributes
    $handler->do_client_auth();      # authorize client session against API, if applicable

    # our "session" is actually just our handler object, serialized and cached
    my $ckey = $handler->{session_id};
    $cache->put_cache($ckey, $handler, $cache_timeout);

    return $handler->{session_id};
}

sub start_session {
    my $self = shift;
    my $conn = shift;
    my $vendor = shift;
    my $ou = shift;
    return _start_session($vendor, $ou);
}
__PACKAGE__->register_method(
    method => 'start_session',
    api_name => 'open-ils.ebook_api.start_session',
    api_level => 1,
    argc => 1,
    signature => {
        desc => "Initiate an EbookAPI session",
        params => [
            {
                name => 'vendor',
                desc => 'The ebook vendor (e.g. "oneclickdigital")',
                type => 'string'
            },
            {
                name => 'ou',
                desc => 'The context org unit ID',
                type => 'number'
            }
        ],
        return => {
            desc => 'Returns an EbookAPI session ID',
            type => 'string'
        }
    }
);

sub cache_patron_password {
    my $self = shift;
    my $conn = shift;
    my $session_id = shift;
    my $password = shift;

    # We don't need the handler module for this.
    # Let's just update the cache directly.
    if (my $ses = $cache->get_cache($session_id)) {
        $ses->{patron_password} = $password;
        if (update_cache($ses)) {
            return $session_id;
        } else {
            $logger->error("EbookAPI: there was an error caching patron password");
            return;
        }
    }
}
__PACKAGE__->register_method(
    method => 'cache_patron_password',
    api_name => 'open-ils.ebook_api.patron.cache_password',
    api_level => 1,
    argc => 2,
    signature => {
        desc => "Cache patron password on login for use during EbookAPI patron authentication",
        params => [
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'patron_password',
                desc => 'The patron password',
                type => 'string'
            }
        ],
        return => { desc => 'A session key, or undef' }
    }
);

# Submit an HTTP request to a specified API endpoint.
#
# Params:
#
#   $req - hashref containing the following:
#       method: HTTP request method (defaults to GET)
#       uri: API endpoint URI (required)
#       header: arrayref of HTTP headers (optional, but see below)
#       content: content of HTTP request (optional)
#       request_timeout (defaults to value in opensrf.xml)
#   $session_id - id of cached EbookAPI session
#
# A "Content-Type: application/json" header is automatically added to each
# request.  If no Authorization header is provided via the $req param, the
# following header will also be automatically added:
#
#   Authorization: basic $basic_token
#
# ... where $basic_token is derived from the cached session identified by the
# $session_id param.  If this does not meet the needs of your API, include the
# correct Authorization header in $req->{header}.
sub request {
    my $self = shift;
    my $req = shift;
    my $session_id = shift;

    my $uri;
    if (!defined ($req->{uri})) {
        $logger->error('EbookAPI: attempted an HTTP request but no URI was provided');
        return;
    } else {
        $uri = $req->{uri};
    }
    
    my $method = defined $req->{method} ? $req->{method} : 'GET';
    my $headers = defined $req->{headers} ? $req->{headers} : {};
    my $content = defined $req->{content} ? $req->{content} : undef;
    my $request_timeout = defined $req->{request_timeout} ? $req->{request_timeout} : $default_request_timeout;

    # JSON as default content type
    if ( !defined ($headers->{'Content-Type'}) ) {
        $headers->{'Content-Type'} = 'application/json';
    }

    # all requests also require an Authorization header;
    # let's default to using our basic token, if available
    if ( !defined ($headers->{'Authorization'}) ) {
        if (!$session_id) {
            $logger->error("EbookAPI: HTTP request requires session info but no session ID was provided");
            return;
        }
        my $ses = retrieve_session($session_id);
        if ($ses) {
            my $basic_token = $ses->{basic_token};
            $headers->{'Authorization'} = "basic $basic_token";
        }
    }

    my $client = OpenILS::Utils::HTTPClient->new();
    my $res = $client->request(
        $method,
        $uri,
        $headers,
        $content,
        $request_timeout
    );
    if (!defined ($res)) {
        $logger->error('EbookAPI: no HTTP response received');
        return;
    } else {
        $logger->info("EbookAPI: response received from server: " . $res->status_line);
        return {
            is_success => $res->is_success,
            status     => $res->status_line,
            content    => OpenSRF::Utils::JSON->JSON2perl($res->decoded_content)
        };
    }
}

sub get_details {
    my ($self, $conn, $session_id, $title_id) = @_;
    my $handler = new_handler($session_id);
    return $handler->get_title_info($title_id);
}
__PACKAGE__->register_method(
    method => 'get_details',
    api_name => 'open-ils.ebook_api.title.details',
    api_level => 1,
    argc => 2,
    signature => {
        desc => "Get basic metadata for an ebook title",
        params => [
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The title ID (ISBN, unique identifier, etc.)',
                type => 'string'
            }
        ],
        return => {
            desc => 'Success: { title => "Title", author => "Author Name" } / Failure: { error => "Title not found" }',
            type => 'hashref'
        }
    }
);

sub get_availability {
    my ($self, $conn, $session_id, $title_id) = @_;
    my $handler = new_handler($session_id);
    return $handler->do_availability_lookup($title_id);
}
__PACKAGE__->register_method(
    method => 'get_availability',
    api_name => 'open-ils.ebook_api.title.availability',
    api_level => 1,
    argc => 2,
    signature => {
        desc => "Get availability info for an ebook title",
        params => [
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The title ID (ISBN, unique identifier, etc.)',
                type => 'string'
            }
        ],
        return => {
            desc => 'Returns 1 if title is available, 0 if not available, or undef if availability info could not be retrieved',
            type => 'number'
        }
    }
);

sub get_holdings {
    my ($self, $conn, $session_id, $title_id) = @_;
    my $handler = new_handler($session_id);
    return $handler->do_holdings_lookup($title_id);
}
__PACKAGE__->register_method(
    method => 'get_holdings',
    api_name => 'open-ils.ebook_api.title.holdings',
    api_level => 1,
    argc => 2,
    signature => {
        desc => "Get detailed holdings info (copy counts and formats) for an ebook title, or basic availability if holdings info is unavailable",
        params => [
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The title ID (ISBN, unique identifier, etc.)',
                type => 'string'
            }
        ],
        return => {
            desc => 'Returns a hashref of holdings info with one or more of the following keys: available (0 or 1), copies_owned, copies_available, formats (arrayref of strings)',
            type => 'hashref'
        }
    }
);

# Wrapper function for performing transactions that require an authenticated
# patron and a title identifier (checkout, checkin, renewal, etc).
#
# Params:
# - title_id: ISBN (OneClickdigital), title identifier (OverDrive)
# - barcode: patron barcode
#
sub do_xact {
    my ($self, $conn, $auth, $session_id, $title_id, $barcode, $param) = @_;

    my $action;
    if ($self->api_name =~ /checkout/) {
        $action = 'checkout';
    } elsif ($self->api_name =~ /checkin/) {
        $action = 'checkin';
    } elsif ($self->api_name =~ /renew/) {
        $action = 'renew';
    } elsif ($self->api_name =~ /place_hold/) {
        $action = 'place_hold';
    } elsif ($self->api_name =~ /cancel_hold/) {
        $action = 'cancel_hold';
    }
    $logger->info("EbookAPI: doing $action for title $title_id...");

    # verify that user is authenticated in EG
    my $e = new_editor(authtoken => $auth);
    if (!$e->checkauth) {
        $logger->error("EbookAPI: authentication failed: " . $e->die_event);
        return;
    }

    my $handler = new_handler($session_id);
    my $user_token = $handler->do_patron_auth($barcode);

    # handler method constructs and submits request (and handles any external authentication)
    my $res;
    if ($action eq 'checkout') {
        # checkout has format as optional additional param
        $res = $handler->checkout($title_id, $user_token, $param);
    } elsif ($action eq 'place_hold') {
        # place_hold has email as optional additional param
        $res = $handler->place_hold($title_id, $user_token, $param);
    } else {
        $res = $handler->$action($title_id, $user_token);
    }
    if (defined ($res)) {
        return $res;
    } else {
        $logger->error("EbookAPI: could not do $action for title $title_id and patron $barcode");
        return;
    }
}
__PACKAGE__->register_method(
    method => 'do_xact',
    api_name => 'open-ils.ebook_api.checkout',
    api_level => 1,
    argc => 4,
    signature => {
        desc => "Checkout an ebook title to a patron",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The identifier of the title',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron to whom the title will be checked out',
                type => 'string'
            },
        ],
        return => {
            desc => 'Success: { due_date => "2017-01-01" } / Failure: { error_msg => "Checkout limit reached." }',
            type => 'hashref'
        }
    }
);
__PACKAGE__->register_method(
    method => 'do_xact',
    api_name => 'open-ils.ebook_api.renew',
    api_level => 1,
    argc => 4,
    signature => {
        desc => "Renew an ebook title for a patron",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The identifier of the title to be renewed',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron to whom the title is checked out',
                type => 'string'
            },
        ],
        return => {
            desc => 'Success: { due_date => "2017-01-01" } / Failure: { error_msg => "Renewal limit reached." }',
            type => 'hashref'
        }
    }
);
__PACKAGE__->register_method(
    method => 'do_xact',
    api_name => 'open-ils.ebook_api.checkin',
    api_level => 1,
    argc => 4,
    signature => {
        desc => "Check in an ebook title for a patron",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The identifier of the title to be checked in',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron to whom the title is checked out',
                type => 'string'
            },
        ],
        return => {
            desc => 'Success: { } / Failure: { error_msg => "Checkin failed." }',
            type => 'hashref'
        }
    }
);
__PACKAGE__->register_method(
    method => 'do_xact',
    api_name => 'open-ils.ebook_api.place_hold',
    api_level => 1,
    argc => 4,
    signature => {
        desc => "Place a hold on an ebook title for a patron",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The identifier of the title',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron for whom the title is being held',
                type => 'string'
            },
        ],
        return => {
            desc => 'Success: { queue_position => 1, queue_size => 1, expire_date => "2017-01-01" } / Failure: { error_msg => "Could not place hold." }',
            type => 'hashref'
        }
    }
);
__PACKAGE__->register_method(
    method => 'do_xact',
    api_name => 'open-ils.ebook_api.cancel_hold',
    api_level => 1,
    argc => 4,
    signature => {
        desc => "Cancel a hold on an ebook title for a patron",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'title_id',
                desc => 'The identifier of the title',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron',
                type => 'string'
            },
        ],
        return => {
            desc => 'Success: { } / Failure: { error_msg => "Could not cancel hold." }',
            type => 'hashref'
        }
    }
);

sub _get_patron_xacts {
    my ($xact_type, $auth, $session_id, $barcode) = @_;

    $logger->info("EbookAPI: getting $xact_type for patron $barcode");

    # verify that user is authenticated in EG
    my $e = new_editor(authtoken => $auth);
    if (!$e->checkauth) {
        $logger->error("EbookAPI: authentication failed: " . $e->die_event);
        return;
    }

    my $handler = new_handler($session_id);
    my $user_token = $handler->do_patron_auth($barcode);

    my $xacts;
    if ($xact_type eq 'checkouts') {
        $xacts = $handler->get_patron_checkouts($user_token);
    } elsif ($xact_type eq 'holds') {
        $xacts = $handler->get_patron_holds($user_token);
    } else {
        $logger->error("EbookAPI: invalid transaction type '$xact_type'");
        return;
    }

    # cache and return transaction details
    $handler->{$xact_type} = $xacts;
    # Overlay transactions onto existing cached handler.
    if (update_cache($handler, 1)) {
        return $handler->{$xact_type};
    } else {
        $logger->error("EbookAPI: error caching transaction details ($xact_type)");
        return;
    }
}

sub get_patron_xacts {
    my ($self, $conn, $auth, $session_id, $barcode) = @_;
    my $xact_type;
    if ($self->api_name =~ /checkouts/) {
        $xact_type = 'checkouts';
    } elsif ($self->api_name =~ /holds/) {
        $xact_type = 'holds';
    }
    return _get_patron_xacts($xact_type, $auth, $session_id, $barcode);
}
__PACKAGE__->register_method(
    method => 'get_patron_xacts',
    api_name => 'open-ils.ebook_api.patron.get_checkouts',
    api_level => 1,
    argc => 3,
    signature => {
        desc => "Get information about a patron's ebook checkouts",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron',
                type => 'string'
            }
        ],
        return => {
            desc => 'Returns an array of transaction details, or undef if no details available',
            type => 'array'
        }
    }
);
__PACKAGE__->register_method(
    method => 'get_patron_xacts',
    api_name => 'open-ils.ebook_api.patron.get_holds',
    api_level => 1,
    argc => 3,
    signature => {
        desc => "Get information about a patron's ebook holds",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron',
                type => 'string'
            }
        ],
        return => {
            desc => 'Returns an array of transaction details, or undef if no details available',
            type => 'array'
        }
    }
);

sub get_all_patron_xacts {
    my ($self, $conn, $auth, $session_id, $barcode) = @_;
    my $checkouts = _get_patron_xacts('checkouts', $auth, $session_id, $barcode);
    my $holds = _get_patron_xacts('holds', $auth, $session_id, $barcode);
    return {
        checkouts => $checkouts,
        holds     => $holds
    };
}
__PACKAGE__->register_method(
    method => 'get_all_patron_xacts',
    api_name => 'open-ils.ebook_api.patron.get_transactions',
    api_level => 1,
    argc => 3,
    signature => {
        desc => "Get information about a patron's ebook checkouts and holds",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'barcode',
                desc => 'The barcode of the patron',
                type => 'string'
            }
        ],
        return => {
            desc => 'Returns a hashref of transactions: { checkouts => [], holds => [], failed => [] }',
            type => 'hashref'
        }
    }
);

sub get_download_link {
    my ($self, $conn, $auth, $session_id, $request_link) = @_;
    my $handler = new_handler($session_id);
    return $handler->do_get_download_link($request_link);
}
__PACKAGE__->register_method(
    method => 'get_download_link',
    api_name => 'open-ils.ebook_api.title.get_download_link',
    api_level => 1,
    argc => 3,
    signature => {
        desc => "Get download link for an OverDrive title that has been checked out",
        params => [
            {
                name => 'authtoken',
                desc => 'Authentication token',
                type => 'string'
            },
            {
                name => 'session_id',
                desc => 'The session ID (provided by open-ils.ebook_api.start_session)',
                type => 'string'
            },
            {
                name => 'request_link',
                desc => 'The URL used to request a download link',
                type => 'string'
            }
        ],
        return => {
            desc => 'Success: { url => "http://example.com/download-link" } / Failure: { error_msg => "Download link request failed." }',
            type => 'hashref'
        }
    }
);

1;
