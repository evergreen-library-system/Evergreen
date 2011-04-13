package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# context additions: 
#   record : bre object
sub load_record {
    my $self = shift;
    my $ctx = $self->ctx;
    $ctx->{page} = 'record';

    my $org = $self->cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $depth = $self->cgi->param('depth') || 0;
    my $copy_limit = int($self->cgi->param('copy_limit') || 10);
    my $copy_offset = int($self->cgi->param('copy_offset') || 0);

    my $rec_id = $ctx->{page_args}->[0]
        or return Apache2::Const::HTTP_BAD_REQUEST;

    # run copy retrieval in parallel to bib retrieval
    # XXX unapi
    my $copy_rec = OpenSRF::AppSession->create('open-ils.cstore')->request(
        'open-ils.cstore.json_query.atomic', 
        $self->mk_copy_query($rec_id, $org, $depth, $copy_limit, $copy_offset));

    my (undef, @rec_data) = $self->get_records_and_facets([$rec_id], undef, {flesh => '{holdings_xml,mra}'});
    $ctx->{bre_id} = $rec_data[0]->{id};
    $ctx->{marc_xml} = $rec_data[0]->{marc_xml};

    $ctx->{copies} = $copy_rec->gather(1);
    $ctx->{copy_limit} = $copy_limit;
    $ctx->{copy_offset} = $copy_offset;

    for my $expand ($self->cgi->param('expand')) {
        $ctx->{"expand_$expand"} = 1;
        if($expand eq 'marchtml') {
            $ctx->{marchtml} = $self->mk_marc_html($rec_id);
        } 
    }

    return Apache2::Const::OK;
}

sub mk_copy_query {
    my $self = shift;
    my $rec_id = shift;
    my $org = shift;
    my $depth = shift;
    my $copy_limit = shift;
    my $copy_offset = shift;

    my $query = {
        select => {
            acp => ['id', 'barcode', 'circ_lib', 'create_date', 'age_protect', 'holdable'],
            acpl => [
                {column => 'name', alias => 'copy_location'},
                {column => 'holdable', alias => 'location_holdable'}
            ],
            ccs => [
                {column => 'name', alias => 'copy_status'},
                {column => 'holdable', alias => 'status_holdable'}
            ],
            acn => [
                {column => 'label', alias => 'call_number_label'},
                {column => 'id', alias => 'call_number'}
            ],
            circ => ['due_date'],
        },
        from => {
            acp => {
                acn => {},
                acpl => {},
                ccs => {},
                circ => {type => 'left'},
                aou => {}
            }
        },
        where => {
            '+acp' => {
                deleted => 'f',
                call_number => {
                    in => {
                        select => {acn => ['id']},
                        from => 'acn',
                        where => {record => $rec_id}
                    }
                },
                circ_lib => {
                    in => {
                        select => {aou => [{
                            column => 'id', 
                            transform => 'actor.org_unit_descendants', 
                            result_field => 'id', 
                            params => [$depth]
                        }]},
                        from => 'aou',
                        where => {id => $org}
                    }
                }
            },
            '+acn' => {deleted => 'f'},
            '+circ' => {checkin_time => undef}
        },

        # Order is: copies with circ_lib=org, followed by circ_lib name, followed by call_number label
        order_by => [
            {class => 'aou', field => 'name'}, 
            {class => 'acn', field => 'label'}
        ],

        limit => $copy_limit,
        offset => $copy_offset
    };

    # Filter hidden items if this is the public catalog
    unless($self->ctx->{is_staff}) { 
        $query->{where}->{'+acp'}->{opac_visible} = 't';
        $query->{where}->{'+acpl'}->{opac_visible} = 't';
        $query->{where}->{'+ccs'}->{opac_visible} = 't';
    }

    return $query;
    #return $self->editor->json_query($query);
}

sub mk_marc_html {
    my($self, $rec_id) = @_;

    # could be optimized considerably by performing the xslt on the already fetched record
    return $U->simplereq(
        'open-ils.search', 
        'open-ils.search.biblio.record.html', $rec_id, 1);
}

1;
