package OpenILS::Application::Trigger::Reactor::AstCall;
use base 'OpenILS::Application::Trigger::Reactor';
use OpenSRF::Utils::Logger qw($logger);
# use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

use strict; use warnings;
use Error qw/:try/;
use Data::Dumper;

use OpenSRF::Utils::SettingsClient;
use RPC::XML::Client;
$Data::Dumper::Indent = 0;

my $U = 'OpenILS::Application::AppUtils';

# $last_channel_used is:
# ~ index (not literal value) of last channel used in a callfile
# ~ index is of position in @channels (zero-based)
# ~ cached at package level
# ~ typically for Zap (PSTN), not VOIP

our @channels;
our $last_channel_used = 0;
our $telephony;

sub ABOUT {
    return <<ABOUT;

    The AstCall reactor module creates a callfile for Asterisk, given a
    template describing the message and an environment defining
    necessary information for contacting the Asterisk server and scheduling
    a call with it.

ABOUT
}

sub get_conf {
   # $logger->info(__PACKAGE__ . ": get_conf()");
    $telephony and return $telephony;
    my $config = OpenSRF::Utils::SettingsClient->new;
    # config object cached by package
    $telephony = $config->config_value('notifications', 'telephony');
    return $telephony;
}

sub get_channels {
    @channels and return @channels;
    my $config = get_conf();    # populated $telephony object
    @channels = @{ $config->{channels} };
    return @channels;
}

sub next_channel {
    # Increments $last_channel_used, or resets it to zero, as necessary.
    # Returns appropriate value from channels array.
    my @chans = get_channels();
    unless(@chans) {
        $logger->error(__PACKAGE__ . ": Cannot build call using " .
            (shift ||'driver') .
            ", no notifications.telephony.channels found in config!");
        return;
    }
    if (++$last_channel_used > $#chans) {
        $last_channel_used = 0;
    }
    return $chans[$last_channel_used];     # say, 'Zap/1' or 'Zap/12'
}

sub channel {
    my $tech = get_conf()->{driver} || 'SIP';
    if ($tech !~ /^SIP/) {
        return next_channel($tech);
    }
    return $tech;                          #  say, 'SIP' or 'SIP/ubab33'
}

sub get_extra_lines {
    my $lines = get_conf()->{callfile_lines} or return '';
    my @fixed;
    foreach (split "\n", $lines) {
        s/^\s*//g;      # strip leading spaces
        /\S/ or next;   # skip empty lines
        push @fixed, $_;
    }
    (scalar @fixed) or return '';
    return join("\n", @fixed) . "\n";
}

sub host_string {
    my $conf = get_conf();
    my $host = $conf->{host};
    unless ($host) {
        $logger->error(__PACKAGE__ . ": No telephony/host in config.");
        return;
    }

    # prepend http:// if no protocol specified
    $host =~ /^\S+:\/\// or $host  = 'http://' . $host;
    # append port number if specified
    $conf->{port} and $host .= ":" . $conf->{port};

    return $host;
}
sub rpc_client {
    # TODO: caching? (would take testing to ensure memory and
    # connections are clean/stable)
    my $host = (@_ ? shift : host_string()) or return;
    return new RPC::XML::Client($host);
}

sub handler {
    my ($self, $env) = @_;

    my $e = new_editor(xact => 1);

    $logger->info(__PACKAGE__ . ": entered handler");

    # assignment, not comparison
    unless ($env->{channel_prefix} = channel()) {
        $logger->error(__PACKAGE__ . ": Cannot find tech/resource in config");
        return 0;
    }

    $env->{extra_lines} = get_extra_lines() || '';
    my $tmpl_output = $self->run_TT($env);
    if (not $tmpl_output) {
        $logger->error(__PACKAGE__ . ": no template input");
        return 0;
    }

    my @eventids = map {$_->id} @{$env->{event}};
    @eventids or push @eventids, '';

    my $eo = Fieldmapper::action_trigger::event_output->new;

    # XXX we have to actually create this in the DB now if we expect to use the
    # ID later
    $eo->data("");
    $eo = $e->create_action_trigger_event_output($eo) or return $e->die_event;
    if ($env->{"extra_lines"}) {
        $tmpl_output .= ";; added by handler:\n";
        $tmpl_output .= $env->{"extra_lines"};
    }

    my $eventids_str = join(",", @eventids);

    # Stuff the call file with data about A/T event IDs and related things,
    # for other processes to pick up on later.

    $tmpl_output =~ s/^(Account:.+)$/$1 . "," . $eventids_str/gem;
    $tmpl_output .= "; event_ids = " . $eventids_str . "\n";
    $tmpl_output .= "; event_output = " . $eo->id . "\n";

    #my $filename_fragment = $userid . '_' . $eventids[0] . 'uniq' . time;
    # not $noticetype,
    # the event_output.id tells us all we need to know
    # XXX why is id in here twice?
    my $filename_fragment = $eo->id . '_' . $eo->id;

    # TODO: add scheduling intelligence and use it here... or not if
    # relying only on crontab
    my $client = rpc_client();
    my $resp = $client->send_request(
        'inject', $tmpl_output, $filename_fragment, 0
    ); # FIXME: 0 could be seconds-from-epoch UTC if deferred call needed

    $logger->debug(
        ref $resp ? ("Response: " . Dumper($resp->value)) : "Error: $resp"
    );

    if ($resp->{code} and $resp->{code}->value == 200) {
        $eo->is_error('f');
        $eo->data('filename: ' . $resp->{spooled_filename}->value);
        # could look for the file that replaced it
    } else {
        $eo->is_error('t');
        my $msg = $resp->{faultcode} ? $resp->{faultcode}->value :
                    $resp->{     code} ? $resp->{     code}->value :
                        " -- UNKNOWN response '$resp'";
        $msg .= " for $filename_fragment";
        $eo->data("Error " . $msg);
        $logger->error(__PACKAGE__ . ": Mediator Error " . $msg);
    }

    # Now point all our events' async_output to the newly made row
#    $eo = $env->{EventProcessor}->editor->
#        create_action_trigger_event_output( $eo );
    $e->update_action_trigger_event_output($eo) or return $e->die_event;
    foreach (@eventids) {
        my $event = $e->retrieve_action_trigger_event($_);
        $event->async_output($eo->id);
        $e->update_action_trigger_event($event);
    }
    $e->commit;    # defer till after loop?

    # TODO: a sub for saving async_output might belong in Trigger.pm
    1;
}

sub _files {
    my $response = shift or return;
    return map {$response->{$_}} sort grep {/^file_\d*/} keys %$response;
}

=head1 EXAMPLE CALFILES

Note: all lines start flush left (no leading whitespace)

=head2 Example callfile (successful)

    Channel: SIP/ubab33/17707775555
    Context: overdue-test
    MaxRetries: 1
    RetryTime: 60
    WaitTime: 30
    Extension: 10
    Archive: 1
    Set: items=1
    Set: titlestring=chez nos gens;; added by OpenILS::Application::Trigger::Reactor::AstCall handler:
    ; event_ids = 123,145
    ; event_output = 14;; added by inject() in the mediator
    Set: callfilename=EG_1258060382_6.call

    StartRetry: 2139 1 (1258060442)
    Status: Completed
    Channel: SIP/ubab33/17707775555

=head2 Example callfile (FAILED)

    CallerID: "Jack Jackson" <17707775555>
    Context: overdue-test
    MaxRetries: 1
    RetryTime: 60
    WaitTime: 30
    Extension: 10
    Archive: 1
    Set: items=1
    Set: titlestring=Land Before Time;; added by OpenILS::Application::Trigger::Reactor::AstCall handler:
    Set: LOOP=1
    Set: callfilename=EG_joe_20091109145355.call

    StartRetry: 2139 1 (1257907526)
    ; FAILED: 0

    EndRetry: 2139 1 (1257907496)

    StartRetry: 2139 2 (1257907617)
    ; FAILED: 0
    Status: Expired

=head2 Possible data structure:

 $feedback = {
     status => val,
     attempts => [ $attempt1, $attempt2 ... $attemptN ],
     anything_else => scalar,
 }
 ...
 $attempt = {
     time => secs from epoch (UTC) for the BEGINNING of the call,
     duration => secs,
     failed => code,
 }

=cut

sub feedback_hash {
    # parses the done callfile comments from Mediator
    # return ref to hash
    my $content  = shift or return;
    my %hash     = ();
    # my @attempts = ();
    my @lines    = split "\n", $content;
    foreach (shift @lines) {
        s/^\s*(Set:\s*)?//i;   # strip leading whitespace, and possible "Set:"
        if (/^StartRetry: \d+ (\d+) \((\d+)\)/) {
            # go parse  an attempt;
            # go record an attempt;
        }
        if (/^(Status):\s*(\S+)/i or /^;+\s*(FAILED):\s*(\S*)/i) {
            $hash{lc $1} = $2;
            next;
        }

        /^;+\s*(\S+)\s*[=:]\s*([^;]*)$/ and $hash{lc $1} = $2;
    }
    if (exists $hash{failed}) {
        $hash{failcode} = $hash{failed};
        # b/c "0" is a common failcode and we want a more binary indicator
        $hash{failed}   = 1;
    }
    return \%hash;
}

sub cleanup {
    my $self   = shift or return;
    my $files  = join(',',@_) or return;
    my $client = rpc_client();
    return $client->send_request('cleanup', $files);
    # TODO: more error checking
}

sub retrieve {
	$logger->info("retrieve() not implemented. how'd we get here?"); # XXX
	return;
}

#sub retrieve {
#    my $self   = shift or return;
#    my $client = rpc_client();
#    my $resp   = $client->send_request('retrieve');
#    unless ($resp and ref $resp) {
#         $logger->error(
#             __PACKAGE__ . ": Mediator Error: " .
#             ($resp ? 'Bad' : 'No') . " response to retrieve request"
#         );
#         return;
#    }
#
#    # my $count   = $resp{match_count}; # how many files we should have
#    # my @rm_list = ();
#    my @files   = _files($resp);
#    foreach (@files) {
#        my $content  = $resp->{$_}->content;
#        my $filename = $resp->{$_}->filename;
#        unless ($content) {
#            $logger->error(__PACKAGE__ .
#                ": Mediator sent incomplete/unintelligible message for " .
#                "filename " . ($filename || 'UNKNOWN'));
#            next;
#        }
#        my $feedback = feedback_hash($content);
#        my $output   = $e->retrieve_action_trigger_event_output(
#            $feedback->{event_output}
#        );
#        if ($content == $output->data) {
#            $logger->error(
#                __PACKAGE__ . ": Mediator sent duplicate file "
#                . $resp->{$_}->filename . " for event_output " .
#                $feedback->{event_output}
#            );
#        } else {
#            $output->data($content);
#        }
#        $e->commit;     # defer until after loop? probably not
#        my $clean = $client->send_request('cleanup', $filename);
#        # TODO: deletion by (comma-separated) filenames in chunks
#        # instead of individually?
#        # push @rm_list, $_; $client->send_request('cleanup', join(',',@rm_list));
#        unless ($clean and ref $clean) {
#            $logger->error(
#                __PACKAGE__ . ": Mediator Error: " .
#                ($clean ? 'Bad' : 'No') .
#                " response to cleanup $filename request");
#            next;
#        }
#        unless ($clean->{code}->value == 200 and $clean->{delete_count}) {
#            $logger->error(__PACKAGE__ . ": cleanup $filename returned " . (
#                $resp->{faultcode} ? $resp->{faultcode}->value :
#                    $resp->{     code} ? $resp->{     code}->value :
#                        " -- UNKNOWN response '$resp'"
#            ) . " with delete_count " .
#            (defined $clean->{delete_count} ? $clean->{delete_count} : 'UNDEF'));
#        }
#    }
#    return @files;
#}

1;
