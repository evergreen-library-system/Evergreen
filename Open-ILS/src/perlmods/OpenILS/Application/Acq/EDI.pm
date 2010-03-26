package OpenILS::Application::Acq::EDI;
use base qw/OpenILS::Application/;

use strict; use warnings;

use IO::Scalar;

use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;

use OpenILS::Utils::RemoteAccount;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI::Translator;

use Data::Dumper;
our $verbose = 0;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    # $self->{args} = {};
    return $self;
}

our $translator;

sub translator {
    return $translator ||= OpenILS::Application::Acq::EDI::Translator->new(@_);
}

my %map = (
    host     => 'remote_host',
    username => 'remote_user',
    password => 'remote_password',
    account  => 'remote_account',
    # in_dir   => 'remote_path',   # field_map overrides path with in_dir
    path     => 'remote_path',
);


## Just for debugging stuff:
sub add_a_msg {
    my ($self, $conn) = @_;
    my $e = new_editor(xact=>1);
    my $incoming = Fieldmapper::acq::edi_message->new;
    $incoming->edi("This is content");
    $incoming->account(1);
    $incoming->remote_file('in/some_file.edi');
    $e->create_acq_edi_message($incoming);;
    $e->commit;
}
# __PACKAGE__->register_method( method => 'add_a_msg', api_name => 'open-ils.acq.edi.add_a_msg');  # debugging

__PACKAGE__->register_method(
	method    => 'retrieve',
	api_name  => 'open-ils.acq.edi.retrieve',
	signature => {
        desc   => 'Fetch incoming message(s) from EDI accounts.  ' .
                  'Optional arguments to restrict to one vendor and/or a max number of messages.  ' .
                  'Note that messages are not parsed or processed here, just fetched and translated.',
        params => [
            {desc => 'Authentication token',        type => 'string'},
            {desc => 'Vendor ID (undef for "all")', type => 'number'},
            {desc => 'Date Inactive Since',         type => 'string'},
            {desc => 'Max Messages Retrieved',      type => 'number'}
        ],
        return => {
            desc => 'List of new message IDs (empty if none)',
            type => 'array'
        }
    }
);

sub retrieve_core {
    my ($self, $e, $set, $max) = @_;    # $e is a working editor

    $e   ||= new_editor();
    $set ||= __PACKAGE__->retrieve_vendors($e);

    my @return = ();
    my $vcount = 0;
    foreach my $account (@$set) {
        my $count = 0;
        my $server;
        $logger->info("EDI check for vendor " . ++$vcount . " of " . scalar(@$set) . ": " . $account->host);
        unless ($server = __PACKAGE__->remote_account($account)) {   # assignment, not comparison
            $logger->err(sprintf "Failed remote account connection for %s (%s)", $account->host, $account->id);
            next;
        };
        my @files    = $server->ls({remote_file => ($account->in_dir || '.')});
        my @ok_files = grep {$_ !~ /\/\.?\.$/ } @files;
        $logger->info(sprintf "%s of %s files at %s/%s", scalar(@ok_files), scalar(@files), $account->host, ($account->in_dir || ''));   
        foreach (@ok_files) {
            ++$count;
            $max and $count > $max and last;
            my $content;
            my $io = IO::Scalar->new(\$content);
            unless ($server->get({remote_file => $_, local_file => $io})) {
                $logger->error("(S)FTP get($_) failed");
                next;
            }
            my $incoming = Fieldmapper::acq::edi_message->new;
            $incoming->remote_file($_);
            $incoming->edi($content);
            $incoming->account($account->id);
             __PACKAGE__->attempt_translation($incoming);
            $e->xact_begin;
            $e->create_acq_edi_message($incoming);
            $e->xact_commit;
            __PACKAGE__->record_activity($account, $e);
            __PACKAGE__->process_jedi($incoming, $e);
#           $server->delete(remote_file => $_);   # delete remote copies of saved message
            push @return, $incoming->id;
        }
    }
    return \@return;
}

# ->send_core
# $account     is a Fieldmapper object for acq.edi_account row
# $messageset  is an arrayref with acq.edi_message.id values
# $e           is optional editor object
sub send_core {
    my ($class, $account, $message_ids, $e) = @_;    # $e is a working editor

    ($account and scalar @$message_ids) or return;
    $e ||= new_editor();

    my @messageset = map {$e->retrieve_acq_edi_message($_)} @$message_ids;
    my $m_count = scalar(@messageset);
    (scalar(@$message_ids) == $m_count) or
        $logger->warn(scalar(@$message_ids) - $m_count . " bad IDs passed to send_core (ignored)");

    my $log_str = sprintf "EDI send to edi_account %s (%s)", $account->id, $account->host;
    $logger->info("$log_str: $m_count message(s)");
    $m_count or return;

    my $server;
    my $server_error;
    unless ($server = __PACKAGE__->remote_account($account, 1)) {   # assignment, not comparison
        $logger->error("Failed remote account connection for $log_str");
        $server_error = 1;
    };
    foreach (@messageset) {
        $_ or next;     # we already warned about bum ids
        my ($res, $error);
        if ($server_error) {
            $error = "Server error: Failed remote account connection for $log_str"; # already told $logger, this is to update object below
        } elsif (! $_->edi) {
            $logger->error("Message (id " . $_->id. ") for $log_str has no EDI content");
            $error = "EDI empty!";
        } elsif ($res = $server->put({remote_path => $account->path, content => $_->edi})) {
            #  This is the successful case!
            $_->remote_file($res);
            $_->status('complete');
            $_->process_time('NOW');    # For outbound files, sending is the end of processing on the EG side.
            $logger->info("Sent message (id " . $_->id. ") via $log_str");
        } else {
            $logger->error("(S)FTP put to $log_str FAILED: " . ($server->error || 'UNKOWNN'));
            $error = "put FAILED: " . ($server->error || 'UNKOWNN');
        }
        if ($error) {
            $_->error($error);
            $_->error_time('NOW');
        }
        $logger->info("Calling update_acq_edi_message");
        $e->xact_begin;
        unless ($e->update_acq_edi_message($_)) {
             $logger->error("EDI send_core update_acq_edi_message failed for message object: " . Dumper($_));
             OpenILS::Application::Acq::EDI::Translator->debug_file(Dumper($_              ), '/tmp/update_acq_edi_message.FAIL');
             OpenILS::Application::Acq::EDI::Translator->debug_file(Dumper($_->to_bare_hash), '/tmp/update_acq_edi_message.FAIL.to_bare_hash');
        }
        # There's always an update, even if we failed.
        $e->xact_commit;
        __PACKAGE__->record_activity($account, $e);  # There's always an update, even if we failed.
    }
    return \@messageset;
}

#  attempt_translation does not touch the DB, just the object.  
sub attempt_translation {
    my ($class, $edi_message, $to_edi) = @_;
    my $tran  = translator();
    my $ret   = $to_edi ? $tran->json2edi($edi_message->jedi) : $tran->edi2json($edi_message->edi);
#   $logger->error("json: " . Dumper($json)); # debugging
    if (not $ret or (! ref($ret)) or $ret->is_fault) {      # RPC::XML::fault on failure
        $edi_message->status('trans_error');
        $edi_message->error_time('NOW');
        my $pre = "EDI Translator " . ($to_edi ? 'json2edi' : 'edi2json') . " failed";
        my $message = ref($ret) ? 
                      ("$pre, Error " . $ret->code . ": " . __PACKAGE__->nice_string($ret->string)) :
                      ("$pre: "                           . __PACKAGE__->nice_string($ret)        ) ;
        $edi_message->error($message);
        $logger->error(  $message);
        return;
    }
    $edi_message->status('translated');
    $edi_message->translate_time('NOW');
    if ($to_edi) {
        $edi_message->edi($ret->value);    # translator returns an object
    } else {
        $edi_message->jedi($ret->value);   # translator returns an object
    }
    return $edi_message;
}

sub retrieve_vendors {
    my ($self, $e, $vendor_id, $last_activity) = @_;    # $e is a working editor

    $e ||= new_editor();

    my $criteria = {'+acqpro' => {active => 't'}};
    # $criteria->{vendor_id} = $vendor_id if $vendor_id;
    return $e->search_acq_edi_account([
        $criteria, {
            'join' => 'acqpro',
            flesh => 1,
            flesh_fields => {
                acqedi => ['provider']
            }
        }
    ]);
#   {"id":{"!=":null},"+acqpro":{"active":"t"}}, {"join":"acqpro", "flesh_fields":{"acqedi":["provider"]},"flesh":1}
}

# This is the SRF-exposed call, so it does checkauth

sub retrieve {
    my ($self, $conn, $auth, $vendor_id, $last_activity, $max) = @_;

    my $e = new_editor(authtoken=>$auth);
    unless ($e and $e->checkauth()) {
        $logger->warn("checkauth failed for authtoken '$auth'");
        return ();
    }
    # return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $li->purchase_order->ordering_agency);  # add permission here ?

    my $set = __PACKAGE__->retrieve_vendors($e, $vendor_id, $last_activity) or return $e->die_event;
    return __PACKAGE__->retrieve_core($e, $set, $max);
}


# field_map takes the hashref of vendor data with fields from acq.edi_account and 
# maps them to the argument style needed for RemoteAccount.  It also extrapolates
# data from the remote_host string for type and port, when available.

sub field_map {
    my $self   = shift;
    my $vendor = shift or return;
    my $no_override = @_ ? shift : 0;
    my %args = ();
    $verbose and $logger->warn("vendor: " . Dumper($vendor));
    foreach (keys %map) {
        $args{$map{$_}} = $vendor->$_ if defined $vendor->$_;
    }
    unless ($no_override) {
        $args{remote_path} = $vendor->in_dir;    # override "path" with "in_dir"
    }
    my $host = $args{remote_host} || '';
    ($host =~ /^(S?FTP):/i    and $args{type} = uc($1)) or
    ($host =~ /^(SSH|SCP):/i  and $args{type} = 'SCP' ) ;
     $host =~ /:(\d+)$/       and $args{port} = $1;
    $verbose and $logger->warn("field_map: " . Dumper(\%args));
    return %args;
}


# The point of remote_account is to get the RemoteAccount object with args from the DB

sub remote_account {
    my ($self, $vendor, $outbound, $e) = @_;

    unless (ref($vendor)) {     # It's not a hashref/object.
        $vendor or return;      # If in fact it's nothing: abort!
                                # else it's a vendor_id string, so get the full vendor data
        $e ||= new_editor();
        my $set_of_one = $self->retrieve_vendors($e, $vendor) or return;
        $vendor = shift @$set_of_one;
    }

    return OpenILS::Utils::RemoteAccount->new(
        $self->field_map($vendor, $outbound)
    );
}

sub record_activity {
    my ($class, $account, $e) = @_;
    $account or return;
    $e ||= new_editor();
    $logger->info("EDI record_activity calling update_acq_edi_account");
    $account->last_activity('NOW') or return;
    $e->xact_begin;
    $e->update_acq_edi_account($account) or $logger->warn("EDI: in record_activity, update_acq_edi_account FAILED");
    $e->xact_commit;
    return $account;
}

sub nice_string {
    my $class = shift;
    my $string = shift or return '';
    chomp($string);
    my $head   = @_ ? shift : 100;
    my $tail   = @_ ? shift :  25;
    (length($string) < $head + $tail) and return $string;
    my $h = substr($string,0,$head);
    my $t = substr($string, -1*$tail);
    $h =~s/\s*$//o;
    $t =~s/\s*$//o;
    return "$h ... $t";
    # return substr($string,0,$head) . "... " . substr($string, -1*$tail);
}

sub jedi2perl {
    my ($class, $jedi) = @_;
    $jedi or return;
    my $msg = OpenSRF::Utils::JSON->JSON2perl( $jedi );
    open (FOO, ">>/tmp/joe_jedi_dump.txt");
    print FOO Dumper($msg), "\n\n";
    close FOO;
    $logger->warn("Dumped JSON2perl to /tmp/JSON2perl_dump.txt");
    return $msg;
}

# ->process_jedi($message, $e)
sub process_jedi {
    my $class    = shift;
    my $message  = shift or return;
    my $jedi     = ref($message) ? $message->jedi : $message;  # If we got an object, it's an edi_message.  A string is the jedi content itself.
    unless ($jedi) {
        $logger->warn("EDI process_jedi missing required argument (edi_message object with jedi or jedi scalar)!");
        return;
    }
    my $perl = __PACKAGE__->jedi2perl($jedi);
    if (ref($message) and not $perl) {
        my $e = @_ ? shift : new_editor();
        $message->error(($message->error || '') . " JSON2perl FAILED to convert jedi");
        $message->error_time('NOW');
        $e->xact_begin;
        $e->udpate_acq_edi_message($message) or $logger->warn("EDI update_acq_edi_message failed! $!");
        $e->xact_commit;
    }
    # __PACKAGE__->process_eval_msg(__PACKAGE__->jedi2perl($jedi), @_);
    return $perl;   # TODO process perl
}

sub process_eval_msg {
    my ($class, $msg, $e) = @_;
    $msg or return;
    $e ||= new_editor();
## Do all the hard work.
#   ID the message type
#   Find PO references
#   update POs & lineitems(?)
}

1;

