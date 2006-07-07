
package JSON::number;
sub new {
	my $class = shift;
	my $x = shift || $class;
	return bless \$x => __PACKAGE__;
}

use overload ( '""' => \&toString );

sub toString { defined($_[1]) ? ${$_[1]} : ${$_[0]} }

package JSON::bool::true;
sub new { return bless {} => __PACKAGE__ }
use overload ( '""' => \&toString );
use overload ( 'bool' => sub { 1 } );
use overload ( '0+' => sub { 1 } );

sub toString { 'true' }

package JSON::bool::false;
sub new { return bless {} => __PACKAGE__ }
use overload ( '""' => \&toString );
use overload ( 'bool' => sub { 0 } );
use overload ( '0+' => sub { 0 } );

sub toString { 'false' }

package JSON;
use Unicode::Normalize;
use vars qw/%_class_map/;

sub register_class_hint {
	my $class = shift;
	my %args = @_;

	$_class_map{hints}{$args{hint}} = \%args;
	$_class_map{classes}{$args{name}} = \%args;
}

sub _JSON_regex {
	my $string = shift;

	$string =~ s/^\s* ( 
			   {				| # start object
			   \[				| # start array
			   -?\d+\.?\d*			| # number literal
			   "(?:(?:\\[\"])|[^\"])*"	| # string literal
			   (?:\/\*.+?\*\/)		| # C comment
			   true				| # bool true
			   false			| # bool false
			   null				| # undef()
			   :				| # object key-value sep
			   ,				| # list sep
			   \]				| # array end
			   }				  # object end
			)
		 \s*//sox;
	return ($string,$1);
}

sub lookup_class {
	my $self = shift;
	my $hint = shift;
	return $_class_map{hints}{$hint}{name}
}

sub lookup_hint {
	my $self = shift;
	my $class = shift;
	return $_class_map{classes}{$class}{hint}
}

sub _json_hint_to_class {
	my $type = shift;
	my $hint = shift;

	return $_class_map{hints}{$hint}{name} if (exists $_class_map{hints}{$hint});
	
	$type = 'hash' if ($type eq '}');
	$type = 'array' if ($type eq ']');

	JSON->register_class_hint(name => $hint, hint => $hint, type => $type);

	return $hint;
}

sub JSON2perl {
	my $class = shift;
	local $_ = shift;

	s/(?<!\\)\$/\\\$/gmo; # fixup $ for later
	s/(?<!\\)\@/\\\@/gmo; # fixup @ for later
	s/(?<!\\)\%/\\\%/gmo; # fixup % for later

	# Convert JSON Unicode...
	s/\\u([0-9a-fA-F]{4})/chr(hex($1))/esog;

	# handle class blessings
	s/\/\*--\s*S\w*?\s+\S+\s*--\*\// bless(/sog;
	s/(\]|\}|")\s*\/\*--\s*E\w*?\s+(\S+)\s*--\*\//$1 => _json_hint_to_class("$1", "$2")) /sog;

	my $re = qr/((?<!\\)"(?>(?<=\\)"|[^"])*(?<!\\)")/;
	# Grab strings...
	my @strings = /$re/sog;

	# Replace with code...
	#s/"(?:(?:\\[\"])|[^\"])*"/ do{ \$t = '"'.shift(\@strings).'"'; eval \$t;} /sog;
	s/$re/ eval shift(\@strings) /sog;

	# Perlify hash notation
	s/:/ => /sog;

	# Do numbers...
	#s/\b(-?\d+\.?\d*)\b/ JSON::number::new($1) /sog;

	# Change javascript stuff to perl...
	s/null/ undef /sog;
	s/true/ bless( {}, "JSON::bool::true") /sog;
	s/false/ bless( {}, "JSON::bool::false") /sog;

	my $ret;
	return eval '$ret = '.$_;
}

my $_json_index;
sub ___JSON2perl {
	my $class = shift;
	my $data = shift;

	$data = [ split //, $data ];

	$_json_index = 0;

	return _json_parse_data($data);
}

sub _eat_WS {
	my $data = shift;
	while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
}

sub _json_parse_data {
	my $data = shift;

	my $out; 

	#warn "parse_data";

	while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }

	my $class = '';

	my $c = $$data[$_json_index];

	if ($c eq '/') {
		$_json_index++;
		$class = _json_parse_comment($data);
		
		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		$c = $$data[$_json_index];
	}

	if ($c eq '"') {
		$_json_index++;
		my $val = '';

		my $seen_slash = 0;
		my $done = 0;
		while (!$done) {
			my $c = $$data[$_json_index];
			#warn "c is $c";

			if ($c eq '\\') {
				if ($seen_slash) {
					$val .= '\\';
					$seen_slash = 0;
				} else {
					$seen_slash = 1;
				}
			} elsif ($c eq '"') {
				if ($seen_slash) {
					$val .= '"';
					$seen_slash = 0;
				} else {
					$done = 1;
				}
			} elsif ($c eq 't') {
				if ($seen_slash) {
					$val .= "\t";
					$seen_slash = 0;
				} else {
					$val .= 't';
				}
			} elsif ($c eq 'b') {
				if ($seen_slash) {
					$val .= "\b";
					$seen_slash = 0;
				} else {
					$val .= 'b';
				}
			} elsif ($c eq 'f') {
				if ($seen_slash) {
					$val .= "\f";
					$seen_slash = 0;
				} else {
					$val .= 'f';
				}
			} elsif ($c eq 'r') {
				if ($seen_slash) {
					$val .= "\r";
					$seen_slash = 0;
				} else {
					$val .= 'r';
				}
			} elsif ($c eq 'n') {
				if ($seen_slash) {
					$val .= "\n";
					$seen_slash = 0;
				} else {
					$val .= 'n';
				}
			} elsif ($c eq 'u') {
				if ($seen_slash) {
					$_json_index++;
					$val .= chr(hex(join('',$$data[$_json_index .. $_json_index + 3])));
					$_json_index += 3;
					$seen_slash = 0;
				} else {
					$val .= 'u';
				}
			} else {
				$val .= $c;
			}
			$_json_index++;

			#warn "string is $val";
		}

		$out = $val;

		#$out = _json_parse_string($data);
	} elsif ($c eq '[') {
		$_json_index++;
		$out = [];

		my $in_parse = 0;
		my $done = 0;
		while(!$done) {
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }

			if ($$data[$_json_index] eq ']') {
				$done = 1;
				$_json_index++;
				last;
			}

			if ($in_parse) {
				if ($$data[$_json_index] ne ',') {
					#warn "_json_parse_array: bad data, leaving array parser";
					last;
				}
				$_json_index++;
				while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
			}

			my $item = _json_parse_data($data);

			push @$out, $item;
			$in_parse++;
		}

		#$out = _json_parse_array($data);
	} elsif ($c eq '{') {
		$_json_index++;
		$out = {};

		my $in_parse = 0;
		my $done = 0;
		while(!$done) {
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }

			if ($$data[$_json_index] eq '}') {
				$done = 1;
				$_json_index++;
				last;
			}

			if ($in_parse) {
				if ($$data[$_json_index] ne ',') {
					#warn "_json_parse_object: bad data, leaving object parser";
					last;
				}
				$_json_index++;
				while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
			}

			my ($key,$value);
			$key = _json_parse_data($data);

			#warn "object key is $key";

			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		
			if ($$data[$_json_index] ne ':') {
				#warn "_json_parse_object: bad data, leaving object parser";
				last;
			}
			$_json_index++;
			$value = _json_parse_data($data);

			$out->{$key} = $value;
			$in_parse++;
		}
		#$out = _json_parse_object($data);
	} elsif (lc($c) eq 'n') {
		if (lc(join('',$$data[$_json_index .. $_json_index + 3])) eq 'null') {
			$_json_index += 4;
		} else {
			warn "CRAP! bad null parsing...";
		}
		$out = undef;
		#$out = _json_parse_null($data);
	} elsif (lc($c) eq 't' or lc($c) eq 'f') {
		if (lc(join('',$$data[$_json_index .. $_json_index + 3])) eq 'true') {
			$out = 1;
			$_json_index += 4;
		} elsif (lc(join('',$$data[$_json_index .. $_json_index + 4])) eq 'false') {
			$out = 0;
			$_json_index += 5;
		} else {
			#warn "CRAP! bad bool parsing...";
			$out = undef;
		}
		#$out = _json_parse_bool($data);
	} elsif ($c =~ /\d+/o or $c eq '.' or $c eq '-') {
		my $val;
		while ($$data[$_json_index] =~ /[-\.0-9]+/io) {
			$val .= $$data[$_json_index];
			$_json_index++;
		}
		$out = 0+$val;
		#$out = _json_parse_number($data);
	}

	if ($class) {
		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		my $c = $$data[$_json_index];

		if ($c eq '/') {
			$_json_index++;
			_json_parse_comment($data)
		}

		bless( $out => lookup_class($class) );
	}

	$out;
}

sub _json_parse_null {
	my $data = shift;

	#warn "parse_null";

	if (lc(join('',$$data[$_json_index .. $_json_index + 3])) eq 'null') {
		$_json_index += 4;
	} else {
		#warn "CRAP! bad null parsing...";
	}
	return undef;
}

sub _json_parse_bool {
	my $data = shift;

	my $out;

	#warn "parse_bool";

	if (lc(join('',$$data[$_json_index .. $_json_index + 3])) eq 'true') {
		$out = 1;
		$_json_index += 4;
	} elsif (lc(join('',$$data[$_json_index .. $_json_index + 4])) eq 'false') {
		$out = 0;
		$_json_index += 5;
	} else {
		#warn "CRAP! bad bool parsing...";
		$out = undef;
	}
	return $out;
}

sub _json_parse_number {
	my $data = shift;

	#warn "parse_number";

	my $val;
	while ($$data[$_json_index] =~ /[-\.0-9]+/io) {
		$val .= $$data[$_json_index];
		$_json_index++;
	}

	return 0+$val;
}

sub _json_parse_object {
	my $data = shift;

	#warn "parse_object";

	my $out = {};

	my $in_parse = 0;
	my $done = 0;
	while(!$done) {
		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }

		if ($$data[$_json_index] eq '}') {
			$done = 1;
			$_json_index++;
			last;
		}

		if ($in_parse) {
			if ($$data[$_json_index] ne ',') {
				#warn "_json_parse_object: bad data, leaving object parser";
				last;
			}
			$_json_index++;
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		}

		my ($key,$value);
		$key = _json_parse_data($data);

		#warn "object key is $key";

		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		
		if ($$data[$_json_index] ne ':') {
			#warn "_json_parse_object: bad data, leaving object parser";
			last;
		}
		$_json_index++;
		$value = _json_parse_data($data);

		$out->{$key} = $value;
		$in_parse++;
	}

	return $out;
}

sub _json_parse_array {
	my $data = shift;

	#warn "parse_array";

	my $out = [];

	my $in_parse = 0;
	my $done = 0;
	while(!$done) {
		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }

		if ($$data[$_json_index] eq ']') {
			$done = 1;
			$_json_index++;
			last;
		}

		if ($in_parse) {
			if ($$data[$_json_index] ne ',') {
				#warn "_json_parse_array: bad data, leaving array parser";
				last;
			}
			$_json_index++;
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		}

		my $item = _json_parse_data($data);

		push @$out, $item;
		$in_parse++;
	}

	return $out;
}


sub _json_parse_string {
	my $data = shift;

	#warn "parse_string";

	my $val = '';

	my $seen_slash = 0;
	my $done = 0;
	while (!$done) {
		my $c = $$data[$_json_index];
		#warn "c is $c";

		if ($c eq '\\') {
			if ($seen_slash) {
				$val .= '\\';
				$seen_slash = 0;
			} else {
				$seen_slash = 1;
			}
		} elsif ($c eq '"') {
			if ($seen_slash) {
				$val .= '"';
				$seen_slash = 0;
			} else {
				$done = 1;
			}
		} elsif ($c eq 't') {
			if ($seen_slash) {
				$val .= "\t";
				$seen_slash = 0;
			} else {
				$val .= 't';
			}
		} elsif ($c eq 'b') {
			if ($seen_slash) {
				$val .= "\b";
				$seen_slash = 0;
			} else {
				$val .= 'b';
			}
		} elsif ($c eq 'f') {
			if ($seen_slash) {
				$val .= "\f";
				$seen_slash = 0;
			} else {
				$val .= 'f';
			}
		} elsif ($c eq 'r') {
			if ($seen_slash) {
				$val .= "\r";
				$seen_slash = 0;
			} else {
				$val .= 'r';
			}
		} elsif ($c eq 'n') {
			if ($seen_slash) {
				$val .= "\n";
				$seen_slash = 0;
			} else {
				$val .= 'n';
			}
		} elsif ($c eq 'u') {
			if ($seen_slash) {
				$_json_index++;
				$val .= chr(hex(join('',$$data[$_json_index .. $_json_index + 3])));
				$_json_index += 3;
				$seen_slash = 0;
			} else {
				$val .= 'u';
			}
		} else {
			$val .= $c;
		}
		$_json_index++;

		#warn "string is $val";
	}

	return $val;
}

sub _json_parse_comment {
	my $data = shift;

	#warn "parse_comment";

	if ($$data[$_json_index] eq '/') {
		$_json_index++;
		while (!($$data[$_json_index] eq "\n")) { $_json_index++ }
		$_json_index++;
		return undef;
	}

	my $class = '';

	if (join('',$$data[$_json_index .. $_json_index + 2]) eq '*--') {
		$_json_index += 3;
		while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		if ($$data[$_json_index] eq 'S') {
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
			while ($$data[$_json_index] !~ /[-\s]+/o) {
				$class .= $$data[$_json_index];
				$_json_index++;
			}
			while ($$data[$_json_index] =~ /\s+/o) { $_json_index++ }
		}
	}

	while ($$data[$_json_index] ne '/') { $_json_index++ };
	$_json_index++;

	return $class;
}

sub old_JSON2perl {
	my ($class, $json) = @_;

	if (!defined($json)) {
		return undef;
	}

	$json =~ s/(?<!\\)\$/\\\$/gmo; # fixup $ for later
	$json =~ s/(?<!\\)\@/\\\@/gmo; # fixup @ for later
	$json =~ s/(?<!\\)\%/\\\%/gmo; # fixup % for later

	my @casts;
	my $casting_depth = 0;
	my $current_cast;
	my $element;
	my $output = '';
	while (($json,$element) = _JSON_regex($json)) {

		last unless ($element);

		if ($element eq 'null') {
			$output .= ' undef() ';
			next;
		} elsif ($element =~ /^\/\*--\s*S\w*?\s+(\w+)\s*--\*\/$/) {
			my $hint = $1;
			if (exists $_class_map{hints}{$hint}) {
				$casts[$casting_depth] = $hint;
				$output .= ' bless(';
			}
			next;
		} elsif ($element =~ /^\/\*/) {
			next;
		} elsif ($element =~ /^\d/) {
			$output .= "do { JSON::number::new($element) }";
			next;
		} elsif ($element eq '{' or $element eq '[') {
			$casting_depth++;
		} elsif ($element eq '}' or $element eq ']') {
			$casting_depth--;
			my $hint = $casts[$casting_depth];
			$casts[$casting_depth] = undef;
			if (defined $hint and exists $_class_map{hints}{$hint}) {
				$output .= $element . ',"'. $_class_map{hints}{$hint}{name} . '")';
				next;
			}
		} elsif ($element eq ':') {
			$output .= ' => ';
			next;
		} elsif ($element eq 'true') {
			$output .= 'bless( {}, "JSON::bool::true")';
			next;
		} elsif ($element eq 'false') {
			$output .= 'bless( {}, "JSON::bool::false")';
			next;
		}
		
		$output .= $element;
	}

	return eval $output;
}

sub perl2JSON {
	my ($class, $perl, $strict) = @_;

	my $output = '';
	if (!defined($perl)) {
		$output = '' if $strict;
		$output = 'null' unless $strict;
	} elsif (ref($perl) and ref($perl) =~ /^JSON/) {
		$output .= $perl;
	} elsif ( ref($perl) && exists($_class_map{classes}{ref($perl)}) ) {
		$output .= '/*--S '.$_class_map{classes}{ref($perl)}{hint}.'--*/';
		if (lc($_class_map{classes}{ref($perl)}{type}) eq 'hash') {
			my %hash =  %$perl;
			$output .= perl2JSON(undef,\%hash, $strict);
		} elsif (lc($_class_map{classes}{ref($perl)}{type}) eq 'array') {
			my @array =  @$perl;
			$output .= perl2JSON(undef,\@array, $strict);
		}
		$output .= '/*--E '.$_class_map{classes}{ref($perl)}{hint}.'--*/';
	} elsif (ref($perl) and ref($perl) =~ /HASH/) {
		$output .= '{';
		my $c = 0;
		for my $key (sort keys %$perl) {
			my $outkey = NFC($key);
			$output .= ',' if ($c); 

			$outkey =~ s{\\}{\\\\}sgo;
			$outkey =~ s/"/\\"/sgo;
			$outkey =~ s/\t/\\t/sgo;
			$outkey =~ s/\f/\\f/sgo;
			$outkey =~ s/\r/\\r/sgo;
			$outkey =~ s/\n/\\n/sgo;
			$outkey =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%0.4x',ord($1))/sgoe;

			$output .= '"'.$outkey.'":'. perl2JSON(undef,$$perl{$key}, $strict);
			$c++;
		}
		$output .= '}';
	} elsif (ref($perl) and ref($perl) =~ /ARRAY/) {
		$output .= '[';
		my $c = 0;
		for my $part (@$perl) {
			$output .= ',' if ($c); 
			
			$output .= perl2JSON(undef,$part, $strict);
			$c++;
		}
		$output .= ']';
	} elsif (ref($perl) and ref($perl) =~ /CODE/) {
		$output .= perl2JSON(undef,$perl->(), $strict);
	} elsif (ref($perl) and ("$perl" =~ /^([^=]+)=(\w+)/o)) {
		my $type = $2;
		my $name = $1;
		JSON->register_class_hint(name => $name, hint => $name, type => lc($type));
		$output .= perl2JSON(undef,$perl, $strict);
	} else {
		$perl = NFC($perl);
		$perl =~ s{\\}{\\\\}sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%0.4x',ord($1))/sgoe;
		if (length($perl) < 10 and $perl =~ /^(?:\+|-)?\d*\.?\d+$/o and $perl !~ /^(?:\+|-)?0\d+/o ) {
			$output = $perl;
		} else {
			$output = '"'.$perl.'"';
		}
	}

	return $output;
}

my $depth = 0;
sub perl2prettyJSON {
	my ($class, $perl, $nospace) = @_;
	$perl ||= $class;

	my $output = '';
	if (!defined($perl)) {
		$output = "   "x$depth unless($nospace);
		$output .= 'null';
	} elsif (ref($perl) and ref($perl) =~ /^JSON/) {
		$output = "   "x$depth unless($nospace);
		$output .= $perl;
	} elsif ( ref($perl) && exists($_class_map{classes}{ref($perl)}) ) {
		$depth++;
		$output .= "\n";
		$output .= "   "x$depth;
		$output .= '/*--S '.$_class_map{classes}{ref($perl)}{hint}."--*/ ";
		if (lc($_class_map{classes}{ref($perl)}{type}) eq 'hash') {
			my %hash =  %$perl;
			$output .= perl2prettyJSON(\%hash,undef,1);
		} elsif (lc($_class_map{classes}{ref($perl)}{type}) eq 'array') {
			my @array =  @$perl;
			$output .= perl2prettyJSON(\@array,undef,1);
		}
		$output .= ' /*--E '.$_class_map{classes}{ref($perl)}{hint}.'--*/';
		$depth--;
	} elsif (ref($perl) and ref($perl) =~ /HASH/) {
		$output .= "   "x$depth unless ($nospace);
		$output .= "{\n";
		my $c = 0;
		$depth++;
		for my $key (sort keys %$perl) {
			$output .= ",\n" if ($c); 
			$output .= "   "x$depth;
			$output .= perl2prettyJSON($key)." : ".perl2prettyJSON($$perl{$key}, undef, 1);
			$c++;
		}
		$depth--;
		$output .= "\n";
		$output .= "   "x$depth;
		$output .= '}';
	} elsif (ref($perl) and ref($perl) =~ /ARRAY/) {
		$output .= "   "x$depth unless ($nospace);
		$output .= "[\n";
		my $c = 0;
		$depth++;
		for my $part (@$perl) {
			$output .= ",\n" if ($c); 
			$output .= "   "x$depth;
			$output .= perl2prettyJSON($part);
			$c++;
		}
		$depth--;
		$output .= "\n";
		$output .= "   "x$depth;
		$output .= "]";
	} elsif (ref($perl) and ref($perl) =~ /CODE/) {
		$output .= perl2prettyJSON(undef,$perl->(), $nospace);
	} elsif (ref($perl) and "$perl" =~ /^([^=]+)=(\w{4,5})\(0x/) {
		my $type = $2;
		my $name = $1;
		register_class_hint(undef, name => $name, hint => $name, type => lc($type));
		$output .= perl2prettyJSON(undef,$perl);
	} else {
		$perl = NFC($perl);
		$perl =~ s/\\/\\\\/sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/([\x{0080}-\x{fffd}])/sprintf('\u%0.4x',ord($1))/sgoe;
		$output .= "   "x$depth unless($nospace);
		if (length($perl) < 10 and $perl =~ /^(?:\+|-)?\d*\.?\d+$/o and $perl !~ /^(?:\+|-)?0\d+/o ) {
			$output = $perl;
		} else {
			$output = '"'.$perl.'"';
		}
	}

	return $output;
}

1;
