# ---------------------------------------------------------------
# Copyright (C) 2011 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package OpenILS::WWW::PhoneList::Holds;

use strict;
use warnings;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::WWW::PhoneList::Base;

my $U = 'OpenILS::Application::AppUtils';

BEGIN {
    our @ISA = ('OpenILS::WWW::PhoneList::Base');
}

my %fields = (
              addcount => 0,
              skipemail => 0,
             );

sub new {
    my $class = shift;
    my $args = shift;
    my $self = $class->SUPER::new($args);
    foreach my $element (keys %fields) {
        $self->{_permitted}->{$element} = $fields{$element};
    }
    @{$self}{keys %fields} = values %fields;
    $self->perms(['VIEW_USER', 'VIEW_HOLD', 'VIEW_HOLD_NOTIFICATION', 'CREATE_HOLD_NOTIFICATION']);
    $self->addcount($args->{addcount}) if (defined($args->{addcount}));
    $self->skipemail($args->{skipemail}) if (defined($args->{skipemail}));
    my $columns = ['Name', 'Phone', 'Barcode'];
    push(@{$columns}, 'Count') if ($self->addcount);
    $self->columns($columns);
    return $self;
}

sub query {
    my $self = shift;
    my $ou_id = $self->work_ou;

    # Hold results in an array ref.
    $self->{results} = [];

    my $raw_query =<<"    QUERY";
{
"select": { "au": [ "first_given_name", "family_name", "email" ],
            "ac": [ "barcode" ],
            "ahr": [ "phone_notify", "id", "email_notify" ] },

"from": { "au" : { "ac" : { "fkey":"card", "field":"id" },
                   "ahr": { "fkey":"id", "field":"usr" } } },

"where": { "+ahr": { "pickup_lib": { "in": {"select": {"aou":[{"transform":"actor.org_unit_descendants","column":"id","result_field":"id","alias":"id"}]},
                                            "from":"aou",
                                            "where":{"id":$ou_id}}},
                     "cancel_time":null,
                     "fulfillment_time":null,
                     "-and": [{"phone_notify": {"<>": null}}, {"phone_notify":{"<>":""}}],
                     "shelf_time":{"<>":null},
                     "capture_time":{"<>":null},
                     "current_copy":{"<>":null},
                     "id": { "not in": { "from":"ahn",
                                         "select": { "ahn": [ "hold" ] },
                                         "where": { "method":"phone" } } } } },
"order_by": { "ac": [ "barcode" ], "ahr": [ "phone_notify" ] }
}
    QUERY

    my $q = OpenSRF::Utils::JSON->JSON2perl($raw_query);
    my $e = new_editor(authtoken=>$self->authtoken);
    my $info = $e->json_query($q);
    if ($info && @$info) {
        my ($bc, $pn,$count,$name, $skipme);
        $bc = "";
        $pn = "";
        $count = 0;
        $skipme = 1; # Assume we skip until we have a notice w/out email.
        foreach my $i (@$info) {
            if ($i->{barcode} ne $bc || $i->{phone_notify} ne $pn) {
                if ($count > 0 && $skipme == 0) {
                    my $phone = $pn;
                    $phone =~ s/[- ]//g;
                    my $out = [$name, $phone, $bc];
                    push(@$out, $count) if ($self->addcount);
                    push(@{$self->{results}}, $out);
                    $count = 0;
                }
                if ($i->{first_given_name} eq 'N/A' || $i->{first_given_name} eq '') {
                    $name = $i->{family_name};
                }
                else {
                    $name = $i->{first_given_name} . ' ' . $i->{family_name};
                }
                $bc = $i->{barcode};
                $pn = $i->{phone_notify};
                $skipme = 1; # Assume we skip until we have a notice w/out email.
            }
            unless ($self->skipemail && $i->{email} && $i->{email_notify} eq 't') {
                my $ahn = Fieldmapper::action::hold_notification->new;
                $ahn->hold($i->{id});
                $ahn->notify_staff($self->user);
                $ahn->method('phone');
                $ahn->note('PhoneList.pm');
                $logger->activity("Attempting notification creation hold: " . $ahn->hold . " method: " . $ahn->method . " note: " . $ahn->note);
                my $notification = $U->simplereq('open-ils.circ', 'open-ils.circ.hold_notification.create', $self->authtoken, $ahn);
                if (ref($notification)) {
                    $logger->error("Error creating notification: " . $notification->{textcode});
                }
                else {
                    $logger->activity("Created ahn: $notification");
                }
                #patron has at least 1 phone-only notice, so we print.
                $skipme = 0;
            }
            $count++;
        }
        # Get that last one, since we only print when barcode and/or
        # phone changes.
        if ($count > 0 && $skipme == 0) {
            my $phone = $pn;
            $phone =~ s/-//g;
            my $out = [$name, $phone, $bc];
            push(@$out, $count) if ($self->addcount);
            push(@{$self->{results}}, $out);
            $count = 0;
        }
    }
    return scalar @{$self->{results}};
}

sub next {
    my $self = shift;
    if (@{$self->{results}}) {
        return shift @{$self->{results}};
    }
    else {
        return [];
    }
}

1;
