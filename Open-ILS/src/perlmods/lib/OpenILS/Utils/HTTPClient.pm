package OpenILS::Utils::HTTPClient;

use strict;
use warnings;

use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::Utils::JSON;
use LWP::UserAgent;
use HTTP::Request;

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    $self->_initialize();

    return $self;
}

sub _initialize {
    my $self = shift;

    # pull settings from opensrf.xml config
    my $conf = OpenSRF::Utils::SettingsClient->new();
    my $settings = $conf->config_value('http_client');

    if ($settings->{useragent}) {
        $self->{useragent} = $settings->{useragent};
    }
    if ($settings->{default_timeout}) {
        $self->{default_timeout} = $settings->{default_timeout};
    }

    # SSL handling options. When communicating over HTTPS, LWP::UserAgent
    # falls back to the environment variables whose values are set here.
    # See LWP::UserAgent docs for details.
    foreach my $opt (keys %{$settings->{ssl_opts}}) {
        # check for a valid SSL cert?
        if ($opt eq 'verify_hostname') {
            $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $settings->{ssl_opts}->{verify_hostname};
        # path to directory for CA certificate files
        } elsif ($opt eq 'SSL_ca_path') {
            $ENV{PERL_LWP_SSL_CA_PATH} = $settings->{ssl_opts}->{SSL_ca_path};
        # path to CA certificate file
        } elsif ($opt eq 'SSL_ca_file') {
            $ENV{PERL_LWP_SSL_CA_FILE} = $settings->{ssl_opts}->{SSL_ca_file};
        }
    }

    return $self;
}

# request(): Send an HTTP request.
#
# Params:
#   $method - HTTP method (GET, POST, PUT, DELETE)
#   $uri - URI of resource to be requested
#   $header - hashref containing HTTP headers
#   $content - content of request
#   $request_timeout - timeout value in seconds; defaults to 60s
#   $useragent - user agent string; defaults to SameOrigin/1.0
#
# Returns an HTTP::Response object, or undef if the request failed/timed out.
# Use $res->content to get response content.
#
sub request {
    my ($self, $method, $uri, $headers, $content, $request_timeout, $useragent) = @_;
    my $ua = new LWP::UserAgent;

    $request_timeout = $request_timeout || $self->{default_timeout} || 60;
    $ua->timeout($request_timeout);

    $useragent = $useragent || $self->{useragent} || 'SameOrigin/1.0';
    $ua->agent($useragent);

    my $h = HTTP::Headers->new();
    foreach my $k (keys %$headers) {
        $h->header($k => $headers->{$k});
    }

    my $req = HTTP::Request->new(
        $method,
        $uri,
        $h,
        $content
    );
    my $res;

    eval {
        $logger->info("HTTPClient: sending HTTP $method request to $uri");
        $res = $ua->request($req);
    } or do {
        $logger->info("HTTPClient: execution error");
        return undef;
    };

    if ($res->status_line =~ /timeout/) {
        $logger->info("HTTPClient: timeout error: " . $res->status_line);
        return undef;
    }

    # TODO handle HTTP response status codes

    return $res;
}

# Wrappers for request() using specific HTTP methods (GET, POST etc).
sub get {
    my $self = shift;
    return $self->request('GET', @_);
}

sub post {
    my $self = shift;
    return $self->request('POST', @_);
}

sub put {
    my $self = shift;
    return $self->request('PUT', @_);
}

sub delete {
    my $self = shift;
    return $self->request('DELETE', @_);
}

1;
