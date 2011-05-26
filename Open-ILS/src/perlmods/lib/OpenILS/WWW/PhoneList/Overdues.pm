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
package OpenILS::WWW::PhoneList::Overdues;

use strict;
use warnings;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::WWW::PhoneList::Base;

my $U = 'OpenILS::Application::AppUtils';

BEGIN {
    our @ISA = ('OpenILS::WWW::PhoneList::Base');
}

my %fields = (
              skipemail => 0,
              days => 14,
             );

sub new {
    my $class = shift;
    my $args = shift;
    my $self = $class->SUPER::new($args);
    foreach my $element (keys %fields) {
        $self->{_permitted}->{$element} = $fields{$element};
    }
    @{$self}{keys %fields} = values %fields;
    $self->perms(['VIEW_USER', 'VIEW_CIRCULATIONS']);
    $self->skipemail($args->{skipemail}) if (defined($args->{skipemail}));
    $self->days($args->{days});
    my $columns = ['Name', 'Phone', 'Barcode', 'Titles'];
    $self->columns($columns);

    # Results in an array ref.
    $self->{results} = [];

    return $self;
}

sub query {
    my $self = shift;
    my $ou_id = $self->work_ou;

    # Need a CStoreEditor to run some queries:
    my $e = new_editor(authtoken => $self->{authtoken});

    # Get org_unit and descendant ids for the main search:
    my $query =
        {
         "select" =>
         {
          "aou"=>
          [
           {
            "transform"=>"actor.org_unit_descendants",
            "column"=>"id",
            "result_field"=>"id",
            "alias"=>"id"
           }
          ]
         },
         "from"=>"aou",
         "where"=>{"id"=>$ou_id}
        };

    my $result = $e->json_query($query);
    my $where = [];
    if (defined($result) && ref($result) eq 'ARRAY') {
        foreach my $r (@$result) {
            push (@$where, $r->{id});
        }
    } else {
        $where = $ou_id;
    }

    # Set the due date to $self->days() ago.
    my $when = DateTime->now();
    $when->subtract(days => $self->days());
    # All due dates are set to 23:59:59 in Evergreen.
    $when->set(hour => 23, minute => 59, second => 59);

    # This is what we're here for, the main search call to get fleshed
    # circulation information for items that were due $where $when
    # days ago.
    my $circs = $e->search_action_circulation(
        [
         {
          circ_lib => $where,
          checkin_time => undef,
          due_date => $when->iso8601()
         },
         {
          flesh => 4,
          flesh_fields =>
          {
           circ => ['usr', 'target_copy'],
           au => ['card'],
           acp => ['call_number'],
           acn => ['record'],
           bre => ['simple_record']
          }
         }
        ], {substream => 1});

    # Add any results to our internal results array.
    if (defined($circs) && ref($circs) eq 'ARRAY') {
        my $stuff = {};
        foreach my $circ (@$circs) {
            next if ($self->skipemail() && $circ->usr->email());
            next unless($circ->usr->day_phone());
            my $barcode = $circ->usr->card->barcode();
            my $title = $circ->target_copy->call_number->record->simple_record->
                title();
            if (defined($stuff->{$barcode})) {
                $stuff->{$barcode}->{titles} .= ':' . $title;
            } else {
                my $phone = $circ->usr->day_phone();
                my $name = $self->_get_usr_name($circ);
                $stuff->{$barcode}->{phone} = $phone;
                $stuff->{$barcode}->{name} = $name;
                $stuff->{$barcode}->{titles} = $title;
            }
        }
        foreach my $key (keys %$stuff) {
            push (@{$self->{results}},
                        [ $stuff->{$key}->{name}, $stuff->{$key}->{phone},
                          $key, $stuff->{$key}->{titles} ]);
        }
    }

    # Clean up?
    $e->finish;

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

# some helper functions:
sub _get_usr_name {
    my $self = shift;
    my $circ = shift;
    my $first_name = $circ->usr->first_given_name();
    my $last_name = $circ->usr->family_name();
    return ($first_name eq 'N/A' || $first_name eq '') ? $last_name
        : $first_name . ' ' . $last_name;
}

1;
