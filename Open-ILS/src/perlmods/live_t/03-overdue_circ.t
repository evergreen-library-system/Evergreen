#!perl

use Test::More tests => 20;

diag("Test fine generation on checkin against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-03-overdue-circ.t';
use constant WORKSTATION_LIB => 7;
use constant ITEM_BARCODE => 'CONC71000345';
use constant ITEM_ID => 810;

use strict;
use warnings;
use Data::Dumper;
use OpenSRF::System;
use OpenSRF::AppSession;
use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/cleanse_ISO8601/;
use OpenSRF::Utils::SettingsClient;

# Some useful objects
our $cache      = "OpenSRF::Utils::Cache";
our $apputils   = "OpenILS::Application::AppUtils";
our $memcache;
our $authtoken;
our $authtime;

#----------------------------------------------------------------
# Exit a script
#----------------------------------------------------------------
sub err {
    my ($pkg, $file, $line, $sub)  = _caller();
    no warnings;
    die "Script halted with error ".
        "($pkg : $file : $line : $sub):\n" . shift() . "\n";
}

#----------------------------------------------------------------
# This is not the function you're looking for
#----------------------------------------------------------------
sub _caller {
    my ($pkg, $file, $line, $sub)  = caller(2);
    if(!$line) {
        ($pkg, $file, $line)  = caller(1);
        $sub = "";
    }
    return ($pkg, $file, $line, $sub);
}

#----------------------------------------------------------------
# Connect to the servers
#----------------------------------------------------------------
sub osrf_connect {
    my $config = `osrf_config --sysconfdir`;
    chomp $config;
    $config .= '/opensrf_core.xml';
    err("Bootstrap config required") unless $config;
    OpenSRF::System->bootstrap_client( config_file => $config );
    Fieldmapper->import(IDL =>
        OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
}

#----------------------------------------------------------------
# Is the given object an OILS event?
#----------------------------------------------------------------
sub oils_is_event {
    my $e = shift;
    if( $e and ref($e) eq 'HASH' ) {
        return 1 if defined($e->{ilsevent});
    }
    return 0;
}

#----------------------------------------------------------------
# If the given object is an event, this prints the event info 
# and exits the script
#----------------------------------------------------------------
sub oils_event_die {
    my $evt = shift;
    my ($pkg, $file, $line, $sub)  = _caller();
    if(oils_is_event($evt)) {
        if($evt->{ilsevent}) {
            diag("\nReceived Event($pkg : $file : $line : $sub): \n" . Dumper($evt));
            exit 1;
        }
    }
}

#----------------------------------------------------------------
# Login to the auth server and set the global $authtoken var
#----------------------------------------------------------------
sub oils_login {
    my( $username, $password, $type, $ws ) = @_;

    $type |= "staff";

    my $seed = $apputils->simplereq( 'open-ils.auth',
        'open-ils.auth.authenticate.init', $username );
    err("No auth seed") unless $seed;

    my $response = $apputils->simplereq( 'open-ils.auth',
        'open-ils.auth.authenticate.complete',
        {   username => $username,
            password => md5_hex($seed . md5_hex($password)),
            type => $type, workstation => $ws });

    err("No auth response returned on login") unless $response;

    oils_event_die($response);

    $authtime  = $response->{payload}->{authtime};
    $authtoken = $response->{payload}->{authtoken};
    diag("authtime is $authtime, authtoken is $authtoken");
    return $authtoken;
}

#----------------------------------------------------------------
# Destroys the login session on the server
#----------------------------------------------------------------
sub oils_logout {
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete', (@_ ? shift : $authtoken) );
}

#----------------------------------------------------------------
# var $response = simplereq( $service, $method, @params );
#----------------------------------------------------------------
sub simplereq    { return $apputils->simplereq(@_); }
sub osrf_request { return $apputils->simplereq(@_); }

#----------------------------------------------------------------

sub register_workstation {
    my $resp = osrf_request(
        'open-ils.actor',
        'open-ils.actor.workstation.register',
        $authtoken, WORKSTATION_NAME, WORKSTATION_LIB);
    return $resp;
}

sub do_checkout {
    my( $patronid, $barcode ) = @_;
    my $args = { patron => $patronid, barcode => $barcode };
    my $resp = osrf_request(
        'open-ils.circ',
        'open-ils.circ.checkout.full', $authtoken, $args );
    return $resp;
}

sub do_checkin {
    my $barcode  = shift;
    my $args = { barcode => $barcode };
    my $resp = osrf_request(
        'open-ils.circ',
        'open-ils.circ.checkin', $authtoken, $args );
    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data, full-auto install by
# eg_wheezy_installer.sh, etc.
#----------------------------------------------------------------

osrf_connect();
my $storage_ses = OpenSRF::AppSession->create('open-ils.storage');
my $circ_ses = OpenSRF::AppSession->create('open-ils.circ');
my $cstore_ses = OpenSRF::AppSession->connect('open-ils.cstore');

my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', 1);
if (my $user_resp = $user_req->recv) {
    if (my $user = $user_resp->content) {
        is(
            ref $user,
            'Fieldmapper::actor::user',
            'open-ils.storage.direct.actor.user.retrieve returned aou object'
        );
        is(
            $user->usrname,
            'admin',
            'User with id = 1 is admin user'
        );
    }
}

my $item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->barcode,
            ITEM_BARCODE,
            'Item with id = ' . ITEM_ID . ' has barcode ' . ITEM_BARCODE
        );
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . ITEM_ID . ' has status of Reshelving or Available'
        );
    }
}

oils_login('admin','demo123','staff');
ok(
    $authtoken,
    'Have an authtoken'
);
my $ws = register_workstation();
ok(
    ! ref $ws,
    'Registered a new workstation'
);

oils_logout();
oils_login('admin','demo123','staff',WORKSTATION_NAME);
ok(
    $authtoken,
    'Have an authtoken associated with the workstation'
);

my $checkout_resp = do_checkout(1, ITEM_BARCODE);
is(
    ref $checkout_resp,
    'HASH',
    'Checkout request returned a HASH'
);
is(
    $checkout_resp->{ilsevent},
    0,
    'Checkout returned a SUCCESS event'
);
ok(
    ref $checkout_resp->{payload},
    'Checkout response object has payload object'
);
ok(
    ref $checkout_resp->{payload}->{circ},
    'Payload object has circ object'
);
is(
    $checkout_resp->{payload}->{circ}->duration,
    '7 days',
    'Circ objection has loan duration of "7 days"'
);

my $circ = $checkout_resp->{payload}->{circ};

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            1,
            'Item with id = ' . ITEM_ID . ' has status of Checked Out after fresh Storage request'
        );
    }
}

my $bill_req = $circ_ses->request(
    'open-ils.circ.money.billing.retrieve.all',
    $authtoken,
    $circ->id
);
if (my $bill_resp = $bill_req->recv) {
    if (my $bills = $bill_resp->content) {
        is(
            scalar( @{ $bills } ),
            0,
            'Zero bills associated with circulation'
        );
    }
}

my $xact_start = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($circ->xact_start))->epoch;
my $due_date = DateTime::Format::ISO8601->parse_datetime(cleanse_ISO8601($circ->due_date))->epoch;
my $twenty_days = OpenSRF::Utils->interval_to_seconds('480 h 0 m 0 s');

# Rewrite history; technically we should rewrite status_changed_item on the copy as well, but, meh...
$circ->xact_start( $apputils->epoch2ISO8601($xact_start - $twenty_days) );
$circ->due_date( $apputils->epoch2ISO8601($due_date - $twenty_days) );

my $xact = $cstore_ses->request('open-ils.cstore.transaction.begin')->gather(1);
my $update_req = $cstore_ses->request(
    'open-ils.cstore.direct.action.circulation.update',
    $circ
);
if (my $update_resp = $update_req->gather(1)) {
    pass(
        'rewrote circ to have happened 20 days ago'
    );
} else {
    fail(
        'rewrote circ to have happened 20 days ago'
    );
}
$cstore_ses->request('open-ils.cstore.transaction.commit')->gather(1);

########

my $checkin_resp = do_checkin(ITEM_BARCODE);
is(
    ref $checkin_resp,
    'HASH',
    'Checkin request returned a HASH'
);
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', ITEM_ID);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . ITEM_ID . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

$bill_req = $circ_ses->request(
    'open-ils.circ.money.billing.retrieve.all',
    $authtoken,
    $circ->id
);
if (my $bill_resp = $bill_req->recv) {
    if (my $bills = $bill_resp->content) {
        is(
            scalar( @{ $bills } ),
            13,
            'Thirteen bills associated with circulation'
        );
    }
}


oils_logout();


