package Fieldmapper;
use JSON;
use vars qw/$fieldmap @class_name_list/;

#
# To dump the Javascript version of the fieldmapper struct use the command:
#
#	PERL5LIB=~/cvs/ILS/OpenSRF/src/perlmods/:~/cvs/ILS/Open-ILS/src/perlmods/ GEN_JS=1 perl -MOpenILS::Utils::Fieldmapper -e 'print "\n";'
#
# ... adjusted for your CVS sandbox, of course.
#

$fieldmap = 
{
	'Fieldmapper::metabib::metarecord' =>
	{
		hint		=> 'cbs1',
		api_level	=> 1,
		fields		=>
		{
			id		=> { position =>  0, virtual => 0 },
			fingerprint	=> { position =>  1, virtual => 0 },
			master_record	=> { position =>  2, virtual => 0 },
			mods		=> { position =>  3, virtual => 0 },

			isnew		=> { position =>  4, virtual => 1 },
			ischanged	=> { position =>  5, virtual => 1 },
			isdeleted	=> { position =>  6, virtual => 1 },
		},
	},

	'Fieldmapper::config::bib_source' =>
	{
		hint		=> 'cbs1',
		api_level	=> 1,
		fields		=>
		{
			id	=> { position =>  0, virtual => 0 },
			quality	=> { position =>  1, virtual => 0 },
			source	=> { position =>  2, virtual => 0 },
		},
	},

	'Fieldmapper::config::metabib_field' =>
	{
		hint		=> 'cmf1',
		api_level	=> 1,
		fields		=>
		{
			id	=> { position =>  0, virtual => 0 },
			class	=> { position =>  1, virtual => 0 },
			name	=> { position =>  2, virtual => 0 },
			xpath	=> { position =>  3, virtual => 0 },
		},
	},

	'Fieldmapper::biblio::record_node' =>
	{
		hint		=> 'brn1',
		api_level	=> 1,
		fields		=>
		{
			id		=> { position =>  0, virtual => 0 },
			owner_doc	=> { position =>  1, virtual => 0 },
			intra_doc_id	=> { position =>  2, virtual => 0 },
			parent_node	=> { position =>  3, virtual => 0 },
			node_type	=> { position =>  4, virtual => 0 },
			namespace_uri	=> { position =>  5, virtual => 0 },
			name		=> { position =>  6, virtual => 0 },
			value		=> { position =>  7, virtual => 0 },
			last_xact_id	=> { position =>  8, virtual => 0 },

			isnew		=> { position =>  9, virtual => 1 },
			ischanged	=> { position => 10, virtual => 1 },
			isdeleted	=> { position => 11, virtual => 1 },
			children	=> { position => 12, virtual => 1 },
		},
	},

	'Fieldmapper::biblio::record_entry' =>
	{
		hint		=> 'bre1',
		api_level	=> 1,
		fields		=>
		{
			id		=> { position =>  0, virtual => 0 },
			tcn_source	=> { position =>  1, virtual => 0 },
			tcn_value	=> { position =>  2, virtual => 0 },
			creator		=> { position =>  3, virtual => 0 },
			editor		=> { position =>  4, virtual => 0 },
			create_date	=> { position =>  5, virtual => 0 },
			edit_date	=> { position =>  6, virtual => 0 },
			source		=> { position =>  7, virtual => 0 },
			active		=> { position =>  8, virtual => 0 },
			deleted		=> { position =>  9, virtual => 0 },
			last_xact_id	=> { position => 10, virtual => 0 },

			isnew		=> { position => 11, virtual => 1 },
			ischanged	=> { position => 12, virtual => 1 },
			isdeleted	=> { position => 13, virtual => 1 },
		},
	},

	'Fieldmapper::actor::user' =>
	{
		hint		=> 'au1',
		api_level	=> 1,
		fields		=>
		{
			id			=> { position =>  0, virtual => 0 },
			usrid			=> { position =>  1, virtual => 0 },
			usrname			=> { position =>  2, virtual => 0 },
			email			=> { position =>  3, virtual => 0 },
			prefix			=> { position =>  4, virtual => 0 },
			first_given_name	=> { position =>  5, virtual => 0 },
			second_given_name	=> { position =>  6, virtual => 0 },
			family_name		=> { position =>  7, virtual => 0 },
			suffix			=> { position =>  8, virtual => 0 },
			address			=> { position =>  9, virtual => 0 },
			home_ou			=> { position => 10, virtual => 0 },
			gender			=> { position => 11, virtual => 0 },
			dob			=> { position => 12, virtual => 0 },
			active			=> { position => 13, virtual => 0 },
			master_acount		=> { position => 14, virtual => 0 },
			super_user		=> { position => 15, virtual => 0 },
			usrgroup		=> { position => 16, virtual => 0 },
			passwd			=> { position => 17, virtual => 0 },
			last_xact_id		=> { position => 18, virtual => 0 },

			isnew			=> { position => 19, virtual => 1 },
			ischanged		=> { position => 20, virtual => 1 },
			isdeleted		=> { position => 21, virtual => 1 },
		},
	},
};

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


#-------------------------------------------------------------------------------
# Now comes the evil!  Generate classes

for my $pkg ( keys %$fieldmap ) {
	eval <<"	PERL";
		package $pkg;
		use base 'Fieldmapper';
	PERL

	push @class_name_list, $pkg;

	JSON->register_class_hint(
		hint => $pkg->json_hint,
		name => $pkg,
		type => 'array',
	);

}
print Fieldmapper->javascript() if ($ENV{GEN_JS});

1;
