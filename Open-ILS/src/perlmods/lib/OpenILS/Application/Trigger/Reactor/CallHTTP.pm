package   OpenILS::Application::Trigger::Reactor::CallHTTP;
use       OpenILS::Application::Trigger::Reactor;
use base 'OpenILS::Application::Trigger::Reactor';

use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;

# use OpenSRF::Utils::SettingsClient;
use LWP::UserAgent;
use URI::Escape;
use Config::General qw(ParseConfig);

use strict;
use warnings;

sub ABOUT {
    return <<ABOUT;

The CallHTTP Reactor Module attempts to make an HTTP call, usually a GET or POST.

The template should output data that can be parsed by the Config::General Perl
module.  See: https://metacpan.org/pod/Config::General

Top level settings should include the HTTP method and the url.

A block called Headers can be used to supply arbitrary HTTP headers.

A block called Parameters can be used to append CGI parameters to the URL, most
useful for GET form submission.  Repeated parameters are allowed.  If this block
is used, the URL should /not/ contain any parameters, use one or the other.

A HEREDOC called "content" can be used with POST or PUT to send an arbitrary block
of content to the remote server.

If the requested URL requires Basic or Digest authentication, the template can
include top level configuration parameters to supply a user, password, realm, and
server/port location.

A default user agent string of "EvergreenReactor/1.0" is used when sending requests.
This can be overridden using the top level "agent" setting.

Example template:

method   post # Valid values are post, get, put, delete, head
url      https://example.com/api/incoming-update
agent    MySpecialAgent/0.1

user     updater
password uPd4t3StufF
realm    "Secret area"
location example.com:443

<Headers>
  Accept-Language en
</Headers>

<Parameters>
  type bib
  id   [% target.id %]
</Parameters>

content <<MARC
[% target.marc %]
MARC

ABOUT
}

sub handler {
    my $self = shift;
    my $env  = shift;

    my $HTTPcontent = $self->run_TT($env) or return;

    my %request_config = ParseConfig(
        -AutoTrue => 1,
        -String => $HTTPcontent
    );

    return unless (keys %request_config);

    my $ua = LWP::UserAgent->new;
    $ua->agent($request_config{agent} ? $request_config{agent} : 'EvergreenReactor/1.0');

    my $url = $request_config{url} or return;
    my $method = $request_config{method} or return;
    return unless (grep { $_ eq $method } qw/post get put delete head/);

    my $user = $request_config{user};
    my $password = $request_config{password};
    my $realm = $request_config{realm};
    my $location = $request_config{location};

    $ua->credentials($location, $realm, $user, $password)
        if ($user and $password and $realm and $location);

    if ($request_config{Headers}) {
        for my $h (keys %{$request_config{Headers}}) {
            $ua->default_header( $h => $request_config{Headers}{$h} );
        }
    }

    if ($request_config{Parameters}) {
        $url .= '?';
        my $first = 1;
        for my $p (keys %{$request_config{Parameters}}) {
            my $pvalues = $request_config{Parameters}{$p};
            $pvalues = [$pvalues] if (!ref($pvalues));
            for my $pv (@$pvalues) {
                $url .= "&" unless $first;
                $first = 0;
                $url .= "$p=".uri_escape($pv);
            }
        }
    }

    my @params = ($url);
    push( @params, Content => $request_config{content} )
        if (grep { $_ eq $method } qw/put post/);

    my $response = $ua->$method(@params);
    my $output_field = $response->is_success ? 'async_output' : 'error_output';

    my $e = new_editor(xact => 1);
    my $eo = Fieldmapper::action_trigger::event_output->new;
    $eo->is_error( $response->is_success ? 'f' : 't');
    $eo->data($response->as_string);
    $eo = $e->create_action_trigger_event_output($eo) or return $e->die_event;

    my @eventids;
    if (ref $$env{event} eq 'ARRAY') {
        @eventids = map { $_->id} @{$$env{event}};
    } else {
        @eventids = ($env->{event}->id);
    }

    foreach (@eventids) {
        my $event = $e->retrieve_action_trigger_event($_);
        $event->$output_field($eo->id);
        $e->update_action_trigger_event($event);
    }

    $e->commit;

    return 1;
}

1;

