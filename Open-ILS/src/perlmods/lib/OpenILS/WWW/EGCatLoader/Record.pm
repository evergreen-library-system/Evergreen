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
    $self->ctx->{page} = 'record';

    my $rec_id = $self->ctx->{page_args}->[0]
        or return Apache2::Const::HTTP_BAD_REQUEST;

    $self->ctx->{record} = $self->editor->retrieve_biblio_record_entry([
        $rec_id,
        {
            flesh => 2, 
            flesh_fields => {
                bre => ['call_numbers'],
                acn => ['copies'] # limit, paging, etc.
            }
        }
    ]);

    $self->ctx->{marc_xml} = XML::LibXML->new->parse_string($self->ctx->{record}->marc);

    return Apache2::Const::OK;
}

1;
