#!perl

use Test::More tests => 10;

diag("Test bill payment against the admin user.");

use constant WORKSTATION_NAME => 'BR4-test-05-pay-bills.t';
use constant WORKSTATION_LIB => 7;
use constant USER_ID => 1;
use constant USER_USRNAME => 'admin';

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

sub fetch_billing_summaries {
    my $resp = osrf_request(
        'open-ils.actor',
        'open-ils.actor.user.transactions.history.have_balance.authoritative',
        $authtoken,
        USER_ID
    );
    return $resp;
}

sub pay_bills {
    my ($user_obj, $payment_blob) = (shift, shift);
    my $resp = osrf_request(
        'open-ils.circ',
        'open-ils.circ.money.payment',
        $authtoken,
        $payment_blob,
        $user_obj->last_xact_id
    );
    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data, full-auto install by
# eg_wheezy_installer.sh, etc.
#----------------------------------------------------------------

osrf_connect();
my $storage_ses = OpenSRF::AppSession->create('open-ils.storage');

my $user_obj;
my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', USER_ID);
if (my $user_resp = $user_req->recv) {
    if ($user_obj = $user_resp->content) {
        is(
            ref $user_obj,
            'Fieldmapper::actor::user',
            'open-ils.storage.direct.actor.user.retrieve returned aou object'
        );
        is(
            $user_obj->usrname,
            USER_USRNAME,
            'User with id = ' . USER_ID . ' is ' . USER_USRNAME . ' user'
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

my $summaries = fetch_billing_summaries();

is(
    scalar(@{ $summaries }),
    2,
    'Two billable xacts for ' . USER_USRNAME . ' user from previous tests'
);

is(
    @{ $summaries }[0]->balance_owed + @{ $summaries }[1]->balance_owed,
    1.25,
    'Both transactions combined have a balance owed of 1.25'
);

my $payment_blob = {
    userid => USER_ID,
    note => '05-pay_bills.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ map { [ $_->id, $_->balance_owed ] } @{ $summaries } ]
};

my $pay_resp = pay_bills($user_obj,$payment_blob);

is(
    ref $pay_resp,
    'HASH',
    'Payment attempt returned HASH'
);

is(
    scalar( @{ $pay_resp->{payments} } ),
    2,
    'Payment response included two payment ids'
);

my $new_summaries = fetch_billing_summaries();
is(
    scalar(@{ $new_summaries }),
    0,
    'Zero billable xacts for ' . USER_USRNAME . ' user after payment'
);

oils_logout();


