package MARC::File::XML;

use warnings;
use strict;
use base qw( MARC::File );
use MARC::Record;
use MARC::Field;
use MARC::File::SAX;
use MARC::Charset;
use IO::File;
use Carp qw( croak );
use Encode ();

our $VERSION = '0.66';

my $handler = MARC::File::SAX->new();
my $parser = XML::SAX::ParserFactory->parser( Handler => $handler );
my $charset = MARC::Charset->new();


=head1 NAME

MARC::File::XML - Work with MARC data encoded as XML 

=head1 SYNOPSIS

    ## reading with MARC::Batch
    my $batch = MARC::Batch->new( 'XML', $filename );
    my $record = $batch->next();

    ## or reading with MARC::File::XML explicitly
    my $file = MARC::File::XML->in( $filename );
    my $record = $file->next();

    ## serialize a single MARC::Record object as XML
    print $record->as_xml();

    ## write a bunch of records to a file
    my $file = MARC::File::XML->out( 'myfile.xml' );
    $file->write( $record1 );
    $file->write( $record2 );
    $file->write( $record3 );
    $file->close();

    ## instead of writing to disk, get the xml directly 
    my $xml = join( "\n", 
        MARC::File::XML::header(),
        MARC::File::XML::record( $record1 ),
        MARC::File::XML::record( $record2 ),
        MARC::File::XML::footer()
    );

=head1 DESCRIPTION

The MARC-XML distribution is an extension to the MARC-Record distribution for 
working with MARC21 data that is encoded as XML. The XML encoding used is the
MARC21slim schema supplied by the Library of Congress. More information may 
be obtained here: http://www.loc.gov/standards/marcxml/

You must have MARC::Record installed to use MARC::File::XML. In fact 
once you install the MARC-XML distribution you will most likely not use it 
directly, but will have an additional file format available to you when you
use MARC::Batch.

This version of MARC-XML supersedes an the versions ending with 0.25 which 
were used with the MARC.pm framework. MARC-XML now uses MARC::Record 
exclusively.

If you have any questions or would like to contribute to this module please
sign on to the perl4lib list. More information about perl4lib is available
at L<http://perl4lib.perl.org>.

=head1 METHODS

When you use MARC::File::XML your MARC::Record objects will have two new
additional methods available to them: 

=head2 as_xml()

Returns a MARC::Record object serialized in XML.

    print $record->as_xml();

=cut 

sub MARC::Record::as_xml {
    my $record = shift;
    my $enc = shift;
    return(  MARC::File::XML::encode( $record, $enc ) );
}

=head2 new_from_xml()

If you have a chunk of XML and you want a record object for it you can use 
this method to generate a MARC::Record object.

    my $record = MARC::Record->new_from_xml( $xml );

Note: only works for single record XML chunks.

=cut 

sub MARC::Record::new_from_xml {
    my $xml = shift;
    ## to allow calling as MARC::Record::new_from_xml()
    ## or MARC::Record->new_from_xml()
    $xml = shift if ( ref($xml) || ($xml eq "MARC::Record") );
    return( MARC::File::XML::decode( $xml ) );
}

=pod 

If you want to write records as XML to a file you can use out() with write()
to serialize more than one record as XML.

=head2 out()

A constructor for creating a MARC::File::XML object that can write XML to a
file. You must pass in the name of a file to write XML to.

    my $file = MARC::XML::File->out( $filename );

=cut

sub out {
    my ( $class, $filename ) = @_;
    my $fh = IO::File->new( ">$filename" ) or croak( $! );
    my %self = ( 
        filename    => $filename,
        fh          => $fh, 
        header      => 0
    );
    return( bless \%self, ref( $class ) || $class );
}

=head2 write()

Used in tandem with out() to write records to a file. 

    my $file = MARC::File::XML->out( $filename );
    $file->write( $record1 );
    $file->write( $record2 );

=cut

sub write {
    my ( $self, $record ) = @_;
    if ( ! $self->{ fh } ) { 
        croak( "MARC::File::XML object not open for writing" );
    }
    if ( ! $record ) { 
        croak( "must pass write() a MARC::Record object" );
    }
    ## print the XML header if we haven't already
    if ( ! $self->{ header } ) { 
        $self->{ fh }->print( header() );
        $self->{ header } = 1;
    } 
    ## print out the record
    $self->{ fh }->print( record( $record ) ) || croak( $! );
    return( 1 );
}

=head2 close()

When writing records to disk the filehandle is automatically closed when you
the MARC::File::XML object goes out of scope. If you want to close it explicitly
use the close() method.

=cut

sub close {
    return( 1 );
    my $self = shift;
    if ( $self->{ fh } ) {
        $self->{ fh }->print( footer() ) if $self->{ header };
        $self->{ fh } = undef;
        $self->{ filename } = undef;
        $self->{ header } = undef;
    }
    return( 1 );
}

## makes sure that the XML file is closed off

sub DESTROY {
    shift->close();
}

=pod

If you want to generate batches of records as XML, but don't want to write to
disk you'll have to use header(), record() and footer() to generate the
different portions.  

    $xml = join( "\n",
        MARC::File::XML::header(),
        MARC::File::XML::record( $record1 ),
        MARC::File::XML::record( $record2 ),
        MARC::File::XML::record( $record3 ),
        MARC::File::XML::footer()
    );

=head2 header() 

Returns a string of XML to use as the header to your XML file.

This method takes an optional $encoding parameter to set the output encoding
to something other than 'UTF-8'.  This is meant mainly to support slightly
broken records that are in ISO-8859-1 (ANSI) format with 8-bit characters.

=cut 

sub header {
    my $encoding = shift || 'UTF-8';
    return( <<MARC_XML_HEADER );
<?xml version="1.0" encoding="$encoding"?>
<collection xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd" xmlns="http://www.loc.gov/MARC21/slim">
MARC_XML_HEADER
}

=head2 footer()

Returns a string of XML to use at the end of your XML file.

=cut

sub footer {
    return( "</collection>" );
}

=head2 record()

Returns a chunk of XML suitable for placement between the header and the footer.

=cut

sub _perhaps_encode {
	my $data = shift;
	my $done = shift;
	$data = Encode::encode('utf8',$charset->to_utf8($data)) unless ($done);
	return $data;
}

sub record {
    my $record = shift;
    my $_is_unicode = shift;
    my @xml = ();
    push( @xml, "<record>" );
    push( @xml, "  <leader>" . escape( _perhaps_encode($record->leader(), $_is_unicode)) . "</leader>" );
    foreach my $field ( $record->fields() ) {
        my $tag = $field->tag();
        if ( $field->is_control_field() ) { 
	    my $data = $field->data;
            push( @xml, qq(  <controlfield tag="$tag">) .
                escape( _perhaps_encode($data, $_is_unicode) ). qq(</controlfield>) );
        } else {
            my $i1 = $field->indicator( 1 );
            my $i2 = $field->indicator( 2 );
            push( @xml, qq(  <datafield tag="$tag" ind1="$i1" ind2="$i2">) );
            foreach my $subfield ( $field->subfields() ) { 
                my ( $code, $data ) = @$subfield;
                push( @xml, qq(    <subfield code="$code">).
                    escape( _perhaps_encode($data, $_is_unicode) ).qq(</subfield>) );
            }
            push( @xml, "  </datafield>" );
        }
    }
    push( @xml, "</record>\n" );
    return( join( "\n", @xml ) );
}

my %ESCAPES = (
    '&'     => '&amp;',
    '<'     => '&lt;',
    '>'     => '&gt;',
);
my $ESCAPE_REGEX = 
    eval 'qr/' . 
    join( '|', map { $_ = "\Q$_\E" } keys %ESCAPES ) .
    '/;'
    ;

sub escape {
    my $string = shift;
    $string =~ s/($ESCAPE_REGEX)/$ESCAPES{$1}/oge;
    return( $string );
}

sub _next {
    my $self = shift;
    my $fh = $self->{ fh };

    ## return undef at the end of the file
    return if eof($fh);

    ## get a chunk of xml for a record
    local $/ = '</record>';
    my $xml = <$fh>;

    ## trim stuff before the start record element 
    $xml =~ s/.*<record.*?>/<record>/s;

    ## return undef if there isn't a good chunk of xml
    return if ( $xml !~ m|<record>.*</record>|s );
    
    ## return the chunk of xml
    return( $xml );
}

=head2 decode()

You probably don't ever want to call this method directly. If you do 
you should pass in a chunk of XML as the argument. 

It is normally invoked by a call to next(), see L<MARC::Batch> or L<MARC::File>.

=cut

sub decode { 

    my $text; 
    my $location = '';
    my $self = shift;

    ## see MARC::File::USMARC::decode for explanation of what's going on
    ## here
    if ( ref($self) =~ /^MARC::File/ ) {
	$location = 'in record '.$self->{recnum};
	$text = shift;
    } else {
	$location = 'in record 1';
	$text = $self=~/MARC::File/ ? shift : $self;
    }

    $parser->{ tagStack } = [];
    $parser->{ subfields } = [];
    $parser->{ Handler }{ record } = MARC::Record->new();
    $parser->parse_string( $text );

    return( $parser->{ Handler }{ record } );
    
}

=head2 encode([$encoding])

You probably want to use the as_marc() method on your MARC::Record object
instead of calling this directly. But if you want to you just need to 
pass in the MARC::Record object you wish to encode as XML, and you will be
returned the XML as a scalar.

This method takes an optional $encoding parameter to set the output encoding
to something other than 'UTF-8'.  This is meant mainly to support slightly
broken records that are in ISO-8859-1 (ANSI) format with 8-bit characters.

=cut

sub encode {
    my $record = shift;
    my $encoding = shift;

    my $_is_unicode = 0;
    my $ldr = $record->leader;
    my $needed_charset;

    if (defined $encoding) {
        # Are we forcing an alternate encoding?  Then leave it alone.
	
    } elsif (substr($ldr,9,1) eq 'a') {
        # Does the record think it is already Unicode?
        $_is_unicode++;
	if ( my ($unneeded_charset) = $record->field('066') ) {
		$record->delete_field( $unneeded_charset );
	}
	
    } else {
	# Not forcing an encoding, and it's NOT Unicode.  We set the leader to say
	# Unicode for the conversion, remove any '066' field, and put it back later.
	#
    	# XXX Need to generat a '066' field here, but I don't understand how yet.
	substr($ldr,9,1,'a');
	$record->leader( $ldr );
	if ( ($needed_charset) = $record->field('066') ) {
		$record->delete_field( $needed_charset );
	}
	
    }
	
    my @xml = ();
    push( @xml, header($encoding) );
    push( @xml, record( $record, $_is_unicode ) );
    push( @xml, footer() );

    if (defined $needed_charset) {
        $record->insert_fields_ordered($needed_charset);
	substr($ldr,8,1,' ');
	$record->leader( $ldr );
    }
    
    return( join( "\n", @xml ) );
}

=head1 TODO

=over 4

=item * Support for character translation using MARC::Charset.

=item * Support for callback filters in decode().

=item * Command line utilities marc2xml, etc.

=back

=head1 SEE ALSO

=over 4

=item L<http://www.loc.gov/standards/marcxml/>

=item L<MARC::File::USMARC>

=item L<MARC::Batch>

=item L<MARC::Record>

=back

=head1 AUTHORS

=over 4 

=item * Ed Summers <ehs@pobox.com>

=back

=cut

1;
