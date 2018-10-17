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
    my $bind_attr   = $self->{'bind_attr'} || $id_attr; # use id_attr to bind if bind_attr not set

    # bind_attr: name of LDAP attribute containing user's LDAP username
    # id_attr: name of LDAP attribute containing user's Evergreen username
    #
    # Normally the LDAP username *is* the Evergreen username, in which case
    # we don't need the extra step of getting the username from the LDAP entry.
    # Thus, bind_attr and id_attr are the same.  (This is the default scenario.)
    #
    # However, suppose we have two college libraries in a consortium.  Each
    # college has its own LDAP-based SSO solution.  An LDAP username like
    # "jsmith" may be in use at both libraries, for two different patrons.
    # In this case, we can't use the LDAP username as the EG username, since
    # every patron must have a unique username in EG.
    #
    # Here's how we handle this second scenario:
    #
    # 1. The user logs in with their LDAP username.
    # 2. EG makes a bind request to the LDAP server using the LDAP username,
    # which is in the LDAP attribute specified by bind_attr.
    # 3. If the bind succeeds, we pull the user's EG username from the LDAP
    # attribute specified by id_attr, and pass it along so that EG looks up the
    # correct user.
    #
    # If bind_attr is not set, or if it specifies the same LDAP attribute as
    # id_attr, we fallback to the default scenario.
    #
    my $username_from_ldap = $bind_attr eq $id_attr ? 0 : 1;

    # When the EG username is retrieved from the LDAP server, we want to ensure
    # that we bind using the actual username provided by the user.
    if ($username_from_ldap) {
        $username = $args->{'provided_username'} || $username;
    }

    my $ldap;
    my $ldap_search;
    if ( $ldap = Net::LDAP->new($hostname) ) {
        $hostname_is_ldap = 1;
        if ( $ldap->bind( $authid, password => $authid_pass )->code == 0 ) {
            $reached_ldap = 1;
            # verify username and lookup user's DN
            $ldap_search = $ldap->search( base => $basedn,
                                             filter => "($bind_attr=$username)" );
            if ( $ldap_search->count != 0 ) {
                $user_in_ldap = 1;

                # verify password (bind check)
                my $binddn = $ldap_search->entry(0)->dn();
                if ( $ldap->bind( $binddn, password => $password )
                    ->code == 0 ) {
                    $login_succeeded = 1;
                }
            }
        }
    }

    if ( $login_succeeded ) {
        if ($username_from_ldap) {
            my $id_attr_val = $ldap_search->entry(0)->get_value($id_attr);
            return OpenILS::Event->new('SUCCESS', payload => $id_attr_val);
        } else {
            return OpenILS::Event->new('SUCCESS');
        }
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
