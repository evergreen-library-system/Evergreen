package OpenILS::OpenAPI::Controller::bib;
use OpenILS::OpenAPI::Controller;
use OpenILS::Utils::CStoreEditor q/new_editor/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Cat::AssetCommon;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use MARC::Record;

our $VERSION = 1;
our $U = "OpenILS::Application::AppUtils";

sub fetch_one_bib {
    my ($c, $bib) = @_;
    my $bre = new_editor()->retrieve_biblio_record_entry($bib);
    my $resp_type = $c->stash('eg_req_resolved_content_format') || 'json';
    return $bre->marc if ($resp_type eq 'xml');
    return MARC::Record->new_from_xml( $bre->marc, 'UTF-8', 'USMARC' )->as_usmarc if ($resp_type eq 'binary');
    return $bre;
}

sub update_bre_parts {
    my ($c, $ses, $bibid, $parts) = @_;
    $parts ||= {};

    my $e = new_editor(xact => 1, authtoken => $ses, personality => 'open-ils.pcrud');

    my $bib = $e->retrieve_biblio_record_entry($bibid) || die 'Could not retrieve record';

    for my $allowed_part ( qw/source owner share_depth/ ) {
        if (exists $$parts{$allowed_part}) { # they want to set it to something...
            if (defined $$parts{$allowed_part}) { # they want a value
                $bib->$allowed_part($$parts{$allowed_part});
            } else { # they want to unset the value
                $allowed_part = 'clear_'.$allowed_part;
                $bib->$allowed_part;
            }
        }
    }

    $e->update_biblio_record_entry($bib) || die 'Could not update record';
    $e->commit;

    return new_editor()->retrieve_biblio_record_entry($bibid);
}

sub fetch_one_bib_display_fields {
    my ($c, $bib, $map) = @_;
    $map ||= '""=>"-1"';

    return $U->simplereq(
        'open-ils.search',
        'open-ils.search.fetch.metabib.display_field.highlight.fleshed',
        $map => $bib
    );
}

sub fetch_one_bib_holdings {
    my ($c, $bib, $limit, $offset) = @_;

    my $acn = new_editor()->search_asset_call_number([
        { record => $bib,
          label => { '<>' => '##URI##'},
          deleted => 'f'
        },
        { order_by => { acn => [qw/label_sortkey label owning_lib/] },
          flesh => 2,
          flesh_fields => {
            acn => [qw/copies prefix suffix/],
            acp => [qw/status circ_lib location parts/]
          }
        }
    ]) or die "cn tree fetch failed";

    # flip CN->CP inside out
    my @copies;
    for my $cn (@$acn) {
        push @copies, map {
            $_->call_number($cn);
            $_->circ_lib($_->circ_lib->id);
            $_;
        } grep {
            !$U->is_true($_->deleted)
            and $U->is_true($_->opac_visible)
            and $U->is_true($_->status->opac_visible)
            and $U->is_true($_->location->opac_visible)
            and $U->is_true($_->circ_lib->opac_visible)
        } sort {
            $a->barcode cmp $b->barcode
        } @{$cn->copies};
        $cn->clear_copies
    }

    if ($limit) {
        $offset ||= 0;
        my $end_index = $offset + $limit - 1;
        $end_index = scalar(@copies) - 1 if $end_index > scalar(@copies) - 1;
        return [ @copies[$offset .. $end_index] ];
    }

    return \@copies;
}

sub item_by_barcode {
    my ($c, $barcode) = @_;
    my $copy = new_editor()->search_asset_copy({deleted => 'f', barcode => $barcode})->[0];
    $c->res->code(404) if (!$copy);
    return $copy;
}

sub fetch_new_items {
    my ($c, $limit, $offset, $age) = @_;
    $offset ||= 0;
    $limit ||= 100;

    my $filter = {deleted => 'f', active_date => {'!=' => undef}};
    $$filter{active_date} = {
        '>=' => {
            transform => 'age',
            params => ['now'],
            value => '-' . $age
        }
    } if ($age);

    my $order = {order_by => {acp => 'active_date DESC'}};
    if ($limit) {
        $$order{limit} = $limit;
        $$order{offset} = $offset;
    }

    return new_editor()->search_asset_copy([ $filter, $order ]);
}

sub delete_one_item {
    my ($c, $ses, $barcode) = @_;
    my $e = new_editor(authtoken=>$ses, xact=>1);

    my $copy = new_editor()->search_asset_copy({deleted => 'f', barcode => $barcode})->[0];
    do { $c->res->code(404); return {error=>"No copy found with barcode $barcode"}; }
        unless ($copy);

    $evt = OpenILS::Application::Cat::AssetCommon->delete_copy(
        $e, {all => 1}, $e->retrieve_asset_call_number($copy->call_number), $copy
    );

    if($evt) {
        $e->rollback;
        $c->res->code(400);
        return $evt;
    }

    $e->commit;

    return 1;
}

sub create_or_update_one_item {
    my ($c, $ses, $copy_blob, $barcode) = @_;

    my $copy;
    my %parts = (
        loan_duration => undef, fine_level => undef,
        copy_number => undef,
        mint_condition => undef, age_protect => undef,
        location => undef, circ_lib => undef,
        deposit => undef, deposit_amount => undef,
        circulate => undef, ref => undef, holdable => undef,
        price => undef, cost => undef,
        dummy_isbn => undef, dummy_author => undef, dummy_title => undef,
        circ_as_type => undef, circ_modifier => undef,
        opac_visible => undef
    );

    my $e = new_editor(authtoken=>$ses, xact=>1);

    if ($barcode) {
        $copy = item_by_barcode($c, $barcode);
        do { $c->res->code(404); return {error=>"No copy found with barcode $barcode"}; }
            unless ($copy);

        OpenILS::OpenAPI::Controller::apply_blob_to_object($copy, $copy_blob, \%parts);
        $copy->ischanged(1);

        $evt = OpenILS::Application::Cat::AssetCommon->update_fleshed_copies(
            $e, {all => 1}, undef, [$copy]
        );

        if($evt) {
            $e->rollback;
            $c->res->code(400);
            return $evt;
        }
    } else {
        do { $c->res->code(400); return {error=>"No record supplied for item in 'bib' property"}; }
            unless ($$copy_blob{bib} || $U->is_true($$copy_blob{precat}));

        do { $c->res->code(400); return {error=>"No call number supplied for item in 'call_number' property"}; }
            unless ($$copy_blob{call_number} || $U->is_true($$copy_blob{precat}));

        $parts{status} = OILS_COPY_STATUS_IN_PROCESS;
        $parts{loan_duration} = 2;
        $parts{fine_level} = 2;
        $parts{barcode} = undef;

        my $evt;
        my $vol;
        if ($U->is_true($$copy_blob{precat})) {
            $vol = $e->retrieve_asset_call_number(-1);
        } else {
            ($vol, $evt) = OpenILS::Application::Cat::AssetCommon->find_or_create_volume(
                $e, $$copy_blob{call_number}, $$copy_blob{bib}, $$copy_blob{circ_lib}
            );

            if($evt) {
                $e->rollback;
                $c->res->code(400);
                return $evt;
            }
        }

        $copy = Fieldmapper::asset::copy->new;
        OpenILS::OpenAPI::Controller::apply_blob_to_object($copy, $copy_blob, \%parts);

        if($evt = OpenILS::Application::Cat::AssetCommon->create_copy($e, $vol, $copy)) {
            $e->rollback;
            $c->res->code(400);
            return $evt;
        }
    }

    $e->commit;

    return $e->retrieve_asset_copy($copy->id);
}

1;
