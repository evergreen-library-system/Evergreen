package Fieldmapper;
use OpenSRF::Utils::JSON;
use Data::Dumper;
use base 'OpenSRF::Application';
use OpenSRF::Utils::Logger;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::System;
use XML::LibXML;
use Scalar::Util 'blessed';

my $log = 'OpenSRF::Utils::Logger';

use vars qw/$fieldmap $VERSION/;

sub publish_fieldmapper {
	my ($self,$client,$class) = @_;

	return $fieldmap unless (defined $class);
	return undef unless (exists($$fieldmap{$class}));
	return {$class => $$fieldmap{$class}};
}
__PACKAGE__->register_method(
	api_name	=> 'opensrf.open-ils.system.fieldmapper',
	api_level	=> 1,
	method		=> 'publish_fieldmapper',
);

#
# To dump the Javascript version of the fieldmapper struct use the command:
#
#	PERL5LIB=:~/vcs/ILS/Open-ILS/src/perlmods/lib/ GEN_JS=1 perl -MOpenILS::Utils::Fieldmapper -e 'print "\n";'
#
# ... adjusted for your VCS sandbox of choice, of course.
#

sub classes {
	return () unless (defined $fieldmap);
	return keys %$fieldmap;
}

# Find a Fieldmapper class given the json hint.
sub class_for_hint {
    my $hint = shift;
    foreach (keys %$fieldmap) {
        return $_ if ($fieldmap->{$_}->{hint} eq $hint);
    }
    return undef;
}

sub get_attribute {
	my $attr_list = shift;
	my $attr_name = shift;

	my $attr = $attr_list->getNamedItem( $attr_name );
	if( defined( $attr ) ) {
		return $attr->getValue();
	}
	return undef;
}

sub load_fields {
	my $field_list = shift;
	my $fm = shift;

	# Get attributes of the field list.  Since there is only one
	# <field> per class, these attributes logically belong to the
	# enclosing class, and that's where we load them.

	my $field_attr_list = $field_list->attributes();

	my $sequence  = get_attribute( $field_attr_list, 'oils_persist:sequence' );
	if( ! defined( $sequence ) ) {
		$sequence = '';
	}
	my $primary   = get_attribute( $field_attr_list, 'oils_persist:primary' );

	# Load attributes into the Fieldmapper ----------------------

	$$fieldmap{$fm}{ sequence } = $sequence;
	$$fieldmap{$fm}{ identity } = $primary;

	# Load each field -------------------------------------------

	my $array_position = 0;
	for my $field ( $field_list->childNodes() ) {    # For each <field>
		if( $field->nodeName eq 'field' ) {
	
			my $attribute_list = $field->attributes();
			
			my $name     = get_attribute( $attribute_list, 'name' );
			next if( $name eq 'isnew' || $name eq 'ischanged' || $name eq 'isdeleted' );
			my $required  = get_attribute( $attribute_list, 'oils_obj:required' );
			my $validate  = get_attribute( $attribute_list, 'oils_obj:validate' );
			my $virtual  = get_attribute( $attribute_list, 'oils_persist:virtual' );
			if( ! defined( $virtual ) ) {
				$virtual = "false";
			}
			my $selector = get_attribute( $attribute_list, 'reporter:selector' );

			$$fieldmap{$fm}{fields}{ $name } =
				{ virtual => ( $virtual eq 'true' ) ? 1 : 0,
				  required => ( $required eq 'true' ) ? 1 : 0,
				  position => $array_position,
				};

			$$fieldmap{$fm}{fields}{ $name }{validate} = qr/$validate/ if (defined($validate));

			# The selector attribute, if present at all, attaches to only one
			# of the fields in a given class.  So if we see it, we store it at
			# the level of the enclosing class.

			if( defined( $selector ) ) {
				$$fieldmap{$fm}{selector} = $selector;
			}

			++$array_position;
		}
	}

	# Load the standard 3 virtual fields ------------------------

	for my $vfield ( qw/isnew ischanged isdeleted/ ) {
		$$fieldmap{$fm}{fields}{ $vfield } =
			{ position => $array_position,
			  virtual => 1
			};
		++$array_position;
	}
}

sub load_links {
	my $link_list = shift;
	my $fm = shift;

	for my $link ( $link_list->childNodes() ) {    # For each <link>
		if( $link->nodeName eq 'link' ) {
			my $attribute_list = $link->attributes();
			
			my $field   = get_attribute( $attribute_list, 'field' );
			my $reltype = get_attribute( $attribute_list, 'reltype' );
			my $key     = get_attribute( $attribute_list, 'key' );
			my $class   = get_attribute( $attribute_list, 'class' );
			my $map	    = get_attribute( $attribute_list, 'map' );

			$$fieldmap{$fm}{links}{ $field } =
				{ class   => $class,
				  reltype => $reltype,
				  key     => $key,
				  map     => $map
				};
		}
	}
}

sub load_class {
	my $class_node = shift;

	# Get attributes ---------------------------------------------

	my $attribute_list = $class_node->attributes();

	my $fm               = get_attribute( $attribute_list, 'oils_obj:fieldmapper' );
	$fm                  = 'Fieldmapper::' . $fm;
	my $id               = get_attribute( $attribute_list, 'id' );
	my $controller       = get_attribute( $attribute_list, 'controller' );
	my $virtual          = get_attribute( $attribute_list, 'virtual' );
	if( ! defined( $virtual ) ) {
		$virtual = 'false';
	}
	my $tablename        = get_attribute( $attribute_list, 'oils_persist:tablename' );
	if( ! defined( $tablename ) ) {
		$tablename = '';
	}
	my $restrict_primary = get_attribute( $attribute_list, 'oils_persist:restrict_primary' );
	my $field_safe = get_attribute( $attribute_list, 'oils_persist:field_safe' );

	# Load the attributes into the Fieldmapper --------------------

	$log->debug("Building Fieldmapper class for [$fm] from IDL");

	$$fieldmap{$fm}{ hint }             = $id;
	$$fieldmap{$fm}{ virtual }          = ( $virtual eq 'true' ) ? 1 : 0;
	$$fieldmap{$fm}{ table }            = $tablename;
	$$fieldmap{$fm}{ controller }       = [ split ' ', $controller ];
	$$fieldmap{$fm}{ restrict_primary } = $restrict_primary;
	$$fieldmap{$fm}{ field_safe }       = $field_safe;

	# Load fields and links

	for my $child ( $class_node->childNodes() ) {
		my $nodeName = $child->nodeName;
		if( $nodeName eq 'fields' ) {
			load_fields( $child, $fm );
		} elsif( $nodeName eq 'links' ) {
			load_links( $child, $fm );
		}
	}
}

import();
sub import {
	my $class = shift;
	my %args = @_;

	return if (keys %$fieldmap);
	return if (!OpenSRF::System->connected && !$args{IDL});

	# parse the IDL ...
	my $parser = XML::LibXML->new();
	my $file = $args{IDL} || OpenSRF::Utils::SettingsClient->new->config_value( 'IDL' );
	my $fmdoc = $parser->parse_file( $file );
	my $rootnode = $fmdoc->documentElement();

	for my $child ( $rootnode->childNodes() ) {    # For each <class>
		my $nodeName = $child->nodeName;
		if( $nodeName eq 'class' ) {
			load_class( $child );
		}
	}

	#-------------------------------------------------------------------------------
	# Now comes the evil!  Generate classes

	for my $pkg ( __PACKAGE__->classes ) {
		(my $cdbi = $pkg) =~ s/^Fieldmapper:://o;

		eval <<"		PERL";
			package $pkg;
			use base 'Fieldmapper';
		PERL

		if (exists $$fieldmap{$pkg}{proto_fields}) {
			for my $pfield ( sort keys %{ $$fieldmap{$pkg}{proto_fields} } ) {
				$$fieldmap{$pkg}{fields}{$pfield} = { position => $pos, virtual => $$fieldmap{$pkg}{proto_fields}{$pfield} };
				$pos++;
			}
		}

		OpenSRF::Utils::JSON->register_class_hint(
			hint => $pkg->json_hint,
			name => $pkg,
			type => 'array',
		);

	}
}

sub new {
	my $self = shift;
	my $value = shift;
	$value = [] unless (defined $value);
	return bless $value => $self->class_name;
}

sub decast {
	my $self = shift;
	return [ @$self ];
}

sub DESTROY {}

sub AUTOLOAD {
	my $obj = shift;
	my $value = shift;
	(my $field = $AUTOLOAD) =~ s/^.*://o;
	my $class_name = $obj->class_name;

	my $fpos = $field;
	$fpos  =~ s/^clear_//og ;

	my $pos = $$fieldmap{$class_name}{fields}{$fpos}{position};

	if ($field =~ /^clear_/o) {
		{	no strict 'subs';
			*{$obj->class_name."::$field"} = sub {
				my $self = shift;
				$self->[$pos] = undef;
				return 1;
			};
		}
		return $obj->$field();
	}

	die "No field by the name $field in $class_name!"
		unless (exists $$fieldmap{$class_name}{fields}{$field} && defined($pos));


	{	no strict 'subs';
		*{$obj->class_name."::$field"} = sub {
			my $self = shift;
			my $new_val = shift;
			$self->[$pos] = $new_val if (defined $new_val);
			return $self->[$pos];
		};
	}
	return $obj->$field($value);
}

sub Selector {
	my $self = shift;
	return $$fieldmap{$self->class_name}{selector};
}

sub Identity {
	my $self = shift;
	return $$fieldmap{$self->class_name}{identity};
}

sub RestrictPrimary {
	my $self = shift;
	return $$fieldmap{$self->class_name}{restrict_primary};
}

sub Sequence {
	my $self = shift;
	return $$fieldmap{$self->class_name}{sequence};
}

sub Table {
	my $self = shift;
	return $$fieldmap{$self->class_name}{table};
}

sub Controller {
	my $self = shift;
	return $$fieldmap{$self->class_name}{controller};
}

sub RequiredField {
	my $self = shift;
	my $f = shift;
    return undef unless ($f);
	return $$fieldmap{$self->class_name}{fields}{$f}{required};
}

sub toXML {
    my $self = shift;
    return undef unless (ref $self);

    my $opts = shift || {};
    my $no_virt = $$opts{no_virt}; # skip virtual fields
    my $skip_fields = $$opts{skip_fields} || {}; # eg. {au => ['passwd']}
    my @to_skip = @{$$skip_fields{$self->json_hint}} 
        if $$skip_fields{$self->json_hint};

    my $dom = XML::LibXML::Document->new;
    my $root = $dom->createElement( $self->json_hint );
    $dom->setDocumentElement( $root );

    my @field_names = $no_virt ? $self->real_fields : $self->properties;

    for my $f (@field_names) {
        next if ($f eq 'isnew');
        next if ($f eq 'ischanged');
        next if ($f eq 'isdeleted');
        next if (grep {$_ eq $f} @to_skip);

        my $value = $self->$f();
        my $element = $dom->createElement( $f );

        $value = [$value] if (blessed($value)); # fm object

        if (ref($value)) { # array
            for my $k (@$value) {
                if (blessed($k)) {
                    my $subdoc = $k->toXML($opts);
                    next unless $subdoc;
                    my $subnode = $subdoc->documentElement;
                    $dom->adoptNode($subnode);
                    $element->appendChild($subnode);
                } elsif (ref $k) { # not sure what to do here
                    $element->appendText($k);
                } else { # meh .. just append, I guess
                    $element->appendText($k);
                }
            }
        } else {
            $element->appendText($value);
        }

        $root->appendChild($element);
    }

    return $dom;
}

sub ValidateField {
	my $self = shift;
	my $f = shift;
    return undef unless ($f);
	return 1 if (!exists($$fieldmap{$self->class_name}{fields}{$f}{validate}));
	return $self->$f =~ $$fieldmap{$self->class_name}{fields}{$f}{validate};
}

sub class_name {
	my $class_name = shift;
	return ref($class_name) || $class_name;
}

sub real_fields {
	my $self = shift;
	my $class_name = $self->class_name;
	my $fields = $$fieldmap{$class_name}{fields};

	my @f = grep {
			!$$fields{$_}{virtual}
		} sort {$$fields{$a}{position} <=> $$fields{$b}{position}} keys %$fields;

	return @f;
}

sub has_field {
	my $self = shift;
	my $field = shift;
	my $class_name = $self->class_name;
	return 1 if grep { $_ eq $field } keys %{$$fieldmap{$class_name}{fields}};
	return 0;
}

sub properties {
	my $self = shift;
	my $class_name = $self->class_name;
	return keys %{$$fieldmap{$class_name}{fields}};
}

sub to_bare_hash {
	my $self = shift;

	my %hash = ();
	for my $f ($self->properties) {
		my $val = $self->$f;
		$hash{$f} = $val;
	}

	return \%hash;
}

sub clone {
	my $self = shift;
	return $self->new( [@$self] );
}

sub api_level {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{api_level};
}

sub cdbi {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{cdbi};
}

sub is_virtual {
	my $self = shift;
	my $field = shift;
	return $fieldmap->{$self->class_name}->{proto_fields}->{$field} if ($field);
	return $fieldmap->{$self->class_name}->{virtual};
}

sub is_readonly {
	my $self = shift;
	my $field = shift;
	return $fieldmap->{$self->class_name}->{readonly};
}

sub json_hint {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{hint};
}


1;
