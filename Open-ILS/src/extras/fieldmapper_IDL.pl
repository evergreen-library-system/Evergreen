#!/usr/bin/perl
use strict;
use Data::Dumper;
use lib '../perlmods/';

{ package OpenILS::Application::Storage; sub register_method {}; }

my $map = {};
eval "
	use lib '../perlmods/';
	use lib '../../../OpenSRF/src/perlmods/';
	use OpenILS::Utils::Fieldmapper;  
	use OpenILS::Application::Storage::Driver::Pg::dbi;  
";
$map = $Fieldmapper::fieldmap unless ($@);

die $@ if ($@);


warn "Generating fieldmapper IDL xml...\n";

print <<XML;
<IDL xmlns="http://opensrf.org/spec/IDL/base/v1" xmlns:oils_persist="http://open-ils.org/spec/opensrf/IDL/persistance/v1" xmlns:oils_obj="http://open-ils.org/spec/opensrf/IDL/objects/v1">
XML


for my $object (keys %$map) {
	next unless ($map->{$object}->{cdbi});

	my $fm = $$map{$object}{cdbi};
	my $short_name= $map->{$object}->{hint};
	my ($primary) = $map->{$object}->{cdbi}->columns('Primary');
	my $table = $map->{$object}->{cdbi}->table;

	print <<"	XML";
	<class id="$short_name" oils_obj:fieldmapper="$fm" oils_persist:tablename="$table">
		<fields oils_persist:primary="$primary">
	XML

	for my $field (sort { $$map{$object}{fields}{$a}{position} <=> $$map{$object}{fields}{$b}{position}} keys %{$map->{$object}->{fields}}) {
		my $position = $map->{$object}->{fields}->{$field}->{position};
		my $virtual = $map->{$object}->{fields}->{$field}->{virtual} ? 'true' : 'false';
		print <<"		XML";
			<field name="$field" oils_obj:array_position="$position" oils_persist:virtual="$virtual" />
		XML
	}

	print <<"	XML";
		</fields>
		<links>
	XML

	my $meta = $$map{$object}{cdbi}->meta_info();
	#warn Dumper($meta);

	for my $reltype ( keys %$meta ) {
		for my $colname ( keys %{ $$meta{$reltype} } ) {
			my $col = $$meta{$reltype}{$colname};
			
			my $f_class = $col->foreign_class;
			my $fm_link = "Fieldmapper::$f_class";
			next unless $$map{$fm_link}{cdbi};

			my $f_key = $col->args->{foreign_key} || ($f_class->columns('Primary'))[0];
			my $f_hint = $$map{$fm_link}{hint};
			my $map = join ' ', @{ $col->args->{mapping} } if ( $col->args->{mapping} );

			print <<"			XML";
			<link field="$colname" reltype="$reltype" key="$f_key" map="$map" class="$f_hint"/>
			XML
		}
	}

	print <<"	XML";
		</links>
	</class>
	XML
}

print <<XML;
</IDL>
XML


