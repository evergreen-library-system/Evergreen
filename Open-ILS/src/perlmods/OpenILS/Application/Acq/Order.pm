package OpenILS::Application::Acq::BatchManager;
use strict; use warnings;

sub new {
    my($class, %args) = @_;
    my $self = bless(\%args, $class);
    $self->{args} = {
        lid => 0,
        li => 0,
        progress => 0,
        debits_accrued => 0,
        purchase_order => undef,
        picklist => undef,
        complete => 0
    };
    return $self;
}

sub respond {
    my($self, $other_args) = @_;
    $self->conn->respond({ %{$self->{args}}, %$other_args });
}
sub respond_complete {
    my($self, $other_args) = @_;
    $self->complete;
    $self->conn->respond_complete({ %{$self->{args}}, %$other_args });
}
sub total {
    my($self, $val) = @_;
    $self->{total} = $val if $val;
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
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::BibCommon;
use OpenILS::Application::Cat::AssetCommon;
my $U = 'OpenILS::Application::AppUtils';


# ----------------------------------------------------------------------------
# Lineitem
# ----------------------------------------------------------------------------
sub create_lineitem {
    my($mgr, $args) = @_;
    my $li = Fieldmapper::acq::lineitem->new;
    $li->creator($mgr->editor->requestor->id);
    $li->selector($li->creator);
    $li->editor($li->creator);
    $li->create_time('now');
    $li->edit_time('now');
    $li->state('new');
    $li->$_($$args{$_}) for keys %$args || ();
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
    return $mgr->editor->update_acq_lineitem($li);
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
    my($mgr, $args) = @_;
    my $lid = Fieldmapper::acq::lineitem_detail->new;
    $lid->$_($$args{$_}) for keys %$args || ();

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
# Picklist
# ----------------------------------------------------------------------------
sub create_picklist {
    my($mgr, $args) = @_;
    my $picklist = Fieldmapper::acq::picklist->new;
    $picklist->creator($mgr->editor->requestor->id);
    $picklist->owner($picklist->creator);
    $picklist->editor($picklist->creator);
    $picklist->create_time('now');
    $picklist->edit_time('now');
    $picklist->org_unit($mgr->editor->requestor->ws_ou);
    $picklist->owner($mgr->editor->requestor->id);
    $picklist->$_($$args{$_}) for keys %$args || ();
    $mgr->picklist($picklist);
    return $mgr->editor->create_acq_picklist($picklist);
}

sub update_picklist {
    my($mgr, $picklist) = @_;
    $picklist = $mgr->editor->retrieve_acq_picklist($picklist) unless ref $picklist;
    $picklist->edit_time('now');
    $picklist->editor($mgr->editor->requestor->id);
    return $mgr->editor->update_acq_picklist($picklist);
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
    return $mgr->editor->update_acq_purchase_order($po);
}

sub create_purchase_order {
    my($mgr, $args) = @_;
    my $po = Fieldmapper::acq::purchase_order->new;
    $po->creator($mgr->editor->requestor->id);
    $po->editor($mgr->editor->requestor->id);
    $po->owner($mgr->editor->requestor->id);
    $po->edit_time('now');
    $po->create_time('now');
    $po->ordering_agency($mgr->editor->requestor->ws_ou);
    $po->$_($$args{$_}) for keys %$args || ();
    return $mgr->editor->create_acq_purchase_order($po);
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
            $mgr = OpenILS::Application::Acq::BatchManager->new({editor => $e, conn => $conn});
            $picklist = zsearch_build_pl($mgr, $name);
            $first = 0;
        }

        my $result = $resp->content;
        my $count = $result->{count};
        $mgr->total( (($count < $search->{limit}) ? $count : $search->{limit})+1 );

        for my $rec (@{$result->{records}}) {

            my $li = create_lineitem($mgr, {
                picklist => $picklist->{id},
                source_label => $result->{service},
                marc => $rec->{marcxml},
                eg_bib_id => $rec->{bibid}
            });

            if($$options{respond_li}) {
                $li->attributes($mgr->editor->search_acq_lineitem_attr({lineitem => $li->id}))
                    if $$options{flesh_attrs};
                $li->clear_marc if $$options{clear_marc};
                $mgr->respond({lineitem => $li});
            } else {
                $mgr->respond;
            }
        }
    }

    $mgr->editor->commit;
    $mgr->respond_complete;
    return undef;
}

sub zsearch_build_pl {
    my($mgr, $name) = @_;

    $name ||= '';
    my $picklist = $mgr->editor->search_acq_picklist({owner=>$mgr->editor->requestor->id, name=>$name})->[0];
    if($name eq '' and $picklist) {
        return 0 unless delete_picklist($mgr, $picklist);
        $picklist = undef;
    }

    if($picklist) {
        update_picklist($mgr, $picklist) or return 0;
        return $picklist;
    } 

    return create_picklist($mgr, {name => $name});
}

1;
