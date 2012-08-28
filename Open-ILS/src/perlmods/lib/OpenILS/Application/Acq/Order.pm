package OpenILS::Application::Acq::BatchManager;
use OpenILS::Application::Acq::Financials;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use strict; use warnings;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    $self->{args} = {
        lid => 0,
        li => 0,
        vqbr => 0,
        copies => 0,
        bibs => 0,
        progress => 0,
        debits_accrued => 0,
        purchase_order => undef,
        picklist => undef,
        complete => 0,
        indexed => 0,
        queue => undef,
        total => 0
    };
    $self->{cache} = {};
    $self->throttle(4) unless $self->throttle;
    $self->{post_proc_queue} = [];
    $self->{last_respond_progress} = 0;
    return $self;
}

sub conn {
    my($self, $val) = @_;
    $self->{conn} = $val if $val;
    return $self->{conn};
}
sub throttle {
    my($self, $val) = @_;
    $self->{throttle} = $val if $val;
    return $self->{throttle};
}
sub respond {
    my($self, %other_args) = @_;
    if($self->throttle and not %other_args) {
        return unless (
            ($self->{args}->{progress} - $self->{last_respond_progress}) >= $self->throttle
        );
    }
    $self->conn->respond({ %{$self->{args}}, %other_args });
    $self->{last_respond_progress} = $self->{args}->{progress};
    $self->throttle($self->throttle * 2) unless $self->throttle >= 256;
}
sub respond_complete {
    my($self, %other_args) = @_;
    $self->complete;
    $self->conn->respond_complete({ %{$self->{args}}, %other_args });
    $self->run_post_response_hooks;
    return undef;
}

# run the post response hook subs, shifting them off as we go
sub run_post_response_hooks {
    my($self) = @_;
    (shift @{$self->{post_proc_queue}})->() while @{$self->{post_proc_queue}};
}

# any subs passed to this method will be run after the call to respond_complete
sub post_process {
    my($self, $sub) = @_;
    push(@{$self->{post_proc_queue}}, $sub);
}

sub total {
    my($self, $val) = @_;
    $self->{args}->{total} = $val if defined $val;
    $self->{args}->{maximum} = $self->{args}->{total};
    return $self->{args}->{total};
}
sub purchase_order {
    my($self, $val) = @_;
    $self->{args}->{purchase_order} = $val if $val;
    return $self;
}
sub picklist {
    my($self, $val) = @_;
    $self->{args}->{picklist} = $val if $val;
    return $self;
}
sub add_lid {
    my $self = shift;
    $self->{args}->{lid} += 1;
    $self->{args}->{progress} += 1;
    return $self;
}
sub add_li {
    my $self = shift;
    $self->{args}->{li} += 1;
    $self->{args}->{progress} += 1;
    return $self;
}
sub add_vqbr {
    my $self = shift;
    $self->{args}->{vqbr} += 1;
    $self->{args}->{progress} += 1;
    return $self;
}
sub add_copy {
    my $self = shift;
    $self->{args}->{copies} += 1;
    $self->{args}->{progress} += 1;
    return $self;
}
sub add_bib {
    my $self = shift;
    $self->{args}->{bibs} += 1;
    $self->{args}->{progress} += 1;
    return $self;
}
sub add_debit {
    my($self, $amount) = @_;
    $self->{args}->{debits_accrued} += $amount;
    $self->{args}->{progress} += 1;
    return $self;
}
sub editor {
    my($self, $editor) = @_;
    $self->{editor} = $editor if defined $editor;
    return $self->{editor};
}
sub complete {
    my $self = shift;
    $self->{args}->{complete} = 1;
    return $self;
}

sub cache {
    my($self, $org, $key, $val) = @_;
    $self->{cache}->{$org} = {} unless $self->{cache}->{org};
    $self->{cache}->{$org}->{$key} = $val if defined $val;
    return $self->{cache}->{$org}->{$key};
}


package OpenILS::Application::Acq::Order;
use base qw/OpenILS::Application/;
use strict; use warnings;
# ----------------------------------------------------------------------------
# Break up each component of the order process and pieces into managable
# actions that can be shared across different workflows
# ----------------------------------------------------------------------------
use OpenILS::Event;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Normalize qw/clean_marc/;
use OpenILS::Const qw/:const/;
use OpenSRF::EX q/:try/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use Digest::MD5 qw(md5_hex);
use Data::Dumper;
$Data::Dumper::Indent = 0;
my $U = 'OpenILS::Application::AppUtils';


# ----------------------------------------------------------------------------
# Lineitem
# ----------------------------------------------------------------------------
sub create_lineitem {
    my($mgr, %args) = @_;
    my $li = Fieldmapper::acq::lineitem->new;
    $li->creator($mgr->editor->requestor->id);
    $li->selector($li->creator);
    $li->editor($li->creator);
    $li->create_time('now');
    $li->edit_time('now');
    $li->state('new');
    $li->$_($args{$_}) for keys %args;
    $li->clear_id;
    $mgr->add_li;
    $mgr->editor->create_acq_lineitem($li) or return 0;
    
    unless($li->estimated_unit_price) {
        # extract the price from the MARC data
        my $price = get_li_price_from_attr($mgr->editor, $li) or return $li;
        $li->estimated_unit_price($price);
        return update_lineitem($mgr, $li);
    }

    return $li;
}

sub get_li_price_from_attr {
    my($e, $li) = @_;
    my $attrs = $li->attributes || $e->search_acq_lineitem_attr({lineitem => $li->id});

    for my $attr_type (qw/    
            lineitem_local_attr_definition 
            lineitem_prov_attr_definition 
            lineitem_marc_attr_definition/) {

        my ($attr) = grep {
            $_->attr_name eq 'estimated_price' and 
            $_->attr_type eq $attr_type } @$attrs;

        return $attr->attr_value if $attr;
    }

    return undef;
}


sub update_lineitem {
    my($mgr, $li) = @_;
    $li->edit_time('now');
    $li->editor($mgr->editor->requestor->id);
    $mgr->add_li;
    return $mgr->editor->retrieve_acq_lineitem($mgr->editor->data) if
        $mgr->editor->update_acq_lineitem($li);
    return undef;
}


# ----------------------------------------------------------------------------
# Create real holds from patron requests for a given lineitem
# ----------------------------------------------------------------------------
sub promote_lineitem_holds {
    my($mgr, $li) = @_;

    my $requests = $mgr->editor->search_acq_user_request(
        { lineitem => $li->id,
          '-or' =>
            [ { need_before => {'>' => 'now'} },
              { need_before => undef }
            ]
        }
    );

    for my $request ( @$requests ) {

        $request->eg_bib( $li->eg_bib_id );
        $mgr->editor->update_acq_user_request( $request ) or return 0;

        next unless ($U->is_true( $request->hold ));

        my $hold = Fieldmapper::action::hold_request->new;
        $hold->usr( $request->usr );
        $hold->requestor( $request->usr );
        $hold->request_time( $request->request_date );
        $hold->pickup_lib( $request->pickup_lib );
        $hold->request_lib( $request->pickup_lib );
        $hold->selection_ou( $request->pickup_lib );
        $hold->phone_notify( $request->phone_notify );
        $hold->email_notify( $request->email_notify );
        $hold->expire_time( $request->need_before );

        if ($request->holdable_formats) {
            my $mrm = $mgr->editor->search_metabib_metarecord_source_map( { source => $li->eg_bib_id } )->[0];
            if ($mrm) {
                $hold->hold_type( 'M' );
                $hold->holdable_formats( $request->holdable_formats );
                $hold->target( $mrm->metarecord );
            }
        }

        if (!$hold->target) {
            $hold->hold_type( 'T' );
            $hold->target( $li->eg_bib_id );
        }

        $mgr->editor->create_action_hold_request( $hold ) or return 0;
    }

    return $li;
}

sub delete_lineitem {
    my($mgr, $li) = @_;
    $li = $mgr->editor->retrieve_acq_lineitem($li) unless ref $li;

    # delete the attached lineitem_details
    my $lid_ids = $mgr->editor->search_acq_lineitem_detail({lineitem => $li->id}, {idlist=>1});
    for my $lid_id (@$lid_ids) {
        return 0 unless delete_lineitem_detail($mgr, $lid_id);
    }

    $mgr->add_li;
    return $mgr->editor->delete_acq_lineitem($li);
}

# begins and commit transactions as it goes
# bib_only exits before creation of copies and callnumbers
sub create_lineitem_list_assets {
    my($mgr, $li_ids, $vandelay, $bib_only) = @_;

    if (check_import_li_marc_perms($mgr, $li_ids)) { # event on error
        $logger->error("acq-vl: user does not have permission to import acq records");
        return undef;
    }

    my $res = import_li_bibs_via_vandelay($mgr, $li_ids, $vandelay);
    return undef unless $res;
    return $res if $bib_only;

    # create the bibs/volumes/copies for the successfully imported records
    for my $li_id (@{$res->{li_ids}}) {
        $mgr->editor->xact_begin;
        my $data = create_lineitem_assets($mgr, $li_id) or return undef;
        $mgr->editor->xact_commit;
        $mgr->respond;
    }

    return $res;
}

sub test_vandelay_import_args {
    my $vandelay = shift;
    my $q_needed = shift;

    # we need valid args and (sometimes) a queue
    return 0 unless $vandelay and (
        !$q_needed or
        $vandelay->{queue_name} or 
        $vandelay->{existing_queue}
    );

    # match-based merge/overlay import
    return 2 if $vandelay->{merge_profile} and (
        $vandelay->{auto_overlay_exact} or
        $vandelay->{auto_overlay_1match} or
        $vandelay->{auto_overlay_best_match}
    );

    # no-match import
    return 2 if $vandelay->{import_no_match};

    return 1; # queue only
}

sub find_or_create_vandelay_queue {
    my ($e, $vandelay) = @_;

    my $queue;
    if (my $name = $vandelay->{queue_name}) {

        # first, see if a queue w/ this name already exists
        # for this user.  If so, use that instead.

        $queue = $e->search_vandelay_bib_queue(
            {name => $name, owner => $e->requestor->id})->[0];

        if ($queue) {

            $logger->info("acq-vl: using existing queue $name");

        } else {

            $logger->info("acq-vl: creating new vandelay queue $name");

            $queue = new Fieldmapper::vandelay::bib_queue;
            $queue->name($name); 
            $queue->queue_type('acq');
            $queue->owner($e->requestor->id);
            $queue->match_set($vandelay->{match_set} || undef); # avoid ''
            $queue = $e->create_vandelay_bib_queue($queue) or return undef;
        }

    } else {
        $queue = $e->retrieve_vandelay_bib_queue($vandelay->{existing_queue})
            or return undef;
    }
    
    return $queue;
}


sub import_li_bibs_via_vandelay {
    my ($mgr, $li_ids, $vandelay) = @_;
    my $res = {li_ids => []};
    my $e = $mgr->editor;
    $e->xact_begin;

    my $needs_importing = $e->search_acq_lineitem(
        {id => $li_ids, eg_bib_id => undef}, 
        {idlist => 1}
    );

    if (!@$needs_importing) {
        $logger->info("acq-vl: all records already imported.  no Vandelay work to do");
        return {li_ids => $li_ids};
    }

    # see if we have any records that are not yet linked to VL records (i.e. 
    # not in a queue).  This will tell us if lack of a queue name is an error.
    my $non_queued = $e->search_acq_lineitem(
        {id => $needs_importing, queued_record => undef},
        {idlist => 1}
    );

    # add the already-imported records to the response list
    push(@{$res->{li_ids}}, grep { $_ != @$needs_importing } @$li_ids);

    $logger->info("acq-vl: processing recs via Vandelay with args: ".Dumper($vandelay));

    my $vl_stat = test_vandelay_import_args($vandelay, scalar(@$non_queued));
    if ($vl_stat == 0) {
        $logger->error("acq-vl: invalid vandelay arguments for acq import (queue needed)");
        return $res;
    }

    my $queue;
    if (@$non_queued) {
        # when any non-queued lineitems exist, their vandelay counterparts 
        # require a place to live.
        $queue = find_or_create_vandelay_queue($e, $vandelay) or return $res;

    } else {
        # if all lineitems are already queued, the queue reported to the user
        # is purely for information / convenience.  pick a random queue.
        $queue = $e->retrieve_acq_lineitem([
            $needs_importing->[0], {   
                flesh => 2, 
                flesh_fields => {
                    jub => ['queued_record'], 
                    vqbr => ['queue']
                }
            }
        ])->queued_record->queue;
    }

    $mgr->{args}->{queue} = $queue;

    # load the lineitems into the queue for merge processing
    my @vqbr_ids;
    my @lis;
    for my $li_id (@$needs_importing) {

        my $li = $e->retrieve_acq_lineitem($li_id) or return $res;

        if ($li->queued_record) {
            $logger->info("acq-vl: $li_id already linked to a vandelay record");
            push(@vqbr_ids, $li->queued_record);

        } else {
            $logger->info("acq-vl: creating new vandelay record for lineitem $li_id");

            # create a new VL queued record and link it up
            my $vqbr = Fieldmapper::vandelay::queued_bib_record->new;
            $vqbr->marc($li->marc);
            $vqbr->queue($queue->id);
            $vqbr->bib_source($vandelay->{bib_source} || undef); # avoid ''
            $vqbr = $e->create_vandelay_queued_bib_record($vqbr) or return $res;
            push(@vqbr_ids, $vqbr->id);

            # tell the acq record which vandelay record it's linked to
            $li->queued_record($vqbr->id);
            $e->update_acq_lineitem($li) or return $res;
        }

        $mgr->add_vqbr;
        $mgr->respond;
        push(@lis, $li);
    }

    $logger->info("acq-vl: created vandelay records [@vqbr_ids]");

    # we have to commit the transaction now since 
    # vandelay uses its own transactions.
    $e->commit;

    return $res if $vl_stat == 1; # queue only

    # Import the bibs via vandelay.  Note: Vandely will 
    # update acq.lineitem.eg_bib_id on successful import.

    $vandelay->{report_all} = 1;
    my $ses = OpenSRF::AppSession->create('open-ils.vandelay');
    my $req = $ses->request(
        'open-ils.vandelay.bib_record.list.import',
        $e->authtoken, \@vqbr_ids, $vandelay);

    # pull the responses, noting all that were successfully imported
    my @success_lis;
    while (my $resp = $req->recv(timeout => 600)) {
        my $stat = $resp->content;

        if(!$stat or $U->event_code($stat)) { # import failure
            $logger->error("acq-vl: error importing vandelay record " . Dumper($stat));
            next;
        }

        # "imported" refers to the vqbr id, not the 
        # success/failure of the vqbr merge attempt
        next unless $stat->{imported};

        my ($imported) = grep {$_->queued_record eq $stat->{imported}} @lis;
        my $li_id = $imported->id;

        if ($stat->{no_import}) {
            $logger->info("acq-vl: acq lineitem $li_id did not import"); 

        } else { # successful import

            push(@success_lis, $li_id);
            $mgr->add_bib;
            $mgr->respond;
            $logger->info("acq-vl: acq lineitem $li_id successfully merged/imported");
        } 
    }

    $ses->kill_me;
    $logger->info("acq-vl: successfully imported lineitems [@success_lis]");

    # add the successfully imported lineitems to the already-imported lineitems
    push (@{$res->{li_ids}}, @success_lis);

    return $res;
}

# returns event on error, undef on success
sub check_import_li_marc_perms {
    my($mgr, $li_ids) = @_;

    # if there are any order records that are not linked to 
    # in-db bib records, verify staff has perms to import order records
    my $order_li = $mgr->editor->search_acq_lineitem(
        [{id => $li_ids, eg_bib_id => undef}, {limit => 1}], {idlist => 1})->[0];

    if($order_li) {
        return $mgr->editor->die_event unless 
            $mgr->editor->allowed('IMPORT_ACQ_LINEITEM_BIB_RECORD');
    }

    return undef;
}


# ----------------------------------------------------------------------------
# if all of the lineitem details for this lineitem have 
# been received, mark the lineitem as received
# returns 1 on non-received, li on received, 0 on error
# ----------------------------------------------------------------------------

sub describe_affected_po {
    my ($e, $po) = @_;

    my ($enc, $spent) =
        OpenILS::Application::Acq::Financials::build_price_summary(
            $e, $po->id
        );

    +{$po->id => {
            "state" => $po->state,
            "amount_encumbered" => $enc,
            "amount_spent" => $spent
        }
    };
}

sub check_lineitem_received {
    my($mgr, $li_id) = @_;

    my $non_recv = $mgr->editor->search_acq_lineitem_detail(
        {recv_time => undef, lineitem => $li_id}, {idlist=>1});

    return 1 if @$non_recv;

    my $li = $mgr->editor->retrieve_acq_lineitem($li_id);
    $li->state('received');
    return update_lineitem($mgr, $li);
}

sub receive_lineitem {
    my($mgr, $li_id, $skip_complete_check) = @_;
    my $li = $mgr->editor->retrieve_acq_lineitem($li_id) or return 0;

    my $lid_ids = $mgr->editor->search_acq_lineitem_detail(
        {lineitem => $li_id, recv_time => undef}, {idlist => 1});

    for my $lid_id (@$lid_ids) {
       receive_lineitem_detail($mgr, $lid_id, 1) or return 0; 
    }

    $mgr->add_li;
    $li->state('received');

    $li = update_lineitem($mgr, $li) or return 0;
    $mgr->post_process( sub { create_lineitem_status_events($mgr, $li_id, 'aur.received'); });

    my $po;
    return 0 unless
        $skip_complete_check or (
            $po = check_purchase_order_received($mgr, $li->purchase_order)
        );

    my $result = {"li" => {$li->id => {"state" => $li->state}}};
    $result->{"po"} = describe_affected_po($mgr->editor, $po) if ref $po;
    return $result;
}

sub rollback_receive_lineitem {
    my($mgr, $li_id) = @_;
    my $li = $mgr->editor->retrieve_acq_lineitem($li_id) or return 0;

    my $lid_ids = $mgr->editor->search_acq_lineitem_detail(
        {lineitem => $li_id, recv_time => {'!=' => undef}}, {idlist => 1});

    for my $lid_id (@$lid_ids) {
       rollback_receive_lineitem_detail($mgr, $lid_id, 1) or return 0; 
    }

    $mgr->add_li;
    $li->state('on-order');
    return update_lineitem($mgr, $li);
}


sub create_lineitem_status_events {
    my($mgr, $li_id, $hook) = @_;

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->connect;
    my $user_reqs = $mgr->editor->search_acq_user_request([
        {lineitem => $li_id}, 
        {flesh => 1, flesh_fields => {aur => ['usr']}}
    ]);

    for my $user_req (@$user_reqs) {
        my $req = $ses->request('open-ils.trigger.event.autocreate', $hook, $user_req, $user_req->usr->home_ou);
        $req->recv; 
    }

    $ses->disconnect;
    return undef;
}

# ----------------------------------------------------------------------------
# Lineitem Detail
# ----------------------------------------------------------------------------
sub create_lineitem_detail {
    my($mgr, %args) = @_;
    my $lid = Fieldmapper::acq::lineitem_detail->new;
    $lid->$_($args{$_}) for keys %args;
    $lid->clear_id;
    $mgr->add_lid;
    return $mgr->editor->create_acq_lineitem_detail($lid);
}


# flesh out any required data with default values where appropriate
sub complete_lineitem_detail {
    my($mgr, $lid) = @_;
    unless($lid->barcode) {
        my $pfx = $U->ou_ancestor_setting_value($lid->owning_lib, 'acq.tmp_barcode_prefix') || 'ACQ';
        $lid->barcode($pfx.$lid->id);
    }

    unless($lid->cn_label) {
        my $pfx = $U->ou_ancestor_setting_value($lid->owning_lib, 'acq.tmp_callnumber_prefix') || 'ACQ';
        $lid->cn_label($pfx.$lid->id);
    }

    if(!$lid->location and my $loc = $U->ou_ancestor_setting_value($lid->owning_lib, 'acq.default_copy_location')) {
        $lid->location($loc);
    }

    $lid->circ_modifier(get_default_circ_modifier($mgr, $lid->owning_lib))
        unless defined $lid->circ_modifier;

    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;
    return $lid;
}

sub get_default_circ_modifier {
    my($mgr, $org) = @_;
    my $code = $mgr->cache($org, 'def_circ_mod');
    $code = $U->ou_ancestor_setting_value($org, 'acq.default_circ_modifier') unless defined $code;
    return $mgr->cache($org, 'def_circ_mod', $code) if defined $code;
    return undef;
}

sub delete_lineitem_detail {
    my($mgr, $lid) = @_;
    $lid = $mgr->editor->retrieve_acq_lineitem_detail($lid) unless ref $lid;
    return $mgr->editor->delete_acq_lineitem_detail($lid);
}


sub receive_lineitem_detail {
    my($mgr, $lid_id, $skip_complete_check) = @_;
    my $e = $mgr->editor;

    my $lid = $e->retrieve_acq_lineitem_detail([
        $lid_id,
        {   flesh => 1,
            flesh_fields => {
                acqlid => ['fund_debit']
            }
        }
    ]) or return 0;

    return 1 if $lid->recv_time;

    $lid->receiver($e->requestor->id);
    $lid->recv_time('now');
    $e->update_acq_lineitem_detail($lid) or return 0;

    if ($lid->eg_copy_id) {
        my $copy = $e->retrieve_asset_copy($lid->eg_copy_id) or return 0;
        $copy->status(OILS_COPY_STATUS_IN_PROCESS);
        $copy->edit_date('now');
        $copy->editor($e->requestor->id);
        $copy->creator($e->requestor->id) if $U->ou_ancestor_setting_value(
            $e->requestor->ws_ou, 'acq.copy_creator_uses_receiver', $e);
        $e->update_asset_copy($copy) or return 0;
    }

    $mgr->add_lid;

    return 1 if $skip_complete_check;

    my $li = check_lineitem_received($mgr, $lid->lineitem) or return 0;
    return 1 if $li == 1; # li not received

    return check_purchase_order_received($mgr, $li->purchase_order) or return 0;
}


sub rollback_receive_lineitem_detail {
    my($mgr, $lid_id) = @_;
    my $e = $mgr->editor;

    my $lid = $e->retrieve_acq_lineitem_detail([
        $lid_id,
        {   flesh => 1,
            flesh_fields => {
                acqlid => ['fund_debit']
            }
        }
    ]) or return 0;

    return 1 unless $lid->recv_time;

    $lid->clear_receiver;
    $lid->clear_recv_time;
    $e->update_acq_lineitem_detail($lid) or return 0;

    if ($lid->eg_copy_id) {
        my $copy = $e->retrieve_asset_copy($lid->eg_copy_id) or return 0;
        $copy->status(OILS_COPY_STATUS_ON_ORDER);
        $copy->edit_date('now');
        $copy->editor($e->requestor->id);
        $e->update_asset_copy($copy) or return 0;
    }

    $mgr->add_lid;
    return $lid;
}

# ----------------------------------------------------------------------------
# Lineitem Attr
# ----------------------------------------------------------------------------
sub set_lineitem_attr {
    my($mgr, %args) = @_;
    my $attr_type = $args{attr_type};

    # first, see if it's already set.  May just need to overwrite it
    my $attr = $mgr->editor->search_acq_lineitem_attr({
        lineitem => $args{lineitem},
        attr_type => $args{attr_type},
        attr_name => $args{attr_name}
    })->[0];

    if($attr) {
        $attr->attr_value($args{attr_value});
        return $attr if $mgr->editor->update_acq_lineitem_attr($attr);
        return undef;

    } else {

        $attr = Fieldmapper::acq::lineitem_attr->new;
        $attr->$_($args{$_}) for keys %args;
        
        unless($attr->definition) {
            my $find = "search_acq_$attr_type";
            my $attr_def_id = $mgr->editor->$find({code => $attr->attr_name}, {idlist=>1})->[0] or return 0;
            $attr->definition($attr_def_id);
        }
        return $mgr->editor->create_acq_lineitem_attr($attr);
    }
}

# ----------------------------------------------------------------------------
# Lineitem Debits
# ----------------------------------------------------------------------------
sub create_lineitem_debits {
    my ($mgr, $li, $dry_run) = @_; 

    unless($li->estimated_unit_price) {
        $mgr->editor->event(OpenILS::Event->new('ACQ_LINEITEM_NO_PRICE', payload => $li->id));
        $mgr->editor->rollback;
        return 0;
    }

    unless($li->provider) {
        $mgr->editor->event(OpenILS::Event->new('ACQ_LINEITEM_NO_PROVIDER', payload => $li->id));
        $mgr->editor->rollback;
        return 0;
    }

    my $lid_ids = $mgr->editor->search_acq_lineitem_detail(
        {lineitem => $li->id}, 
        {idlist=>1}
    );

    for my $lid_id (@$lid_ids) {

        my $lid = $mgr->editor->retrieve_acq_lineitem_detail([
            $lid_id,
            {   flesh => 1, 
                flesh_fields => {acqlid => ['fund']}
            }
        ]);

        create_lineitem_detail_debit($mgr, $li, $lid, $dry_run) or return 0;
    }

    return 1;
}


# flesh li->provider
# flesh lid->fund
sub create_lineitem_detail_debit {
    my ($mgr, $li, $lid, $dry_run, $no_translate) = @_;

    # don't create the debit if one already exists
    return $mgr->editor->retrieve_acq_fund_debit($lid->fund_debit) if $lid->fund_debit;

    my $li_id = ref($li) ? $li->id : $li;

    unless(ref $li and ref $li->provider) {
       $li = $mgr->editor->retrieve_acq_lineitem([
            $li_id,
            {   flesh => 1,
                flesh_fields => {jub => ['provider']},
            }
        ]);
    }

    if(ref $lid) {
        $lid->fund($mgr->editor->retrieve_acq_fund($lid->fund)) unless(ref $lid->fund);
    } else {
        $lid = $mgr->editor->retrieve_acq_lineitem_detail([
            $lid,
            {   flesh => 1, 
                flesh_fields => {acqlid => ['fund']}
            }
        ]);
    }

    unless ($lid->fund) {
        $mgr->editor->event(
            new OpenILS::Event("ACQ_FUND_NOT_FOUND") # close enough
        );
        return 0;
    }

    my $amount = $li->estimated_unit_price;
    if($li->provider->currency_type ne $lid->fund->currency_type and !$no_translate) {

        # At Fund debit creation time, translate into the currency of the fund
        # TODO: org setting to disable automatic currency conversion at debit create time?

        $amount = $mgr->editor->json_query({
            from => [
                'acq.exchange_ratio', 
                $li->provider->currency_type, # source currency
                $lid->fund->currency_type, # destination currency
                $li->estimated_unit_price # source amount
            ]
        })->[0]->{'acq.exchange_ratio'};
    }

    my $debit = create_fund_debit(
        $mgr, 
        $dry_run,
        fund => $lid->fund->id,
        origin_amount => $li->estimated_unit_price,
        origin_currency_type => $li->provider->currency_type,
        amount => $amount
    ) or return 0;

    $lid->fund_debit($debit->id);
    $lid->fund($lid->fund->id);
    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;
    return $debit;
}


__PACKAGE__->register_method(
	"method" => "fund_exceeds_balance_percent_api",
	"api_name" => "open-ils.acq.fund.check_balance_percentages",
	"signature" => {
        "desc" => q/Determine whether a given fund exceeds its defined
            "balance stop and warning percentages"/,
        "params" => [
            {"desc" => "Authentication token", "type" => "string"},
            {"desc" => "Fund ID", "type" => "number"},
            {"desc" => "Theoretical debit amount (optional)",
                "type" => "number"}
        ],
        "return" => {"desc" => q/An array of two values, for stop and warning,
            in that order: 1 if fund exceeds that balance percentage, else 0/}
    }
);

sub fund_exceeds_balance_percent_api {
    my ($self, $conn, $auth, $fund_id, $debit_amount) = @_;

    $debit_amount ||= 0;

    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $fund = $e->retrieve_acq_fund($fund_id) or return $e->die_event;
    return $e->die_event unless $e->allowed("VIEW_FUND", $fund->org);

    my $result = [
        fund_exceeds_balance_percent($fund, $debit_amount, $e, "stop"),
        fund_exceeds_balance_percent($fund, $debit_amount, $e, "warning")
    ];

    $e->disconnect;
    return $result;
}

sub fund_exceeds_balance_percent {
    my ($fund, $debit_amount, $e, $which) = @_;

    my ($method_name, $event_name) = @{{
        "warning" => [
            "balance_warning_percent", "ACQ_FUND_EXCEEDS_WARN_PERCENT"
        ],
        "stop" => [
            "balance_stop_percent", "ACQ_FUND_EXCEEDS_STOP_PERCENT"
        ]
    }->{$which}};

    if ($fund->$method_name) {
        my $balance =
            $e->search_acq_fund_combined_balance({"fund" => $fund->id})->[0];
        my $allocations =
            $e->search_acq_fund_allocation_total({"fund" => $fund->id})->[0];

        $balance = ($balance) ? $balance->amount : 0;
        $allocations = ($allocations) ? $allocations->amount : 0;

        if ( 
            $allocations == 0 || # if no allocations were ever made, assume we have hit the stop percent
            ((($allocations - $balance + $debit_amount) / $allocations) * 100) > $fund->$method_name
        ) {
            $logger->info("fund would hit a limit: " . $fund->id . ", $balance, $debit_amount, $allocations, $method_name");
            $e->event(
                new OpenILS::Event(
                    $event_name,
                    "payload" => {
                        "fund" => $fund, "debit_amount" => $debit_amount
                    }
                )
            );
            return 1;
        }
    }
    return 0;
}

# ----------------------------------------------------------------------------
# Fund Debit
# ----------------------------------------------------------------------------
sub create_fund_debit {
    my($mgr, $dry_run, %args) = @_;

    # Verify the fund is not being spent beyond the hard stop amount
    my $fund = $mgr->editor->retrieve_acq_fund($args{fund}) or return 0;

    return 0 if
        fund_exceeds_balance_percent(
            $fund, $args{"amount"}, $mgr->editor, "stop"
        );
    return 0 if
        $dry_run and fund_exceeds_balance_percent(
            $fund, $args{"amount"}, $mgr->editor, "warning"
        );

    my $debit = Fieldmapper::acq::fund_debit->new;
    $debit->debit_type('purchase');
    $debit->encumbrance('t');
    $debit->$_($args{$_}) for keys %args;
    $debit->clear_id;
    $mgr->add_debit($debit->amount);
    return $mgr->editor->create_acq_fund_debit($debit);
}


# ----------------------------------------------------------------------------
# Picklist
# ----------------------------------------------------------------------------
sub create_picklist {
    my($mgr, %args) = @_;
    my $picklist = Fieldmapper::acq::picklist->new;
    $picklist->creator($mgr->editor->requestor->id);
    $picklist->owner($picklist->creator);
    $picklist->editor($picklist->creator);
    $picklist->create_time('now');
    $picklist->edit_time('now');
    $picklist->org_unit($mgr->editor->requestor->ws_ou);
    $picklist->owner($mgr->editor->requestor->id);
    $picklist->$_($args{$_}) for keys %args;
    $picklist->clear_id;
    $mgr->picklist($picklist);
    return $mgr->editor->create_acq_picklist($picklist);
}

sub update_picklist {
    my($mgr, $picklist) = @_;
    $picklist = $mgr->editor->retrieve_acq_picklist($picklist) unless ref $picklist;
    $picklist->edit_time('now');
    $picklist->editor($mgr->editor->requestor->id);
    if ($mgr->editor->update_acq_picklist($picklist)) {
        $picklist = $mgr->editor->retrieve_acq_picklist($mgr->editor->data);
        $mgr->picklist($picklist);
        return $picklist;
    } else {
        return undef;
    }
}

sub delete_picklist {
    my($mgr, $picklist) = @_;
    $picklist = $mgr->editor->retrieve_acq_picklist($picklist) unless ref $picklist;

    # delete all 'new' lineitems
    my $li_ids = $mgr->editor->search_acq_lineitem(
        {
            picklist => $picklist->id,
            "-or" => {state => "new", purchase_order => undef}
        },
        {idlist => 1}
    );
    for my $li_id (@$li_ids) {
        my $li = $mgr->editor->retrieve_acq_lineitem($li_id);
        return 0 unless delete_lineitem($mgr, $li);
        $mgr->respond;
    }

    # detach all non-'new' lineitems
    $li_ids = $mgr->editor->search_acq_lineitem({picklist => $picklist->id, state => {'!=' => 'new'}}, {idlist => 1});
    for my $li_id (@$li_ids) {
        my $li = $mgr->editor->retrieve_acq_lineitem($li_id);
        $li->clear_picklist;
        return 0 unless update_lineitem($mgr, $li);
        $mgr->respond;
    }

    # remove any picklist-specific object perms
    my $ops = $mgr->editor->search_permission_usr_object_perm_map({object_type => 'acqpl', object_id => ''.$picklist->id});
    for my $op (@$ops) {
        return 0 unless $mgr->editor->delete_usr_object_perm_map($op);
    }

    return $mgr->editor->delete_acq_picklist($picklist);
}

# ----------------------------------------------------------------------------
# Purchase Order
# ----------------------------------------------------------------------------
sub update_purchase_order {
    my($mgr, $po) = @_;
    $po = $mgr->editor->retrieve_acq_purchase_order($po) unless ref $po;
    $po->editor($mgr->editor->requestor->id);
    $po->edit_time('now');
    $mgr->purchase_order($po);
    return $mgr->editor->retrieve_acq_purchase_order($mgr->editor->data)
        if $mgr->editor->update_acq_purchase_order($po);
    return undef;
}

sub create_purchase_order {
    my($mgr, %args) = @_;

    # verify the chosen provider is still active
    my $provider = $mgr->editor->retrieve_acq_provider($args{provider}) or return 0;
    unless($U->is_true($provider->active)) {
        $logger->error("provider is not active.  cannot create PO");
        $mgr->editor->event(OpenILS::Event->new('ACQ_PROVIDER_INACTIVE'));
        return 0;
    }

    my $po = Fieldmapper::acq::purchase_order->new;
    $po->creator($mgr->editor->requestor->id);
    $po->editor($mgr->editor->requestor->id);
    $po->owner($mgr->editor->requestor->id);
    $po->edit_time('now');
    $po->create_time('now');
    $po->state('pending');
    $po->ordering_agency($mgr->editor->requestor->ws_ou);
    $po->$_($args{$_}) for keys %args;
    $po->clear_id;
    $mgr->purchase_order($po);
    return $mgr->editor->create_acq_purchase_order($po);
}

# ----------------------------------------------------------------------------
# if all of the lineitems for this PO are received,
# mark the PO as received
# ----------------------------------------------------------------------------
sub check_purchase_order_received {
    my($mgr, $po_id) = @_;

    my $non_recv_li = $mgr->editor->search_acq_lineitem(
        {   purchase_order => $po_id,
            state => {'!=' => 'received'}
        }, {idlist=>1});

    my $po = $mgr->editor->retrieve_acq_purchase_order($po_id);
    return $po if @$non_recv_li;

    $po->state('received');
    return update_purchase_order($mgr, $po);
}


# ----------------------------------------------------------------------------
# Bib, Callnumber, and Copy data
# ----------------------------------------------------------------------------

sub create_lineitem_assets {
    my($mgr, $li_id) = @_;
    my $evt;

    my $li = $mgr->editor->retrieve_acq_lineitem([
        $li_id,
        {   flesh => 1,
            flesh_fields => {jub => ['purchase_order', 'attributes']}
        }
    ]) or return 0;

    # note: at this point, the bib record this LI links to should already be created

    # -----------------------------------------------------------------
    # The lineitem is going live, promote user request holds to real holds
    # -----------------------------------------------------------------
    promote_lineitem_holds($mgr, $li) or return 0;

    my $li_details = $mgr->editor->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});

    # -----------------------------------------------------------------
    # for each lineitem_detail, create the volume if necessary, create 
    # a copy, and link them all together.
    # -----------------------------------------------------------------
    my $first_cn;
    for my $lid_id (@{$li_details}) {

        my $lid = $mgr->editor->retrieve_acq_lineitem_detail($lid_id) or return 0;
        next if $lid->eg_copy_id;

        # use the same callnumber label for all items within this lineitem
        $lid->cn_label($first_cn) if $first_cn and not $lid->cn_label;

        # apply defaults if necessary
        return 0 unless complete_lineitem_detail($mgr, $lid);

        $first_cn = $lid->cn_label unless $first_cn;

        my $org = $lid->owning_lib;
        my $label = $lid->cn_label;
        my $bibid = $li->eg_bib_id;

        my $volume = $mgr->cache($org, "cn.$bibid.$label");
        unless($volume) {
            $volume = create_volume($mgr, $li, $lid) or return 0;
            $mgr->cache($org, "cn.$bibid.$label", $volume);
        }
        create_copy($mgr, $volume, $lid, $li) or return 0;
    }

    return { li => $li };
}

sub create_volume {
    my($mgr, $li, $lid) = @_;

    my ($volume, $evt) = 
        OpenILS::Application::Cat::AssetCommon->find_or_create_volume(
            $mgr->editor, 
            $lid->cn_label, 
            $li->eg_bib_id, 
            $lid->owning_lib
        );

    if($evt) {
        $mgr->editor->event($evt);
        return 0;
    }

    return $volume;
}

sub create_copy {
    my($mgr, $volume, $lid, $li) = @_;
    my $copy = Fieldmapper::asset::copy->new;
    $copy->isnew(1);
    $copy->loan_duration(2);
    $copy->fine_level(2);
    $copy->status(($lid->recv_time) ? OILS_COPY_STATUS_IN_PROCESS : OILS_COPY_STATUS_ON_ORDER);
    $copy->barcode($lid->barcode);
    $copy->location($lid->location);
    $copy->call_number($volume->id);
    $copy->circ_lib($volume->owning_lib);
    $copy->circ_modifier($lid->circ_modifier);

    # AKA list price.  We might need a $li->list_price field since 
    # estimated price is not necessarily the same as list price
    $copy->price($li->estimated_unit_price); 

    my $evt = OpenILS::Application::Cat::AssetCommon->create_copy($mgr->editor, $volume, $copy);
    if($evt) {
        $mgr->editor->event($evt);
        return 0;
    }

    $mgr->add_copy;
    $lid->eg_copy_id($copy->id);
    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;
}






# ----------------------------------------------------------------------------
# Workflow: Build a selection list from a Z39.50 search
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'zsearch',
	api_name => 'open-ils.acq.picklist.search.z3950',
    stream => 1,
	signature => {
        desc => 'Performs a z3950 federated search and creates a picklist and associated lineitems',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Search definition', type => 'object'},
            {desc => 'Picklist name, optional', type => 'string'},
        ]
    }
);

sub zsearch {
    my($self, $conn, $auth, $search, $name, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('CREATE_PICKLIST');

    $search->{limit} ||= 10;
    $options ||= {};

    my $ses = OpenSRF::AppSession->create('open-ils.search');
    my $req = $ses->request('open-ils.search.z3950.search_class', $auth, $search);

    my $first = 1;
    my $picklist;
    my $mgr;
    while(my $resp = $req->recv(timeout=>60)) {

        if($first) {
            my $e = new_editor(requestor=>$e->requestor, xact=>1);
            $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
            $picklist = zsearch_build_pl($mgr, $name);
            $first = 0;
        }

        my $result = $resp->content;
        my $count = $result->{count} || 0;
        $mgr->total( (($count < $search->{limit}) ? $count : $search->{limit})+1 );

        for my $rec (@{$result->{records}}) {

            my $li = create_lineitem($mgr, 
                picklist => $picklist->id,
                source_label => $result->{service},
                marc => $rec->{marcxml},
                eg_bib_id => $rec->{bibid}
            );

            if($$options{respond_li}) {
                $li->attributes($mgr->editor->search_acq_lineitem_attr({lineitem => $li->id}))
                    if $$options{flesh_attrs};
                $li->clear_marc if $$options{clear_marc};
                $mgr->respond(lineitem => $li);
            } else {
                $mgr->respond;
            }
        }
    }

    $mgr->editor->commit;
    return $mgr->respond_complete;
}

sub zsearch_build_pl {
    my($mgr, $name) = @_;
    $name ||= '';

    my $picklist = $mgr->editor->search_acq_picklist({
        owner => $mgr->editor->requestor->id, 
        name => $name
    })->[0];

    if($name eq '' and $picklist) {
        return 0 unless delete_picklist($mgr, $picklist);
        $picklist = undef;
    }

    return update_picklist($mgr, $picklist) if $picklist;
    return create_picklist($mgr, name => $name);
}


# ----------------------------------------------------------------------------
# Workflow: Build a selection list / PO by importing a batch of MARC records
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
    method   => 'upload_records',
    api_name => 'open-ils.acq.process_upload_records',
    stream   => 1,
    max_chunk_count => 1
);

sub upload_records {
    my($self, $conn, $auth, $key, $args) = @_;
    $args ||= {};

	my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $cache = OpenSRF::Utils::Cache->new;

    my $data = $cache->get_cache("vandelay_import_spool_$key");
    my $filename        = $data->{path};
    my $provider        = $args->{provider};
    my $picklist        = $args->{picklist};
    my $create_po       = $args->{create_po};
    my $activate_po     = $args->{activate_po};
    my $vandelay        = $args->{vandelay};
    my $ordering_agency = $args->{ordering_agency} || $e->requestor->ws_ou;
    my $fiscal_year     = $args->{fiscal_year} || DateTime->now->year;
    my $po;
    my $evt;

    unless(-r $filename) {
        $logger->error("unable to read MARC file $filename");
        $e->rollback;
        return OpenILS::Event->new('FILE_UPLOAD_ERROR', payload => {filename => $filename});
    }

    $provider = $e->retrieve_acq_provider($provider) or return $e->die_event;

    if($picklist) {
        $picklist = $e->retrieve_acq_picklist($picklist) or return $e->die_event;
        if($picklist->owner != $e->requestor->id) {
            return $e->die_event unless 
                $e->allowed('CREATE_PICKLIST', $picklist->org_unit, $picklist);
        }
        $mgr->picklist($picklist);
    }

    if($create_po) {
        return $e->die_event unless 
            $e->allowed('CREATE_PURCHASE_ORDER', $ordering_agency);

        $po = create_purchase_order($mgr, 
            ordering_agency => $ordering_agency,
            provider => $provider->id,
            state => 'pending' # will be updated later if activated
        ) or return $mgr->editor->die_event;
    }

    $logger->info("acq processing MARC file=$filename");

	my $batch = new MARC::Batch ('USMARC', $filename);
	$batch->strict_off;

	my $count = 0;
    my @li_list;

	while(1) {

	    my ($err, $xml, $r);
		$count++;

		try {
            $r = $batch->next;
        } catch Error with {
            $err = shift;
			$logger->warn("Proccessing of record $count in set $key failed with error $err.  Skipping this record");
        };

        next if $err;
        last unless $r;

		try {
            $xml = clean_marc($r);
		} catch Error with {
			$err = shift;
			$logger->warn("Proccessing XML of record $count in set $key failed with error $err.  Skipping this record");
		};

        next if $err or not $xml;

        my %args = (
            source_label => $provider->code,
            provider => $provider->id,
            marc => $xml,
        );

        $args{picklist} = $picklist->id if $picklist;
        if($po) {
            $args{purchase_order} = $po->id;
            $args{state} = 'pending-order';
        }

        my $li = create_lineitem($mgr, %args) or return $mgr->editor->die_event;
        $mgr->respond;
        $li->provider($provider); # flesh it, we'll need it later

        import_lineitem_details($mgr, $ordering_agency, $li, $fiscal_year) 
            or return $mgr->editor->die_event;
        $mgr->respond;

        push(@li_list, $li->id);
        $mgr->respond;
	}

	$e->commit;
    unlink($filename);
    $cache->delete_cache('vandelay_import_spool_' . $key);

    if ($po and $activate_po) {
        my $die_event = activate_purchase_order_impl($mgr, $po->id, $vandelay);
        return $die_event if $die_event;

    } elsif ($vandelay) {
        $vandelay->{new_rec_perm} = 'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD';
        create_lineitem_list_assets($mgr, \@li_list, $vandelay, 
            !$vandelay->{create_assets}) or return $e->die_event;
    }

    return $mgr->respond_complete;
}

sub import_lineitem_details {
    my($mgr, $ordering_agency, $li, $fiscal_year) = @_;

    my $holdings = $mgr->editor->json_query({from => ['acq.extract_provider_holding_data', $li->id]});
    return 1 unless @$holdings;
    my $org_path = $U->get_org_ancestors($ordering_agency);
    $org_path = [ reverse (@$org_path) ];
    my $price;


    my $idx = 1;
    while(1) {
        # create a lineitem detail for each copy in the data

        my $compiled = extract_lineitem_detail_data($mgr, $org_path, $holdings, $idx, $fiscal_year);
        last unless defined $compiled;
        return 0 unless $compiled;

        # this takes the price of the last copy and uses it as the lineitem price
        # need to determine if a given record would include different prices for the same item
        $price = $$compiled{estimated_price};

        last unless $$compiled{quantity};

        for(1..$$compiled{quantity}) {
            my $lid = create_lineitem_detail(
                $mgr, 
                lineitem        => $li->id,
                owning_lib      => $$compiled{owning_lib},
                cn_label        => $$compiled{call_number},
                fund            => $$compiled{fund},
                circ_modifier   => $$compiled{circ_modifier},
                note            => $$compiled{note},
                location        => $$compiled{copy_location},
                collection_code => $$compiled{collection_code},
                barcode         => $$compiled{barcode}
            ) or return 0;
        }

        $mgr->respond;
        $idx++;
    }

    $li->estimated_unit_price($price);
    update_lineitem($mgr, $li) or return 0;
    return 1;
}

# return hash on success, 0 on error, undef on no more holdings
sub extract_lineitem_detail_data {
    my($mgr, $org_path, $holdings, $index, $fiscal_year) = @_;

    my @data_list = grep { $_->{holding} eq $index } @$holdings;
    return undef unless @data_list;

    my %compiled = map { $_->{attr} => $_->{data} } @data_list;
    my $base_org = $$org_path[0];

    my $killme = sub {
        my $msg = shift;
        $logger->error("Item import extraction error: $msg");
        $logger->error('Holdings Data: ' . OpenSRF::Utils::JSON->perl2JSON(\%compiled));
        $mgr->editor->rollback;
        $mgr->editor->event(OpenILS::Event->new('ACQ_IMPORT_ERROR', payload => $msg));
        return 0;
    };

    # ---------------------------------------------------------------------
    # Fund
    if(my $code = $compiled{fund_code}) {

        my $fund = $mgr->cache($base_org, "fund.$code");
        unless($fund) {
            # search up the org tree for the most appropriate fund
            for my $org (@$org_path) {
                $fund = $mgr->editor->search_acq_fund(
                    {org => $org, code => $code, year => $fiscal_year}, {idlist => 1})->[0];
                last if $fund;
            }
        }
        return $killme->("no fund with code $code at orgs [@$org_path]") unless $fund;
        $compiled{fund} = $fund;
        $mgr->cache($base_org, "fund.$code", $fund);
    }


    # ---------------------------------------------------------------------
    # Owning lib
    if(my $sn = $compiled{owning_lib}) {
        my $org_id = $mgr->cache($base_org, "orgsn.$sn") ||
            $mgr->editor->search_actor_org_unit({shortname => $sn}, {idlist => 1})->[0];
        return $killme->("invalid owning_lib defined: $sn") unless $org_id;
        $compiled{owning_lib} = $org_id;
        $mgr->cache($$org_path[0], "orgsn.$sn", $org_id);
    }


    # ---------------------------------------------------------------------
    # Circ Modifier
    my $code = $compiled{circ_modifier};

    if(defined $code) {

        # verify this is a valid circ modifier
        return $killme->("invlalid circ_modifier $code") unless 
            defined $mgr->cache($base_org, "mod.$code") or 
            $mgr->editor->retrieve_config_circ_modifier($code);

            # if valid, cache for future tests
            $mgr->cache($base_org, "mod.$code", $code);

    } else {
        $compiled{circ_modifier} = get_default_circ_modifier($mgr, $base_org);
    }


    # ---------------------------------------------------------------------
    # Shelving Location
    if( my $name = $compiled{copy_location}) {
        my $loc = $mgr->cache($base_org, "copy_loc.$name");
        unless($loc) {
            for my $org (@$org_path) {
                $loc = $mgr->editor->search_asset_copy_location(
                    {owning_lib => $org, name => $name}, {idlist => 1})->[0];
                last if $loc;
            }
        }
        return $killme->("Invalid copy location $name") unless $loc;
        $compiled{copy_location} = $loc;
        $mgr->cache($base_org, "copy_loc.$name", $loc);
    }

    return \%compiled;
}



# ----------------------------------------------------------------------------
# Workflow: Given an existing purchase order, import/create the bibs, 
# callnumber and copy objects
# ----------------------------------------------------------------------------

__PACKAGE__->register_method(
	method => 'create_po_assets',
	api_name	=> 'open-ils.acq.purchase_order.assets.create',
	signature => {
        desc => q/Creates assets for each lineitem in the purchase order/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'The purchase order id', type => 'number'},
        ],
        return => {desc => 'Streams a total versus completed counts object, event on error'}
    },
    max_chunk_count => 1
);

sub create_po_assets {
    my($self, $conn, $auth, $po_id, $args) = @_;
    $args ||= {};

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;

    my $li_ids = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist => 1});

    # it's ugly, but it's fast.  Get the total count of lineitem detail objects to process
    my $lid_total = $e->json_query({
        select => { acqlid => [{aggregate => 1, transform => 'count', column => 'id'}] }, 
        from => {
            acqlid => {
                jub => {
                    fkey => 'lineitem', 
                    field => 'id', 
                    join => {acqpo => {fkey => 'purchase_order', field => 'id'}}
                }
            }
        }, 
        where => {'+acqpo' => {id => $po_id}}
    })->[0]->{id};

    $mgr->total(scalar(@$li_ids) + $lid_total);

    create_lineitem_list_assets($mgr, $li_ids, $args->{vandelay}) 
        or return $e->die_event;

    $e->xact_begin;
    update_purchase_order($mgr, $po) or return $e->die_event;
    $e->commit;

    return $mgr->respond_complete;
}



__PACKAGE__->register_method(
    method    => 'create_purchase_order_api',
    api_name  => 'open-ils.acq.purchase_order.create',
    signature => {
        desc   => 'Creates a new purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to create', type => 'object'}
        ],
        return => {desc => 'The purchase order id, Event on failure'}
    },
    max_chunk_count => 1
);

sub create_purchase_order_api {
    my($self, $conn, $auth, $po, $args) = @_;
    $args ||= {};

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    # create the PO
    my %pargs = (ordering_agency => $e->requestor->ws_ou); # default
    $pargs{provider}            = $po->provider            if $po->provider;
    $pargs{ordering_agency}     = $po->ordering_agency     if $po->ordering_agency;
    $pargs{prepayment_required} = $po->prepayment_required if $po->prepayment_required;
    my $vandelay = $args->{vandelay};
        
    $po = create_purchase_order($mgr, %pargs) or return $e->die_event;

    my $li_ids = $$args{lineitems};

    if($li_ids) {

        for my $li_id (@$li_ids) { 

            my $li = $e->retrieve_acq_lineitem([
                $li_id,
                {flesh => 1, flesh_fields => {jub => ['attributes']}}
            ]) or return $e->die_event;

            $li->provider($po->provider);
            $li->purchase_order($po->id);
            $li->state('pending-order');
            update_lineitem($mgr, $li) or return $e->die_event;
            $mgr->respond;
        }
    }

    # commit before starting the asset creation
    $e->xact_commit;

    if($li_ids and $vandelay) {
        create_lineitem_list_assets($mgr, $li_ids, $vandelay, !$$args{create_assets}) or return $e->die_event;
    }

    return $mgr->respond_complete;
}



__PACKAGE__->register_method(
    method   => 'update_lineitem_fund_batch',
    api_name => 'open-ils.acq.lineitem.fund.update.batch',
    stream   => 1,
    signature => { 
        desc => q/Given a set of lineitem IDS, updates the fund for all attached lineitem details/
    }
);

sub update_lineitem_fund_batch {
    my($self, $conn, $auth, $li_ids, $fund_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    for my $li_id (@$li_ids) {
        my ($li, $evt) = fetch_and_check_li($e, $li_id, 'write');
        return $evt if $evt;
        my $li_details = $e->search_acq_lineitem_detail({lineitem => $li_id});
        $_->fund($fund_id) and $_->ischanged(1) for @$li_details;
        $evt = lineitem_detail_CUD_batch($mgr, $li_details);
        return $evt if $evt;
        $mgr->add_li;
        $mgr->respond;
    }
    $e->commit;
    return $mgr->respond_complete;
}



__PACKAGE__->register_method(
    method    => 'lineitem_detail_CUD_batch_api',
    api_name  => 'open-ils.acq.lineitem_detail.cud.batch',
    stream    => 1,
    signature => {
        desc   => q/Creates a new purchase order line item detail. / .
                  q/Additionally creates the associated fund_debit/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of lineitem_details to create', type => 'array'},
            {desc => 'Create Debits.  Used for creating post-po-asset-creation debits', type => 'bool'},
        ],
        return => {desc => 'Streaming response of current position in the array'}
    }
);

__PACKAGE__->register_method(
    method    => 'lineitem_detail_CUD_batch_api',
    api_name  => 'open-ils.acq.lineitem_detail.cud.batch.dry_run',
    stream    => 1,
    signature => { 
        desc => q/
            Dry run version of open-ils.acq.lineitem_detail.cud.batch.
            In dry_run mode, updated fund_debit's the exceed the warning
            percent return an event.  
        /
    }
);


sub lineitem_detail_CUD_batch_api {
    my($self, $conn, $auth, $li_details, $create_debits) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    my $dry_run = ($self->api_name =~ /dry_run/o);
    my $evt = lineitem_detail_CUD_batch($mgr, $li_details, $create_debits, $dry_run);
    return $evt if $evt;
    $e->commit;
    return $mgr->respond_complete;
}


sub lineitem_detail_CUD_batch {
    my($mgr, $li_details, $create_debits, $dry_run) = @_;

    $mgr->total(scalar(@$li_details));
    my $e = $mgr->editor;
    
    my $li;
    my %li_cache;
    my $fund_cache = {};
    my $evt;

    for my $lid (@$li_details) {

        unless($li = $li_cache{$lid->lineitem}) {
            ($li, $evt) = fetch_and_check_li($e, $lid->lineitem, 'write');
            return $evt if $evt;
        }

        if($lid->isnew) {
            $lid = create_lineitem_detail($mgr, %{$lid->to_bare_hash}) or return $e->die_event;
            if($create_debits) {
                $li->provider($e->retrieve_acq_provider($li->provider)) or return $e->die_event;
                $lid->fund($e->retrieve_acq_fund($lid->fund)) or return $e->die_event;
                create_lineitem_detail_debit($mgr, $li, $lid, 0, 1) or return $e->die_event;
            }

        } elsif($lid->ischanged) {
            return $evt if $evt = handle_changed_lid($e, $lid, $dry_run, $fund_cache);

        } elsif($lid->isdeleted) {
            delete_lineitem_detail($mgr, $lid) or return $e->die_event;
        }

        $mgr->respond(li => $li);
        $li_cache{$lid->lineitem} = $li;
    }

    return undef;
}

sub handle_changed_lid {
    my($e, $lid, $dry_run, $fund_cache) = @_;

    my $orig_lid = $e->retrieve_acq_lineitem_detail($lid->id) or return $e->die_event;

    # updating the fund, so update the debit
    if($orig_lid->fund_debit and $orig_lid->fund != $lid->fund) {

        my $debit = $e->retrieve_acq_fund_debit($orig_lid->fund_debit);
        my $new_fund = $$fund_cache{$lid->fund} = 
            $$fund_cache{$lid->fund} || $e->retrieve_acq_fund($lid->fund);

        # check the thresholds
        return $e->die_event if
            fund_exceeds_balance_percent($new_fund, $debit->amount, $e, "stop");
        return $e->die_event if $dry_run and 
            fund_exceeds_balance_percent($new_fund, $debit->amount, $e, "warning");

        $debit->fund($new_fund->id);
        $e->update_acq_fund_debit($debit) or return $e->die_event;
    }

    $e->update_acq_lineitem_detail($lid) or return $e->die_event;
    return undef;
}


__PACKAGE__->register_method(
    method   => 'receive_po_api',
    api_name => 'open-ils.acq.purchase_order.receive'
);

sub receive_po_api {
    my($self, $conn, $auth, $po_id) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $po->ordering_agency);

    my $li_ids = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist => 1});

    for my $li_id (@$li_ids) {
        receive_lineitem($mgr, $li_id) or return $e->die_event;
        $mgr->respond;
    }

    $po->state('received');
    update_purchase_order($mgr, $po) or return $e->die_event;

    $e->commit;
    return $mgr->respond_complete;
}


# At the moment there's a lack of parallelism between the receive and unreceive
# API methods for POs and the API methods for LIs and LIDs.  The methods for
# POs stream back objects as they act, whereas the methods for LIs and LIDs
# atomically return an object that describes only what changed (in LIs and LIDs
# themselves or in the objects to which to LIs and LIDs belong).
#
# The methods for LIs and LIDs work the way they do to faciliate the UI's
# maintaining correct information about the state of these things when a user
# wants to receive or unreceive these objects without refreshing their whole
# display.  The UI feature for receiving and un-receiving a whole PO just
# refreshes the whole display, so this absence of parallelism in the UI is also
# relected in this module.
#
# This could be neatened in the future by making POs receive and unreceive in
# the same way the LIs and LIDs do.

__PACKAGE__->register_method(
	method => 'receive_lineitem_detail_api',
	api_name	=> 'open-ils.acq.lineitem_detail.receive',
	signature => {
        desc => 'Mark a lineitem_detail as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc =>
            "on success, object describing changes to LID and possibly " .
            "to LI and PO; on error, Event"
        }
    }
);

sub receive_lineitem_detail_api {
    my($self, $conn, $auth, $lid_id) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $fleshing = {
        "flesh" => 2, "flesh_fields" => {
            "acqlid" => ["lineitem"], "jub" => ["purchase_order"]
        }
    };

    my $lid = $e->retrieve_acq_lineitem_detail([$lid_id, $fleshing]);

    return $e->die_event unless $e->allowed(
        'RECEIVE_PURCHASE_ORDER', $lid->lineitem->purchase_order->ordering_agency);

    # update ...
    my $recvd = receive_lineitem_detail($mgr, $lid_id) or return $e->die_event;

    # .. and re-retrieve
    $lid = $e->retrieve_acq_lineitem_detail([$lid_id, $fleshing]);

    # Now build result data structure.
    my $result = {"lid" => {$lid->id => {"recv_time" => $lid->recv_time}}};

    if (ref $recvd) {
        if ($recvd->class_name =~ /::purchase_order/) {
            $result->{"po"} = describe_affected_po($e, $recvd);
            $result->{"li"} = {
                $lid->lineitem->id => {"state" => $lid->lineitem->state}
            };
        } elsif ($recvd->class_name =~ /::lineitem/) {
            $result->{"li"} = {$recvd->id => {"state" => $recvd->state}};
        }
    }
    $result->{"po"} ||=
        describe_affected_po($e, $lid->lineitem->purchase_order);

    $e->commit;
    return $result;
}

__PACKAGE__->register_method(
	method => 'receive_lineitem_api',
	api_name	=> 'open-ils.acq.lineitem.receive',
	signature => {
        desc => 'Mark a lineitem as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID', type => 'number'}
        ],
        return => {desc =>
            "on success, object describing changes to LI and possibly PO; " .
            "on error, Event"
        }
    }
);

sub receive_lineitem_api {
    my($self, $conn, $auth, $li_id) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $li = $e->retrieve_acq_lineitem([
        $li_id, {
            flesh => 1,
            flesh_fields => {
                jub => ['purchase_order']
            }
        }
    ]) or return $e->die_event;

    return $e->die_event unless $e->allowed(
        'RECEIVE_PURCHASE_ORDER', $li->purchase_order->ordering_agency);

    my $res = receive_lineitem($mgr, $li_id) or return $e->die_event;
    $e->commit;
    $conn->respond_complete($res);
    $mgr->run_post_response_hooks
}


__PACKAGE__->register_method(
    method   => 'rollback_receive_po_api',
    api_name => 'open-ils.acq.purchase_order.receive.rollback'
);

sub rollback_receive_po_api {
    my($self, $conn, $auth, $po_id) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $po->ordering_agency);

    my $li_ids = $e->search_acq_lineitem({purchase_order => $po_id}, {idlist => 1});

    for my $li_id (@$li_ids) {
        rollback_receive_lineitem($mgr, $li_id) or return $e->die_event;
        $mgr->respond;
    }

    $po->state('on-order');
    update_purchase_order($mgr, $po) or return $e->die_event;

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
    method    => 'rollback_receive_lineitem_detail_api',
    api_name  => 'open-ils.acq.lineitem_detail.receive.rollback',
    signature => {
        desc   => 'Mark a lineitem_detail as Un-received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc =>
            "on success, object describing changes to LID and possibly " .
            "to LI and PO; on error, Event"
        }
    }
);

sub rollback_receive_lineitem_detail_api {
    my($self, $conn, $auth, $lid_id) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $lid = $e->retrieve_acq_lineitem_detail([
        $lid_id, {
            flesh => 2,
            flesh_fields => {
                acqlid => ['lineitem'],
                jub => ['purchase_order']
            }
        }
    ]);
    my $li = $lid->lineitem;
    my $po = $li->purchase_order;

    return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $po->ordering_agency);

    my $result = {};

    my $recvd = rollback_receive_lineitem_detail($mgr, $lid_id)
        or return $e->die_event;

    if (ref $recvd) {
        $result->{"lid"} = {$recvd->id => {"recv_time" => $recvd->recv_time}};
    } else {
        $result->{"lid"} = {$lid->id => {"recv_time" => $lid->recv_time}};
    }

    if ($li->state eq "received") {
        $li->state("on-order");
        $li = update_lineitem($mgr, $li) or return $e->die_event;
        $result->{"li"} = {$li->id => {"state" => $li->state}};
    }

    if ($po->state eq "received") {
        $po->state("on-order");
        $po = update_purchase_order($mgr, $po) or return $e->die_event;
    }
    $result->{"po"} = describe_affected_po($e, $po);

    $e->commit and return $result or return $e->die_event;
}

__PACKAGE__->register_method(
    method    => 'rollback_receive_lineitem_api',
    api_name  => 'open-ils.acq.lineitem.receive.rollback',
    signature => {
        desc   => 'Mark a lineitem as Un-received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID',          type => 'number'}
        ],
        return => {desc =>
            "on success, object describing changes to LI and possibly PO; " .
            "on error, Event"
        }
    }
);

sub rollback_receive_lineitem_api {
    my($self, $conn, $auth, $li_id) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $li = $e->retrieve_acq_lineitem([
        $li_id, {
            "flesh" => 1, "flesh_fields" => {"jub" => ["purchase_order"]}
        }
    ]);
    my $po = $li->purchase_order;

    return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $po->ordering_agency);

    $li = rollback_receive_lineitem($mgr, $li_id) or return $e->die_event;

    my $result = {"li" => {$li->id => {"state" => $li->state}}};
    if ($po->state eq "received") {
        $po->state("on-order");
        $po = update_purchase_order($mgr, $po) or return $e->die_event;
    }
    $result->{"po"} = describe_affected_po($e, $po);

    $e->commit and return $result or return $e->die_event;
}


__PACKAGE__->register_method(
    method    => 'set_lineitem_price_api',
    api_name  => 'open-ils.acq.lineitem.price.set',
    signature => {
        desc   => 'Set lineitem price.  If debits already exist, update them as well',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID',          type => 'number'}
        ],
        return => {desc => 'status blob, Event on error'}
    }
);

sub set_lineitem_price_api {
    my($self, $conn, $auth, $li_id, $price) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my ($li, $evt) = fetch_and_check_li($e, $li_id, 'write');
    return $evt if $evt;

    $li->estimated_unit_price($price);
    update_lineitem($mgr, $li) or return $e->die_event;

    my $lid_ids = $e->search_acq_lineitem_detail(
        {lineitem => $li_id, fund_debit => {'!=' => undef}}, 
        {idlist => 1}
    );

    for my $lid_id (@$lid_ids) {

        my $lid = $e->retrieve_acq_lineitem_detail([
            $lid_id, {
            flesh => 1, flesh_fields => {acqlid => ['fund', 'fund_debit']}}
        ]);

        $lid->fund_debit->amount($price);
        $e->update_acq_fund_debit($lid->fund_debit) or return $e->die_event;
        $mgr->add_lid;
        $mgr->respond;
    }

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
    method    => 'clone_picklist_api',
    api_name  => 'open-ils.acq.picklist.clone',
    signature => {
        desc   => 'Clones a picklist, including lineitem and lineitem details',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Picklist ID', type => 'number'},
            {desc => 'New Picklist Name', type => 'string'}
        ],
        return => {desc => 'status blob, Event on error'}
    }
);

sub clone_picklist_api {
    my($self, $conn, $auth, $pl_id, $name) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $old_pl = $e->retrieve_acq_picklist($pl_id);
    my $new_pl = create_picklist($mgr, %{$old_pl->to_bare_hash}, name => $name) or return $e->die_event;

    my $li_ids = $e->search_acq_lineitem({picklist => $pl_id}, {idlist => 1});

    # get the current user
    my $cloner = $mgr->editor->requestor->id;

    for my $li_id (@$li_ids) {

        # copy the lineitems' MARC
        my $marc = ($e->retrieve_acq_lineitem($li_id))->marc;

        # create a skeletal clone of the item
        my $li = Fieldmapper::acq::lineitem->new;
        $li->creator($cloner);
        $li->selector($cloner);
        $li->editor($cloner);
        $li->marc($marc);

        my $new_li = create_lineitem($mgr, %{$li->to_bare_hash}, picklist => $new_pl->id) or return $e->die_event;

        $mgr->respond;
    }

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
    method    => 'merge_picklist_api',
    api_name  => 'open-ils.acq.picklist.merge',
    signature => {
        desc   => 'Merges 2 or more picklists into a single list',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Lead Picklist ID', type => 'number'},
            {desc => 'List of subordinate picklist IDs', type => 'array'}
        ],
        return => {desc => 'status blob, Event on error'}
    }
);

sub merge_picklist_api {
    my($self, $conn, $auth, $lead_pl, $pl_list) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    # XXX perms on each picklist modified

    $lead_pl = $e->retrieve_acq_picklist($lead_pl) or return $e->die_event;
    # point all of the lineitems at the lead picklist
    my $li_ids = $e->search_acq_lineitem({picklist => $pl_list}, {idlist => 1});

    for my $li_id (@$li_ids) {
        my $li = $e->retrieve_acq_lineitem($li_id);
        $li->picklist($lead_pl);
        update_lineitem($mgr, $li) or return $e->die_event;
        $mgr->respond;
    }

    # now delete the subordinate lists
    for my $pl_id (@$pl_list) {
        my $pl = $e->retrieve_acq_picklist($pl_id);
        $e->delete_acq_picklist($pl) or return $e->die_event;
    }

    update_picklist($mgr, $lead_pl) or return $e->die_event;

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
    method    => 'delete_picklist_api',
    api_name  => 'open-ils.acq.picklist.delete',
    signature => {
        desc   => q/Deletes a picklist.  It also deletes any lineitems in the "new" state. / .
                  q/Other attached lineitems are detached/,
        params => [
            {desc => 'Authentication token',  type => 'string'},
            {desc => 'Picklist ID to delete', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub delete_picklist_api {
    my($self, $conn, $auth, $picklist_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    my $pl = $e->retrieve_acq_picklist($picklist_id) or return $e->die_event;
    delete_picklist($mgr, $pl) or return $e->die_event;
    $e->commit;
    return $mgr->respond_complete;
}



__PACKAGE__->register_method(
    method   => 'activate_purchase_order',
    api_name => 'open-ils.acq.purchase_order.activate.dry_run'
);

__PACKAGE__->register_method(
    method    => 'activate_purchase_order',
    api_name  => 'open-ils.acq.purchase_order.activate',
    signature => {
        desc => q/Activates a purchase order.  This updates the status of the PO / .
                q/and Lineitems to 'on-order'.  Activated PO's are ready for EDI delivery if appropriate./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Purchase ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub activate_purchase_order {
    my($self, $conn, $auth, $po_id, $vandelay) = @_;

    my $dry_run = ($self->api_name =~ /\.dry_run/) ? 1 : 0;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);
    my $die_event = activate_purchase_order_impl($mgr, $po_id, $vandelay, $dry_run);
    return $e->die_event if $die_event;
    $conn->respond_complete(1);
    $mgr->run_post_response_hooks unless $dry_run;
    return undef;
}

# xacts managed within
sub activate_purchase_order_impl {
    my ($mgr, $po_id, $vandelay, $dry_run) = @_;

    # read-only until lineitem asset creation
    my $e = $mgr->editor;
    $e->xact_begin;

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);

    return $e->die_event(OpenILS::Event->new('PO_ALREADY_ACTIVATED'))
        if $po->order_date; # PO cannot be re-activated

    my $provider = $e->retrieve_acq_provider($po->provider);

    # find lineitems and create assets for all

    my $query = {   
        purchase_order => $po_id, 
        state => [qw/pending-order new order-ready/]
    };

    my $li_ids = $e->search_acq_lineitem($query, {idlist => 1});

    my $vl_resp; # imported li's and the queue the managing queue
    if (!$dry_run) {
        $e->rollback; # read-only thus far
        $vl_resp = create_lineitem_list_assets($mgr, $li_ids, $vandelay)
            or return OpenILS::Event->new('ACQ_LI_IMPORT_FAILED');
        $e->xact_begin;
    }

    # create fund debits for lineitems 

    for my $li_id (@$li_ids) {
        my $li = $e->retrieve_acq_lineitem($li_id);
        
        if (!$li->eg_bib_id and !$dry_run) {
            # we encountered a lineitem that was not successfully imported.
            # we cannot continue.  rollback and report.
            $e->rollback;
            return OpenILS::Event->new('ACQ_LI_IMPORT_FAILED', {queue => $vl_resp->{queue}});
        }

        $li->state('on-order');
        $li->claim_policy($provider->default_claim_policy)
            if $provider->default_claim_policy and !$li->claim_policy;
        create_lineitem_debits($mgr, $li, $dry_run) or return $e->die_event;
        update_lineitem($mgr, $li) or return $e->die_event;
        $mgr->post_process( sub { create_lineitem_status_events($mgr, $li->id, 'aur.ordered'); });
        $mgr->respond;
    }

    # create po-item debits

    for my $po_item (@{$e->search_acq_po_item({purchase_order => $po_id})}) {

        my $debit = create_fund_debit(
            $mgr, 
            $dry_run, 
            debit_type => 'direct_charge', # to match invoicing
            origin_amount => $po_item->estimated_cost,
            origin_currency_type => $e->retrieve_acq_fund($po_item->fund)->currency_type,
            amount => $po_item->estimated_cost,
            fund => $po_item->fund
        ) or return $e->die_event;
        $po_item->fund_debit($debit->id);
        $e->update_acq_po_item($po_item) or return $e->die_event;
        $mgr->respond;
    }

    # mark PO as ordered

    $po->state('on-order');
    $po->order_date('now');
    update_purchase_order($mgr, $po) or return $e->die_event;

    # clean up the xact
    $dry_run and $e->rollback or $e->commit;

    # tell the world we activated a PO
    $U->create_events_for_hook('acqpo.activated', $po, $po->ordering_agency) unless $dry_run;

    return undef;
}


__PACKAGE__->register_method(
    method    => 'split_purchase_order_by_lineitems',
    api_name  => 'open-ils.acq.purchase_order.split_by_lineitems',
    signature => {
        desc   => q/Splits a PO into many POs, 1 per lineitem.  Only works for / .
                  q/POs a) with more than one lineitems, and b) in the "pending" state./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Purchase order ID',    type => 'number'}
        ],
        return => {desc => 'list of new PO IDs on success, Event on error'}
    }
);

sub split_purchase_order_by_lineitems {
    my ($self, $conn, $auth, $po_id) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $po = $e->retrieve_acq_purchase_order([
        $po_id, {
            "flesh" => 1,
            "flesh_fields" => {"acqpo" => [qw/lineitems notes/]}
        }
    ]) or return $e->die_event;

    return $e->die_event
        unless $e->allowed("CREATE_PURCHASE_ORDER", $po->ordering_agency);

    unless ($po->state eq "pending") {
        $e->rollback;
        return new OpenILS::Event("ACQ_PURCHASE_ORDER_TOO_LATE");
    }

    unless (@{$po->lineitems} > 1) {
        $e->rollback;
        return new OpenILS::Event("ACQ_PURCHASE_ORDER_TOO_SHORT");
    }

    # To split an existing PO into many, it seems unwise to just delete the
    # original PO, so we'll instead detach all of the original POs' lineitems
    # but the first, then create new POs for each of the remaining LIs, and
    # then attach the LIs to their new POs.

    my @po_ids = ($po->id);
    my @moving_li = @{$po->lineitems};
    shift @moving_li;    # discard first LI

    foreach my $li (@moving_li) {
        my $new_po = $po->clone;
        $new_po->clear_id;
        $new_po->clear_name;
        $new_po->creator($e->requestor->id);
        $new_po->editor($e->requestor->id);
        $new_po->owner($e->requestor->id);
        $new_po->edit_time("now");
        $new_po->create_time("now");

        $new_po = $e->create_acq_purchase_order($new_po);

        # Clone any notes attached to the old PO and attach to the new one.
        foreach my $note (@{$po->notes}) {
            my $new_note = $note->clone;
            $new_note->clear_id;
            $new_note->edit_time("now");
            $new_note->purchase_order($new_po->id);
            $e->create_acq_po_note($new_note);
        }

        $li->edit_time("now");
        $li->purchase_order($new_po->id);
        $e->update_acq_lineitem($li);

        push @po_ids, $new_po->id;
    }

    $po->edit_time("now");
    $e->update_acq_purchase_order($po);

    return \@po_ids if $e->commit;
    return $e->die_event;
}


sub not_cancelable {
    my $o = shift;
    (ref $o eq "HASH" and $o->{"textcode"} eq "ACQ_NOT_CANCELABLE");
}

__PACKAGE__->register_method(
	method => "cancel_purchase_order_api",
	api_name	=> "open-ils.acq.purchase_order.cancel",
	signature => {
        desc => q/Cancels an on-order purchase order/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "PO ID to cancel", type => "number"},
            {desc => "Cancel reason ID", type => "number"}
        ],
        return => {desc => q/Object describing changed POs, LIs and LIDs
            on success; Event on error./}
    }
);

sub cancel_purchase_order_api {
    my ($self, $conn, $auth, $po_id, $cancel_reason) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = new OpenILS::Application::Acq::BatchManager(
        "editor" => $e, "conn" => $conn
    );

    $cancel_reason = $mgr->editor->retrieve_acq_cancel_reason($cancel_reason) or
        return new OpenILS::Event(
            "BAD_PARAMS", "note" => "Provide cancel reason ID"
        );

    my $result = cancel_purchase_order($mgr, $po_id, $cancel_reason) or
        return $e->die_event;
    if (not_cancelable($result)) { # event not from CStoreEditor
        $e->rollback;
        return $result;
    } elsif ($result == -1) {
        $e->rollback;
        return new OpenILS::Event("ACQ_ALREADY_CANCELED");
    }

    $e->commit or return $e->die_event;

    # XXX create purchase order status events?

    if ($mgr->{post_commit}) {
        foreach my $func (@{$mgr->{post_commit}}) {
            $func->();
        }
    }

    return $result;
}

sub cancel_purchase_order {
    my ($mgr, $po_id, $cancel_reason) = @_;

    my $po = $mgr->editor->retrieve_acq_purchase_order($po_id) or return 0;

    # XXX is "cancelled" a typo?  It's not correct US spelling, anyway.
    # Depending on context, this may not warrant an event.
    return -1 if $po->state eq "cancelled";

    # But this always does.
    return new OpenILS::Event(
        "ACQ_NOT_CANCELABLE", "note" => "purchase_order $po_id"
    ) unless ($po->state eq "on-order" or $po->state eq "pending");

    return 0 unless
        $mgr->editor->allowed("CREATE_PURCHASE_ORDER", $po->ordering_agency);

    $po->state("cancelled");
    $po->cancel_reason($cancel_reason->id);

    my $li_ids = $mgr->editor->search_acq_lineitem(
        {"purchase_order" => $po_id}, {"idlist" => 1}
    );

    my $result = {"li" => {}, "lid" => {}};
    foreach my $li_id (@$li_ids) {
        my $li_result = cancel_lineitem($mgr, $li_id, $cancel_reason)
            or return 0;

        next if $li_result == -1; # already canceled:skip.
        return $li_result if not_cancelable($li_result); # not cancelable:stop.

        # Merge in each LI result (there's only going to be
        # one per call to cancel_lineitem).
        my ($k, $v) = each %{$li_result->{"li"}};
        $result->{"li"}->{$k} = $v;

        # Merge in each LID result (there may be many per call to
        # cancel_lineitem).
        while (($k, $v) = each %{$li_result->{"lid"}}) {
            $result->{"lid"}->{$k} = $v;
        }
    }

    # TODO who/what/where/how do we indicate this change for electronic orders?
    # TODO return changes to encumbered/spent
    # TODO maybe cascade up from smaller object to container object if last
    # smaller object in the container has been canceled?

    update_purchase_order($mgr, $po) or return 0;
    $result->{"po"} = {
        $po_id => {"state" => $po->state, "cancel_reason" => $cancel_reason}
    };
    return $result;
}


__PACKAGE__->register_method(
	method => "cancel_lineitem_api",
	api_name	=> "open-ils.acq.lineitem.cancel",
	signature => {
        desc => q/Cancels an on-order lineitem/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Lineitem ID to cancel", type => "number"},
            {desc => "Cancel reason ID", type => "number"}
        ],
        return => {desc => q/Object describing changed LIs and LIDs on success;
            Event on error./}
    }
);

__PACKAGE__->register_method(
	method => "cancel_lineitem_api",
	api_name	=> "open-ils.acq.lineitem.cancel.batch",
	signature => {
        desc => q/Batched version of open-ils.acq.lineitem.cancel/,
        return => {desc => q/Object describing changed LIs and LIDs on success;
            Event on error./}
    }
);

sub cancel_lineitem_api {
    my ($self, $conn, $auth, $li_id, $cancel_reason) = @_;

    my $batched = $self->api_name =~ /\.batch/;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = new OpenILS::Application::Acq::BatchManager(
        "editor" => $e, "conn" => $conn
    );

    $cancel_reason = $mgr->editor->retrieve_acq_cancel_reason($cancel_reason) or
        return new OpenILS::Event(
            "BAD_PARAMS", "note" => "Provide cancel reason ID"
        );

    my ($result, $maybe_event);

    if ($batched) {
        $result = {"li" => {}, "lid" => {}};
        foreach my $one_li_id (@$li_id) {
            my $one = cancel_lineitem($mgr, $one_li_id, $cancel_reason) or
                return $e->die_event;
            if (not_cancelable($one)) {
                $maybe_event = $one;
            } elsif ($result == -1) {
                $maybe_event = new OpenILS::Event("ACQ_ALREADY_CANCELED");
            } else {
                my ($k, $v);
                if ($one->{"li"}) {
                    while (($k, $v) = each %{$one->{"li"}}) {
                        $result->{"li"}->{$k} = $v;
                    }
                }
                if ($one->{"lid"}) {
                    while (($k, $v) = each %{$one->{"lid"}}) {
                        $result->{"lid"}->{$k} = $v;
                    }
                }
            }
        }
    } else {
        $result = cancel_lineitem($mgr, $li_id, $cancel_reason) or
            return $e->die_event;

        if (not_cancelable($result)) {
            $e->rollback;
            return $result;
        } elsif ($result == -1) {
            $e->rollback;
            return new OpenILS::Event("ACQ_ALREADY_CANCELED");
        }
    }

    if ($batched and not scalar keys %{$result->{"li"}}) {
        $e->rollback;
        return $maybe_event;
    } else {
        $e->commit or return $e->die_event;
        # create_lineitem_status_events should handle array li_id ok
        create_lineitem_status_events($mgr, $li_id, "aur.cancelled");

        if ($mgr->{post_commit}) {
            foreach my $func (@{$mgr->{post_commit}}) {
                $func->();
            }
        }

        return $result;
    }
}

sub cancel_lineitem {
    my ($mgr, $li_id, $cancel_reason) = @_;
    my $li = $mgr->editor->retrieve_acq_lineitem([
        $li_id, {flesh => 1, flesh_fields => {jub => ['purchase_order']}}
    ]) or return 0;

    return 0 unless $mgr->editor->allowed(
        "CREATE_PURCHASE_ORDER", $li->purchase_order->ordering_agency
    );

    # Depending on context, this may not warrant an event.
    return -1 if $li->state eq "cancelled";

    # But this always does.
    return new OpenILS::Event(
        "ACQ_NOT_CANCELABLE", "note" => "lineitem $li_id"
    ) unless (
        (! $li->purchase_order) or (
            $li->purchase_order and (
                $li->state eq "on-order" or $li->state eq "pending-order"
            )
        )
    );

    $li->state("cancelled");
    $li->cancel_reason($cancel_reason->id);

    my $lids = $mgr->editor->search_acq_lineitem_detail([{
        "lineitem" => $li_id
    }, {
        flesh => 1,
        flesh_fields => { acqlid => ['eg_copy_id'] }
    }]);

    my $result = {"lid" => {}};
    my $copies = [];
    foreach my $lid (@$lids) {
        my $lid_result = cancel_lineitem_detail($mgr, $lid->id, $cancel_reason)
            or return 0;

        # gathering any real copies for deletion
        if ($lid->eg_copy_id) {
            $lid->eg_copy_id->isdeleted('t');
            push @$copies, $lid->eg_copy_id;
        }

        next if $lid_result == -1; # already canceled: just skip it.
        return $lid_result if not_cancelable($lid_result); # not cxlable: stop.

        # Merge in each LID result (there's only going to be one per call to
        # cancel_lineitem_detail).
        my ($k, $v) = each %{$lid_result->{"lid"}};
        $result->{"lid"}->{$k} = $v;
    }

    # Attempt to delete the gathered copies (this will also handle volume deletion and bib deletion)
    # Delete empty bibs according org unit setting
    my $force_delete_empty_bib = $U->ou_ancestor_setting_value(
        $mgr->editor->requestor->ws_ou, 'cat.bib.delete_on_no_copy_via_acq_lineitem_cancel', $mgr->editor);
    if (scalar(@$copies)>0) {
        my $override = 1;
        my $delete_stats = undef;
        my $retarget_holds = [];
        my $cat_evt = OpenILS::Application::Cat::AssetCommon->update_fleshed_copies(
            $mgr->editor, $override, undef, $copies, $delete_stats, $retarget_holds,$force_delete_empty_bib);

        if( $cat_evt ) {
            $logger->info("fleshed copy update failed with event: ".OpenSRF::Utils::JSON->perl2JSON($cat_evt));
            return new OpenILS::Event(
                "ACQ_NOT_CANCELABLE", "note" => "lineitem $li_id", "payload" => $cat_evt
            );
        }

        # We can't do the following and stay within the same transaction, but that's okay, the hold targeter will pick these up later.
        #my $ses = OpenSRF::AppSession->create('open-ils.circ');
        #$ses->request('open-ils.circ.hold.reset.batch', $auth, $retarget_holds);
    }

    # if we have a bib, check to see whether it has been deleted.  if so, cancel any active holds targeting that bib
    if ($li->eg_bib_id) {
        my $bib = $mgr->editor->retrieve_biblio_record_entry($li->eg_bib_id) or return new OpenILS::Event(
            "ACQ_NOT_CANCELABLE", "note" => "Could not retrieve bib " . $li->eg_bib_id . " for lineitem $li_id"
        );
        if ($U->is_true($bib->deleted)) {
            my $holds = $mgr->editor->search_action_hold_request(
                {   cancel_time => undef,
                    fulfillment_time => undef,
                    target => $li->eg_bib_id
                }
            );

            my %cached_usr_home_ou = ();

            for my $hold (@$holds) {

                $logger->info("Cancelling hold ".$hold->id.
                    " due to acq lineitem cancellation.");

                $hold->cancel_time('now');
                $hold->cancel_cause(5); # 'Staff forced'--we may want a new hold cancel cause reason for this
                $hold->cancel_note('Corresponding Acquistion Lineitem/Purchase Order was cancelled.');
                unless($mgr->editor->update_action_hold_request($hold)) {
                    my $evt = $mgr->editor->event;
                    $logger->error("Error updating hold ". $evt->textcode .":". $evt->desc .":". $evt->stacktrace);
                    return new OpenILS::Event(
                        "ACQ_NOT_CANCELABLE", "note" => "Could not cancel hold " . $hold->id . " for lineitem $li_id", "payload" => $evt
                    );
                }
                if (! defined $mgr->{post_commit}) { # we need a mechanism for creating trigger events, but only if the transaction gets committed
                    $mgr->{post_commit} = [];
                }
                push @{ $mgr->{post_commit} }, sub {
                    my $home_ou = $cached_usr_home_ou{$hold->usr};
                    if (! $home_ou) {
                        my $user = $mgr->editor->retrieve_actor_user($hold->usr); # FIXME: how do we want to handle failures here?
                        $home_ou = $user->home_ou;
                        $cached_usr_home_ou{$hold->usr} = $home_ou;
                    }
                    $U->create_events_for_hook('hold_request.cancel.cancelled_order', $hold, $home_ou);
                };
            }
        }
    }

    update_lineitem($mgr, $li) or return 0;
    $result->{"li"} = {
        $li_id => {
            "state" => $li->state,
            "cancel_reason" => $cancel_reason
        }
    };
    return $result;
}


__PACKAGE__->register_method(
	method => "cancel_lineitem_detail_api",
	api_name	=> "open-ils.acq.lineitem_detail.cancel",
	signature => {
        desc => q/Cancels an on-order lineitem detail/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Lineitem detail ID to cancel", type => "number"},
            {desc => "Cancel reason ID", type => "number"}
        ],
        return => {desc => q/Object describing changed LIDs on success;
            Event on error./}
    }
);

sub cancel_lineitem_detail_api {
    my ($self, $conn, $auth, $lid_id, $cancel_reason) = @_;

    my $e = new_editor("xact" => 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = new OpenILS::Application::Acq::BatchManager(
        "editor" => $e, "conn" => $conn
    );

    $cancel_reason = $mgr->editor->retrieve_acq_cancel_reason($cancel_reason) or
        return new OpenILS::Event(
            "BAD_PARAMS", "note" => "Provide cancel reason ID"
        );

    my $result = cancel_lineitem_detail($mgr, $lid_id, $cancel_reason) or
        return $e->die_event;

    if (not_cancelable($result)) {
        $e->rollback;
        return $result;
    } elsif ($result == -1) {
        $e->rollback;
        return new OpenILS::Event("ACQ_ALREADY_CANCELED");
    }

    $e->commit or return $e->die_event;

    # XXX create lineitem detail status events?
    return $result;
}

sub cancel_lineitem_detail {
    my ($mgr, $lid_id, $cancel_reason) = @_;
    my $lid = $mgr->editor->retrieve_acq_lineitem_detail([
        $lid_id, {
            "flesh" => 2,
            "flesh_fields" => {
                "acqlid" => ["lineitem"], "jub" => ["purchase_order"]
            }
        }
    ]) or return 0;

    # Depending on context, this may not warrant an event.
    return -1 if $lid->cancel_reason;

    # But this always does.
    return new OpenILS::Event(
        "ACQ_NOT_CANCELABLE", "note" => "lineitem_detail $lid_id"
    ) unless (
        (! $lid->lineitem->purchase_order) or
        (
            (not $lid->recv_time) and
            $lid->lineitem and
            $lid->lineitem->purchase_order and (
                $lid->lineitem->state eq "on-order" or
                $lid->lineitem->state eq "pending-order"
            )
        )
    );

    return 0 unless $mgr->editor->allowed(
        "CREATE_PURCHASE_ORDER",
        $lid->lineitem->purchase_order->ordering_agency
    ) or (! $lid->lineitem->purchase_order);

    $lid->cancel_reason($cancel_reason->id);

    unless($U->is_true($cancel_reason->keep_debits)) {
        my $debit_id = $lid->fund_debit;
        $lid->clear_fund_debit;

        if($debit_id) {
            # item is cancelled.  Remove the fund debit.
            my $debit = $mgr->editor->retrieve_acq_fund_debit($debit_id);
            if (!$U->is_true($debit->encumbrance)) {
                $mgr->editor->rollback;
                return OpenILS::Event->new('ACQ_NOT_CANCELABLE', 
                    note => "Debit is marked as paid: $debit_id");
            }
            $mgr->editor->delete_acq_fund_debit($debit) or return $mgr->editor->die_event;
        }
    }

    # XXX LIDs don't have either an editor or a edit_time field. Should we
    # update these on the LI when we alter an LID?
    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;

    return {"lid" => {$lid_id => {"cancel_reason" => $cancel_reason}}};
}


__PACKAGE__->register_method(
    method    => 'user_requests',
    api_name  => 'open-ils.acq.user_request.retrieve.by_user_id',
    stream    => 1,
    signature => {
        desc   => 'Retrieve fleshed user requests and related data for a given user.',
        params => [
            { desc => 'Authentication token',      type => 'string' },
            { desc => 'User ID of the owner, or array of IDs',      },
            { desc => 'Options hash (optional) with any of the keys: order_by, limit, offset, state (of the lineitem)',
              type => 'object'
            }
        ],
        return => {
            desc => 'Fleshed user requests and related data',
            type => 'object'
        }
    }
);

__PACKAGE__->register_method(
    method    => 'user_requests',
    api_name  => 'open-ils.acq.user_request.retrieve.by_home_ou',
    stream    => 1,
    signature => {
        desc   => 'Retrieve fleshed user requests and related data for a given org unit or units.',
        params => [
            { desc => 'Authentication token',      type => 'string' },
            { desc => 'Org unit ID, or array of IDs',               },
            { desc => 'Options hash (optional) with any of the keys: order_by, limit, offset, state (of the lineitem)',
              type => 'object'
            }
        ],
        return => {
            desc => 'Fleshed user requests and related data',
            type => 'object'
        }
    }
);

sub user_requests {
    my($self, $conn, $auth, $search_value, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    my $rid = $e->requestor->id;
    $options ||= {};

    my $query = {
        "select"=>{"aur"=>["id"],"au"=>["home_ou", {column => 'id', alias => 'usr_id'} ]},
        "from"=>{ "aur" => { "au" => {}, "jub" => { "type" => "left" } } },
        "where"=>{
            "+jub"=> {
                "-or" => [
                    {"id"=>undef}, # this with the left-join pulls in requests without lineitems
                    {"state"=>["new","on-order","pending-order"]} # FIXME - probably needs softcoding
                ]
            }
        },
        "order_by"=>[{"class"=>"aur", "field"=>"request_date", "direction"=>"desc"}]
    };

    foreach (qw/ order_by limit offset /) {
        $query->{$_} = $options->{$_} if defined $options->{$_};
    }
    if (defined $options->{'state'}) {
        $query->{'where'}->{'+jub'}->{'-or'}->[1]->{'state'} = $options->{'state'};        
    }

    if ($self->api_name =~ /by_user_id/) {
        $query->{'where'}->{'usr'} = $search_value;
    } else {
        $query->{'where'}->{'+au'} = { 'home_ou' => $search_value };
    }

    my $pertinent_ids = $e->json_query($query);

    my %perm_test = ();
    for my $id_blob (@$pertinent_ids) {
        if ($rid != $id_blob->{usr_id}) {
            if (!defined $perm_test{ $id_blob->{home_ou} }) {
                $perm_test{ $id_blob->{home_ou} } = $e->allowed( ['user_request.view'], $id_blob->{home_ou} );
            }
            if (!$perm_test{ $id_blob->{home_ou} }) {
                next; # failed test
            }
        }
        my $aur_obj = $e->retrieve_acq_user_request([
            $id_blob->{id},
            {flesh => 1, flesh_fields => { "aur" => [ 'lineitem' ] } }
        ]);
        if (! $aur_obj) { next; }

        if ($aur_obj->lineitem()) {
            $aur_obj->lineitem()->clear_marc();
        }
        $conn->respond($aur_obj);
    }

    return undef;
}

__PACKAGE__->register_method (
    method    => 'update_user_request',
    api_name  => 'open-ils.acq.user_request.cancel.batch',
    stream    => 1,
    signature => {
        desc   => 'If given a cancel reason, will update the request with that reason, otherwise, this will delete the request altogether.  The '    .
                  'intention is for staff interfaces or processes to provide cancel reasons, and for patron interfaces to just delete the requests.' ,
        params => [
            { desc => 'Authentication token',              type => 'string' },
            { desc => 'ID or array of IDs for the user requests to cancel'  },
            { desc => 'Cancel Reason ID (optional)',       type => 'string' }
        ],
        return => {
            desc => 'progress object, event on error',
        }
    }
);
__PACKAGE__->register_method (
    method    => 'update_user_request',
    api_name  => 'open-ils.acq.user_request.set_no_hold.batch',
    stream    => 1,
    signature => {
        desc   => 'Remove the hold from a user request or set of requests',
        params => [
            { desc => 'Authentication token',              type => 'string' },
            { desc => 'ID or array of IDs for the user requests to modify'  }
        ],
        return => {
            desc => 'progress object, event on error',
        }
    }
);

sub update_user_request {
    my($self, $conn, $auth, $aur_ids, $cancel_reason) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $rid = $e->requestor->id;

    my $x = 1;
    my %perm_test = ();
    for my $id (@$aur_ids) {

        my $aur_obj = $e->retrieve_acq_user_request([
            $id,
            {   flesh => 1,
                flesh_fields => { "aur" => ['lineitem', 'usr'] }
            }
        ]) or return $e->die_event;

        my $context_org = $aur_obj->usr()->home_ou();
        $aur_obj->usr( $aur_obj->usr()->id() );

        if ($rid != $aur_obj->usr) {
            if (!defined $perm_test{ $context_org }) {
                $perm_test{ $context_org } = $e->allowed( ['user_request.update'], $context_org );
            }
            if (!$perm_test{ $context_org }) {
                next; # failed test
            }
        }

        if($self->api_name =~ /set_no_hold/) {
            if ($U->is_true($aur_obj->hold)) { 
                $aur_obj->hold(0); 
                $e->update_acq_user_request($aur_obj) or return $e->die_event;
            }
        }

        if($self->api_name =~ /cancel/) {
            if ( $cancel_reason ) {
                $aur_obj->cancel_reason( $cancel_reason );
                $e->update_acq_user_request($aur_obj) or return $e->die_event;
                create_user_request_events( $e, [ $aur_obj ], 'aur.rejected' );
            } else {
                $e->delete_acq_user_request($aur_obj);
            }
        }

        $conn->respond({maximum => scalar(@$aur_ids), progress => $x++});
    }

    $e->commit;
    return {complete => 1};
}

__PACKAGE__->register_method (
    method    => 'new_user_request',
    api_name  => 'open-ils.acq.user_request.create',
    signature => {
        desc   => 'Create a new user request object in the DB',
        param  => [
            { desc => 'Authentication token',   type => 'string' },
            { desc => 'User request data hash.  Hash keys match the fields for the "aur" object', type => 'object' }
        ],
        return => {
            desc => 'The created user request object, or event on error'
        }
    }
);

sub new_user_request {
    my($self, $conn, $auth, $form_data) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $rid = $e->requestor->id;
    my $target_user_fleshed;
    if (! defined $$form_data{'usr'}) {
        $$form_data{'usr'} = $rid;
    }
    if ($$form_data{'usr'} != $rid) {
        # See if the requestor can place the request on behalf of a different user.
        $target_user_fleshed = $e->retrieve_actor_user($$form_data{'usr'}) or return $e->die_event;
        $e->allowed('user_request.create', $target_user_fleshed->home_ou) or return $e->die_event;
    } else {
        $target_user_fleshed = $e->requestor;
        $e->allowed('CREATE_PURCHASE_REQUEST') or return $e->die_event;
    }
    if (! defined $$form_data{'pickup_lib'}) {
        if ($target_user_fleshed->ws_ou) {
            $$form_data{'pickup_lib'} = $target_user_fleshed->ws_ou;
        } else {
            $$form_data{'pickup_lib'} = $target_user_fleshed->home_ou;
        }
    }
    if (! defined $$form_data{'request_type'}) {
        $$form_data{'request_type'} = 1; # Books
    }
    my $aur_obj = new Fieldmapper::acq::user_request; 
    $aur_obj->isnew(1);
    $aur_obj->usr( $$form_data{'usr'} );
    $aur_obj->request_date( 'now' );
    for my $field ( keys %$form_data ) {
        if (defined $$form_data{$field} and $field !~ /^(id|lineitem|eg_bib|request_date|cancel_reason)$/) {
            $aur_obj->$field( $$form_data{$field} );
        }
    }

    $aur_obj = $e->create_acq_user_request($aur_obj) or return $e->die_event;

    $e->commit and create_user_request_events( $e, [ $aur_obj ], 'aur.created' );

    return $aur_obj;
}

sub create_user_request_events {
    my($e, $user_reqs, $hook) = @_;

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->connect;

    my %cached_usr_home_ou = ();
    for my $user_req (@$user_reqs) {
        my $home_ou = $cached_usr_home_ou{$user_req->usr};
        if (! $home_ou) {
            my $user = $e->retrieve_actor_user($user_req->usr) or return $e->die_event;
            $home_ou = $user->home_ou;
            $cached_usr_home_ou{$user_req->usr} = $home_ou;
        }
        my $req = $ses->request('open-ils.trigger.event.autocreate', $hook, $user_req, $home_ou);
        $req->recv;
    }

    $ses->disconnect;
    return undef;
}


__PACKAGE__->register_method(
	method => "po_note_CUD_batch",
	api_name => "open-ils.acq.po_note.cud.batch",
    stream => 1,
	signature => {
        desc => q/Manage purchase order notes/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "List of po_notes to manage", type => "array"},
        ],
        return => {desc => "Stream of successfully managed objects"}
    }
);

sub po_note_CUD_batch {
    my ($self, $conn, $auth, $notes) = @_;

    my $e = new_editor("xact"=> 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;
    # XXX perms

    my $total = @$notes;
    my $count = 0;

    foreach my $note (@$notes) {

        $note->editor($e->requestor->id);
        $note->edit_time("now");

        if ($note->isnew) {
            $note->creator($e->requestor->id);
            $note = $e->create_acq_po_note($note) or return $e->die_event;
        } elsif ($note->isdeleted) {
            $e->delete_acq_po_note($note) or return $e->die_event;
        } elsif ($note->ischanged) {
            $e->update_acq_po_note($note) or return $e->die_event;
        }

        unless ($note->isdeleted) {
            $note = $e->retrieve_acq_po_note($note->id) or
                return $e->die_event;
        }

        $conn->respond(
            {"maximum" => $total, "progress" => ++$count, "note" => $note}
        );
    }

    $e->commit and $conn->respond_complete or return $e->die_event;
}


# retrieves a lineitem, fleshes its PO and PL, checks perms
sub fetch_and_check_li {
    my $e = shift;
    my $li_id = shift;
    my $perm_mode = shift || 'read';

    my $li = $e->retrieve_acq_lineitem([
        $li_id,
        {   flesh => 1,
            flesh_fields => {jub => ['purchase_order', 'picklist']}
        }
    ]) or return $e->die_event;

    if(my $po = $li->purchase_order) {
        my $perms = ($perm_mode eq 'read') ? 'VIEW_PURCHASE_ORDER' : 'CREATE_PURCHASE_ORDER';
        return ($li, $e->die_event) unless $e->allowed($perms, $po->ordering_agency);

    } elsif(my $pl = $li->picklist) {
        my $perms = ($perm_mode eq 'read') ? 'VIEW_PICKLIST' : 'CREATE_PICKLIST';
        return ($li, $e->die_event) unless $e->allowed($perms, $pl->org_unit);
    }

    return ($li);
}


__PACKAGE__->register_method(
	method => "clone_distrib_form",
	api_name => "open-ils.acq.distribution_formula.clone",
    stream => 1,
	signature => {
        desc => q/Clone a distribution formula/,
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Original formula ID", type => 'integer'},
            {desc => "Name of new formula", type => 'string'},
        ],
        return => {desc => "ID of newly created formula"}
    }
);

sub clone_distrib_form {
    my($self, $client, $auth, $form_id, $new_name) = @_;

    my $e = new_editor("xact"=> 1, "authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    my $old_form = $e->retrieve_acq_distribution_formula($form_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_ACQ_DISTRIB_FORMULA', $old_form->owner);

    my $new_form = Fieldmapper::acq::distribution_formula->new;

    $new_form->owner($old_form->owner);
    $new_form->name($new_name);
    $e->create_acq_distribution_formula($new_form) or return $e->die_event;

    my $entries = $e->search_acq_distribution_formula_entry({formula => $form_id});
    for my $entry (@$entries) {
       my $new_entry = Fieldmapper::acq::distribution_formula_entry->new;
       $new_entry->$_($entry->$_()) for $entry->real_fields;
       $new_entry->formula($new_form->id);
       $new_entry->clear_id;
       $e->create_acq_distribution_formula_entry($new_entry) or return $e->die_event;
    }

    $e->commit;
    return $new_form->id;
}

__PACKAGE__->register_method(
	method => 'add_li_to_po',
	api_name	=> 'open-ils.acq.purchase_order.add_lineitem',
	signature => {
        desc => q/Adds a lineitem to an existing purchase order/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'The purchase order id', type => 'number'},
            {desc => 'The lineitem ID', type => 'number'},
        ],
        return => {desc => 'Streams a total versus completed counts object, event on error'}
    }
);

sub add_li_to_po {
    my($self, $conn, $auth, $po_id, $li_id) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $po = $e->retrieve_acq_purchase_order($po_id)
        or return $e->die_event;

    my $li = $e->retrieve_acq_lineitem($li_id)
        or return $e->die_event;

    return $e->die_event unless 
        $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);

    unless ($po->state =~ /new|pending/) {
        $e->rollback;
        return {success => 0, po => $po, error => 'bad-po-state'};
    }

    unless ($li->state =~ /new|order-ready|pending-order/) {
        $e->rollback;
        return {success => 0, li => $li, error => 'bad-li-state'};
    }

    $li->provider($po->provider);
    $li->purchase_order($po_id);
    $li->state('pending-order');
    update_lineitem($mgr, $li) or return $e->die_event;
    
    $e->commit;
    return {success => 1};
}

1;

