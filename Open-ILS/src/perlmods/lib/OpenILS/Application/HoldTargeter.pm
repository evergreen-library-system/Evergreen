package OpenILS::Application::HoldTargeter;
use strict; 
use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use OpenILS::Utils::HoldTargeter;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::EX qw(:try);

__PACKAGE__->register_method(
    method    => 'hold_targeter',
    api_name  => 'open-ils.hold-targeter.target',
    api_level => 1,
    argc      => 1,
    stream    => 1,
    # Caller is given control over how often to receive responses.
    max_bundle_count => 1,
    signature => {
        desc     => q/Batch or single hold targeter./,
        params   => [
            {   name => 'args',
                type => 'hash',
                desc => q/
API Options:

return_count - Return number of holds processed so far instead 
  of hold targeter result summary objects.

return_throttle - Only reply each time this many holds have been 
  targeted.  This prevents dumping a fast stream of responses
  at the client if the client doesn't need them.

Targeter Options:

hold => <id> OR [<id>, <id>, ...]
 (Re)target one or more specific holds.  Specified as a single hold ID
 or an array ref of hold IDs.

retarget_interval => <interval string>
  Override the 'circ.holds.retarget_interval' global_flag value.

soft_retarget_interval => <interval string>
  Apply soft retarget logic to holds whose prev_check_time sits
  between the retarget_interval and the soft_retarget_interval.

next_check_interval => <interval string>
  Use this interval to determine when the targeter will run next
  instead of relying on the retarget_interval.  This value is used
  to determine if an org unit will be closed during the next iteration
  of the targeter.  Applying a specific interval is useful when
  the retarget_interval is shorter than the time between targeter runs.

newest_first => 1
  Target holds in reverse order of create_time. 

parallel_count => n
  Number of parallel targeters running.  This acts as the indication
  that other targeter instances are running.

parallel_slot => n [starts at 1]
  Sets the parallel targeter instance slot.  Used to determine
  which holds to process to avoid conflicts with other running instances.
/
            }
        ],
        return => {desc => 'See API Options for return types'}
    }
);

sub hold_targeter {
    my ($self, $client, $args) = @_;

    my $targeter = OpenILS::Utils::HoldTargeter->new(%$args);

    $targeter->init;

    my $throttle = $args->{return_throttle} || 1;
    my $count = 0;

    my @hold_ids = $targeter->find_holds_to_target;
    my $total = scalar(@hold_ids);

    $logger->info("targeter processing $total holds");

    my $hold_ses = create OpenSRF::AppSession("open-ils.circ");

    for my $hold_id (@hold_ids) {
        $count++;

        my $single = 
            OpenILS::Utils::HoldTargeter::Single->new(parent => $targeter);

        # Don't let an explosion on a single hold stop processing
        eval { $single->target($hold_id) };

        if ($@) {
            my $msg = "Targeter failed processing hold: $hold_id : $@";
            $single->error(1);
            $logger->error($msg);
            $single->message($msg) unless $single->message;
        }
        else {
            if (defined($args->{hold}) ||
                ( defined( $single->{previous_copy_id} ) &&
                  defined( $single->hold->current_copy ) &&
                  $single->{previous_copy_id} == $single->hold->current_copy )) {

                $logger->info("Targeter could not find a hold or previous copy is the current copy");
            } else {
                $hold_ses->request(
                    "open-ils.circ.hold_reset_reason_entry.create",
                    $single->editor()->authtoken,
                    $hold_id,
                    OILS_HOLD_TIMED_OUT,
                    undef,
                    $single->{previous_copy_id}
                );
            }
        }

        if (($count % $throttle) == 0) { 
            # Time to reply to the caller.  Return either the number
            # processed thus far or the most recent summary object.

            my $res = $args->{return_count} ? $count : $single->result;
            $client->respond($res);

            $logger->info("targeted $count of $total holds");
        }
    }

    $hold_ses->disconnect;

    return undef;
}

1;

