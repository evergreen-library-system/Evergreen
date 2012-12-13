package OpenILS::Application::Acq::EDI;
use base qw/OpenILS::Application/;

use strict; use warnings;

use IO::Scalar;

use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;

use OpenILS::Application::Acq::Lineitem;
use OpenILS::Utils::RemoteAccount;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI::Translator;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

use OpenILS::Utils::EDIReader;

use Data::Dumper;
our $verbose = 0;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    # $self->{args} = {};
    return $self;
}

# our $reasons = {};   # cache for acq.cancel_reason rows ?

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
    authoritative => 1,
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
    my ($self, $set, $max, $e, $test) = @_;    # $e is a working editor

    $e   ||= new_editor();
    $set ||= __PACKAGE__->retrieve_vendors($e);

    my @return = ();
    my $vcount = 0;
    foreach my $account (@$set) {
        my $count = 0;
        my $server;
        $logger->info("EDI check for vendor " . ++$vcount . " of " . scalar(@$set) . ": " . $account->host);
        unless ($server = __PACKAGE__->remote_account($account)) {   # assignment, not comparison
            $logger->err(sprintf "Failed remote account mapping for %s (%s)", $account->host, $account->id);
            next;
        };
#       my $rf_starter = './';  # default to current dir
        if ($account->in_dir) { 
            if ($account->in_dir =~ /\*+.*\//) {
                $logger->err("EDI in_dir has a slash after an asterisk in value: '" . $account->in_dir . "'.  Skipping account with indeterminate target dir!");
                next;
            }
#           $rf_starter = $account->in_dir;
#           $rf_starter =~ s/((\/)?[^\/]*)\*+[^\/]*$//;  # kill up to the first (possible) slash before the asterisk: keep the preceeding static dir
#           $rf_starter .= '/' if $rf_starter or $2;   # recap the dir, or replace leading "/" if there was one (but don't add if empty)
        }
        my @files    = ($server->ls({remote_file => ($account->in_dir || './')}));
        my @ok_files = grep {$_ !~ /\/\.?\.$/ and $_ ne '0'} @files;
        $logger->info(sprintf "%s of %s files at %s/%s", scalar(@ok_files), scalar(@files), $account->host, $account->in_dir);   
        # $server->remote_path(undef);
        foreach my $remote_file (@ok_files) {
            # my $remote_file = $rf_starter . $_;
            my $description = sprintf "%s/%s", $account->host, $remote_file;
            
            # deduplicate vs. acct/filenames already in DB
            my $hits = $e->search_acq_edi_message([
                {
                    account     => $account->id,
                    remote_file => $remote_file,
                    status      => {'in' => [qw/ processed /]},     # if it never got processed, go ahead and get the new one (try again)
                    # create_time => 'NOW() - 60 DAYS',     # if we wanted to allow filenames to be reused after a certain time
                    # ideally we would also use the date from FTP, but that info isn't available via RemoteAccount
                }
                # { flesh => 1, flesh_fields => {...}, }
            ]);
            if (scalar(@$hits)) {
                $logger->debug("EDI: $remote_file already retrieved.  Skipping");
                warn "EDI: $remote_file already retrieved.  Skipping";
                next;
            }

            ++$count;
            $max and $count > $max and last;
            $logger->info(sprintf "%s of %s targets: %s", $count, scalar(@ok_files), $description);
            print sprintf "%s of %s targets: %s\n", $count, scalar(@ok_files), $description;
            if ($test) {
                push @return, "test_$count";
                next;
            }
            my $content;
            my $io = IO::Scalar->new(\$content);
            unless ( $server->get({remote_file => $remote_file, local_file => $io}) ) {
                $logger->error("(S)FTP get($description) failed");
                next;
            }
            my $incoming = __PACKAGE__->process_retrieval($content, $remote_file, $server, $account->id);
#           $server->delete(remote_file => $_);   # delete remote copies of saved message
            push @return, @$incoming;
        }
    }
    return \@return;
}

# my $msg_ids = OpenILS::Application::Acq::EDI->process_retrieval(
#   $file_content, $remote_filename, $server, $account_id, $editor);

sub process_retrieval {
    my ($class, $content, $filename, $server, $account_or_id) = @_;
    $content or return;

    my $e = new_editor;
    my $account = __PACKAGE__->record_activity($account_or_id, $e);

    # a single EDI blob can contain multiple messages
    # create one edi_message per included message

    my $messages = OpenILS::Utils::EDIReader->new->read($content);
    my @return;

    for my $msg_hash (@$messages) {

        my $incoming = Fieldmapper::acq::edi_message->new;

        $incoming->remote_file($filename);
        $incoming->account($account->id);
        $incoming->edi($content);
        $incoming->message_type($msg_hash->{message_type});
        $incoming->jedi(OpenSRF::Utils::JSON->perl2JSON($msg_hash)); # jedi-2.0
        $incoming->status('translated');
        $incoming->translate_time('NOW');

        if ($msg_hash->{purchase_order}) {
            $logger->info("EDI: processing message for PO " . $msg_hash->{purchase_order});
            $incoming->purchase_order($msg_hash->{purchase_order});
            unless ($e->retrieve_acq_purchase_order($incoming->purchase_order)) {
                $logger->warn("EDI: received order response for nonexistent PO.  Skipping...");
                next;
            }
        }

        $e->xact_begin;
        unless($e->create_acq_edi_message($incoming)) {
            $logger->error("EDI: unable to create edi_message " . $e->die_event);
            next;
        }
        # refresh to pickup create_date, etc.
        $incoming = $e->retrieve_acq_edi_message($incoming->id);
        $e->xact_commit;

        # since there's a fair chance of unhandled problems 
        # cropping up, particularly with new vendors, wrap w/ eval.
        eval { $class->process_parsed_msg($account, $incoming, $msg_hash) };

        $e->xact_begin;
        $incoming = $e->retrieve_acq_edi_message($incoming->id);
        if ($@) {
            $incoming->status('proc_error');
            $incoming->error($@);
        } else {
            $incoming->status('processed');
        }
        $e->update_acq_edi_message($incoming);
        $e->xact_commit;

        push(@return, $incoming->id);
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

    $e->xact_begin;
    my @messageset = map {$e->retrieve_acq_edi_message($_)} @$message_ids;
    $e->xact_rollback;
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
        } elsif ($res = $server->put({remote_path => $account->path, content => $_->edi, single_ext => 1})) {
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
        $logger->error($message);
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
    $criteria->{'+acqpro'}->{id} = $vendor_id if $vendor_id;
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
    ($host =~ s/^(S?FTP)://i    and $args{type} = uc($1)) or
    ($host =~ s/^(SSH|SCP)://i  and $args{type} = 'SCP' ) ;
     $host =~ s/:(\d+)$//       and $args{port} = $1;
    ($args{remote_host} = $host) =~ s#/+##;
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

# takes account ID or account Fieldmapper object

sub record_activity {
    my ($class, $account_or_id, $e) = @_;
    $account_or_id or return;
    $e ||= new_editor();
    my $account = ref($account_or_id) ? $account_or_id : $e->retrieve_acq_edi_account($account_or_id);
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

# parts of this process can fail without the entire
# thing failing.  If a catastrophic error occurs,
# it will occur via die.
sub process_parsed_msg {
    my ($class, $account, $incoming, $msg_hash) = @_;

    if ($incoming->message_type eq 'INVOIC') {
        return $class->create_acq_invoice_from_edi(
            $msg_hash, $account->provider, $incoming);
    }

    # ORDRSP
    for my $li_hash (@{$msg_hash->{lineitems}}) {
        my $e = new_editor(xact => 1);

        my $li_id = $li_hash->{id};
        my $li = $e->retrieve_acq_lineitem($li_id);

        if (!$li) {
            $logger->error("EDI: request for invalid lineitem ID '$li_id'");
            $e->rollback;
            next;
        }

         $li->expected_recv_time(
            $class->edi_date_to_iso($li_hash->{expected_date}));

        $li->estimated_unit_price($li_hash->{unit_price});

        if (not $incoming->purchase_order) {                
            # PO should come from the EDI message, but if not...

            # fetch the latest copy
            $incoming = $e->retrieve_acq_edi_message($incoming->id);
            $incoming->purchase_order($li->purchase_order); 

            unless($e->update_acq_edi_message($incoming)) {
                $logger->error("EDI: unable to update edi_message " . $e->die_event);
                next;
            }
        }

        my $lids = $e->json_query({
            select => {acqlid => ['id']},
            from => 'acqlid',
            where => {lineitem => $li->id}
        });

        my @lids = map { $_->{id} } @$lids;
        my $lid_count = scalar(@lids);
        my $lids_covered = 0;
        my $lids_cancelled = 0;
        my $order_qty;
        my $dispatch_qty;
  
        for my $qty (@{$li_hash->{quantities}}) {

            my $qty_count = $qty->{quantity};
            my $qty_code = $qty->{code};

            next unless defined $qty_count;

            if (!$qty_code) {
                $logger->warn("EDI: Response for LI $li_id specifies quantity ".
                    "$qty_count with no 6063 code! Contact vendor to resolve.");
                next;
            }

            $logger->info("EDI: LI $li_id processing quantity count=$qty_count / code=$qty_code");

            if ($qty_code eq '21') { # "ordered quantity"
                $order_qty = $qty_count;
                $logger->info("EDI: LI $li_id -- vendor confirms $qty_count ordered");
                $logger->warn("EDI: LI $li_id -- order count $qty_count ".
                    "does not match LID count $lid_count") unless $qty_count == $lid_count;
                next;
            }

            $lids_covered += $qty_count;

            if ($qty_code eq '12') {
                $dispatch_qty = $qty_count;
                $logger->info("EDI: LI $li_id -- vendor dispatched $qty_count");
                next;

            } elsif ($qty_code eq '57') {
                $logger->info("EDI: LI $li_id -- $qty_count in transit");
                next;
            }
            # 84: urgent delivery
            # 118: quantity manifested
            # ...

            # -------------------------------------------------------------------------
            # All of the remaining quantity types require that we apply a cancel_reason
            # DB populated w/ 6063 keys in 1200's

            my $eg_reason = $e->retrieve_acq_cancel_reason(1200 + $qty_code);  

            if (!$eg_reason) {
                $logger->warn("EDI: Unhandled quantity qty_code '$qty_code' ".
                    "for li $li_id.  $qty_count items unprocessed");
                next;
            } 

            my ($cancel_count, $fatal) = 
                $class->cancel_lids($e, $eg_reason, $qty_count, $lid_count, \@lids);

            last if $fatal;

            $lids_cancelled += $cancel_count;

            # if ALL the items have the same cancel_reason, the LI gets it too
            if ($qty_count == $lid_count) {
                $li->cancel_reason($eg_reason->id);
                $li->state("cancelled");
            }
                
            $li->edit_time('now'); 
            unless ($e->update_acq_lineitem($li)) {
                $logger->error("EDI: update_acq_lineitem failed " . $e->die_event);
                last;
            }
        }

        # in case the provider neglected to echo back the order count
        $order_qty = $lid_count unless defined $order_qty;

        # it may be necessary to change the logic here to look for lineitem
        # order status / availability status instead of dispatch_qty and 
        # assume that dispatch_qty simply equals the number of unaccounted-for copies
        if (defined $dispatch_qty) {
            # provider is telling us how may copies were delivered

            # number of copies neither cancelled or delivered
            my $remaining_lids = $order_qty - ($dispatch_qty + $lids_cancelled);

            if ($remaining_lids > 0) {

                # the vendor did not ship all items and failed to provide cancellation
                # quantities for some or all of the items to be cancelled.  When this
                # happens, we cancel the remaining un-delivered copies using the
                # lineitem order status to determine the cancel reason.

                my $reason_id;
                my $stat;

                if ($stat = $li_hash->{order_status}) {
                    $logger->info("EDI: lineitem has order status $stat");

                    if ($stat eq '200') { 
                        $reason_id = 1007; # not accepted

                    } elsif ($stat eq '400') { 
                        $reason_id = 1283; # back-order
                    }

                } elsif ($stat = $li_hash->{avail_status}) {
                    $logger->info("EDI: lineitem has availability status $stat");

                    if ($stat eq 'NP') {
                        # not yet published
                        # TODO: needs cancellation?
                    } 
                }

                if ($reason_id) {
                    my $reason = $e->retrieve_acq_cancel_reason($reason_id);

                    my ($cancel_count, $fatal) = 
                        $class->cancel_lids($e, $reason, $remaining_lids, $lid_count, \@lids);

                    last if $fatal;
                    $lids_cancelled += $cancel_count;

                    # All LIDs cancelled with same reason, apply 
                    # the same cancel reason to the lineitem 
                    if ($remaining_lids == $order_qty) {
                        $li->cancel_reason($reason->id);
                        $li->state("cancelled");
                    }

                    $li->edit_time('now'); 
                    unless ($e->update_acq_lineitem($li)) {
                        $logger->error("EDI: update_acq_lineitem failed " . $e->die_event);
                        last;
                    }

                } else {
                    $logger->warn("EDI: vendor says we ordered $order_qty and cancelled ". 
                        "$lids_cancelled, but only shipped $dispatch_qty");
                }
            }
        }

        # LI and LIDs updated, let's wrap this one up.
        # this is a no-op if the xact has already been rolled back
        $e->commit;

        $logger->info("EDI: LI $li_id -- $order_qty LIDs ordered; ". 
            "$lids_cancelled LIDs cancelled");
    }
}

sub cancel_lids {
    my ($class, $e, $reason, $count, $lid_count, $lid_ids) = @_;

    my $cancel_count = 0;

    foreach (1 .. $count) {

        my $lid_id = shift @$lid_ids;

        if (!$lid_id) {
            $logger->warn("EDI: Used up all $lid_count LIDs. ".
                "Ignoring extra status '" . $reason->label . "'");
            last;
        }

        my $lid = $e->retrieve_acq_lineitem_detail($lid_id);
        $lid->cancel_reason($reason->id);

        # item is cancelled.  Remove the fund debit.
        unless ($U->is_true($reason->keep_debits)) {

            if (my $debit_id = $lid->fund_debit) {

                $lid->clear_fund_debit;
                my $debit = $e->retrieve_acq_fund_debit($debit_id);

                if ($U->is_true($debit->encumbrance)) {
                    $logger->info("EDI: deleting debit $debit_id for cancelled LID $lid_id");

                    unless ($e->delete_acq_fund_debit($debit)) {
                        $logger->error("EDI: unable to update fund_debit " . $e->die_event);
                        return (0, 1);
                    }
                } else {
                    # do not delete a paid-for debit
                    $logger->warn("EDI: cannot delete invoiced debit $debit_id");
                }
            }
        }

        $e->update_acq_lineitem_detail($lid);
        $cancel_count++;
    }

    return ($cancel_count);
}

sub edi_date_to_iso {
    my ($class, $date) = @_;
    return undef unless $date and $date =~ /\d+/;
    my ($iso, $m, $d) = $date =~ /^(\d{4})(\d{2})(\d{2})/g;
    $iso .= "-$m" if $m;
    $iso .= "-$d" if $d;
    return $iso;
}


# create_acq_invoice_from_edi() does what it sounds like it does for INVOIC
# messages.  For similar operation on ORDRSP messages, see the guts of
# process_jedi().
# Return boolean success indicator.
sub create_acq_invoice_from_edi {
    my ($class, $invoice, $provider, $message) = @_;
    # $invoice is O::U::EDIReader hash
    # $provider is only a pkey
    # $message is Fieldmapper::acq::edi_message

    my $e = new_editor();

    my $log_prefix = "create_acq_invoice_from_edi(..., <acq.edi_message #" .
        $message->id . ">): ";

    my $eg_inv = Fieldmapper::acq::invoice->new;

    $eg_inv->provider($provider);
    $eg_inv->shipper($provider);    # XXX Do we really have a meaningful way to
                                    # distinguish provider and shipper?
    $eg_inv->recv_method("EDI");

    $eg_inv->recv_date(
        $class->edi_date_to_iso($invoice->{invoice_date}));


    # some vendors encode the account number as the SAN.
    # starting with the san value, then the account value, 
    # treat each as a san, then an acct number until the first success
    for my $buyer ( ($invoice->{buyer_san}, $invoice->{buyer_acct}) ) {
        next unless $buyer;

        # some vendors encode the SAN as "$SAN $vendcode"
        $buyer =~ s/\s.*//g;

        my $addr = $e->search_actor_org_address(
            {valid => "t", san => $buyer})->[0];

        if ($addr) {

            $eg_inv->receiver($addr->org_unit);
            last;

        } else {

            my $acct = $e->search_acq_edi_account({vendacct => $buyer})->[0];

            if ($acct) {
                $eg_inv->receiver($acct->owner);
                last;
            }
        }
    }

    if (!$eg_inv->receiver) {
        $logger->error($log_prefix . 
            sprintf("unable to determine buyer (org unit) in invoice; ".
                "buyer_san=%s; buyer_acct=%s",
                ($invoice->{buyer_san} || ''), 
                ($invoice->{buyer_acct} || '')
            )
        );
        return 0;
    }

    $eg_inv->inv_ident($invoice->{invoice_ident});

    if (!$eg_inv->inv_ident) {
        $logger->error(
            $log_prefix . "no invoice ID # in INVOIC message; " . shift
        );
        return 0;
    }

    my @eg_inv_entries;
    my @eg_inv_cancel_lis;

    $message->purchase_order($invoice->{purchase_order});

    for my $lineitem (@{$invoice->{lineitems}}) {
        my $li_id = $lineitem->{id};

        if (!$li_id) {
            $logger->warn($log_prefix . "no lineitem ID");
            next;
        }

        my $li = $e->retrieve_acq_lineitem($li_id);

        if (!$li) {
            $logger->warn($log_prefix . 
                "no LI found with ID: $li_id : " . $e->event);
            return 0;
        }

        my ($quant) = grep {$_->{code} eq '47'} @{$lineitem->{quantities}};
        my $quantity = ($quant) ? $quant->{quantity} : 0;
        
        if (!$quantity) {
            $logger->warn($log_prefix . 
                "no invoice quantity specified for LI $li_id");
            next;
        }

        # NOTE: if needed, we also have $lineitem->{net_unit_price}
        # and $lineitem->{gross_unit_price}
        my $lineitem_price = $lineitem->{amount_billed};

        # if the top-level PO value is unset, get it from the first LI
        $message->purchase_order($li->purchase_order)
            unless $message->purchase_order;

        my $eg_inv_entry = Fieldmapper::acq::invoice_entry->new;
        $eg_inv_entry->inv_item_count($quantity);

        # amount staff agree to pay for
        $eg_inv_entry->phys_item_count($quantity);

        # XXX Validate by making sure the LI is on-order and belongs to
        # the right provider and ordering agency and all that.
        $eg_inv_entry->lineitem($li_id);

        # XXX Do we actually need to link to PO directly here?
        $eg_inv_entry->purchase_order($li->purchase_order);

        # This is the total price for all units billed, not per-unit.
        $eg_inv_entry->cost_billed($lineitem_price);

        # amount staff agree to pay
        $eg_inv_entry->amount_paid($lineitem_price);

        push @eg_inv_entries, $eg_inv_entry;
        push @eg_inv_cancel_lis, 
            {lineitem => $li, quantity => $quantity} 
            if $li->cancel_reason;
    }

    my @eg_inv_items;

    my %charge_type_map = (
        'TX' => ['TAX', 'Tax from electronic invoice'],
        'CA' => ['PRO', 'Cataloging services'], 
        'DL' => ['SHP', 'Delivery']
    );

    for my $charge (@{$invoice->{misc_charges}}) {
        my $eg_inv_item = Fieldmapper::acq::invoice_item->new;

        my $amount = $charge->{charge_amount};

        if (!$amount) {
            $logger->warn($log_prefix . "charge with no amount");
            next;
        }

        my $map = $charge_type_map{$charge->{charge_type}};

        if (!$map) {
            $map = [
                'PRO',
                'Unknown charge type ' .  $charge->{charge_type}
            ];
        }

        $eg_inv_item->inv_item_type($$map[0]);
        $eg_inv_item->note($$map[1]);
        $eg_inv_item->cost_billed($amount);

        push @eg_inv_items, $eg_inv_item;
    }

    $logger->info($log_prefix . 
        sprintf("creating invoice with %d entries and %d items.",
            scalar(@eg_inv_entries), scalar(@eg_inv_items)));

    $e->xact_begin;

    # save changes to acq.edi_message row
    if (not $e->update_acq_edi_message($message)) {
        $logger->error(
            $log_prefix . "couldn't update edi_message " . $message->id
        );
        return 0;
    }

    # create EG invoice
    if (not $e->create_acq_invoice($eg_inv)) {
        $logger->error($log_prefix . "couldn't create invoice: " . $e->event);
        return 0;
    }

    # Now we have a pkey for our EG invoice, so set the invoice field on all
    # our entries according and create those too.
    my $eg_inv_id = $e->data->id;
    foreach (@eg_inv_entries) {
        $_->invoice($eg_inv_id);
        if (not $e->create_acq_invoice_entry($_)) {
            $logger->error(
                $log_prefix . "couldn't create entry against lineitem " .
                $_->lineitem . ": " . $e->event
            );
            return 0;
        }
    }

    # Create any invoice items (taxes)
    foreach (@eg_inv_items) {
        $_->invoice($eg_inv_id);
        if (not $e->create_acq_invoice_item($_)) {
            $logger->error(
                $log_prefix . "couldn't create inv item: " . $e->event
            );
            return 0;
        }
    }

    # if an invoiced lineitem is marked as cancelled 
    # (e.g. back-order), invoicing the lineitem implies 
    # we need to un-cancel it
    for my $li_chunk (@eg_inv_cancel_lis) {
        my $li = $li_chunk->{lineitem};
        my $quantity = $li_chunk->{quantity};

        $logger->info($log_prefix . 
            "un-cancelling invoiced lineitem ". $li->id);
         
        # collect the LIDs, starting with those that are
        # not cancelled (should not happen), followed by
        # those that have keep-debits cancel_reasons, 
        # followed by non-keep-debit cancel reasons.

        my $lid_ids = $e->json_query({
            select => {acqlid => ['id']},
            from => {
                acqlid => {
                    acqcr => {type => 'left'},
                    acqfdeb => {type => 'left'}
                }
            },
            where => {
                '+acqlid' => {lineitem => $li->id},
                # not-yet invoiced copies
                '+acqfdeb' => {encumbrance => 't'}
            },
            order_by => [{
                class => 'acqcr',
                field => 'keep_debits',
                direction => 'desc'
            }],
            limit => $quantity
        });

        for my $lid_id (map {$_->{id}} @$lid_ids) {
            my $lid = $e->retrieve_acq_lineitem_detail($lid_id);
            next unless $lid->cancel_reason;

            $lid->clear_cancel_reason;
            unless ($e->update_acq_lineitem_detail($lid)) {
                $logger->error($log_prefix . 
                    "couldn't clear lid cancel reason: ". $e->die_event
                );
                return 0;
            }
        }

        $li->clear_cancel_reason;
        $li->state("on-order");
        $li->edit_time('now'); 

        unless ($e->update_acq_lineitem($li)) {
            $logger->error($log_prefix . 
                "couldn't clear li cancel reason: ". $e->die_event
            );
            return 0;
        }
    }


    $e->xact_commit;
    return 1;
}

1;

