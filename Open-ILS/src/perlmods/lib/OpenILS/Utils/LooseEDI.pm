# The OpenILS::Utils::LooseEDI classes are an intentiaonally simplistic way to
# represent EDI interchanges and the messages contained therein (which are in
# turn made up of segment groups, segments, and smaller data structures).
#
# There is virtually no validation against EDIFACT or Editeur rules.  All we're
# doing here is the minimum data munging against incoming JEDI that will let us
# access segments by name without looping and searching for them (much), when
# they're where they should be.
#
# Segment groups are hereinafter just "groups."  Groups can belong to other
# groups, and segments can belong to groups, but groups cannot belong to
# segments.
#
# Groups and segments at a given level always appear in
# arrays in case there are any repeats of the the same thing at the same level.
# Anything "less" than a segment is just copied as-is from the JEDI.
#
# The class you want to instantiate is OpenILS::Utils::LooseEDI::Interchange.
# The only argument you need to give new() is the JEDI data (in string form
# will do nicely).

package OpenILS::Utils::LooseEDI::Segment; # so simple it does nothing.

use strict;
use warnings;

sub new {
    my ($class, $data) = @_;

    my $self = bless $data, $class; # data is already hashref

    return $self;
}

1;

package OpenILS::Utils::LooseEDI::Group;

use strict;
use warnings;

use OpenSRF::Utils::Logger qw/:logger/;

sub new {
    my ($class, $data) = @_;

    my $self = bless {
        data => $data
    }, $class;

    $self->load;

    return $self;
}

sub load {
    my $self = shift;

    foreach (@{$self->{data}}) {
        $logger->warn("bad element in data for " . __PACKAGE__) unless
            @$_ == 2;

        my ($left, $right) = @$_;
        $self->{$left} ||= [];
        push @{$self->{$left}}, $self->load_children($right);
    }

    delete $self->{data};
}

sub load_children {
    my ($self, $thing) = @_;

    if (ref $thing eq 'ARRAY') {
        return new OpenILS::Utils::LooseEDI::Group($thing);
    } elsif (ref $thing eq 'HASH') {
        return new OpenILS::Utils::LooseEDI::Segment($thing);
    } else {
        $logger->warn("unexpected data, neither array nor hashref");
    }
}

1;

package OpenILS::Utils::LooseEDI::Message;

use strict;
use warnings;

# In our unsophisticated implementation, a message is just like a segment group.
use base 'OpenILS::Utils::LooseEDI::Group';

sub message_name {
    my ($self) = @_;

    return $self->{UNH}[0]{S009}{'0065'};
}

1;

package OpenILS::Utils::LooseEDI::Interchange;

use strict;
use warnings;

use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;

sub new {
    my ($class, $data) = @_;

    $data = OpenSRF::Utils::JSON->JSON2perl($data) unless ref $data;

    if (ref $data eq 'HASH') {
        # Like a bad wine...
        throw new OpenSRF::EX::Error("Interchange lacks body") unless
            $data->{body};
        throw new OpenSRF::EX::Error("Interchange has empty body") unless
            ref $data->{body} eq 'ARRAY' and @{ $data->{body} };

        my $self = bless {}, $class;

        foreach my $part (@{ $data->{body} }) {
            foreach my $msgname (grep /^[A-Z]/, keys %$part) {
                $self->{$msgname} ||= [];
                my $message =
                    new OpenILS::Utils::LooseEDI::Message($part->{$msgname});
                if ($msgname ne $message->message_name) {
                    $logger->warn(
                        "Found message thought to be named $msgname, " .
                        "but it says " . $message->message_name
                    );
                }
                push @{$self->{$msgname}}, $message;
            }
        }
        return $self;
    } else {
        $logger->error(__PACKAGE__ . " given bad data");
    }
}

1;
