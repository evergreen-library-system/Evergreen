package OpenILS::Application::Trigger::Reactor::StaticEmail;
use Email::Send;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Trigger::Reactor;
use OpenSRF::Utils::Logger qw/:level/;

use base 'OpenILS::Application::Trigger::Reactor';

my $log = 'OpenSRF::Utils::Logger';

my $default_template = <<TT;
To: [%- env.params.recipient -%]
From: [%- env.params.sender -%]
Subject: [%- env.params.subject -%]

[% env.params.body %]
TT

sub handler {
    my $self = shift;
    my $env = shift;

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $smtp = $conf->config_value('email_notify', 'smtp_server');
    $$env{params}{sender} ||= $conf->config_value('email_notify', 'sender_address');
    $$env{params}{subject} ||= 'Test subject -- StaticEmail Reactor';
    $$env{params}{body} ||= 'Test body -- StaticEmail Reactor';

    $$env{params}{recipient} or return 0;

    $logger->info("StaticEmail Reactor: sending email to ".
        $$env{params}{recipient}." via SMTP server $smtp");

    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => $smtp]);

    my $TT = $$env{template} || $default_template;
    my $text = ''; # XXX TemplateToolkit stuff goes here...

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

