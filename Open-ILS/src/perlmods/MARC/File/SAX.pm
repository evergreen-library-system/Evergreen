package MARC::File::SAX;

## no POD here since you don't really want to use this module
## directly. Look at MARC::File::XML instead.
##
## MARC::File::SAX is a SAX handler for parsing XML encoded using the 
## MARC21slim XML schema from the Library of Congress. It builds a MARC::Record
## object up from SAX events.
##
## For more details see: http://www.loc.gov/standards/marcxml/

use strict;
use XML::SAX;
use base qw( XML::SAX::Base );
use Data::Dumper;
use MARC::Charset;
use Encode ();

my $charset = MARC::Charset->new();
my $_is_unicode;

sub start_element {
    my ( $self, $element ) = @_;
    my $name = $element->{ Name };
    if ( $name eq 'leader' ) { 
	$self->{ tag } = 'LDR';
    } elsif ( $name eq 'controlfield' ) {
	$self->{ tag } = $element->{ Attributes }{ '{}tag' }{ Value };
    } elsif ( $name eq 'datafield' ) { 
	$self->{ tag } = $element->{ Attributes }{ '{}tag' }{ Value };
	$self->{ i1 } = $element->{ Attributes }{ '{}ind1' }{ Value };
	$self->{ i2 } = $element->{ Attributes }{ '{}ind2' }{ Value };
    } elsif ( $name eq 'subfield' ) { 
	$self->{ subcode } = $element->{ Attributes }{ '{}code' }{ Value };
    }
}

sub end_element { 
    my ( $self, $element ) = @_;
    my $name = $element->{ Name };
    if ( $name eq 'subfield' ) { 
	push( @{ $self->{ subfields } }, $self->{ subcode }, save_space_in_utf8($self->{ chars }) );
	$self->{ chars } = '';
	$self->{ subcode } = '';
    } elsif ( $name eq 'controlfield' ) { 
	$self->{ record }->append_fields(
	    MARC::Field->new(
		$self->{ tag },
		save_space_in_utf8($self->{ chars })
	    )
	);
	$self->{ chars } = '';
	$self->{ tag } = '';
    } elsif ( $name eq 'datafield' ) { 
	$self->{ record }->append_fields( 
	    MARC::Field->new( 
		$self->{ tag }, 
		$self->{ i1 }, 
		$self->{ i2 },
		@{ $self->{ subfields } }
	    )
	);
	$self->{ tag } = '';
	$self->{ i1 } = '';
	$self->{ i2 } = '';
	$self->{ subfields } = [];
	$self->{ chars } = '';
    } elsif ( $name eq 'leader' ) { 
	$_is_unicode = 0;
	my $ldr = $self->{ chars };
	$_is_unicode++ if (substr($ldr,9,1) eq 'a');
	substr($ldr,9,1,' ');
	$self->{ record }->leader( save_space_in_utf8($ldr) );
	$self->{ chars } = '';
	$self->{ tag } = '';
    }

}

sub save_space_in_utf8 {
	my $string = shift;
	my $output = '';
	while ($string =~ /(\s*)(\S*)(\s*)/gcsmo) {
		$output .= $1 . Encode::encode('latin1',$charset->to_marc8($2)) . $3;# if ($_is_unicode);
		#$output .= $1 . $2 . $3 unless ($_is_unicode);
	}
	return $output;
}

sub characters {
    my ( $self, $chars ) = @_;
    if ( $self->{ subcode } or ( $self->{ tag } and 
	( $self->{ tag } eq 'LDR' or $self->{ tag } < 10 ) ) ) { 
	$self->{ chars } .= $chars->{ Data };
    } 
}

1;
