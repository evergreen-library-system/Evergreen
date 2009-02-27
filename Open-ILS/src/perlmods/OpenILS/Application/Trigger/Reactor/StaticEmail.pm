package OpenILS::Application::Trigger::Reactor::StaticEmail;
use Error qw/:try/;
use Data::Dumper;
use Email::Send;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Trigger::Reactor;
use OpenSRF::Utils::Logger qw/:logger/;

use base 'OpenILS::Application::Trigger::Reactor';

my $log = 'OpenSRF::Utils::Logger';

my $default_template = <<TT;
To: [%- params.recipient -%]
From: [%- params.sender -%]
Subject: [%- params.subject -%]

[% params.body %]
TT

sub ABOUT {
    return <<ABOUT;

The StagicEmail Reactor Module sends an email to the address specified by the
"recipient" parameter.  This is the only required parameter (in fact the
template is not even required), though sender, subject and body parameters are
also accepted and used by the default template.

The default template looks like:
-------
$default_template
-------

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $smtp = $conf->config_value('email_notify', 'smtp_server');
    $$env{params}{sender} ||= $conf->config_value('email_notify', 'sender_address');
    $$env{params}{subject} ||= 'Test subject -- StaticEmail Reactor';
    $$env{params}{body} ||= 'Test body -- StaticEmail Reactor';
    $$env{template} ||= $default_template;

    $$env{params}{recipient} or return 0;

    my $text = $self->run_TT($env);
    return 0 if (!$text);

    $logger->info("StaticEmail Reactor: sending email to ".
        $$env{params}{recipient}." via SMTP server $smtp");

    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => $smtp]);


    my $stat;
    my $err;

    try {
        $stat = $sender->send($text);
    } catch Error with {
        $err = $stat = shift;
        $logger->error("StaticEmail Reactor: Email failed with error: $err");
    };

    if( !$err and $stat and $stat->type eq 'success' ) {
        $logger->info("StaticEmail Reactor: successfully sent email");
        return 1;
    } else {
        $logger->warn("StaticEmail Reactor: unable to send email: ".Dumper($stat));
        return 0;
    }

}

1;

