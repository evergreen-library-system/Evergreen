package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::metabib;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

sub create_full_rec {
        my $self = shift;
        my $client = shift;
        my $metadata = shift;

        try {
                my $rec = biblio::record_entry->create($metadata);
                $client->respond( $rec->id );
        } catch Error with {
                $client->respond( 0 );
        };

        return undef;
}
__PACKAGE__->register_method(
        method          => 'create_full_rec',
        api_name        => 'open-ils.storage.metabib.record_entry.create',
        api_level       => 1,
        argc            => 1,
	doxy		=> <<TEXT
/** Method to create a "full_rec" (Koha) nodeset in the DB.
  * ....
  */
int open-ils.storage.metabib.record_entry.create ( full_rec_nodeset* );

TEXT
);
