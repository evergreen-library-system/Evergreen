package Fieldmapper;
use JSON;
use Data::Dumper;
use OpenILS::Application::Storage::CDBI;
use OpenILS::Application::Storage::CDBI::actor;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Application::Storage::CDBI::config;
use OpenILS::Application::Storage::CDBI::metabib;

use vars qw/$fieldmap $VERSION/;

_init();

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
		'Fieldmapper::actor::org_unit'			=> { hint => 'aou'  },
		'Fieldmapper::actor::org_unit_type'		=> { hint => 'aout' },
		'Fieldmapper::biblio::record_node'		=> { hint		=> 'brn',
								     proto_fields	=> { children => 1 } },
		'Fieldmapper::biblio::record_entry'		=> { hint => 'bre'  },
		'Fieldmapper::config::bib_source'		=> { hint => 'cbs'  },
		'Fieldmapper::config::metabib_field'		=> { hint => 'cmf'  },
		'Fieldmapper::metabib::metarecord'		=> { hint => 'mmr'  },
		'Fieldmapper::metabib::title_field_entry'	=> { hint => 'mmr'  },
		'Fieldmapper::metabib::author_field_entry'	=> { hint => 'mmr'  },
		'Fieldmapper::metabib::subject_field_entry'	=> { hint => 'mmr'  },
		'Fieldmapper::metabib::keyword_field_entry'	=> { hint => 'mmr'  },
		'Fieldmapper::metabib::full_rec'		=> { hint => 'mmr'  },
	};

	#-------------------------------------------------------------------------------
	# Now comes the evil!  Generate classes

	for my $pkg ( keys %$fieldmap ) {
		(my $cdbi = $pkg) =~ s/^Fieldmapper:://o;

		eval <<"		PERL";
			package $pkg;
			use base 'Fieldmapper';
		PERL

		$$fieldmapp{$pkg}{cdbi} = $cdbi;

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
			*{$obj->class_name."::clear_$field"} = sub {
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

sub api_level {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{api_level};
}

sub json_hint {
	my $self = shift;
	return $fieldmap->{$self->class_name}->{hint};
}


1;
