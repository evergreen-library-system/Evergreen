package JSON::object_unknown;

package JSON::number;
sub new {
	my $class = shift;
	my $x = shift || $class;
	return bless \$x => __PACKAGE__;
}
use overload ( '""' => \&toString );
use overload ( '0+' => sub { $_[0]->toString } );
use overload ( '+' => sub { int($_[0]) + int($_[1]) } );
use overload ( '-' => sub { int($_[0]) - int($_[1]) } );
use overload ( '*' => sub { int($_[0]) * int($_[1]) } );
use overload ( '/' => sub { int($_[0]) / int($_[1]) } );
use overload ( '%' => sub { int($_[0]) % int($_[1]) } );
use overload ( '**' => sub { int($_[0]) ** int($_[1]) } );
use overload ( 'neg' => sub { -int($_[0]) } );

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
use vars qw/%_class_map/;

sub register_class_hint {
	my $class = shift;
	my %args = @_;

	$_class_map{hints}{$args{hint}} = \%args;
	$_class_map{classes}{$args{name}} = \%args;
}
JSON->register_class_hint(
	name => 'JSON::object_unknown',
	hint => 'DUNNO',
	type => 'hash',
);

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

sub _json_hint_to_class {
	my $hint = shift;
	return $_class_map{hints}{$hint}{name} if (exists $_class_map{hints}{$hint});
	return 'JSON::object_unknown';
}

sub JSON2perl {
	my $class = shift;
	local $_ = shift;

	# Convert JSON Unicode...
	s/\\u(\d{4})/chr(hex($1))/esog;

	warn $_;

	# Grab strings...
	my @strings = /"((?:(?:\\[\"])|[^\"])*)"/sog;

	# Replace with code...
	s/"(?:(?:\\[\"])|[^\"])*"/ shift(\@strings) /sog;

	# Perlify hash notation
	s/:/ => /sog;

	# handle class blessings
	s/\/\*--\s*S\w*?\s+\S+\s*--\*\// bless(/sog;
	s/\/\*--\s*E\w*?\s+(\S+)\s*--\*\// => _json_hint_to_class("$1")) /sog;

	s/\b(-?\d+\.?\d*)\b/ JSON::number::new($1) /sog;


	# Change javascript stuff to perl...
	s/null/ undef /sog;
	s/true/ bless( {}, "JSON::bool::true") /sog;
	s/false/ bless( {}, "JSON::bool::false") /sog;


	my $ret;
	return eval '$ret = '.$_;
}

sub old_JSON2perl {
	my ($class, $json) = @_;

	if (!defined($json)) {
		return undef;
	}

	$json =~ s/(?<!\\)\$/\\\$/gmo; # fixup $ for later
	$json =~ s/(?<!\\)\@/\\\@/gmo; # fixup @ for later

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
	my ($class, $perl) = @_;

	my $output = '';
	if (!defined($perl)) {
		$output = 'null';
	} elsif (ref($perl) and ref($perl) =~ /^JSON/) {
		$output .= $perl;
	} elsif ( ref($perl) && exists($_class_map{classes}{ref($perl)}) ) {
		$output .= '/*--S '.$_class_map{classes}{ref($perl)}{hint}.'--*/';
		if (lc($_class_map{classes}{ref($perl)}{type}) eq 'hash') {
			my %hash =  %$perl;
			$output .= perl2JSON(undef,\%hash);
		} elsif (lc($_class_map{classes}{ref($perl)}{type}) eq 'array') {
			my @array =  @$perl;
			$output .= perl2JSON(undef,\@array);
		}
		$output .= '/*--E '.$_class_map{classes}{ref($perl)}{hint}.'--*/';
	} elsif (ref($perl) and ref($perl) =~ /HASH/) {
		$output .= '{';
		my $c = 0;
		for my $key (sort keys %$perl) {
			$output .= ',' if ($c); 
			
			$output .= perl2JSON(undef,$key).':'.perl2JSON(undef,$$perl{$key});
			$c++;
		}
		$output .= '}';
	} elsif (ref($perl) and ref($perl) =~ /ARRAY/) {
		$output .= '[';
		my $c = 0;
		for my $part (@$perl) {
			$output .= ',' if ($c); 
			
			$output .= perl2JSON(undef,$part);
			$c++;
		}
		$output .= ']';
	} else {
		$perl =~ s/\\/\\\\/sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/(\pM)/sprintf('\u%0.4x',ord($1))/sgoe;
		$output = '"'.$perl.'"';
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
			
			$output .= perl2prettyJSON($part);
			$c++;
		}
		$depth--;
		$output .= "\n";
		$output .= "   "x$depth;
		$output .= "]";
	} else {
		$perl =~ s/\\/\\\\/sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/(\pM)/sprintf('\u%0.4x',ord($1))/sgoe;
		$output .= "   "x$depth unless($nospace);
		$output .= '"'.$perl.'"';
	}

	return $output;
}

1;
