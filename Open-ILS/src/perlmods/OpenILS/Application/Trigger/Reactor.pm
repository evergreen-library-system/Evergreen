package OpenILS::Application::Trigger::Reactor;
use strict; use warnings;
use Template;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;

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

    $env->{format_date} = \&format_date;
    $env->{escape_xml} = \&escape_xml;
    $env->{user_locale} = \&user_locale;

    $tt->process(\$env->{template}, $env, \$output) or 
        $logger->error("Error processing Trigger template: " . $tt->error);

    return $output;
}

# turns a date into something TT can understand
sub format_date {
    my $date = shift;
    $date = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($date));
    return sprintf(
        "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
        $due->hour,
        $due->minute,
        $due->second,
        $due->day,
        $due->month,
        $due->year
    );
}

sub escape_xml {
    my $str = shift;
    $str =~ s/&/&amp;/sog;
    $str =~ s/</&lt;/sog;
    $str =~ s/>/&gt;/sog;
    return $str;
}


sub user_locale { 
    my $user_id = shift;
    return OpenILS::Application::AppUtils->get_user_locale($user_id);
}

1;
