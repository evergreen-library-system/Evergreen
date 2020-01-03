package OpenILS::Application::Trigger::Reactor::SendEmail;
use strict; use warnings;
use Error qw/:try/;
use Data::Dumper;
use Email::Send;
use Email::MIME;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Trigger::Reactor;
use OpenSRF::Utils::Logger qw/:logger/;
use Encode;
$Data::Dumper::Indent = 0;

use base 'OpenILS::Application::Trigger::Reactor';

my $log = 'OpenSRF::Utils::Logger';

sub ABOUT {
    return <<ABOUT;

The SendEmail Reactor Module attempts to email out, via Email::Send,
whatever is constructed by the template passed in from the Event Definition.

The SMTP server specified by the /opensrf/default/email_notify/smtp_server
setting is used to send the email, and the value at
/opensrf/default/email_notify/sender_address is passed into the template as
the 'default_sender' variable.

Email is encoded in UTF-8 and the corresponding MIME-Version, Content-Type,
and Content-Transfer-Encoding headers are set to help mail user agents
decode the content.

The From, To, Bcc, Cc, Reply-To, Sender, and Subject fields are
automatically MIME-encoded.

No default template is assumed, and all information other than the
default_sender that the system provides is expected to be gathered by the
Event Definition through either Environment or Parameter definitions.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $smtp = $conf->config_value('email_notify', 'smtp_server');
    $$env{default_sender} = $conf->config_value('email_notify', 'sender_address');

    my $text = encode_utf8($self->run_TT($env));
    return 0 if (!$text);

    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => $smtp]);

    my $stat;
    my $err;

    my $email = Email::MIME->new($text);

    # Handle the address fields.  In addition to encoding the values
    # properly, we make sure there is only 1 each.
    for my $hfield (qw/From To Bcc Cc Reply-To Sender/) {
        my @headers = $email->header($hfield);
        $email->header_str_set($hfield => decode_utf8(join(',', @headers))) if ($headers[0]);
    }

    # Handle the Subject field.  Again, the standard says there can be
    # only one.
    my @headers = $email->header('Subject');
    $email->header_str_set('Subject' => decode_utf8($headers[0])) if ($headers[0]);

    $email->header_set('MIME-Version' => '1.0');
    $email->header_set('Content-Type' => "text/plain; charset=UTF-8");
    $email->header_set('Content-Transfer-Encoding' => '8bit');

    try {
        $stat = $sender->send($email);
    } catch Error with {
        $err = $stat = shift;
        $logger->error("SendEmail Reactor: Email failed with error: $err");
    };

    if( !$err and $stat and $stat->type eq 'success' ) {
        $logger->info("SendEmail Reactor: successfully sent email");
        return 1;
    } else {
        $logger->warn("SendEmail Reactor: unable to send email: ".Dumper($stat));
        $text =~ s/\n//og;
        $logger->warn("SendEmail Reactor: failed email template: $text");
        return 0;
    }

}

1;

