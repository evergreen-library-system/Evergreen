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
package OpenILS::WWW::PhoneList::Base;

use strict;
use warnings;
use Carp;
# A base class for generating phone list output.

use OpenILS::Application::AppUtils;

my %fields = (
              columns => [],
              perms => [],
              user => undef,
              authtoken => undef,
              work_ou => undef,
             );

sub new {
    my $invocant = shift;
    my $args = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {
                _permitted => \%fields,
                %fields,
               };
    bless($self, $class);
    $self->authtoken($args->{authtoken});
    $self->user($args->{user});
    $self->work_ou($args->{work_ou});
    return $self;
}

sub checkperms {
    my $self = shift;
    my $rv = 0;
    if ($self->perms && $self->user && $self->authtoken && $self->work_ou) {
        my $r = OpenILS::Application::AppUtils->simplereq('open-ils.actor', 'open-ils.actor.user.perm.check', $self->authtoken, $self->user, $self->work_ou, $self->perms);
        $rv = 1 unless(@$r);
    }
    return $rv;
}

# Return empty array ref.
sub next {
    return [];
}

# Always return false.
sub query {
    return 0;
}

sub AUTOLOAD {
    my $self = shift;
    my $class = ref($self) or croak "$self is not an object";
    my $name = our $AUTOLOAD;

    $name =~ s/.*://;

    unless (exists $self->{_permitted}->{$name}) {
        croak "Can't access '$name' field of class '$class'";
    }

    if (@_) {
        return $self->{$name} = shift;
    } else {
        return $self->{$name};
    }
}

1;
