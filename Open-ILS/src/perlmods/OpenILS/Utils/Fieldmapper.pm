package Fieldmapper;
use JSON;
use Data::Dumper;
use base 'OpenSRF::Application';

use OpenSRF::Utils::Logger;
my $log = 'OpenSRF::Utils::Logger';

use OpenILS::Application::Storage::CDBI;
use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::config;
use OpenILS::Application::Storage::CDBI::metabib;

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
	return if (defined $fieldmap);

	$fieldmap = 
	{
		'Fieldmapper::actor::user'			=> { hint => 'au'   },
		'Fieldmapper::actor::org_unit'			=> { hint 		=> 'aou',
								     proto_fields	=> { children => 1 } },
		'Fieldmapper::actor::org_unit_type'		=> { hint 		=> 'aout',
								     proto_fields	=> { children => 1 } },
		
		'Fieldmapper::biblio::record_node'		=> { hint		=> 'brn',
								     proto_fields	=> { children => 1 } },
		'Fieldmapper::biblio::record_entry'		=> { hint		=> 'bre',
								     proto_fields	=> { call_numbers => 1 } },
		'Fieldmapper::biblio::record_mods'		=> { hint => 'brm'  },
		'Fieldmapper::biblio::record_marc'		=> { hint => 'brx'  },

		'Fieldmapper::config::bib_source'		=> { hint => 'cbs'  },
		'Fieldmapper::config::metabib_field'		=> { hint => 'cmf'  },

		'Fieldmapper::metabib::metarecord'		=> { hint => 'mmr'  },
		'Fieldmapper::metabib::title_field_entry'	=> { hint => 'mtfe' },
		'Fieldmapper::metabib::author_field_entry'	=> { hint => 'mafe' },
		'Fieldmapper::metabib::subject_field_entry'	=> { hint => 'msfe' },
		'Fieldmapper::metabib::keyword_field_entry'	=> { hint => 'mkfe' },
		'Fieldmapper::metabib::full_rec'		=> { hint => 'mfr'  },

		'Fieldmapper::asset::copy'			=> { hint => 'acp'  },
		'Fieldmapper::asset::copy_note'			=> { hint => 'acpn' },
		'Fieldmapper::asset::call_number'		=> { hint		=> 'acn',
								     proto_fields	=> { copies => 1 } },
		'Fieldmapper::asset::call_number_note'		=> { hint => 'acnn' },
	};

	#-------------------------------------------------------------------------------
	# Now comes the evil!  Generate classes

	for my $pkg ( keys %$fieldmap ) {
		(my $cdbi = $pkg) =~ s/^Fieldmapper:://o;

		eval <<"		PERL";
			package $pkg;
			use base 'Fieldmapper';
		PERL

		$$fieldmap{$pkg}{cdbi} = $cdbi;

		my $pos = 0;
		for my $vfield ( qw/isnew ischanged isdeleted/ ) {
			$$fieldmap{$pkg}{fields}{$vfield} = { position => $pos, virtual => 1 };
			$pos++;
		}

		if (exists $$fieldmap{$pkg}{proto_fields}) {
			for my $pfield ( keys %{ $$fieldmap{$pkg}{proto_fields} } ) {
				$$fieldmap{$pkg}{fields}{$pfield} = { position => $pos, virtual => $$fieldmap{$pkg}{proto_fields}{$pfield} };
				$pos++;
			}
		}

		for my $col ( $cdbi->columns('All') ) {
			$$fieldmap{$pkg}{fields}{$col} = { position => $pos, virtual => 0 };
			$pos++;
		}

		JSON->register_class_hint(
			hint => $pkg->json_hint,
			name => $pkg,
			type => 'array',
		);

	}

	print Fieldmapper->javascript() if ($ENV{GEN_JS});
}

sub new {
	my $self = shift;
	my $value = shift;
	$value = [] unless (defined $value);
	return bless $value => $self->class_name;
}

sub javascript {
	my $class_name = shift;
	return 'var fieldmap = ' . JSON->perl2JSON($fieldmap) . ';'
}

sub DESTROY {}

sub AUTOLOAD {
	my $obj = shift;
	my $value = shift;
	(my $field = $AUTOLOAD) =~ s/^.*://o;
	my $class_name = $obj->class_name;


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
		unless (exists $$fieldmap{$class_name}{fields}{$field});

	my $pos = $$fieldmap{$class_name}{fields}{$field}{position};

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

sub api_level {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{api_level};
}

sub json_hint {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{hint};
}


1;
