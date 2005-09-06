
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
	s/\\u(\d{4})/chr(hex($1))/esog;

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
#	s/\b(-?\d+\.?\d*)\b/ JSON::number::new($1) /sog;

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
			my $outkey = $key;
			$output .= ',' if ($c); 

			$outkey =~ s{\\}{\\\\}sgo;
			$outkey =~ s/"/\\"/sgo;
			$outkey =~ s/\t/\\t/sgo;
			$outkey =~ s/\f/\\f/sgo;
			$outkey =~ s/\r/\\r/sgo;
			$outkey =~ s/\n/\\n/sgo;
			$outkey =~ s/(\pM)/sprintf('\u%0.4x',ord($1))/sgoe;

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
	} elsif (ref($perl) and ("$perl" =~ /^([^=]+)=(\w+)/o)) {
		my $type = $2;
		my $name = $1;
		JSON->register_class_hint(name => $name, hint => $name, type => lc($type));
		$output .= perl2JSON(undef,$perl, $strict);
	} else {
		$perl = NFD($perl);
		$perl =~ s{\\}{\\\\}sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/(\P{L}|\P{N})/sprintf('\u%0.4x',ord($1))/sgoe;
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
	} elsif (ref($perl) and "$perl" =~ /^([^=]+)=(\w{4,5})\(0x/) {
		my $type = $2;
		my $name = $1;
		register_class_hint(undef, name => $name, hint => $name, type => lc($type));
		$output .= perl2prettyJSON(undef,$perl);
	} else {
		$perl = NFD($perl);
		$perl =~ s/\\/\\\\/sgo;
		$perl =~ s/"/\\"/sgo;
		$perl =~ s/\t/\\t/sgo;
		$perl =~ s/\f/\\f/sgo;
		$perl =~ s/\r/\\r/sgo;
		$perl =~ s/\n/\\n/sgo;
		$perl =~ s/(\P{L}|\P{N}|\P{P})/sprintf('\u%0.4x',ord($1))/sgoe;
		$output .= "   "x$depth unless($nospace);
		if (length($perl) < 10 and $perl =~ /^(?:\+|-)?\d*\.?\d+$/o and $perl !~ /^(?:\+|-)?0\d+/o ) {
			$output = $perl;
		} else {
			$output = '"'.$perl.'"';
		}
		$output .= '"'.$perl.'"';
	}

	return $output;
}

1;
