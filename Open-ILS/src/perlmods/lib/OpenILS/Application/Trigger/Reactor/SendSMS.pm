package OpenILS::Application::Trigger::Reactor::SendSMS;
use strict; use warnings;
use Error qw/:try/;
use Data::Dumper;
use Email::Send;
use Email::Simple;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Trigger::Reactor;
use OpenSRF::Utils::Logger qw/:logger/;
use Encode;
$Data::Dumper::Indent = 0;

use base 'OpenILS::Application::Trigger::Reactor::SendEmail';

# This module is just another name for SendEmail, as a way to get around the
# "ev_def_owner_hook_val_react_clean_delay_once" index/constraint on the table
# action.event_definition.  The template fed to SendSMS is responsible for
# using helpers.get_sms_email_gateway to, for example,  convert .sms_carrier
# and .sms_notify off of a hold into an email address.

1;
