package OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use MIME::Base64;

our $VERSION = 1;
my $U = "OpenILS::Application::AppUtils";

sub retrieve_one_object_via_pcrud {
    my ($controller, $ses, $type, $pkey_value, $flesh_fields, $flesh_depth) = @_;
    $flesh_fields ||= {};
    $flesh_depth ||= 1;

    my $method = "retrieve_$type";

    my $o = new_editor(
        personality => 'open-ils.pcrud',
        authtoken   => $ses
    )->$method([
        $pkey_value,
        {flesh => $flesh_depth, flesh_fields => $flesh_fields}
    ]);

    $controller->res->code(404) unless ($o);
    return $o;
}

sub authenticateUser {
    my ($c, $u, $p, $t) = @_;

    my ($type, $creds) = split ' ', $c->req->headers->authorization || '';
    if ($creds and $type =~ /basic/i) {
        $creds = decode_base64($creds);
        ($u,$p,$t) = split ':', $creds;
    }

    $t ||= 'api'; # Default to requiring the API_LOGIN permission and an integrator account

    my $auth = {};
    if ($u) {
        my $throttle_user = check_auth_limits($u, $c->forwarded_for);

        if ($throttle_user) {
            log_authentication_attempt($c, $u);
            $c->res->code(429);
            $c->res->headers->header('Retry-After' => $throttle_user);
            return $auth;
        } elsif ($p) {
            $c->app->log->trace("Attempting login for user $u, login type $t");
            $auth = $U->simplereq(
                'open-ils.auth', 'open-ils.auth.login',
                { username => $u,
                  password => $p,
                  type => $t
                }
            );

            if (!$auth or !$auth->{textcode} or $auth->{textcode} ne 'SUCCESS') {
                log_authentication_attempt($c, $u);
                $c->res->code(401);
                $c->res->message('Login failed');
                return $auth;
            } else {
                log_authentication_attempt($c, $u, $auth->{payload}->{authtoken});
                my $resp_type = $c->stash('eg_req_resolved_content_format') || 'json';
                return $auth->{payload}->{authtoken} if ($resp_type eq 'text');
                return { token => $auth->{payload}->{authtoken} };
            }

        } else {
            log_authentication_attempt($c, $u);
            $c->res->code(400);
            return $auth;
        }
    }

    log_authentication_attempt($c);
    $c->res->code(400);
    return $auth;
}

sub check_auth_limits {
    my $username = shift;
    my $ip = shift;

    my $limits = new_editor()->json_query({from => ['openapi.check_auth_endpoint_rate_limit', $username, $ip]});
    return $$limits[0]{'openapi.check_auth_endpoint_rate_limit'} if @$limits;

    return undef; # proceed
}

sub log_authentication_attempt {
    my $c = shift;
    my $user = shift;
    my $token = shift;

    my $authen_attempt_log = Fieldmapper::openapi::authen_attempt_log->new;
    $authen_attempt_log->request_id( $c->req->request_id );
    $authen_attempt_log->ip_addr( $c->forwarded_for );
    $authen_attempt_log->cred_user( $user );
    $authen_attempt_log->token( $token );

    my $e = new_editor(xact=>1);
    $e->create_openapi_authen_attempt_log($authen_attempt_log);
    $e->commit;
}

sub where_clause_from_triples {
    my ($fields, $ops, $values) = @_;

    my %search_parts;
    while (my $f = shift @$fields) {
        my $o = shift @$ops;
        my $v = shift @$values;
        $search_parts{$f} ||= [];
        push @{$search_parts{$f}}, { $f => { $o => $v } };
    }

    my %search = ( '-and' => [] );
    for my $f (keys %search_parts) {
        my $p = $search_parts{$f};
        if (@$p > 1) { # or them for the same field
            push @{$search{'-and'}}, { '-or' => $p };
        } else {
            push @{$search{'-and'}}, $$p[0];
        }
    }

    return \%search;
}

sub apply_blob_to_object {
    my ($obj,$blob,$allowed) = @_;

    my %defaults;
    if (ref($allowed) eq 'HASH') {
        %defaults = %$allowed;
        $allowed = [ keys %defaults ];
    }

    my %parts = %$blob; # work on a copy
    %parts = %parts{@$allowed}
        if ($allowed and @$allowed); # trim if requested

    $obj->$_(defined($parts{$_}) ? $parts{$_} : $defaults{$_}) for keys %parts;
}

1;
