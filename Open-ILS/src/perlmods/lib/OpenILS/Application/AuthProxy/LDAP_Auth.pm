package OpenILS::Application::AuthProxy::LDAP_Auth;
use strict;
use warnings;
use base 'OpenILS::Application::AuthProxy::AuthBase';
use OpenILS::Event;
use Net::LDAP;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw(:logger);

# default config var (override in configuration xml)
my $id_attr = 'uid';

sub authenticate {
    my ( $self, $args ) = @_;
    my $username = $args->{'username'};
    my $password = $args->{'password'};

    if (!$username) {
        $logger->debug("User login failed: No username provided");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    }
    if (!$password) {
        $logger->debug("User login failed: No password provided");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    }

    my $hostname_is_ldap = 0;
    my $reached_ldap     = 0;
    my $user_in_ldap     = 0;
    my $login_succeeded  = 0;

    my $hostname    = $self->{'hostname'};
    my $basedn      = $self->{'basedn'};
    my $authid      = $self->{'authid'};
    my $authid_pass = $self->{'password'};
    $id_attr        = $self->{'id_attr'} || $id_attr;

    my $ldap;
    if ( $ldap = Net::LDAP->new($hostname) ) {
        $hostname_is_ldap = 1;
        if ( $ldap->bind( $authid, password => $authid_pass )->code == 0 ) {
            $reached_ldap = 1;
            # verify username
            if ( $ldap
                ->search( base => $basedn, filter => "($id_attr=$username)" )
                ->count != 0 ) {
                $user_in_ldap = 1;

                # verify password (bind check)
                my $binddn = "$id_attr=$username,$basedn";
                if ( $ldap->bind( $binddn, password => $password )
                    ->code == 0 ) {
                    $login_succeeded = 1;
                }
            }
        }
    }

    if ( $login_succeeded ) {
        return OpenILS::Event->new('SUCCESS');
    } elsif ( !$hostname_is_ldap ) {
        # TODO: custom failure events?
        $logger->debug("User login failed: Incorrect LDAP hostname");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    } elsif ( !$reached_ldap ) {
        $logger->debug("User login failed: The LDAP server is misconfigured or unavailable");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    } elsif ( !$user_in_ldap ) {
        $logger->debug("User login failed: Username $username not in LDAP");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    } else {
        $logger->debug("User login failed: Incorrect LDAP password");
        return OpenILS::Event->new( 'LOGIN_FAILED' );
    }
}

1;
