package Fieldmapper;
use JSON;
use vars qw/$fieldmap @class_list/;

$fieldmap = 
{
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

			isnew		=> { position =>  8, virtual => 1 },
			ischanged	=> { position =>  9, virtual => 1 },
			isdeleted	=> { position => 10, virtual => 1 },
			children	=> { position => 11, virtual => 1 },
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
			metarecord	=> { position =>  3, virtual => 0 },
			creator		=> { position =>  4, virtual => 0 },
			editor		=> { position =>  5, virtual => 0 },
			create_date	=> { position =>  6, virtual => 0 },
			edit_date	=> { position =>  7, virtual => 0 },
			source		=> { position =>  8, virtual => 0 },
			active		=> { position =>  9, virtual => 0 },
			deleted		=> { position => 10, virtual => 0 },

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

			isnew			=> { position => 18, virtual => 1 },
			ischanged		=> { position => 19, virtual => 1 },
			isdeleted		=> { position => 20, virtual => 1 },
		},
	},
};

sub new {
	my $self = shift;
	my $value = shift;
	$value = [] unless (defined $value);
	return bless $value => $self->class;
}

sub javascript {
	my $class = shift;
	$class = $class->class;
	my $js_class = $class->json_hint;
	
	my $output = <<"	JS";

function $js_class (thing) { var new_thing = thing; if (!new_thing) { new_thing = []; } return new_thing; }
  $js_class.prototype.class_name = function () { return "$js_class"; }
	JS

	for my $field ( sort keys %{$$fieldmap{$class}{fields}} ) {
		my $pos = $$fieldmap{$class}{fields}{$field}{position};
		$output .= <<"		JS";
  $js_class.prototype.$field = function (arg) { if (arg) { this[$pos] = arg; } return this[$pos]; }
		JS
	}
	return $output;
}

sub AUTOLOAD {
	my $obj = shift;
	my $value = shift;
	(my $field = $AUTOLOAD) =~ s/^.*://o;
	my $class = $obj->class;

	die "No field by the name $field in $class!"
		unless (exists $$fieldmap{$class}{fields}{$field});

	my $pos = $$fieldmap{$class}{fields}{$field}{position};

	{	no strict 'subs';
		*{$obj->class."::$field"} = sub {
			my $self = shift;
			my $new_val = shift;
			$self->[$pos] = $new_val if (defined $new_val);
			return $self->[$pos];
		};
	}

	return $obj->$field($value);
}

sub class {
	my $class = shift;
	return ref($class) || $class;
}

sub real_fields {
	my $class = shift;
	my @f = grep {
			!$$fieldmap{$self->class}{fields}{$_}{virtual}
		} keys %{$$fieldmap{$self->class}{fields}};

	return @f;
}

sub api_level {
	my $self = shift;
	return $fieldmap->{$self->class}->{api_level};
}

sub json_hint {
	my $self = shift;
	return $fieldmap->{$self->class}->{hint};
}


#-------------------------------------------------------------------------------
# Now comes the evil!  Generate classes

for my $pkg ( keys %$fieldmap ) {
	eval <<"	PERL";
		package $pkg;
		use base 'Fieldmapper';
	PERL

	push @class_list, $pkg;

	JSON->register_class_hint(
		hint => $pkg->json_hint,
		name => $pkg,
		type => 'array',
	);

	print $pkg->javascript if ($ENV{GEN_JS});
}

1;
