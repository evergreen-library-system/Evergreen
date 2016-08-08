# ---------------------------------------------------------------
# Copyright (C) 2016  Equinox Software, Inc.
# Mike Rylander <mrylander@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------


package OpenILS::Application::Circ::CircNotify;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use vars q/$AUTOLOAD/;
use OpenILS::Event;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::MultiSession;
use Email::Send;
use Data::Dumper;
use OpenSRF::EX qw/:try/;
my $U = 'OpenILS::Application::AppUtils';

use open ':utf8';

sub circ_batch_notify {
    my ($self, $client, $auth, $patronid, $circlist) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('STAFF_LOGIN');

    my $circs = $e->search_action_circulation({ id => $circlist });
    return $e->event if $e->event;

    my $hook = 'circ.checkout.batch_notify';
    $hook .= '.session' if $self->api_name =~ /session/;

    for my $circ (@$circs) {
        # WISHLIST: This may become more sophisticated and check "friend" permissions
        # in the future, at lease in the non-session variant.
        return OpenILS::Event->new('PATRON_CIRC_MISMATCH') if $circ->usr != $patronid;
        return $e->event unless $e->allowed('VIEW_CIRCULATIONS', $circ->circ_lib);
    }

    my %events;
    my $multi = OpenSRF::MultiSession->new(
        app                 => 'open-ils.trigger',
        cap                 => 3,
        success_handler     => sub {
            my $self = shift;
            my $req = shift;

            return unless $req->{response}->[0];
            my $event = $req->{response}->[0]->content;
            return unless $event;
            $event = $e->retrieve_action_trigger_event($event);

            return unless $event;
            $events{$event->event_def} ||= [];
            push @{$events{$event->event_def}}, $event->id;
        },
    );

    $multi->request(
        'open-ils.trigger.event.autocreate.ignore_opt_in',
        $hook => $_ => $e->requestor->ws_ou
    ) for ( @$circs );
    $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

    $multi->session_wait(1);
    $client->status( new OpenSRF::DomainObject::oilsContinueStatus );

    if (!keys(%events)) {
        return $client->respond_complete;
    }

    $multi = OpenSRF::MultiSession->new(
        app                 => 'open-ils.trigger',
        cap                 => 3,
        success_handler     => sub {
            my $self = shift;
            my $req = shift;

            return unless $req->{response}->[0];
            $client->respond( $req->{response}->[0]->content );
        },
    );

    $multi->request(
        'open-ils.trigger.event_group.fire',
        $events{$_}
    ) for ( sort keys %events );

    $multi->session_wait(1);
    return $client->respond_complete;
}
__PACKAGE__->register_method(
    method   => 'circ_batch_notify',
    api_name => 'open-ils.circ.checkout.batch_notify',
    stream   => 1,
    signature => {
        desc   => 'Creates and fires grouped events for a set of circulation IDs',
        params => [
            { name => 'authtoken', desc => 'Staff auth token',   type => 'string' },
            { name => 'patronid', desc => 'actor.usr.id of patron which must own the circulations', type => 'number' },
            { name => 'circlist', desc => 'Arrayref of circulation IDs to bundle into the event group', type => 'array' }
        ],
        return => {
            desc => 'Event on error, stream of zero or more event group firing results '.
                    'otherwise. See: open-ils.trigger.event_group.fire'
        }
    }
);
__PACKAGE__->register_method(
    method   => 'circ_batch_notify',
    api_name => 'open-ils.circ.checkout.batch_notify.session',
    stream   => 1,
    signature => {
        desc   => 'Creates and fires grouped events for a set of circulation IDs.  '.
                  'For use by session-specific actions such as self-checkout or circ desk checkout.',
        params => [
            { name => 'authtoken', desc => 'Staff auth token',   type => 'string' },
            { name => 'patronid', desc => 'actor.usr.id of patron which must own the circulations', type => 'number' },
            { name => 'circlist', desc => 'Arrayref of circulation IDs to bundle into the event group', type => 'array' }
        ],
        return => {
            desc => 'Event on error, stream of zero or more event group firing results '.
                    'otherwise. See: open-ils.trigger.event_group.fire'
        }
    }
);

1;
