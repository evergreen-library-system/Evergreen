#-------------------------------------------------------------------------------
use Class::DBI;
package Class::DBI;

sub search_fti {
	my $self = shift;
	my @args = @_;
	if (ref($args[-1]) eq 'HASH') {
		$args[-1]->{_placeholder} = "to_tsquery('default',?)";
	} else {
		push @args, {_placeholder => "to_tsquery('default',?)"};
	}
	$self->_do_search("@@"  => @args);
}

#-------------------------------------------------------------------------------
package OpenILS::Application::Storage::FTS;
use OpenSRF::Utils::Logger qw/:level/;
my $log = 'OpenSRF::Utils::Logger';

sub compile {
	my $self = shift;
	my $term = shift;

	$self = ref($self) || $self;
	$self = bless {} => $self;

	$self->decompose($term);

	my $newterm = join('&', $self->words);

	if ($self->nots) {
		$newterm = '('.$newterm.')&('. join('|', $self->nots) . ')';
	}

	$newterm = OpenILS::Application::Storage->driver->quote($newterm);

	$self->{fts_query} = ["to_tsquery('default',$newterm)"];
	$self->{fts_query_nots} = [];
	$self->{fts_op} = '@@';

	return $self;
}


#-------------------------------------------------------------------------------
package OpenILS::Application::Storage::Driver::Pg;
use base qw/Class::DBI DBD::Pg OpenILS::Application::Storage/;
use DBI;
use DBD::Pg;
use OpenSRF::Utils::Logger qw/:level/;

__PACKAGE__->set_sql( retrieve_limited => 'SELECT * FROM __TABLE__ ORDER BY id LIMIT ?' );

my $_dbh;

sub db_Main {	
	return $_dbh if (defined $_dbh and $_dbh->ping);

	my $self = shift;

	my %args = (%OpenILS::Application::Storage::_db_params,@_);

	my %attrs = (	%{$self->_default_attributes},
			RootClass => 'DBIx::ContextualFetch',
			ShowErrorStatement => 1,
			RaiseError => 1,
			AutoCommit => 1,
			PrintError => 1,
			Taint => 1,
			pg_enable_utf8 => 1,
			FetchHashKeyName => 'NAME_lc',
			ChopBlanks => 1,
	);

	$log->debug(" Default attributes for this DB connection are:\n\t".join("\n\t",map { "$_\t==> $attrs{$_}" } keys %attrs), INTERNAL);

	$_dbh = DBI->connect( "dbi:Pg:host=$args{host};dbname=$args{database}",$args{user},$args{pw}, \%attrs );
	$_dbh->do("SET CLIENT_ENCODING TO 'SQL_ASCII';");

	return $_dbh;
}

#-------------------------------------------------------------------------------
package asset::call_number;
use base qw/OpenILS::App::Storage::CDBI/;

__PACKAGE__->table( 'asset.call_number' );
__PACKAGE__->sequence( 'asset.call_number_id_seq' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/record/ );

__PACKAGE__->has_a( record => 'biblio::record_entry' );
__PACKAGE__->has_many( copies => 'asset::copy' );



#-------------------------------------------------------------------------------
package asset::copy;
use base qw/OpenILS::App::Storage::CDBI/;

__PACKAGE__->table( 'asset.copy' );
__PACKAGE__->sequence( 'asset.copy_id_seq' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/call_number barcode/ );

#__PACKAGE__->has_a( call_number => 'asset::call_number' );



#-------------------------------------------------------------------------------
package biblio::record_entry;
use base qw/OpenILS::App::Storage::CDBI/;

__PACKAGE__->table( 'biblio.record_entry' );
__PACKAGE__->sequence( 'biblio.record_entry_id_seq' );
__PACKAGE__->columns( Primary => qw/id/ );

#__PACKAGE__->columns( Essential => qw/tcn_source tcn_value metarecord creator editor create_date edit_date source active deleted/ );
__PACKAGE__->columns( Others => qw/tcn_source tcn_value metarecord creator editor create_date edit_date source active deleted/ );

__PACKAGE__->has_a( note => 'biblio::record_note' );
__PACKAGE__->has_many( nodes => 'biblio::record_data' );

#__PACKAGE__->has_a( metarecord => 'metabib::metarecord' );
#__PACKAGE__->has_many( field_entries => 'metabib::field_entry' );
#__PACKAGE__->has_many( call_numbers => 'asset::call_number' );

#-------------------------------------------------------------------------------
package biblio::record_node::subnode;
sub _load { 
	my $intra_doc_id = shift;
	my $owner_doc = shift()->owner_doc;
	return (biblio::record_node->search( owner_doc => $owner_doc, intra_doc_id => $intra_doc_id ))[0];
}

package biblio::record_node;
use base qw/OpenILS::App::Storage::CDBI/;

__PACKAGE__->table( 'biblio.record_data' );
__PACKAGE__->sequence( 'biblio.record_data_id_seq' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Essential => qw/owner_doc intra_doc_id parent_node node_type namespace_uri name value/ );

__PACKAGE__->has_a( owner_doc => 'biblio::record_entry' );
__PACKAGE__->has_a(
	parent_node	=> 'biblio::record_node::subnode',
	inflate		=> sub { return biblio::record_node::subnode::_load(@_) },
);


#-------------------------------------------------------------------------------
package biblio::record_note;
use base qw/OpenILS::App::Storage::CDBI/;

__PACKAGE__->table( 'biblio.record_note' );
__PACKAGE__->sequence( 'biblio.record_note_id_seq' );
__PACKAGE__->columns( Primary => qw/id/ );
__PACKAGE__->columns( Stringify => qw/value/ );
__PACKAGE__->columns( Essential => qw/record value creator editor create_date edit_date/ );

__PACKAGE__->has_a( record_entry => 'biblio::record_entry' );

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

1;

