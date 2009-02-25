package OpenILS::Application::Trigger::Reactor;
use Template;
use OpenSRF::Utils::Logger qw(:logger);

sub fourty_two { return 42 }
sub NOOP_True { return 1 }
sub NOOP_False { return 0 }


# processes templates.  Returns template output on success, undef on error
sub run_TT {
    my $self = shift;
    my $env = shift;
    return '' unless $env->{template};

    my $output = '';
    my $tt = Template->new;

    $tt->process($env->{template}, $env, \$output) or 
        $logger->error("Error processing Trigger template: " . $tt->error);

    return $output;
}

1;
