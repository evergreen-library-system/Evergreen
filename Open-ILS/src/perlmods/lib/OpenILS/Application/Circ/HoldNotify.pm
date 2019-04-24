# ---------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <billserickson@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------


package OpenILS::Application::Circ::HoldNotify;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use vars q/$AUTOLOAD/;
use OpenILS::Event;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Fieldmapper;
use Email::Send;
use Data::Dumper;
use OpenSRF::EX qw/:try/;
my $U = 'OpenILS::Application::AppUtils';

use open ':utf8';


__PACKAGE__->register_method(
    method => 'send_email_notify_pub',
    api_name => 'open-ils.circ.send_hold_notify.email',
);


sub send_email_notify_pub {
    my( $self, $conn, $auth, $hold_id ) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CREATE_HOLD_NOTIFICATION');
    my $notifier = __PACKAGE__->new(requestor => $e->requestor, hold_id => $hold_id);
    return $notifier->event if $notifier->event;
    my $stat = $notifier->send_email_notify;
#   $e->commit if $stat == '1';
    return $stat;
}





# ---------------------------------------------------------------
# Define the notifier object
# ---------------------------------------------------------------

my @AUTOLOAD_FIELDS = qw/
    hold
    copy
    volume
    title
    editor
    patron
    event
    pickup_lib
    smtp_server
    settings_client
/;

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or die "$self is not an object";
    my $data = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://o;   

    unless (grep { $_ eq $name } @AUTOLOAD_FIELDS) {
        $logger->error("hold_notify: $type: invalid autoload field: $name");
        die "$type: invalid autoload field: $name\n" 
    }

    {
        no strict 'refs';
        *{"${type}::${name}"} = sub {
            my $s = shift;
            my $v = shift;
            $s->{$name} = $v if defined $v;
            return $s->{$name};
        }
    }
    return $self->$name($data);
}


sub new {
    my( $class, %args ) = @_;
    $class = ref($class) || $class;
    my $self = bless( {}, $class );
    $self->editor( new_editor( xact => 1, requestor => $args{requestor} ));
    $logger->debug("circulator: creating new hold-notifier with requestor ".
        $self->editor->requestor->id);
    $self->fetch_data($args{hold_id});
    return $self;
}

sub send_email_notify {
    my $self = shift;

    my $sc = OpenSRF::Utils::SettingsClient->new;
    my $setting = $sc->config_value(
        qw/ apps open-ils.circ app_settings notify_hold email / );

    $logger->debug("hold_notify: email enabled setting = $setting");

    if( !$setting or $setting ne 'true' ) {
      $self->editor->rollback;
        $logger->info("hold_notify: not sending hold notify - email notifications disabled");
        return 0;
    }

    unless ($U->is_true($self->hold->email_notify)) {
      $self->editor->rollback;
        $logger->info("hold_notify: not sending hold notification because email_notify is false");
        return 0;
    }

    unless( $self->patron->email and $self->patron->email =~ /.+\@.+/ ) { # see if it's remotely email-esque
      $self->editor->rollback;
       return OpenILS::Event->new('PATRON_NO_EMAIL_ADDRESS');
   }

    $logger->info("hold_notify: attempting email notify on hold ".$self->hold->id);

    my $sclient = OpenSRF::Utils::SettingsClient->new;
    $self->settings_client($sclient);
    my $template = $sclient->config_value('email_notify', 'template');
    my $str = $self->flesh_template($self->load_template($template));

    unless( $str ) {
      $self->editor->rollback;
        $logger->error("hold_notify: No email notify template found - cannot notify");
        return 0;
    }

   my $reqr = $self->editor->requestor;
   $self->editor->rollback; # we're done with this transaction

    return 0 unless $self->send_email($str);

    # ------------------------------------------------------------------
    # If the hold email takes too long to send, the existing editor 
    # transaction may have timed out.  Create a one-off editor to write 
    # the notification to the DB.
    # ------------------------------------------------------------------
    my $we = new_editor(xact=>1, requestor=>$reqr);

    my $notify = Fieldmapper::action::hold_notification->new;
    $notify->hold($self->hold->id);
    $notify->notify_staff($we->requestor->id);
    $notify->notify_time('now');
    $notify->method('email');
    
    $we->create_action_hold_notification($notify)
        or return $we->die_event;
    $we->commit;

    return 1;
}

sub send_email {
    my( $self, $text ) = @_;

   # !!! $self->editor xact has been rolled back before we get here

    my $smtp = $self->settings_client->config_value('email_notify', 'smtp_server');

    $logger->info("hold_notify: sending email notice to ".
        $self->patron->email." with SMTP server $smtp");

    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => $smtp]);

    my $stat;
    my $err;

    try {
        $stat = $sender->send($text);
    } catch Error with {
        $err = $stat = shift;
        $logger->error("hold_notify: Email notify failed with error: $err");
    };

    if( !$err and $stat and $stat->type eq 'success' ) {
        $logger->info("hold_notify: successfully sent hold notification");
        return 1;
    } else {
        $logger->warn("hold_notify: unable to send hold notification: ".Dumper($stat));
        return 0;
    }

    return undef;
}


# -------------------------------------------------------------------------
# Fetches all of the hold-related data
# -------------------------------------------------------------------------
sub fetch_data {
    my $self        = shift;
    my $holdid  = shift;
    my $e           = $self->editor;

    $logger->debug("circulator: fetching hold notify data");

    $self->hold($e->retrieve_action_hold_request($holdid)) or return $self->event($e->event);
    $self->copy($e->retrieve_asset_copy($self->hold->current_copy)) or return $self->event($e->event);
    $self->volume($e->retrieve_asset_call_number($self->copy->call_number)) or return $self->event($e->event);
    $self->title($e->retrieve_biblio_record_entry($self->volume->record)) or return $self->event($e->event);
    $self->patron($e->retrieve_actor_user($self->hold->usr)) or return $self->event($e->event);
    $self->pickup_lib($e->retrieve_actor_org_unit($self->hold->pickup_lib)) or return $self->event($e->event);
}


sub extract_data {
    my $self = shift;
    my $e = $self->editor;

    my $patron = $self->patron;
    my $o_name = $self->pickup_lib->name;
    my $p_name = $patron->first_given_name .' '.$patron->family_name;

    # try to find a suitable address for the patron
    my $p_addr;
    my $p_addrs;
    unless( $p_addr = 
            $e->retrieve_actor_user_address($patron->billing_address)) {
        unless( $p_addr = 
                $e->retrieve_actor_user_address($patron->mailing_address)) {
            $logger->warn("hold_notify: No address for user ".$patron->id);
            $p_addrs = "";
        }
    }

    unless( defined $p_addrs ) {
        $p_addrs = 
            $p_addr->street1." ".
            $p_addr->street2." ".
            $p_addr->city." ".
            $p_addr->state." ".
            $p_addr->post_code;
    }

    my $l_addr = $e->retrieve_actor_org_address($self->pickup_lib->holds_address);
    my $l_addrs = (!$l_addr) ? "" : 
            $l_addr->street1." ".
            $l_addr->street2." ".
            $l_addr->city." ".
            $l_addr->state." ".
            $l_addr->post_code;

    my $title;  
    my $author;

    if( $self->title->id == OILS_PRECAT_RECORD ) {
        $title = ($self->copy->dummy_title) ? 
            $self->copy->dummy_title : "";
        $author = ($self->copy->dummy_author) ? 
            $self->copy->dummy_author : "";
    } else {
        my $mods    = $U->record_to_mvr($self->title);
        $title  = ($mods->title) ? $mods->title : "";
        $author = ($mods->author) ? $mods->author : "";
    }


    return { 
        patron_email => $self->patron->email,
        pickup_lib_name => $o_name,
        pickup_lib_addr => $l_addrs,
        patron_name => $p_name, 
        patron_addr => $p_addrs, 
        title => $title, 
        author => $author, 
        call_number => $self->volume->label,
        copy_barcode => $self->copy->barcode,
        copy_number => $self->copy->copy_number,
    };
}



sub load_template {
    my $self = shift;
    my $template = shift;

    unless( open(F, $template) ) {
        $logger->error("hold_notify: Unable to open hold notification template file: $template");
        return undef;
    }

    # load the template, strip comments
    my @lines = <F>;
    close(F);

    my $str = '';
    for(@lines) {
    chomp $_;
    next if $_ =~ /^\s*\#/o;
    $_ =~ s/\#.*//og;
    $str .= "$_\n";
    }

    return $str;
}

sub flesh_template {
    my( $self, $str ) = @_;
    return undef unless $str;

    my @time    = CORE::localtime();
    my $day         = $time[3];
    my $month   = $time[4] + 1;
    my $year    = $time[5] + 1900;

    my $data = $self->extract_data;

    my $email       = $$data{patron_email};
    my $p_name      = $$data{patron_name};
    my $p_addr      = $$data{patron_addr};
    my $o_name      = $$data{pickup_lib_name};
    my $o_addr      = $$data{pickup_lib_addr};
    my $title       = $$data{title};
    my $author      = $$data{author};
    my $cn          = $$data{call_number};
    my $barcode     = $$data{copy_barcode};
    my $copy_number = $$data{copy_number};

    my $sender = $self->settings_client->config_value('email_notify', 'sender_address');
    my $reply_to = $self->pickup_lib->email;
    $reply_to ||= $sender; 

   # if they have an org setting for bounced emails, use that as the sender address
   if( my $set = $self->editor->search_actor_org_unit_setting(
         {  name => OILS_SETTING_ORG_BOUNCED_EMAIL, 
            org_unit => $self->pickup_lib->id } )->[0] ) {

      my $bemail = OpenSRF::Utils::JSON->JSON2perl($set->value);
      $sender = $bemail if $bemail;
   }

   $str =~ s/\$\{EMAIL_SENDER}/$sender/;
   $str =~ s/\$\{EMAIL_RECIPIENT}/$email/;
   $str =~ s/\$\{EMAIL_REPLY_TO}/$reply_to/;
   $str =~ s/\$\{EMAIL_HEADERS}//;

   $str =~ s/\$\{DATE}/$year-$month-$day/;
   $str =~ s/\$\{LIBRARY}/$o_name/;
   $str =~ s/\$\{LIBRARY_ADDRESS}/$o_addr/;
   $str =~ s/\$\{PATRON_NAME}/$p_name/;
   $str =~ s/\$\{PATRON_ADDRESS}/$p_addr/;

   $str =~ s/\$\{TITLE}/$title/;
   $str =~ s/\$\{AUTHOR}/$author/;
   $str =~ s/\$\{CALL_NUMBER}/$cn/;
   $str =~ s/\$\{COPY_BARCODE}/$barcode/;
   $str =~ s/\$\{COPY_NUMBER}/$copy_number/;

    return $str;
}





1;
