use OpenSRF::Utils::Logger qw/:level/;
my $log = 'OpenSRF::Utils::Logger';

#-------------------------------------------------------------------------------
package OpenILS::Application::Storage::FTS;
use OpenSRF::Utils::Logger qw/:level/;

sub compile {

	$log->debug("You must override me somewhere, or I will make searching really slow!!!!",ERROR);;

	my $self = shift;
	my $term = shift;

	$self = ref($self) || $self;
	$self = bless {} => $self;

	$self->decompose($term);

	for my $part ( $self->words, $self->phrases ) {
		$part = OpenILS::Application::Storage::CDBI->quote($part);
		push @{ $self->{ fts_query } },   "'\%$part\%'";
	}

	for my $part ( $self->nots ) {
		$part = OpenILS::Application::Storage::CDBI->quote($part);
		push @{ $self->{ fts_query_not } },   "'\%$part\%'";
	}
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

	$log->debug("Stripped search term string is [$term]",DEBUG);

	my @words = $term =~ /\b((?<!!)\w+)\b/go;
	my @nots = $term =~ /\b(?<=!)(\w+)\b/go;

	$log->debug("Stripped words are[".join(', ',@words)."]",DEBUG);
	$log->debug("Stripped nots are[".join(', ',@nots)."]",DEBUG);

	my @parts;
	while ($term =~ s/ ((?<!\\)"{1}) (.*?) ((?<!\\)"){1} //x) {
		my $part = $2;
		$part =~ s/^\s*//o;
		$part =~ s/\s*$//o;
		next unless $part;
		push @parts, lc($part);
	}

	$self->{ fts_op } = 'ILIKE';
	$self->{ fts_col } = $self->{ text_col } = 'value';
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

sub fts_rank {
	my $self = shift;
	return wantarray ? @{ $self->{fts_rank} } : $self->{fts_rank};
}

sub fts_query {
	my $self = shift;
	return wantarray ? @{ $self->{fts_query} } : $self->{fts_query};
}

sub raw {
	my $self = shift;
	return $self->{raw};
}

sub fts_col {
	my $self = shift;
	return $self->{fts_col};
}

sub text_col {
	my $self = shift;
	return $self->{text_col};
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
	my $column = $self->text_col;
	my $output = '';
	for my $phrase ( $self->phrases ) {
		$phrase =~ s/%/\\%/go;
		$phrase =~ s/_/\\_/go;
		$phrase =~ s/'/\\'/go;
		$log->debug("Adding phrase [$phrase] to the match list", DEBUG);
		$output .= " AND $column ILIKE '\%$phrase\%'";
	}
	$log->debug("Phrase list is [$output]", DEBUG);
	return $output;
}

sub sql_exact_word_bump {
	my $self = shift;
	my $bump = shift || '0.1';

	my $column = $self->text_col;
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
	my @output;

	for my $fts ( $self->fts_query ) {
		push @output, join(' ', $self->fts_col, $self->{fts_op}, $fts);
	}

	for my $fts ( $self->fts_query_not ) {
		push @output, 'NOT (' . join(' ', $self->fts_col, $self->{fts_op}, $fts) . ')';
	}

	my $phrase_match = $self->sql_exact_phrase_match();
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
		
		my (@cols, @vals);
		my $search_opts = (@args > 1 and ref($args[-1]) eq 'HASH') ? pop @args : {};

		@args = %{ $args[0] } if ref $args[0] eq "HASH";

		$search_opts->{offset} = int($search_opts->{page} - 1) * int($search_opts->{page_size})  if ($search_opts->{page_size});
		$search_opts->{_placeholder} ||= '?';

		my @frags;
		while (my ($col, $val) = splice @args, 0, 2) {
			my $column = $class->find_column($col)
				|| (List::Util::first { $_->accessor eq $col } $class->columns)
				|| $class->_croak("$col is not a column of $class");

			if (!defined($val)) {
				push @frags, "$col IS NULL";
			} elsif (ref($val) and ref($val) eq 'ARRAY') {
				push @frags, "$col IN (".join(',',map{'?'}@$val).")";
				for my $v (@$val) {
					push @vals, ''.$class->_deflated_column($column, $v);
				}
			} else {
				push @frags, "$col $search_type $$search_opts{_placeholder}";
				push @vals, $class->_deflated_column($column, $val);
			}
		}

		my $frag = join " AND ", @frags;

		$frag .= " ORDER BY $search_opts->{order_by}"
			if $search_opts->{order_by};
		$frag .= " LIMIT $search_opts->{limit}"
			if $search_opts->{limit};
		$frag .= " OFFSET $search_opts->{offset}"
			if ($search_opts->{limit} && defined($search_opts->{offset}));

		return $class->sth_to_objects($class->sql_Retrieve($frag), \@vals);
	}
}

1;
