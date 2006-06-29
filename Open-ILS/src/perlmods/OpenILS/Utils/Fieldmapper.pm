package Fieldmapper;
use JSON;
use Data::Dumper;
use base 'OpenSRF::Application';
use OpenSRF::Utils::Logger;
use OpenSRF::Utils::SettingsClient;
use XML::Simple;

my $log = 'OpenSRF::Utils::Logger';

use vars qw/$fieldmap $VERSION/;

_init();

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
#	PERL5LIB=~/cvs/ILS/OpenSRF/src/perlmods/:~/cvs/ILS/Open-ILS/src/perlmods/ GEN_JS=1 perl -MOpenILS::Utils::Fieldmapper -e 'print "\n";'
#
# ... adjusted for your CVS sandbox, of course.
#

sub classes {
	return () unless (defined $fieldmap);
	return keys %$fieldmap;
}

sub _init {
	return if (keys %$fieldmap);

        # parse the IDL ...
        my $file = OpenSRF::Utils::SettingsClient->new->config_value( 'IDL' );
        my $idl = XMLin( $file )->{class};
	for my $c ( keys %$idl ) {
		next unless ($idl->{$c}{'oils_obj:fieldmapper'});
		my $n = 'Fieldmapper::'.$idl->{$c}{'oils_obj:fieldmapper'};

		$log->debug("Building Fieldmapper clas for [$n] from IDL");

		$$fieldmap{$n}{hint} = $c;
		$$fieldmap{$n}{virtual} = ($idl->{$c}{'oils_persist:virtual'} eq 'true') ? 1 : 0;

		for my $f ( keys %{ $idl->{$c}{fields}{field} } ) {
			$$fieldmap{$n}{fields}{$f} =
				{ virtual => ($idl->{$c}{fields}{field}{$f}{'oils_persist:virtual'} eq 'true') ? 1 : 0,
				  position => $idl->{$c}{fields}{field}{$f}{'oils_obj:array_position'}
				};
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

		my $pos = 0;
		for my $vfield ( qw/isnew ischanged isdeleted/ ) {
			$$fieldmap{$pkg}{fields}{$vfield} = { position => $pos, virtual => 1 };
			$pos++;
		}

		if (exists $$fieldmap{$pkg}{proto_fields}) {
			for my $pfield ( sort keys %{ $$fieldmap{$pkg}{proto_fields} } ) {
				$$fieldmap{$pkg}{fields}{$pfield} = { position => $pos, virtual => $$fieldmap{$pkg}{proto_fields}{$pfield} };
				$pos++;
			}
		}

		JSON->register_class_hint(
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
