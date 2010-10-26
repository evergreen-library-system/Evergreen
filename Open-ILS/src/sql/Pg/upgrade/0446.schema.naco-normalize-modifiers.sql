BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0446'); -- gmc

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$
	use Unicode::Normalize;
	use Encode;

	# When working with Unicode data, the first step is to decode it to
	# a byte string; after that, lowercasing is safe
	my $txt = lc(decode_utf8(shift));
	my $sf = shift;

	$txt = NFD($txt);
	$txt =~ s/\pM+//go;	# Remove diacritics

	# remove non-combining diacritics
	# this list of characters follows the NACO normalization spec,
	# but a looser but more comprehensive version might be
	# $txt =~ s/\pLm+//go;
	$txt =~ tr/\x{02B9}\x{02BA}\x{02BB}\x{02BC}//d;

	$txt =~ s/\xE6/AE/go;	# Convert ae digraph
	$txt =~ s/\x{153}/OE/go;# Convert oe digraph
	$txt =~ s/\xFE/TH/go;	# Convert Icelandic thorn

	$txt =~ tr/\x{2070}\x{2071}\x{2072}\x{2073}\x{2074}\x{2075}\x{2076}\x{2077}\x{2078}\x{2079}\x{207A}\x{207B}/0123456789+-/;# Convert superscript numbers
	$txt =~ tr/\x{2080}\x{2081}\x{2082}\x{2083}\x{2084}\x{2085}\x{2086}\x{2087}\x{2088}\x{2089}\x{208A}\x{208B}/0123456889+-/;# Convert subscript numbers

	$txt =~ tr/\x{0251}\x{03B1}\x{03B2}\x{0262}\x{03B3}/AABGG/;	 	# Convert Latin and Greek
	$txt =~ tr/\x{2113}\xF0\x{111}\!\"\(\)\-\{\}\<\>\;\:\.\?\xA1\xBF\/\\\@\*\%\=\xB1\+\xAE\xA9\x{2117}\$\xA3\x{FFE1}\xB0\^\_\~\`/LDD /;	# Convert Misc
	$txt =~ tr/\'\[\]\|//d;							# Remove Misc

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($txt,',');
		if ($commapos > -1) {
			if ($commapos != length($txt) - 1) {
				my @list = split /,/, $txt;
				my $first = shift @list;
				$txt = $first . ',' . join(' ', @list);
			} else {
				$txt =~ s/,/ /go;
			}
		}
	} else {
		$txt =~ s/,/ /go;
	}

	$txt =~ s/\s+/ /go;	# Compress multiple spaces
	$txt =~ s/^\s+//o;	# Remove leading space
	$txt =~ s/\s+$//o;	# Remove trailing space

	# Encoding the outgoing string is good practice, but not strictly
	# necessary in this case because we've stripped everything from it
	return encode_utf8($txt);
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

END;
