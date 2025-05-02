package OpenILS::Application::Acq::EDI;
use base qw/OpenILS::Application/;

use strict; use warnings;

use IO::Scalar;

use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;

use OpenILS::Application::Acq::Lineitem;
use OpenILS::Application::Acq::Invoice;
use OpenILS::Utils::RemoteAccount;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI::Translator;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

use OpenILS::Utils::EDIReader;

use Data::Dumper;
$Data::Dumper::Indent = 0;
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

my $VENDOR_KLUDGE_MAP = {
    INVOIC => {
        amount_billed_is_per_unit => [1699342]
    },
    ORDRSP => {
    }
};


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

    # Deduplicate the set based on host, username, password, and
    # in_dir to eliminate unnecessary connections to the remote host.
    my @subset = ();
    foreach my $i (@$set) {
        unless (@subset) {
            push @subset, $i;
        } elsif (! grep {$_->host eq $i->host && $_->username eq $i->username
                             && $_->password eq $i->password && $_->in_dir eq $i->in_dir} @subset) {
            push @subset, $i;
        }
    }

    my @return = ();
    my $vcount = 0;
    foreach my $account (@subset) {
        my $count = 0;
        my $server;
        $logger->info(
            "EDI check for vendor " .
            ++$vcount . " of " . scalar(@subset) . ": " . $account->host
        );
        unless ($server = __PACKAGE__->remote_account($account)) { # assignment
            $logger->err(
                sprintf "Failed remote account mapping for %s (%s)",
                $account->host, $account->id
            );
            next;
        };

        if ($account->in_dir) { 
            if ($account->in_dir =~ /\*+.*\//) {
                $logger->err(
                    "EDI in_dir has a slash after an asterisk in value: '" .
                    $account->in_dir .
                    "'.  Skipping account with indeterminate target dir!"
                );
                next;
            }
        }

        my @files    = ($server->ls({remote_file => ($account->in_dir || './')}));
        my @ok_files = grep {$_ !~ /\/\.?\.$/ and $_ ne '0'} @files;
        $logger->info(sprintf "%s of %s files at %s/%s", scalar(@ok_files), scalar(@files), $account->host, $account->in_dir || "");   

        foreach my $remote_file (@ok_files) {
            my $description = sprintf "%s/%s", $account->host, $remote_file;

            # deduplicate vs. acct/filenames already in DB.
            #
            # The reason we match against host/username/password/in_dir
            # is that there may be many variant accounts that point to the
            # same FTP site and credentials.  If we only checked based on
            # acq.edi_account.id, we'd not find out in those cases that we've
            # already processed the same file before.
            my $hits = $e->search_acq_edi_message(
                [
                    {
                        "+acqedi" => {
                            host => $account->host,
                            username => $account->username,
                            password => $account->password,
                            in_dir => $account->in_dir
                        },
                        remote_file => {'=' => {
                            transform => 'evergreen.lowercase',
                            value => ['evergreen.lowercase', $remote_file]
                        }},
                        status      => {'in' => [qw/ processed proc_error trans_error /]},
                    },
                    { join => {"acqedi" => {}}, limit => 1 }
                ], { idlist => 1 }
            );

            if (!$hits) {
                my $msg = "EDI: test for already-retrieved files yielded " .
                    "event " . $e->event->{textcode};
                $logger->warn($msg);
                warn $msg;
                return $e->die_event;
            }

            if (@$hits) {
                $logger->debug("EDI: $remote_file already retrieved.  Skipping");
                warn "EDI: $remote_file already retrieved.  Skipping";
                next;
            }

            ++$count;
            if ($max and $count > $max) {
                last;
            }

            $logger->info(
                sprintf "%s of %s targets: %s",
                    $count, scalar(@ok_files), $description
            );
            printf("%d of %d targets: %s\n", $count, scalar(@ok_files), $description);
            if ($test) {
                push @return, "test_$count";
                next;
            }
            my $content;
            my $io = IO::Scalar->new(\$content);

            unless (
                $server->get({remote_file => $remote_file, local_file => $io})
            ) {
                $logger->error("(S)FTP get($description) failed");
                next;
            }

            my $incoming = __PACKAGE__->process_retrieval(
                $content, $remote_file, $server, $account->id
            );

            push @return, @$incoming;
        }
    }
    return \@return;
}


# procses_retrieval() returns a reference to a list of acq.edi_message IDs
sub process_retrieval {
    my ($class, $content, $filename, $server, $account_or_id) = @_;
    $content or return;

    my $e = new_editor;
    my $account = __PACKAGE__->record_activity($account_or_id, $e);

    # a single EDI blob can contain multiple messages
    # create one edi_message per included message

    my $seen_container_codes = {};
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
            # Some vendors just put their name where there ought to be a number,
            # and others put alphanumeric strings that mean nothing to us, so
            # we sure won't match a PO in the system this way. We can pick
            # up PO number later from the lineitems themselves if necessary.

            if ($msg_hash->{purchase_order} !~ /^\d+$/) {
                $logger->warn("EDI: PO identifier is non-numeric. Blanking and continuing.");
                undef $msg_hash->{purchase_order};
            } else {
                $logger->info("EDI: processing message for PO " .
                    $msg_hash->{purchase_order});
                $incoming->purchase_order($msg_hash->{purchase_order});
                unless ($e->retrieve_acq_purchase_order(
                        $incoming->purchase_order)) {
                    $logger->warn("EDI: received order response for " .
                        "nonexistent PO.  Skipping...");
                    next;
                }
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
        eval { $class->process_parsed_msg($account, $incoming, $msg_hash, $seen_container_codes) };

        $e->xact_begin;
        if ($@) {
            $incoming = $e->retrieve_acq_edi_message($incoming->id);
            $logger->error($@);
            $incoming->status('proc_error');
            $incoming->error_time('now');
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
# $message_ids is an arrayref with acq.edi_message.id values
# $e           is optional editor object
sub send_core {
    my ($class, $account, $message_ids, $e) = @_;    # $e is a working editor

    return unless $account and @$message_ids;
    $e ||= new_editor();

    $e->xact_begin;
    my @messageset = map {$e->retrieve_acq_edi_message($_)} @$message_ids;
    $e->xact_rollback;
    my $m_count = scalar(@messageset);
    if (@$message_ids != $m_count) {
        $logger->warn(scalar(@$message_ids) - $m_count . " bad IDs passed to send_core (ignored)");
    }

    my $log_str = sprintf "EDI send to edi_account %s (%s)", $account->id, $account->host;
    $logger->info("$log_str: $m_count message(s)");
    return unless $m_count;

    my $server;
    my $server_error;
    unless ($server = __PACKAGE__->remote_account($account, 1)) { # assignment
        $logger->error("Failed remote account connection for $log_str");
        $server_error = 1;
    }

    foreach (@messageset) {
        $_ or next;     # we already warned about bum ids
        my ($res, $error);
        if ($server_error) {
            # We already told $logger; this is to update object below
            $error = "Server error: Failed remote account connection ".
                "for $log_str";
        } elsif (! $_->edi) {
            $logger->error(
                "Message (id " . $_->id. ") for $log_str has no EDI content"
            );
            $error = "EDI empty!";
        } elsif (
            $res = $server->put({
                remote_path => $account->path, content => $_->edi,
                    single_ext => 1
            })
        ) {
            #  This is the successful case!
            $_->remote_file($res);
            $_->status('complete');
            $_->process_time('NOW');

            # For outbound files, sending is the end of processing on
            # the EG side.

            $logger->info("Sent message (id " . $_->id. ") via $log_str");
        } else {
            $logger->error(
                "(S)FTP put to $log_str FAILED: " .
                ($server->error || 'UNKOWNN')
            );
            $error = "put FAILED: " . ($server->error || 'UNKOWNN');
        }

        if ($error) {
            $_->error($error);
            $_->error_time('NOW');
        }

        $logger->info("Calling update_acq_edi_message");
        $e->xact_begin;

        unless ($e->update_acq_edi_message($_)) {
             $logger->error(
                 "EDI send_core update_acq_edi_message failed " .
                 "for message object: " . Dumper($_)
             );

             OpenILS::Application::Acq::EDI::Translator->debug_file(
                 Dumper($_),
                 '/tmp/update_acq_edi_message.FAIL'
             );
             OpenILS::Application::Acq::EDI::Translator->debug_file(
                 Dumper($_->to_bare_hash),
                 '/tmp/update_acq_edi_message.FAIL.to_bare_hash'
             );
        }

        # There's always an update, even if we failed.
        $e->xact_commit;
        __PACKAGE__->record_activity($account, $e);
    }
    return \@messageset;
}

#  attempt_translation does not touch the DB, just the object.  
sub attempt_translation {
    my ($class, $edi_message, $to_edi) = @_;

    my $ret = $to_edi ? translator->json2edi($edi_message->jedi) :
        translator->edi2json($edi_message->edi);

    if (not $ret or (! ref($ret)) or $ret->is_fault) {
        # RPC::XML::fault on failure

        $edi_message->status('trans_error');
        $edi_message->error_time('NOW');
        my $pre = "EDI Translator " .
            ($to_edi ? 'json2edi' : 'edi2json') . " failed";

        my $message = ref($ret) ? 
            ("$pre, Error " . $ret->code . ": " .
                __PACKAGE__->nice_string($ret->string)) :
            ("$pre: " . __PACKAGE__->nice_string($ret)) ;

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

# process_message_buyer() is used in processing both INVOIC
# messages as well as ORDRSP ones.  As such, the $eg_inv parameter is
# optional.
sub process_message_buyer {
    my ($class, $e, $msg_hash, $message,  $log_prefix, $eg_inv) = @_;

    my $vendcode = $msg_hash->{buyer_code};

    # some vendors encode the account number as the SAN.
    # starting with the san value, then the account value, 
    # treat each as a san, then an acct number until the first success
    for my $buyer ( ($msg_hash->{buyer_san}, 
        $msg_hash->{buyer_acct}, $msg_hash->{buyer_ident}) ) {

        next unless $buyer;

        # some vendors encode the SAN as "$SAN $vendcode"
        if (!$vendcode) {
            ($buyer, $vendcode) = $buyer =~ /(\S+)\s*(\S+)?$/;
        }

        my $addr = $e->search_actor_org_address(
            {valid => "t", san => $buyer})->[0];

        if ($addr) {

            $eg_inv->receiver($addr->org_unit) if $eg_inv;

            my $orig_acct = $e->retrieve_acq_edi_account($message->account);

            if (defined($vendcode) and ($orig_acct->vendcode ne $vendcode)) {
                # The vendcode can give us the opportunity to change the
                # acq.edi_account with which our acq.edi_message is associated
                # in case it's wrong.

                my $other_accounts = $e->search_acq_edi_account(
                    {
                        vendcode => $vendcode,
                        host => $orig_acct->host,
                        username => $orig_acct->username,
                        password => $orig_acct->password,
                        in_dir => $orig_acct->in_dir
                    }
                );

                if (@$other_accounts) {
                    # We can update this object because the caller saves
                    # it with cstore later.
                    $message->account($other_accounts->[0]->id);

                    $logger->info(
                        $log_prefix . sprintf(
                            "changing edi_account from %d to %d based on " .
                            "vendcode '%s' (%d match(es))",
                            $orig_acct->id, $message->account, $vendcode,
                            scalar(@$other_accounts)
                        )
                    );

                    # If we've updated the message's account, and if we're
                    # dealing with an invoice, we should update the invoice's
                    # provider and shipper fields. XXX what's the difference
                    # between shipper and provider, really?
                    if ($eg_inv) {
                        $eg_inv->provider(
                            $eg_inv->shipper($other_accounts->[0]->provider)
                        );
                    }
                }
            }

            last;

        } else {

            my $accts = $e->search_acq_edi_account({vendacct => $buyer});

            if (@$accts) {
                if (grep { $_->id == $message->account } @$accts) {
                    $logger->warn(
                        $log_prefix . sprintf(
                            "Not changing edi_account because we found " .
                            "(%d) matching vendacct(s), one of which " .
                            "being on the edi_account we already had",
                            scalar(@$accts)
                        )
                    );
                }

                $logger->info(
                    $log_prefix . sprintf(
                        "changing edi_account from %d to %d based on " .
                        "vendacct '%s' (%d match(es))",
                        $message->account, $accts->[0]->id, $buyer,
                        scalar(@$accts)
                    )
                );

                # Both $message and $eg_inv should be saved later by the caller.
                $message->account($accts->[0]->id);
                if ($eg_inv) {
                    $eg_inv->receiver($accts->[0]->owner);
                    $eg_inv->provider(
                        $eg_inv->shipper($accts->[0]->provider)
                    );
                }

                last;
            }
        }
    }
}

# parts of this process can fail without the entire
# thing failing.  If a catastrophic error occurs,
# it will occur via die.
sub process_parsed_msg {
    my ($class, $account, $incoming, $msg_hash, $seen_container_codes) = @_;

    # INVOIC
    if ($incoming->message_type eq 'INVOIC') {
        return $class->create_acq_invoice_from_edi(
            $msg_hash, $account->provider, $incoming);

    } elsif ($incoming->message_type eq 'DESADV') {
        return $class->create_shipment_notification_from_edi(
            $msg_hash, $account->provider, $incoming, $seen_container_codes);
    }

    # ORDRSP

    #  First do this for the whole message...
    $class->process_message_buyer(
        new_editor, $msg_hash, $incoming, "ORDRSP processing"
    );

    #  ... now do this stuff per-lineitem.
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

            # NOTE: We used to refetch $incoming here, but that discarded
            # changes made by process_message_buyer() above, and is not
            # necessary since our caller just did that before invoking us.

            $incoming->purchase_order($li->purchase_order); 

            # NOTE: $li *just* came from the database, so if this update fails
            # we should actually die() and thereby abort any changes from this
            # entire message, because something weird is happening.
            die(
                "EDI: unable to update edi_message ". $e->die_event->{textcode}
            ) unless $e->update_acq_edi_message($incoming);
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


# Return hash with a key for every kludge that should apply for this
# msg_type (INVOIC,ORDRSP) and this vendor SAN.
sub get_kludges {
    my ($class, $msg_type, $vendor_san) = @_;

    my @kludges;
    while (my ($kludge, $vendors) = each %{$VENDOR_KLUDGE_MAP->{$msg_type}}) {
        push @kludges, $kludge if grep { $_ eq $vendor_san } @$vendors;
    }

    return map { $_ => 1 } @kludges;
}

sub invoice_lineitem_to_invoice_entry {
    my ($li, $quantity, $price) = @_;

    my $eg_inv_entry = Fieldmapper::acq::invoice_entry->new;
    $eg_inv_entry->isnew(1);
    $eg_inv_entry->inv_item_count($quantity);

    # amount staff agree to pay for
    $eg_inv_entry->phys_item_count($quantity);

    # XXX Validate by making sure the LI is on-order and belongs to
    # the right provider and ordering agency and all that.
    $eg_inv_entry->lineitem($li->id);

    # XXX Do we actually need to link to PO directly here?
    $eg_inv_entry->purchase_order($li->purchase_order);

    # This is the total price for all units billed, not per-unit.
    $eg_inv_entry->cost_billed($price);

    # amount staff agree to pay
    $eg_inv_entry->amount_paid($price);

    # The EDIReader class does detect certain per-lineitem
    # taxes, but we'll ignore them for now, as the only sample
    # invoices I've yet seen containing them also had a final
    # cumulative tax at the end.

    return $eg_inv_entry;
}

# Return an arrayref containing acqie objects, an another of unknown lineitem
# references from the electronic invoice.
# @param    $message            An acqedim object
# @param    $invoice_lineitems  An arrayref from part of EDIReader output
# NOTE: This sub can have side-effects on $message.
sub process_invoice_lineitems {
    my ($e, $msg_kludges, $log_prefix, $message, $invoice_lineitems) = @_;

    my (@entries, @unknowns);

    foreach my $lineitem (@$invoice_lineitems) {
        if (!$lineitem->{id}) {
            $logger->warn($log_prefix . "no lineitem ID");
            next;
        }

        my ($quant) = grep {$_->{code} eq '47'} @{$lineitem->{quantities}};
        my $quantity = ($quant) ? $quant->{quantity} : 0;

        if (!$quantity) {
            $logger->warn($log_prefix . "no invoice quantity " .
                "specified for invoice LI $lineitem->{id}");
            next;
        }

        # NOTE: if needed, we also have $lineitem->{net_unit_price}
        # and $lineitem->{gross_unit_price}
        my $price = $lineitem->{amount_billed};

        # XXX Should we set acqie.billed_per_item=t in this case
        # instead? Not sure whether that actually works everywhere
        # it needs to. LFW
        $price *= $quantity if $msg_kludges->{amount_billed_is_per_unit};

        my $li = $e->retrieve_acq_lineitem($lineitem->{id});

        if ($li) {
            # If the top-level PO value is unset, get it from the first LI
            $message->purchase_order($li->purchase_order)
                unless $message->purchase_order;

            push @entries, invoice_lineitem_to_invoice_entry(
                $li, $quantity, $price
            );
        } else {
            push @unknowns, $lineitem->{id};
        }
    }

    return \@entries, \@unknowns;
}

# create_acq_invoice_from_edi() does what it sounds like it does for INVOIC
# messages.  For similar operation on ORDRSP messages, see the guts of
# process_jedi().
# Return boolean success indicator.
sub create_acq_invoice_from_edi {
    my ($class, $msg_data, $provider, $message) = @_;
    # $msg_data is O::U::EDIReader hash
    # $provider is only a pkey
    # $message is Fieldmapper::acq::edi_message

    my $e = new_editor();

    my $log_prefix = "create_acq_invoice_from_edi(..., <acq.edi_message #" .
        $message->id . ">): ";

    my %msg_kludges;
    if ($msg_data->{vendor_san}) {
        %msg_kludges = $class->get_kludges('INVOIC', $msg_data->{vendor_san});
    } else {
        $logger->warn($log_prefix . "no vendor_san field!");
    }

    my $eg_inv = Fieldmapper::acq::invoice->new;
    $eg_inv->isnew(1);

    # Some troubleshooting aids.  Yeah we should have made appropriate links
    # for this in the schema, but this is better than nothing.  Probably
    # *don't* try to i18n this.
    $eg_inv->note("Generated from acq.edi_message #" . $message->id . ".");
    if (%msg_kludges) {
        $eg_inv->note(
            $eg_inv->note .
            " Vendor kludges: " . join(", ", keys(%msg_kludges)) . "."
        );
    }

    $eg_inv->provider($provider);
    $eg_inv->shipper($provider);    # XXX Do we really have a meaningful way to
                                    # distinguish provider and shipper?
    $eg_inv->recv_method("EDI");

    $eg_inv->recv_date(
        $class->edi_date_to_iso($msg_data->{invoice_date}));


    $class->process_message_buyer($e, $msg_data, $message, $log_prefix, $eg_inv);

    if (!$eg_inv->receiver) {
        die($log_prefix .
            sprintf("unable to determine buyer (org unit) in invoice; ".
                "buyer_san=%s; buyer_acct=%s",
                ($msg_data->{buyer_san} || ''), 
                ($msg_data->{buyer_acct} || '')
            )
        );
    }

    $eg_inv->inv_ident($msg_data->{invoice_ident});

    if (!$eg_inv->inv_ident) {
        die($log_prefix . "no invoice ID # in INVOIC message; " . shift);
    }

    $message->purchase_order($msg_data->{purchase_order});

    # Invoice lineitems should generally link to Evergreen lineitems
    # (with acq.invoice_entry rows), except when they don't refer to any
    # Evergreen lineitems by their known number. In that case, they're
    # probably things ordered not through the ILS. We don't have an
    # appropriate table for storing that kind of information right now,
    # so we skip those. No, we don't have enough information to create
    # Evergreen lineitems on the fly and create acqie rows linking to
    # those.
    my ($eg_inv_entries, $unknowns) = process_invoice_lineitems(
        $e, \%msg_kludges, $log_prefix, $message, $msg_data->{lineitems}

    );

    if (@$unknowns) {
        $logger->warn(
            $log_prefix . sprintf(
                "skipped %d unknown lineitem reference(s) from EDI invoice: %s",
                scalar(@$unknowns),
                join("; ", map { "'$_'" } @$unknowns)
            )
        );
    }

    my %charge_type_map = (
        'TX' => ['TAX', 'Tax from electronic invoice'],
        'CA' => ['PRO', 'Cataloging services'], 
        'DL' => ['SHP', 'Delivery'],
        'GST' => ['TAX', 'Goods and services tax']
    ); # XXX i18n, somehow

    my $eg_inv_items = [];

    for my $charge (@{$msg_data->{misc_charges}}, @{$msg_data->{taxes}}) {
        my $eg_inv_item = Fieldmapper::acq::invoice_item->new;
        $eg_inv_item->isnew(1);

        my $amount = $charge->{amount};

        if (!$amount) {
            $logger->warn($log_prefix . "charge with no amount");
            next;
        }

        my $map = $charge_type_map{$charge->{type}};

        if (!$map) {
            $map = ['PRO', 'Misc / unspecified'];
            $eg_inv_item->note($charge->{type});
        }

        $eg_inv_item->inv_item_type($$map[0]);
        $eg_inv_item->title($$map[1]);  # title is user-visible; note isn't.
        $eg_inv_item->cost_billed($amount);
        $eg_inv_item->amount_paid($amount);

        push @$eg_inv_items, $eg_inv_item;
    }

    $logger->info($log_prefix . 
        sprintf("creating invoice with %d entries and %d items.",
            scalar(@$eg_inv_entries), scalar(@$eg_inv_items)));

    $e->xact_begin;

    # save changes to acq.edi_message row
    if (not $e->update_acq_edi_message($message)) {
        die($log_prefix . "couldn't update edi_message " . $message->id);
    }

    my $result = OpenILS::Application::Acq::Invoice::build_invoice_impl(
        $e, $eg_inv, $eg_inv_entries, $eg_inv_items, 0   # don't commit yet
    );

    if ($U->event_code($result)) {
        die($log_prefix. "build_invoice_impl() failed: " . $result->{textcode});
    }

    $e->xact_commit;
    return 1;
}

sub create_shipment_notification_from_edi {
    my ($class, $msg_data, $provider_id, $edi_message, $seen_container_codes) = @_;
    # $msg_data is O::U::EDIReader hash

    $logger->info("ASN: " . Dumper($msg_data));

    my $e = new_editor();

    # Uniqify the container codes
    my %containers = map {$_->{container_code} => 1} @{$msg_data->{lineitems}};

    for my $container_code (keys %containers) {

        next unless $container_code;

        $logger->info("ACQ processing container: $container_code");

        my $eg_asn;
        if ($seen_container_codes->{$container_code}) {
            # Appending to a container we created earlier in this EDI file

            $logger->info("ACQ appending to existing container $container_code");

            # This is coming through as an object?
            $provider_id = $provider_id->id if ref $provider_id;

            $eg_asn = $e->search_acq_shipment_notification({
                container_code => $container_code,
                provider => $provider_id
            })->[0] or return $e->event;

            # The else branch below starts its own transaction so it
            # can create a new shipment_nofication, which we don't need.
            # But we do need a xact to add the entries past the if()
            $e->xact_begin;

        } else {
            # New container code.  Create a new shipment notification
            # and update the edi_message accordingly.
            $logger->info("ACQ creating new shipment noficiation for $container_code");

            $eg_asn = Fieldmapper::acq::shipment_notification->new;
            $eg_asn->isnew(1);

            # Some troubleshooting aids.  Yeah we should have made appropriate links
            # for this in the schema, but this is better than nothing.  Probably
            # *don't* try to i18n this.
            $eg_asn->note("Generated from acq.edi_message #" . $edi_message->id . ".");

            $eg_asn->provider($provider_id);
            $eg_asn->shipper($provider_id);
            $eg_asn->recv_method('EDI');

            $eg_asn->recv_date( # invoice_date is a misnomer; should be message date.
                $class->edi_date_to_iso($msg_data->{invoice_date}));

            $class->process_message_buyer($e, $msg_data, $edi_message, "ASN" , $eg_asn);

            if (!$eg_asn->receiver) {
                die(sprintf(
                    "Unable to determine buyer (org unit) in shipment notification; ".
                    "buyer_san=%s; buyer_acct=%s",
                    ($msg_data->{buyer_san} || ''), 
                    ($msg_data->{buyer_acct} || '')
                ));
            }

            $eg_asn->container_code($container_code);

            die("No container code in DESADV message") unless $eg_asn->container_code;

            $e->xact_begin;

            die "Error updating EDI message: " . $e->die_event
                unless $e->update_acq_edi_message($edi_message);

            die "Error creating shipment notification: " . $e->die_event
                unless $e->create_acq_shipment_notification($eg_asn);

        }

        my $entries = extract_shipment_notification_entries([
            grep {$_->{container_code} eq $container_code} @{$msg_data->{lineitems}}]);

        for my $entry (@$entries) {
            $entry->shipment_notification($eg_asn->id);
            die "Error creating shipment notification entry: " . $e->die_event
                unless $e->create_acq_shipment_notification_entry($entry);
        }

        $e->xact_commit;

        $seen_container_codes->{$container_code} = 1;
    }

    return 1;
}

sub extract_shipment_notification_entries {
    my ($lineitem_hashes) = @_;

    my $e = new_editor();
    my @entries;
    for my $li_hash (@$lineitem_hashes) {

        # A shipment notification may cover multiple PO's. 
        # Each LI will include its own PO ID.
        my $po_id = $li_hash->{purchase_order};

        unless ($po_id) {
            $logger->warn("Skipping ASN lineitem which has no PO ID");
            next;
        }

        my ($quant) = grep {$_->{code} eq '12'} @{$li_hash->{quantities}};
        my $quantity = ($quant) ? $quant->{quantity} : 0;

        # LI identifiers map to order identifiers, not lineitem IDs, 
        # at least not in the data seen so far.
        my $li_id;
        for my $ident_spec (@{$li_hash->{identifiers}}) {

            my $ident = $ident_spec->{value};
            next unless $ident;

            my $li_id_hash = $e->json_query({
                select => {jub => ['id']},
                from => {
                    jub => {
                        acqlia => {
                            filter => {
                                order_ident => 't', 
                                attr_value => $ident
                            }
                        }
                    }
                },
                where => {'+jub' => {purchase_order => $po_id}}
            })->[0];

            if ($li_id_hash) {
                $li_id = $li_id_hash->{id};
                last;
            } else {
                $logger->warn("Cannot find lineitem with order ".
                    "identifier=$ident and purchase_order=$po_id");
            }
        }

        unless ($li_id) {
            $logger->warn("Cannot find lineitem for ASN entry; skippping");
            next;
        }
        
        my $entry = Fieldmapper::acq::shipment_notification_entry->new;

        $entry->lineitem($li_id);
        $entry->item_count($quantity);

        push(@entries, $entry);
    }

    return \@entries;
}

1;

