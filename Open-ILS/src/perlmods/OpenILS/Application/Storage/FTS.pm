use OpenILS::Utils::Logger qw/:level/;
my $log = 'OpenILS::Utils::Logger';

#-------------------------------------------------------------------------------
package OpenILS::Application::Storage::FTS;
use OpenILS::Utils::Logger qw/:level/;

sub compile {
	die "You must override me somewhere!";
}

sub decompose {
	my $self = shift;
	my $term = shift;

	$term =~ s/:/ /go;
	$term =~ s/(?:&[^;]+;)//go;
	$term =~ s/\s+/ /go;
	$term =~ s/(^|\s+)-(\w+)/$1!$2/go;
	$term =~ s/\b(\+)(\w+)/$2/go;
	$term =~ s/^\s*\b(.+)\b\s*$/$1/o;
	$term =~ s/^(?:an?|the)\b(.*)/$1/o;

	OpenILS::Utils::Logger->debug("Stripped search term string is [$term]",DEBUG);

	my @words = $term =~ /\b((?<!!)\w+)\b/go;
	my @nots = $term =~ /\b(?<=!)(\w+)\b/go;

	my @parts;
	while ($term =~ s/ ("+) (.*?) ((?<!\\)"){1} //x) {
		my $part = $2;
		$part =~ s/^\s*//o;
		$part =~ s/\s*$//o;
		next unless $part;
		push @parts, lc($part);
	}

	$self->{ fts_op } = 'ILIKE';

	for my $part ( @words, @parts ) {
		$part = OpenILS::Application::Storage->driver->quote($part);
		push @{ $self->{ fts_query },   "'\%$part\%'";
	}

	for my $part ( @nots ) {
		$part = OpenILS::Application::Storage->driver->quote($part);
		push @{ $self->{ fts_query_not },   "'\%$part\%'";
	}

	$self->{ raw } = $term;
	$self->{ words } = \@words;
	$self->{ nots } = \@nots;
	$self->{ phrases } = \@parts;

	return $self;
}

sub fts_query_not {
	my $self = shift;
	return wantarray ? @{ $self->{fts_query_not} } : $self->{fts_query_not};
}

sub fts_query {
	my $self = shift;
	return wantarray ? @{ $self->{fts_query} } : $self->{fts_query};
}

sub raw {
	my $self = shift;
	return $self->{raw};
}

sub phrases {
	my $self = shift;
	return wantarray ? @{ $self->{phrases} } : $self->{phrases};
}

sub words {
	my $self = shift;
	return wantarray ? @{ $self->{words} } : $self->{words};
}

sub nots {
	my $self = shift;
	return wantarray ? @{ $self->{nots} } : $self->{nots};
}

sub sql_exact_phrase_match {
	my $self = shift;
	my $column = shift;
	my $output = '';
	for my $phrase ( $self->phrases ) {
		$phrase =~ s/%/\\%/go;
		$phrase =~ s/_/\\_/go;
		$phrase =~ s/'/\\_/go;
		$log->debug("Adding phrase [$phrase] to the match list", DEBUG);
		$output .= " AND $column ILIKE '\%$phrase\%'";
	}
	$log->debug("Phrase list is [$output]", DEBUG);
	return $output;
}

sub sql_exact_word_bump {
	my $self = shift;
	my $column = shift;
	my $bump = shift || '0.1';
	my $output = '';
	for my $word ( $self->words ) {
		$word =~ s/%/\\%/go;
		$word =~ s/_/\\_/go;
		$word =~ s/'/''/go;
		$log->debug("Adding word [$word] to the relevancy bump list", DEBUG);
		$output .= " + CASE WHEN $column ILIKE '\%$word\%' THEN $bump ELSE 0 END";
	}
	$log->debug("Word bump list is [$output]", DEBUG);
	return $output;
}

sub sql_where_clause {
	my $self = shift;
	my $column = shift;
	my @output;

	for my $fts ( $self->fts_query ) {
		push @output, join(' ', $column, $self->{fts_op}, $fts);
	}

	for my $fts ( $self->fts_query_nots ) {
		push @output, 'NOT (' . join(' ', $column, $self->{fts_op}, $fts) . ')';
	}

	return join(' AND ', @output);
}

#-------------------------------------------------------------------------------
use Class::DBI;

package Class::DBI;

{
	no warnings;
	no strict;
	sub _do_search {
		my ($proto, $search_type, @args) = @_;
		my $class = ref $proto || $proto;
		
		@args = %{ $args[0] } if ref $args[0] eq "HASH";

		my (@cols, @vals);
		my $search_opts = @args % 2 ? pop @args : {};

		$search_opts->{offset} = int($search_opts->{page}) * int($search_opts->{page_size})  if ($search_opts->{page_size});
		$search_opts->{_placeholder} ||= '?';

		while (my ($col, $val) = splice @args, 0, 2) {
			my $column = $class->find_column($col)
				|| (List::Util::first { $_->accessor eq $col } $class->columns)
				|| $class->_croak("$col is not a column of $class");

			push @cols, $column;
			push @vals, $class->_deflated_column($column, $val);
		}

		my $frag = join " AND ",
		map defined($vals[$_]) ? "$cols[$_] $search_type $$search_opts{_placeholder}" : "$cols[$_] IS NULL",
			0 .. $#cols;

		$frag .= " ORDER BY $search_opts->{order_by}"
			if $search_opts->{order_by};
		$frag .= " LIMIT $search_opts->{limit}"
			if $search_opts->{limit};
		$frag .= " OFFSET $search_opts->{offset}"
			if ($search_opts->{limit} && defined($search_opts->{offset}));

		return $class->sth_to_objects($class->sql_Retrieve($frag),
			[ grep defined, @vals ]);
	}
}

1;
