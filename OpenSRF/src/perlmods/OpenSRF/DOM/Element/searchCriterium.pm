package OpenSRF::DOM::Element::searchCriterium;
use base 'OpenSRF::DOM::Element';
use OpenSRF::DOM::Element::searchTargetValue;

sub new {
	my $class = shift;
	my @nodes;
	my @args = @_;
	while (scalar(@args)) {
		my ($attr,$cmp,$val) = (shift(@args),shift(@args),shift(@args),shift(@args));
		push @nodes, $class->SUPER::new(property => $attr, comparison => $cmp);
		$nodes[-1]->appendChild( $_ ) for OpenSRF::DOM::Element::searchTargetValue->new($val);
	}
	return @nodes if (wantarray);
	return $nodes[0];
}

sub toSQL {
	my $self = shift;
	my %args = @_;

	my $column = $self->getAttribute('property');
	my $cmp = lc($self->getAttribute('comparison'));

	my $value = [ map { ($_->getAttribute('value')) } $self->childNodes ];

	if ($cmp eq '=' || $cmp eq '==' || $cmp eq 'eq' || $cmp eq 'is') {
		$cmp = '=';
		if (!$value || lc($value) eq 'null') {
			$cmp = 'IS';
			$value = 'NULL';
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value = "'$value'" unless $args{no_quote};
	} elsif ($cmp eq '>' || $cmp eq 'gt' || $cmp eq 'over' || $cmp eq 'after') {
		$cmp = '>';
		if (!$value || lc($value) eq 'null') {
			warn "Can not compare NULL";
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value = "'$value'" unless $args{no_quote};
	} elsif ($cmp eq '<' || $cmp eq 'lt' || $cmp eq 'under' || $cmp eq 'before') {
		$cmp = '<';
		if (!$value || lc($value) eq 'null') {
			warn "Can not compare NULL";
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value = "'$value'" unless $args{no_quote};
	} elsif ($cmp eq '!=' || $cmp eq '<>' || $cmp eq 'ne' || $cmp eq 'not') {
		$cmp = '<>';
		if (!$value || lc($value) eq 'null') {
			$cmp = 'IS NOT';
			$value = 'NULL';
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value = "'$value'" unless $args{no_quote};
	} elsif (lc($cmp) eq 'fts' || $cmp eq 'tsearch' || $cmp eq '@@') {
		$cmp = '@@';
		if (!$value || lc($value) eq 'null') {
			warn "Can not compare NULL";
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value = "to_tsquery('$value')";
	} elsif ($cmp eq 'like' || $cmp eq 'contains' || $cmp eq 'has') {
		$cmp = 'LIKE';
		if (!$value || lc($value) eq 'null') {
			warn "Can not compare NULL";
		}
		($value = $value->[0]) =~ s/'/''/gmso;
		$value =~ s/\\/\\\\/gmso;
		$value =~ s/%/\\%/gmso;
		$value =~ s/_/\\_/gmso;
		$value = "'\%$value\%'";
	} elsif ($cmp eq 'between') {
		$cmp = 'BETWEEN';
		if (!ref($value) || lc($value) eq 'null') {
			warn "Can not check 'betweenness' of NULL";
		}
		if (ref($value) and ref($value) =~ /ARRAY/o) {
			$value = "(\$text\$$$value[0]\$text\$ AND \$text\$$$value[-1]\$text\$)";
		}
	} elsif ($cmp eq 'not between') {
		$cmp = 'NOT BETWEEN';
		if (!ref($value) || lc($value) eq 'null') {
			warn "Can not check 'betweenness' of NULL";
		}
		if (ref($value) and ref($value) =~ /ARRAY/o) {
			$value = "(\$text\$$$value[0]\$text\$ AND \$text\$$$value[-1]\$text\$)";
		}
	} elsif ($cmp eq 'in' || $cmp eq 'any' || $cmp eq 'some') {
		$cmp = 'IN';
		if (!ref($value) || lc($value) eq 'null') {
			warn "Can not check 'inness' of NULL";
		}
		if (ref($value) and ref($value) =~ /ARRAY/o) {
			$value = '($text$'.join('$text$,$text$', @$value).'$text$)';
		}
	} elsif ($cmp eq 'not in' || $cmp eq 'not any' || $cmp eq 'not some') {
		$cmp = 'NOT IN';
		if (!ref($value) || lc($value) eq 'null') {
			warn "Can not check 'inness' of NULL";
		}
		if (ref($value) and ref($value) =~ /ARRAY/o) {
			$value = '($text$'.join('$text$,$text$', @$value).'$text$)';
		}
	}

	return join(' ', ($column, $cmp, $value));
}

1;
