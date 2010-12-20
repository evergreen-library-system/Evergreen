use OpenSRF::Utils::Logger qw/:level/;
my $log = 'OpenSRF::Utils::Logger';

#-------------------------------------------------------------------------------
package OpenILS::Application::Storage::FTS;
use OpenSRF::Utils::Logger qw/:level/;
use Parse::RecDescent;
use Unicode::Normalize;

my $_default_grammar_parser = new Parse::RecDescent ( <<'GRAMMAR' );

<autotree>

search_expression: or_expr(s) | and_expr(s) | expr(s)
or_expr: lexpr '||' rexpr
and_expr: lexpr '&&' rexpr
lexpr: expr
rexpr: expr
expr: phrase(s) | group(s) | word(s)
joiner: '||' | '&&'
phrase: '"' token(s) '"'
group : '(' search_expression ')'
word: numeric_range | negative_token | token
negative_token: '-' .../\D+/ token
token: /[-\w]+/
numeric_range: /\d+-\d*/

GRAMMAR

# FIXME - this is a copy-and-paste of the naco_normalize
#         stored procedure
sub naco_normalize {

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
}

#' stupid vim syntax highlighting ...

sub compile {

	$log->debug("You must override me somewhere, or I will make searching really slow!!!!",ERROR);;

	my $self = shift;
	my $class = shift;
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
	my $parser = shift || $_default_grammar_parser;

	$term =~ s/:/ /go;
	$term =~ s/\s+--\s+/ /go;
	$term =~ s/(?:&[^;]+;)//go;
	$term =~ s/\s+/ /go;
	$term =~ s/(^|\s+)-(\w+)/$1!$2/go;
	$term =~ s/\b(\+)(\w+)/$2/go;
	$term =~ s/^\s*\b(.+)\b\s*$/$1/o;
	$term =~ s/(\d{4})-(\d{4})/$1 $2/go;
	#$term =~ s/^(?:an?|the)\b(.*)/$1/o;

	$log->debug("Stripped search term string is [$term]",DEBUG);

	my $parsetree = $parser->search_expression( $term );
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
	$self->{ parsetree } = $parsetree;
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

sub parse_tree {
	my $self = shift;
	return $self->{parsetree};
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
use UNIVERSAL::require; 
BEGIN {                 
	'Class::DBI::Frozen::301'->use or 'Class::DBI'->use or die $@;
}     

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

