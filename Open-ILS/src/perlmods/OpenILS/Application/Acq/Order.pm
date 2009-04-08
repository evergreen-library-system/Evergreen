package OpenILS::Application::Acq::BatchManager;
use strict; use warnings;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    $self->{args} = {
        lid => 0,
        li => 0,
        copies => 0,
        progress => 0,
        debits_accrued => 0,
        purchase_order => undef,
        picklist => undef,
        complete => 0
    };
    $self->{cache} = {};
    return $self;
}

sub conn {
    my($self, $val) = @_;
    $self->{conn} = $val if $val;
    return $self->{conn};
}
sub respond {
    my($self, %other_args) = @_;
    if($self->throttle and not %other_args) {
        return unless ($self->progress % $self->throttle) == 0;
    }
    $self->conn->respond({ %{$self->{args}}, %other_args });
}
sub respond_complete {
    my($self, %other_args) = @_;
    $self->complete;
    $self->conn->respond_complete({ %{$self->{args}}, %other_args });
    return undef;
}
sub total {
    my($self, $val) = @_;
    $self->{total} = $val if defined $val;
    return $self->{total};
}
sub purchase_order {
    my($self, $val) = @_;
    $self->{purchase_order} = $val if $val;
    return $self;
}
sub picklist {
    my($self, $val) = @_;
    $self->{picklist} = $val if $val;
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
    if($li->picklist) {
        return 0 unless update_picklist($mgr, $li->picklist);
    }
    $mgr->add_li;
    return $mgr->editor->create_acq_lineitem($li);
}

sub update_lineitem {
    my($mgr, $li) = @_;
    $li->edit_time('now');
    $li->editor($mgr->editor->requestor->id);
    return $li if $mgr->editor->update_acq_lineitem($li);
    return undef;
}

sub delete_lineitem {
    my($mgr, $li) = @_;
    $li = $mgr->editor->retrieve_acq_lineitem($li) unless ref $li;

    if($li->picklist) {
        return 0 unless update_picklist($mgr, $li->picklist);
    }

    if($li->purchase_order) {
        return 0 unless update_purchase_order($mgr, $li->purchase_order);
    }

    # delete the attached lineitem_details
    my $lid_ids = $mgr->editor->search_acq_lineitem_detail({lineitem => $li->id}, {idlist=>1});
    for my $lid_id (@$lid_ids) {
        return 0 unless delete_lineitem_detail($mgr, undef, $lid_id);
    }

    return $mgr->editor->delete_acq_lineitem($li);
}

# ----------------------------------------------------------------------------
# Lineitem Detail
# ----------------------------------------------------------------------------
sub create_lineitem_detail {
    my($mgr, %args) = @_;
    my $lid = Fieldmapper::acq::lineitem_detail->new;
    $lid->$_($args{$_}) for keys %args;

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

    my $li = $mgr->editor->retrieve_acq_lineitem($lid->lineitem) or return 0;
    return 0 unless update_lineitem($mgr, $li);
    return $mgr->editor->create_acq_lineitem_detail($lid);
}

sub delete_lineitem_detail {
    my($mgr, $lid) = @_;
    $lid = $mgr->editor->retrieve_acq_lineitem_detail($lid) unless ref $lid;
    return $mgr->editor->delete_acq_lineitem_detail($lid);
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
            my $find = "search_acq_" . $attr->$attr_type;
            my $attr_def_id = $mgr->editor->$find({code => $attr->attr_name}, {idlist=>1})->[0] or return 0;
            $attr->definition($attr_def_id);
        }
        return $mgr->editor->create_acq_lineitem_attr($attr);
    }
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
    $mgr->picklist($picklist);
    return $mgr->editor->create_acq_picklist($picklist);
}

sub update_picklist {
    my($mgr, $picklist) = @_;
    $picklist = $mgr->editor->retrieve_acq_picklist($picklist) unless ref $picklist;
    $picklist->edit_time('now');
    $picklist->editor($mgr->editor->requestor->id);
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
        return 0 unless update_lineitem($li);
    }

    # remove any picklist-specific object perms
    my $ops = $mgr->editor->search_permission_usr_object_perm_map({object_type => 'acqpl', object_id => "".$picklist->id});
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
    $po->edit_date('now');
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
    $mgr->purchase_order($po);
    return $mgr->editor->create_acq_purchase_order($po);
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
    unless($li->eg_bib_id) {
        create_bib($mgr, $li) or return 0;
    }

    my $li_details = $mgr->editor->search_acq_lineitem_detail({lineitem => $li_id}, {idlist=>1});

    # -----------------------------------------------------------------
    # for each lineitem_detail, create the volume if necessary, create 
    # a copy, and link them all together.
    # -----------------------------------------------------------------
    for my $lid_id (@{$li_details}) {

        my $lid = $mgr->editor->retrieve_acq_lineitem_detail($lid_id) or return 0;
        my $org = $lid->owning_lib;
        my $label = $lid->cn_label;

        my $volume = $mgr->cache($org, "cn.$label");
        unless($volume) {
            $volume = create_volume($li, $lid) or return 0;
            $mgr->cache($org, "cn.$label", $volume);
        }
        create_copy($mgr, $volume, $lid) or return 0;
    }

    return 1;
}

sub create_bib {
    my($mgr, $li) = @_;

    my $record = OpenILS::Application::Cat::BibCommon->biblio_record_xml_import(
        $mgr->editor, $li->marc, undef, undef, undef, 1); #$rec->bib_source

    if($U->event_code($record)) {
        $mgr->editor->event($record);
        $mgr->editor->rollback;
        return 0;
    }

    $li->eg_bib_id($record->id);
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
    my $mgr = OpenILS::Application::Acq::BatchManager->new(
        editor => $e, conn => $conn, throttle => 5);

    my $cache = OpenSRF::Utils::Cache->new;
    my $evt;

    my $data = $cache->get_cache("vandelay_import_spool_$key");
	my $purpose = $data->{purpose};
    my $filename = $data->{path};
    my $provider = $data->{provider};
    my $picklist = $data->{picklist};
    my $create_po = $data->{create_po};
    my $ordering_agency = $data->{ordering_agency};
    my $purchase_order;

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
        my $po = create_purchase_order($mgr, 
            ordering_agency => $ordering_agency,
            provider => $provider->id
        ) or return $mgr->editor->die_event;
    }

    $logger->info("acq processing MARC file=$filename");

    my $marctype = 'USMARC'; # ?
	my $batch = new MARC::Batch ($marctype, $filename);
	$batch->strict_off;

	my $count = 0;

	while(1) {

        my $r;
	    my $err;
		$count++;

        try { 
            $r = $batch->next;
        } catch Error with { $err = shift; };

        last unless $r;

        if($err) {
			$logger->warn("Proccessing of record $count in set $key failed with error $err.  Skipping this record");
            next;
		}

		try {

			(my $xml = $r->as_xml_record()) =~ s/\n//sog;
			$xml =~ s/^<\?xml.+\?\s*>//go;
			$xml =~ s/>\s+</></go;
			$xml =~ s/\p{Cc}//go;
			$xml = $U->entityize($xml);
			$xml =~ s/[\x00-\x1f]//go;

            my %args = (
                source_label => $provider->code,
                provider => $provider->id,
                marc => $xml,
            );

            $args{picklist} = $picklist->id if $picklist;
            if($purchase_order) {
                $args{purchase_order} = $purchase_order->id;
                $args{state} = 'on-order';
            }

            my $li = create_lineitem($mgr, %args);
            $mgr->respond;

            import_lineitem_details($mgr, $ordering_agency, $li) 
                or die $mgr->editor->event; # caught below

		} catch Error with {
			$err = shift;
			$logger->warn("Error importing ACQ record $count : $err");
		};

        return $e->event if $err or $e->died;
	}

	$e->commit;
    unlink($filename);
    $cache->delete_cache('vandelay_import_spool_' . $key);

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
        my $compiled = extract_lineitem_detail_data($mgr, $org_path, $holdings, $idx);
        last unless $compiled;

        for(1..$$compiled{quantity}) {
            create_lineitem_detail($mgr, 
                lineitem => $li->id,
                owning_lib => $$compiled{owning_lib},
                cn_label => $$compiled{call_number}.
                fund => $$compiled{fund},
                circ_modifier => $$compiled{circ_modifier},
                note => $$compiled{note}
            ) or return 0;
        }

        $mgr->respond;
        $idx++;
    }

    set_lineitem_attr(
        $mgr, 
        attr_name => 'estimated_price',
        attr_type => 'lineitem_provider_attr_definition',
        attr_value => $price,
        lineitem => $li->id
    ) or return 0;

    if($li->purchase_order) {
        create_lineitem_assets($mgr, $li->id) or return 0;
    }

    return 1;
}

sub extract_lineitem_detail_data {
    my($mgr, $org_path, $holdings, $index) = @_;

    my @data_list = { grep { $_->holding eq $index } @$holdings };
    my %compiled = map { $_->{attr} => $_->{data} } @data_list;
    my $base_org = $$org_path[0];

    my $killme = sub {
        my $msg = shift;
        $logger->error("Item import extraction error: $msg");
        $mgr->editor->rollback;
        $mgr->editor->event(OpenILS::Event->new('ACQ_IMPORT_ERROR', payload => $msg));
        return 0;
    };

    $compiled{quantity} ||= 1;

    # ---------------------------------------------------------------------
    # Fund
    my $code = $compiled{fund_code};
    return $killme->("no fund code provided") unless $code;

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
    return $killme->("no owning_lib defined") unless $sn;
    my $org_id = 
        $mgr->cache($base_org, "orgsn.$sn") ||
            $mgr->editor->search_actor_org_unit({shortname => $sn}, {idlist => 1})->[0];
    return $killme->("invalid owning_lib defined: $sn") unless $org_id;
    $compiled{owning_lib} = $org_id;
    $mgr->cache($$org_path[0], "orgsn.$sn", $org_id);


    # ---------------------------------------------------------------------
    # Circ Modifier
    my $name = $compiled{circ_modifier};
    return $killme->("no circ_modifier defined") unless $name;
    my $mod = 
        $mgr->cache($base_org, "mod.$name") ||
            $mgr->editor->search_config_circ_modifier({code => $name, {idlist => 1}})->[0];
    return $killme->("invlalid circ_modifier $name") unless $mod;
    $compiled{circ_modifier} = $mod;
    $mgr->cache($base_org, "mod.$name", $mod);

    # ---------------------------------------------------------------------
    # Shelving Location
    $name = $compiled{copy_location};
    return $killme->("no copy_location defined") unless $name;
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


1;
