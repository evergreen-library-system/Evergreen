{ # Every driver needs to provide a 'compile()' method to OpenILS::Application::Storage::FTS.
  # If that driver wants to support FTI, that is...
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

		if (@{$self->nots}) {
			$newterm = '('.$newterm.')&('. join('|', $self->nots) . ')';
		}

		$log->debug("Compiled term is [$newterm]", DEBUG);
		$newterm = OpenILS::Application::Storage::Driver::Pg->quote($newterm);
		$log->debug("Quoted term is [$newterm]", DEBUG);

		$self->{fts_query} = ["to_tsquery('default',$newterm)"];
		$self->{fts_query_nots} = [];
		$self->{fts_op} = '@@';
		$self->{text_col} = shift;
		$self->{fts_col} = shift;

		return $self;
	}

	sub sql_where_clause {
		my $self = shift;
		my $column = $self->fts_col;
		my @output;
	
		my @ranks;
		for my $fts ( $self->fts_query ) {
			push @output, join(' ', $self->fts_col, $self->{fts_op}, $fts);
			push @ranks, "rank($column, $fts)";
		}
		$self->{fts_rank} = \@ranks;
	
		my $phrase_match = $self->sql_exact_phrase_match();
		return join(' AND ', @output) . $phrase_match;
	}

}

1;
