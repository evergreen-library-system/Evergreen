package OpenILS::Application::Storage::Publisher::authority;
use base qw/OpenILS::Application::Storage::Publisher/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils::Cache;
use Data::Dumper;
use Digest::MD5 qw/md5_hex/;
use XML::LibXML;
use Time::HiRes qw/time sleep/;
use Unicode::Normalize;

my $log = 'OpenSRF::Utils::Logger';

$VERSION = 1;

my $parser = XML::LibXML->new;

sub find_authority_marc {
	my $self = shift;
	my $client = shift;
	my %args = @_;
	
	my $term = NFD(lc($args{term}));
	my $tag = $args{tag};
	my $subfield = $args{subfield};
	my $limit = $args{limit} || 100;
	my $offset = $args{offset} || 0;

	if ($limit) {
		$limit = "LIMIT $limit";
	} else {
		$limit = '';
	}

	if ($offset) {
		$offset = "OFFSET $offset";
	} else {
		$offset = '';
	}

	my $tag_where = "AND f.tag LIKE '$tag'";
	if (ref $tag) {
		$tag_where = "AND f.tag IN ('".join("','",@$tag)."')";
	}

	my $sf_where = "AND f.subfield = '$subfield'";
	if (ref $subfield) {
		$sf_where = "AND f.subfield IN ('".join("','",@$subfield)."')";
	}

	my $search_table = authority::full_rec->table;
	my $marc_table = authority::record_entry->table;

	my ($index_col) = authority::full_rec->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'f.value', "f.$index_col");

	$term =~ s/'/''/gso;
	$term =~ s/\pM//gso;

	my $fts_where = $fts->sql_where_clause;
	my $fts_words = join '%', $fts->words;
	my $fts_words_where = "f.value LIKE '$fts_words\%'";
	my $fts_start_where = "f.value LIKE '$term\%'";
	my $fts_eq_where = "f.value = '$term'";

	my $fts_rank = join '+', $fts->fts_rank;

	my $select = <<"	SQL";
		SELECT	a.marc, sum($fts_rank), count(f.record), first(f.value)
  	  	FROM	$search_table f,
			$marc_table a
  	  	WHERE	$fts_start_where
			$tag_where
			$sf_where
	  		AND a.id = f.record
			GROUP BY 1
			ORDER BY 2 desc, 3 desc, 4
			$limit
			$offset
			
	SQL

	$log->debug("Authority Search SQL :: [$select]",DEBUG);

	my $recs = authority::full_rec->db_Main->selectcol_arrayref( $select );
	
	$log->debug("Search yielded ".scalar(@$recs)." results.",DEBUG);

	$client->respond($_) for (@$recs);
	return undef;
}
__PACKAGE__->register_method(
	api_name	=> "open-ils.storage.authority.search.marc",
	method		=> 'find_authority_marc',
	api_level	=> 1,
	stream		=> 1,
	cachable	=> 1,
);

sub _empty_check {
	my $term = shift;
	my $class = shift || 'metabib::full_rec';

	my $table = $class->table;

	my ($index_col) = $class->columns('FTS');
	$index_col ||= 'value';

	my $fts = OpenILS::Application::Storage::FTS->compile($term, 'm.value', "m.$index_col");
	my $fts_where = $fts->sql_where_clause;

	my $sql = <<"	SQL";
		SELECT	TRUE
		FROM	$table m
		WHERE	$fts_where
		LIMIT 1
	SQL

	return $class->db_Main->selectcol_arrayref($sql)->[0];
}

my $prevtime;

sub find_see_from_controlled {
	my $self = shift;
	my $client = shift;
	my $term = shift;
	my $limit = shift;
	my $offset = shift;

	$prevtime = time;

	(my $class = $self->api_name) =~ s/^.+authority.([^\.]+)\.see.+$/$1/o;
	my $sf = 'a';
	$sf = 't' if ($class eq 'title');

	my @marc = $self->method_lookup('open-ils.storage.authority.search.marc')
			->run( term => $term, tag => [400,410,411,430,450,455], subfield => $sf, limit => $limit, offset => $offset );

	
	for my $m ( @marc ) {
		my $doc = $parser->parse_string($m);
		my @nodes = $doc->documentElement->findnodes('//*[substring(@tag,1,1)="1"]/*[@code="a" or @code="d" or @code="x"]');
		my $list = [ map { $_->textContent } @nodes ];
		$client->respond( $list ) if (_empty_check(join(' ',@$list), "metabib::${class}_field_entry"));
	}
	return undef;
}
for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.authority.$class.see_from.controlled",
		method		=> 'find_see_from_controlled',
		api_level	=> 1,
		stream		=> 1,
		cachable	=> 1,
	);
}

sub find_see_also_from_controlled {
	my $self = shift;
	my $client = shift;
	my $term = shift;
	my $limit = shift;
	my $offset = shift;

	(my $class = $self->api_name) =~ s/^.+authority.([^\.]+)\.see.+$/$1/o;
	my $sf = 'a';
	$sf = 't' if ($class eq 'title');

	my @marc = $self->method_lookup('open-ils.storage.authority.search.marc')
			->run( term => $term, tag => [500,510,511,530,550,555], subfield => $sf, limit => $limit, offset => $offset );
	for my $m ( @marc ) {
		my $doc = $parser->parse_string($m);
		my @nodes = $doc->documentElement->findnodes('//*[substring(@tag,1,1)="1"]/*[@code="a" or @code="d" or @code="x"]');
		my $list = [ map { $_->textContent } @nodes ];
		$client->respond( $list ) if (_empty_check(join(' ',@$list), "metabib::${class}_field_entry"));
	}
	return undef;
}
for my $class ( qw/title author subject keyword series/ ) {
	__PACKAGE__->register_method(
		api_name	=> "open-ils.storage.authority.$class.see_also_from.controlled",
		method		=> 'find_see_also_from_controlled',
		api_level	=> 1,
		stream		=> 1,
		cachable	=> 1,
	);
}


1;
