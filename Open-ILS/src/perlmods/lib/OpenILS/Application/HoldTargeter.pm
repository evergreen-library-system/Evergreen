package OpenILS::Application::HoldTargeter;
use strict; 
use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenILS::Utils::HoldTargeter;

__PACKAGE__->register_method(
    method    => 'hold_targeter',
    api_name  => 'open-ils.hold-targeter.target',
    api_level => 1,
    argc      => 1,
    stream    => 1,
    # Caller is given control over how often to receive responses.
    max_chunk_size => 0,
    signature => {
        desc     => q/Batch or single hold targeter./,
        params   => [
            {   name => 'args',
                desc => 'Hash of targeter options',
                type => 'hash'
            }
        ],
        return => {
            desc => q/
                TODO
            /
        }
    }
);

# args:
#
#   return_count - Return number of holds processed so far instead 
#       of hold targeter result summary objects.
#
#   return_throttle - Only reply each time this many holds have been 
#       targeted.  This prevents dumping a fast stream of responses
#       at the client if the client doesn't need them.
#
#   See OpenILS::Utils::HoldTargeter::target() docs.

sub hold_targeter {
    my ($self, $client, $args) = @_;

    my $targeter = OpenILS::Utils::HoldTargeter->new(%$args);

    $targeter->init;

    my $throttle = $args->{return_throttle} || 1;
    my $count = 0;

    for my $hold_id ($targeter->find_holds_to_target) {
        $count++;

        my $single = OpenILS::Utils::HoldTargeter::Single->new(
            parent => $targeter,
            skip_viable => $args->{skip_viable}
        );

        $single->target($hold_id);

        if (($count % $throttle) == 0) { 
            # Time to reply to the caller.  Return either the number
            # processed thus far or the most recent summary object.

            my $res = $args->{return_count} ? $count : $single->result;
            $client->respond($res);
        }
    }

    return undef;
}

1;

