package OpenILS::Application::Acq::BatchManager;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use strict; use warnings;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    $self->{args} = {
        lid => 0,
        li => 0,
        copies => 0,
        bibs => 0,
        progress => 0,
        debits_accrued => 0,
        purchase_order => undef,
        picklist => undef,
        complete => 0,
        indexed => 0,
        total => 0
    };
    $self->{ingest_queue} = [];
    $self->{cache} = {};
    $self->throttle(5) unless $self->throttle;
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
}
sub respond_complete {
    my($self, %other_args) = @_;
    $self->complete;
    $self->conn->respond_complete({ %{$self->{args}}, %other_args });
    return undef;
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

sub ingest_ses {
    my($self, $val) = @_;
    $self->{ingest_ses} = $val if $val;
    return $self->{ingest_ses};
}

sub push_ingest_queue {
    my($self, $rec_id) = @_;

    $self->ingest_ses(OpenSRF::AppSession->connect('open-ils.ingest'))
        unless $self->ingest_ses;

    my $req = $self->ingest_ses->request('open-ils.ingest.full.biblio.record', $rec_id);

    push(@{$self->{ingest_queue}}, $req);
}

sub process_ingest_records {
    my $self = shift;
    return unless @{$self->{ingest_queue}};

    for my $req (@{$self->{ingest_queue}}) {

        try { 
            $req->gather(1); 
            $self->{args}->{indexed} += 1;
            $self->{args}->{progress} += 1;
        } otherwise {};

        $self->respond;
    }
    $self->ingest_ses->disconnect;
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
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::EX q/:try/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML;
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
    return $mgr->editor->create_acq_lineitem($li);
}

sub update_lineitem {
    my($mgr, $li) = @_;
    $li->edit_time('now');
    $li->editor($mgr->editor->requestor->id);
    $mgr->add_li;
    return $li if $mgr->editor->update_acq_lineitem($li);
    return undef;
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
sub create_lineitem_list_assets {
    my($mgr, $li_ids) = @_;
    # create the bibs/volumes/copies and ingest the records
    for my $li_id (@$li_ids) {
        $mgr->editor->xact_begin;
        my $data = create_lineitem_assets($mgr, $li_id) or return undef;
        $mgr->editor->xact_commit;
        $mgr->push_ingest_queue($data->{li}->eg_bib_id) if $data->{new_bib};
        $mgr->respond;
    }
    $mgr->process_ingest_records;
    return 1;
}

# ----------------------------------------------------------------------------
# if all of the lineitem details for this lineitem have 
# been received, mark the lineitem as received
# returns 1 on non-received, li on received, 0 on error
# ----------------------------------------------------------------------------
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
    update_lineitem($mgr, $li) or return 0;
    return 1 if $skip_complete_check;

    return check_purchase_order_received($mgr, $li->purchase_order);
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

# ----------------------------------------------------------------------------
# Lineitem Detail
# ----------------------------------------------------------------------------
sub create_lineitem_detail {
    my($mgr, %args) = @_;
    my $lid = Fieldmapper::acq::lineitem_detail->new;
    $lid->$_($args{$_}) for keys %args;
    $lid->clear_id;
    $mgr->editor->create_acq_lineitem_detail($lid) or return 0;
    $mgr->add_lid;

    # create some default values
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

    if(!$lid->circ_modifier and my $mod = get_default_circ_modifier($mgr, $lid->owning_lib)) {
        $lid->circ_modifier($mod);
    }

    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;
    return $lid;
}

sub get_default_circ_modifier {
    my($mgr, $org) = @_;
    my $mod = $mgr->cache($org, 'def_circ_mod');
    return $mod if $mod;
    $mod = $U->ou_ancestor_setting_value($org, 'acq.default_circ_modifier');
    return $mgr->cache($org, 'def_circ_mod', $mod) if $mod;
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

    $lid->recv_time('now');
    $e->update_acq_lineitem_detail($lid) or return 0;

    my $copy = $e->retrieve_asset_copy($lid->eg_copy_id) or return 0;
    $copy->status(OILS_COPY_STATUS_IN_PROCESS);
    $copy->edit_date('now');
    $copy->editor($e->requestor->id);
    $e->update_asset_copy($copy) or return 0;

    if($lid->fund_debit) {
        $lid->fund_debit->encumbrance('f');
        $e->update_acq_fund_debit($lid->fund_debit) or return 0;
    }

    $mgr->add_lid;

    return 1 if $skip_complete_check;

    my $li = check_lineitem_received($mgr, $lid->lineitem) or return 0;
    return 1 if $li == 1; # li not received

    return check_purchase_order_received($mgr, $li->purchase_order);
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

    $lid->clear_recv_time;
    $e->update_acq_lineitem_detail($lid) or return 0;

    my $copy = $e->retrieve_asset_copy($lid->eg_copy_id) or return 0;
    $copy->status(OILS_COPY_STATUS_ON_ORDER);
    $copy->edit_date('now');
    $copy->editor($e->requestor->id);
    $e->update_asset_copy($copy) or return 0;

    if($lid->fund_debit) {
        $lid->fund_debit->encumbrance('t');
        $e->update_acq_fund_debit($lid->fund_debit) or return 0;
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

sub get_li_price {
    my $li = shift;
    my $attrs = $li->attributes;
    my ($marc_estimated, $local_estimated, $local_actual, $prov_estimated, $prov_actual);

    for my $attr (@$attrs) {
        if($attr->attr_name eq 'estimated_price') {
            $local_estimated = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_local_attr_definition';
            $prov_estimated = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_prov_attr_definition';
            $marc_estimated = $attr->attr_value
                if $attr->attr_type eq 'lineitem_marc_attr_definition';

        } elsif($attr->attr_name eq 'actual_price') {
            $local_actual = $attr->attr_value     
                if $attr->attr_type eq 'lineitem_local_attr_definition';
            $prov_actual = $attr->attr_value 
                if $attr->attr_type eq 'lineitem_prov_attr_definition';
        }
    }

    return ($local_actual, 1) if $local_actual;
    return ($prov_actual, 2) if $prov_actual;
    return ($local_estimated, 1) if $local_estimated;
    return ($prov_estimated, 2) if $prov_estimated;
    return ($marc_estimated, 3);
}


# ----------------------------------------------------------------------------
# Lineitem Debits
# ----------------------------------------------------------------------------
sub create_lineitem_debits {
    my($mgr, $li, $price, $ptype) = @_; 

    ($price, $ptype) = get_li_price($li) unless $price;

    unless($price) {
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

        create_lineitem_detail_debit($mgr, $li, $lid, $price, $ptype) or return 0;
    }

    return 1;
}


# flesh li->provider
# flesh lid->fund
# ptype 1=local, 2=provider, 3=marc
sub create_lineitem_detail_debit {
    my($mgr, $li, $lid, $price, $ptype) = @_;

    unless(ref $li and ref $li->provider) {
       $li = $mgr->editor->retrieve_acq_lineitem([
            $li,
            {   flesh => 1,
                flesh_fields => {jub => ['provider']},
            }
        ]);
    }

    unless(ref $lid and ref $lid->fund) {
        $lid = $mgr->editor->retrieve_acq_lineitem_detail([
            $lid,
            {   flesh => 1, 
                flesh_fields => {acqlid => ['fund']}
            }
        ]);
    }

    my $ctype = $lid->fund->currency_type;
    my $amount = $price;

    if($ptype == 2) { # price from vendor
        $ctype = $li->provider->currency_type;
        $amount = currency_conversion($mgr, $ctype, $lid->fund->currency_type, $price);
    }

    my $debit = create_fund_debit(
        $mgr, 
        fund => $lid->fund->id,
        origin_amount => $price,
        origin_currency_type => $ctype,
        amount => $amount
    ) or return 0;

    $lid->fund_debit($debit->id);
    $lid->fund($lid->fund->id);
    $mgr->editor->update_acq_lineitem_detail($lid) or return 0;
    return $debit;
}


# ----------------------------------------------------------------------------
# Fund Debit
# ----------------------------------------------------------------------------
sub create_fund_debit {
    my($mgr, %args) = @_;
    my $debit = Fieldmapper::acq::fund_debit->new;
    $debit->debit_type('purchase');
    $debit->encumbrance('t');
    $debit->$_($args{$_}) for keys %args;
    $debit->clear_id;
    $mgr->add_debit($debit->amount);
    return $mgr->editor->create_acq_fund_debit($debit);
}

sub currency_conversion {
    my($mgr, $src_currency, $dest_currency, $amount) = @_;
    my $result = $mgr->editor->json_query(
        {from => ['acq.exchange_ratio', $src_currency, $dest_currency, $amount]});
    return $result->[0]->{'acq.exchange_ratio'};
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
    $mgr->picklist($picklist);
    return $picklist if $mgr->editor->update_acq_picklist($picklist);
    return undef;
}

sub delete_picklist {
    my($mgr, $picklist) = @_;
    $picklist = $mgr->editor->retrieve_acq_picklist($picklist) unless ref $picklist;

    # delete all 'new' lineitems
    my $lis = $mgr->editor->search_acq_lineitem({picklist => $picklist->id, state => 'new'});
    for my $li (@$lis) {
        return 0 unless delete_lineitem($mgr, $li);
    }

    # detach all non-'new' lineitems
    $lis = $mgr->editor->search_acq_lineitem({picklist => $picklist->id, state => {'!=' => 'new'}});
    for my $li (@$lis) {
        $li->clear_picklist;
        return 0 unless update_lineitem($mgr, $li);
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
    return $po if $mgr->editor->update_acq_purchase_order($po);
    return undef;
}

sub create_purchase_order {
    my($mgr, %args) = @_;
    my $po = Fieldmapper::acq::purchase_order->new;
    $po->creator($mgr->editor->requestor->id);
    $po->editor($mgr->editor->requestor->id);
    $po->owner($mgr->editor->requestor->id);
    $po->edit_time('now');
    $po->create_time('now');
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

    return 1 if @$non_recv_li;

    my $po = $mgr->editor->retrieve_acq_purchase_order($po_id);
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

    # -----------------------------------------------------------------
    # first, create the bib record if necessary
    # -----------------------------------------------------------------
    my $new_bib = 0;
    unless($li->eg_bib_id) {
        create_bib($mgr, $li) or return 0;
        $new_bib = 1;
    }

    my $li_details = $mgr->editor->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});

    # -----------------------------------------------------------------
    # for each lineitem_detail, create the volume if necessary, create 
    # a copy, and link them all together.
    # -----------------------------------------------------------------
    for my $lid_id (@{$li_details}) {

        my $lid = $mgr->editor->retrieve_acq_lineitem_detail($lid_id) or return 0;
        next if $lid->eg_copy_id;

        my $org = $lid->owning_lib;
        my $label = $lid->cn_label;
        my $bibid = $li->eg_bib_id;

        my $volume = $mgr->cache($org, "cn.$bibid.$label");
        unless($volume) {
            $volume = create_volume($mgr, $li, $lid) or return 0;
            $mgr->cache($org, "cn.$bibid.$label", $volume);
        }
        create_copy($mgr, $volume, $lid) or return 0;
    }

    return { li => $li, new_bib => $new_bib };
}

sub create_bib {
    my($mgr, $li) = @_;

    my $record = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
        $mgr->editor, 
        $li->marc, 
        undef, 
        undef, 
        1, # override tcn collisions
        1, # no-ingest
        undef # $rec->bib_source
    ); 

    if($U->event_code($record)) {
        $mgr->editor->event($record);
        $mgr->editor->rollback;
        return 0;
    }

    $li->eg_bib_id($record->id);
    $mgr->add_bib;
    return update_lineitem($mgr, $li);
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
    my($mgr, $volume, $lid) = @_;
    my $copy = Fieldmapper::asset::copy->new;
    $copy->isnew(1);
    $copy->loan_duration(2);
    $copy->fine_level(2);
    $copy->status(OILS_COPY_STATUS_ON_ORDER);
    $copy->barcode($lid->barcode);
    $copy->location($lid->location);
    $copy->call_number($volume->id);
    $copy->circ_lib($volume->owning_lib);
    $copy->circ_modifier($lid->circ_modifier);

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
        my $count = $result->{count};
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
    method => 'upload_records',
    api_name => 'open-ils.acq.process_upload_records',
    stream => 1,
);

sub upload_records {
    my($self, $conn, $auth, $key) = @_;

	my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $cache = OpenSRF::Utils::Cache->new;

    my $data = $cache->get_cache("vandelay_import_spool_$key");
	my $purpose = $data->{purpose};
    my $filename = $data->{path};
    my $provider = $data->{provider};
    my $picklist = $data->{picklist};
    my $create_po = $data->{create_po};
    my $ordering_agency = $data->{ordering_agency};
    my $create_assets = $data->{create_assets};
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
    }

    if($create_po) {
        $po = create_purchase_order($mgr, 
            ordering_agency => $ordering_agency,
            provider => $provider->id
        ) or return $mgr->editor->die_event;
    }

    $logger->info("acq processing MARC file=$filename");

    my $marctype = 'USMARC'; # ?
	my $batch = new MARC::Batch ($marctype, $filename);
	$batch->strict_off;

	my $count = 0;
    my @li_list;

	while(1) {

	    my $err;
        my $xml;
		$count++;
        my $r;

		try {
            $r = $batch->next;
        } catch Error with {
            $err = shift;
			$logger->warn("Proccessing of record $count in set $key failed with error $err.  Skipping this record");
        };

        next if $err;
        last unless $r;

		try {
            ($xml = $r->as_xml_record()) =~ s/\n//sog;
            $xml =~ s/^<\?xml.+\?\s*>//go;
            $xml =~ s/>\s+</></go;
            $xml =~ s/\p{Cc}//go;
            $xml = $U->entityize($xml);
            $xml =~ s/[\x00-\x1f]//go;

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
            $args{state} = 'on-order';
        }

        my $li = create_lineitem($mgr, %args) or return $mgr->editor->die_event;
        $mgr->respond;
        $li->provider($provider); # flesh it, we'll need it later

        import_lineitem_details($mgr, $ordering_agency, $li) or return $mgr->editor->die_event;
        $mgr->respond;

        push(@li_list, $li->id);
        $mgr->respond;
	}

	$e->commit;
    unlink($filename);
    $cache->delete_cache('vandelay_import_spool_' . $key);

    if($create_assets) {
        create_lineitem_list_assets($mgr, \@li_list) or return $e->die_event;
    }

    return $mgr->respond_complete;
}

sub import_lineitem_details {
    my($mgr, $ordering_agency, $li) = @_;

    my $holdings = $mgr->editor->json_query({from => ['acq.extract_provider_holding_data', $li->id]});
    return 1 unless @$holdings;
    my $org_path = $U->get_org_ancestors($ordering_agency);
    $org_path = [ reverse (@$org_path) ];
    my $price;

    my $idx = 1;
    while(1) {
        # create a lineitem detail for each copy in the data

        my $compiled = extract_lineitem_detail_data($mgr, $org_path, $holdings, $idx);
        last unless defined $compiled;
        return 0 unless $compiled;

        # this takes the price of the last copy and uses it as the lineitem price
        # need to determine if a given record would include different prices for the same item
        $price = $$compiled{price};

        for(1..$$compiled{quantity}) {
            my $lid = create_lineitem_detail($mgr, 
                lineitem => $li->id,
                owning_lib => $$compiled{owning_lib},
                cn_label => $$compiled{call_number},
                fund => $$compiled{fund},
                circ_modifier => $$compiled{circ_modifier},
                note => $$compiled{note},
                location => $$compiled{copy_location}
            ) or return 0;
        }

        $mgr->respond;
        $idx++;
    }

    # set the price attr so we'll know the source of the price
    set_lineitem_attr(
        $mgr, 
        attr_name => 'estimated_price',
        attr_type => 'lineitem_local_attr_definition',
        attr_value => $price,
        lineitem => $li->id
    ) or return 0;

    # if we're creating a purchase order, create the debits
    if($li->purchase_order) {
        create_lineitem_debits($mgr, $li, $price, 2) or return 0;
        $mgr->respond;
    }

    return 1;
}

# return hash on success, 0 on error, undef on no more holdings
sub extract_lineitem_detail_data {
    my($mgr, $org_path, $holdings, $index) = @_;

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

    $compiled{quantity} ||= 1;

    # ---------------------------------------------------------------------
    # Fund
    my $code = $compiled{fund_code};
    return $killme->('no fund code provided') unless $code;

    my $fund = $mgr->cache($base_org, "fund.$code");
    unless($fund) {
        # search up the org tree for the most appropriate fund
        for my $org (@$org_path) {
            $fund = $mgr->editor->search_acq_fund(
                {org => $org, code => $code, year => DateTime->now->year}, {idlist => 1})->[0];
            last if $fund;
        }
    }
    return $killme->("no fund with code $code at orgs [@$org_path]") unless $fund;
    $compiled{fund} = $fund;
    $mgr->cache($base_org, "fund.$code", $fund);


    # ---------------------------------------------------------------------
    # Owning lib
    my $sn = $compiled{owning_lib};
    return $killme->('no owning_lib defined') unless $sn;
    my $org_id = 
        $mgr->cache($base_org, "orgsn.$sn") ||
            $mgr->editor->search_actor_org_unit({shortname => $sn}, {idlist => 1})->[0];
    return $killme->("invalid owning_lib defined: $sn") unless $org_id;
    $compiled{owning_lib} = $org_id;
    $mgr->cache($$org_path[0], "orgsn.$sn", $org_id);


    # ---------------------------------------------------------------------
    # Circ Modifier
    my $mod;
    $code = $compiled{circ_modifier};

    if($code) {

        $mod = $mgr->cache($base_org, "mod.$code") ||
            $mgr->editor->retrieve_config_circ_modifier($code);
        return $killme->("invlalid circ_modifier $code") unless $mod;
        $mgr->cache($base_org, "mod.$code", $mod);

    } else {
        # try the default
        $mod = get_default_circ_modifier($mgr, $base_org)
            or return $killme->('no circ_modifier defined');
    }

    $compiled{circ_modifier} = $mod;


    # ---------------------------------------------------------------------
    # Shelving Location
    my $name = $compiled{copy_location};
    return $killme->('no copy_location defined') unless $name;
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
    }
);

sub create_po_assets {
    my($self, $conn, $auth, $po_id) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $po = $e->retrieve_acq_purchase_order($po_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('IMPORT_PURCHASE_ORDER_ASSETS', $po->ordering_agency);

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

    create_lineitem_list_assets($mgr, $li_ids) or return $e->die_event;

    $e->xact_begin;
    update_purchase_order($mgr, $po) or return $e->die_event;
    $e->commit;

    return $mgr->respond_complete;
}



__PACKAGE__->register_method(
	method => 'create_purchase_order_api',
	api_name	=> 'open-ils.acq.purchase_order.create',
	signature => {
        desc => 'Creates a new purchase order',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'purchase_order to create', type => 'object'}
        ],
        return => {desc => 'The purchase order id, Event on failure'}
    }
);

sub create_purchase_order_api {
    my($self, $conn, $auth, $po, $args) = @_;
    $args ||= {};

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PURCHASE_ORDER', $po->ordering_agency);
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    # create the PO
    my %pargs = (ordering_agency => $e->requestor->ws_ou);
    $pargs{provider} = $po->provider if $po->provider;
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
            update_lineitem($mgr, $li) or return $e->die_event;
            $mgr->respond;

            create_lineitem_debits($mgr, $li) or return $e->die_event;
        }
    }

    # commit before starting the asset creation
    $e->xact_commit;

    if($li_ids and $$args{create_assets}) {
        create_lineitem_list_assets($mgr, $li_ids) or return $e->die_event;
    }

    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
	method => 'lineitem_detail_CUD_batch',
	api_name => 'open-ils.acq.lineitem_detail.cud.batch',
    stream => 1,
	signature => {
        desc => q/Creates a new purchase order line item detail.  
            Additionally creates the associated fund_debit/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of lineitem_details to create', type => 'array'},
        ],
        return => {desc => 'Streaming response of current position in the array'}
    }
);

sub lineitem_detail_CUD_batch {
    my($self, $conn, $auth, $li_details) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    # XXX perms

    $mgr->total(scalar(@$li_details));
    
    my %li_cache;

    for my $lid (@$li_details) {

        my $li = $li_cache{$lid->lineitem} || $e->retrieve_acq_lineitem($lid->lineitem);

        if($lid->isnew) {
            create_lineitem_detail($mgr, %{$lid->to_bare_hash}) or return $e->die_event;

        } elsif($lid->ischanged) {
            $e->update_acq_lineitem_detail($lid) or return $e->die_event;

        } elsif($lid->isdeleted) {
            delete_lineitem_detail($mgr, $lid) or return $e->die_event;
        }

        $mgr->respond(li => $li);
        $li_cache{$lid->lineitem} = $li;
    }

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
	method => 'receive_po_api',
	api_name	=> 'open-ils.acq.purchase_order.receive'
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


__PACKAGE__->register_method(
	method => 'receive_lineitem_detail_api',
	api_name	=> 'open-ils.acq.lineitem_detail.receive',
	signature => {
        desc => 'Mark a lineitem_detail as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub receive_lineitem_detail_api {
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

    return $e->die_event unless $e->allowed(
        'RECEIVE_PURCHASE_ORDER', $lid->lineitem->purchase_order->ordering_agency);

    receive_lineitem_detail($mgr, $lid_id) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'receive_lineitem_api',
	api_name	=> 'open-ils.acq.lineitem.receive',
	signature => {
        desc => 'Mark a lineitem as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
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

    receive_lineitem($mgr, $li_id) or return $e->die_event;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method => 'rollback_receive_po_api',
	api_name	=> 'open-ils.acq.purchase_order.receive.rollback'
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
	method => 'rollback_receive_lineitem_detail_api',
	api_name	=> 'open-ils.acq.lineitem_detail.receive.rollback',
	signature => {
        desc => 'Mark a lineitem_detail as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
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
    rollback_receive_lineitem_detail($mgr, $lid_id) or return $e->die_event;

    $li->state('on-order');
    $po->state('on-order');
    udpate_lineitem($mgr, $li) or return $e->die_event;
    udpate_purchase_order($mgr, $po) or return $e->die_event;

    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => 'rollback_receive_lineitem_api',
	api_name	=> 'open-ils.acq.lineitem.receive.rollback',
	signature => {
        desc => 'Mark a lineitem as received',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem detail ID', type => 'number'}
        ],
        return => {desc => '1 on success, Event on error'}
    }
);

sub rollback_receive_lineitem_api {
    my($self, $conn, $auth, $li_id) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    my $li = $e->retrieve_acq_lineitem_detail([
        $li_id, {
            flesh => 1,
            flesh_fields => {
                jub => ['purchase_order']
            }
        }
    ]);
    my $po = $li->purchase_order;

    return $e->die_event unless $e->allowed('RECEIVE_PURCHASE_ORDER', $po->ordering_agency);

    rollback_receive_lineitem($mgr, $li_id) or return $e->die_event;

    $po->state('on-order');
    update_purchase_order($mgr, $po) or return $e->die_event;

    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method => 'set_lineitem_price_api',
	api_name	=> 'open-ils.acq.lineitem.price.set',
	signature => {
        desc => 'Set lineitem price.  If debits already exist, update them as well',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'lineitem ID', type => 'number'}
        ],
        return => {desc => 'status blob, Event on error'}
    }
);

sub set_lineitem_price_api {
    my($self, $conn, $auth, $li_id, $price, $currency) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $mgr = OpenILS::Application::Acq::BatchManager->new(editor => $e, conn => $conn);

    # XXX perms

    my $li = $e->retrieve_acq_lineitem($li_id) or return $e->die_event;

    # update the local attr for estimated price
    set_lineitem_attr(
        $mgr, 
        attr_name => 'estimated_price',
        attr_type => 'lineitem_local_attr_definition',
        attr_value => $price,
        lineitem => $li_id
    ) or return $e->die_event;

    my $lid_ids = $e->search_acq_lineitem_detail(
        {lineitem => $li_id, fund_debit => {'!=' => undef}}, 
        {idlist => 1}
    );

    for my $lid_id (@$lid_ids) {

        my $lid = $e->retrieve_acq_lineitem_detail([
            $lid_id, {
            flesh => 1, flesh_fields => {acqlid => ['fund', 'fund_debit']}}
        ]);

        # onless otherwise specified, assume currency of new price is same as currency type of the fund
        $currency ||= $lid->fund->currency_type;
        my $amount = $price;

        if($lid->fund->currency_type ne $currency) {
            $amount = currency_conversion($mgr, $currency, $lid->fund->currency_type, $price);
        }
        
        $lid->fund_debit->origin_currency_type($currency);
        $lid->fund_debit->origin_amount($price);
        $lid->fund_debit->amount($amount);

        $e->update_acq_fund_debit($lid->fund_debit) or return $e->die_event;
        $mgr->add_lid;
        $mgr->respond;
    }

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
	method => 'clone_picklist_api',
	api_name	=> 'open-ils.acq.picklist.clone',
	signature => {
        desc => 'Clones a picklist, including lineitem and lineitem details',
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

    for my $li_id (@$li_ids) {

        # copy the lineitems
        my $li = $e->retrieve_acq_lineitem($li_id);
        my $new_li = create_lineitem($mgr, %{$li->to_bare_hash}, picklist => $new_pl->id) or return $e->die_event;

        my $lid_ids = $e->search_acq_lineitem_detail({lineitem => $li_id}, {idlist => 1});
        for my $lid_id (@$lid_ids) {

            # copy the lineitem details
            my $lid = $e->retrieve_acq_lineitem_detail($lid_id);
            create_lineitem_detail($mgr, %{$lid->to_bare_hash}, lineitem => $new_li->id) or return $e->die_event;
        }

        $mgr->respond;
    }

    $e->commit;
    return $mgr->respond_complete;
}


__PACKAGE__->register_method(
	method => 'merge_picklist_api',
	api_name	=> 'open-ils.acq.picklist.merge',
	signature => {
        desc => 'Merges 2 or more picklists into a single list',
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

    $e->commit;
    return $mgr->respond_complete;
}



1;
