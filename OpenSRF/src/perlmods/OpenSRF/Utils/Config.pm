package OpenSRF::Utils::Config::Section;

no strict 'refs';

use vars qw/@ISA $AUTOLOAD $VERSION/;
push @ISA, qw/OpenSRF::Utils/;

use OpenSRF::Utils (':common');

$VERSION = do { my @r=(q$Revision$=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

my %SECTIONCACHE;
my %SUBSECTION_FIXUP;

#use overload '""' => \&OpenSRF::Utils::Config::dump_ini;

sub SECTION {
	my $sec = shift;
	return $sec->__id(@_);
}

sub new {
	my $self = shift;
	my $class = ref($self) || $self;

	$self = bless {}, $class;

	my $lines = shift;

	for my $line (@$lines) {

		#($line) = split(/\s+\/\//, $line);
		#($line) = split(/\s+#/, $line);

		if ($line =~ /^\s*\[([^\[\]]+)\]/) {
			$self->_sub_builder('__id');
			$self->__id( $1 );
			next;
		}

		my ($protokey,$value,$keytype,$key);
		if ($line =~ /^([^=\s]+)\s*=\s*(.*)/s) {
			($protokey,$value) = ($1,$2);
			($keytype,$key) = split(/:/,$protokey);
		}

		$key = $protokey unless ($key);

		if ($keytype ne $key) {
			$keytype = lc $keytype;
			if ($keytype eq 'list') {
				$value = [split /\s*,\s*/, $value];
			} elsif ($keytype eq 'bool') {
				$value = do{ $value =~ /^t|y|1/i ? 1 : 0; };
			} elsif ($keytype eq 'interval') {
				$value = interval_to_seconds($value);
			} elsif ($keytype eq 'subsection') {
				if (exists $SECTIONCACHE{$value}) {
					$value = $SECTIONCACHE{$value};
				} else {
					$SUBSECTION_FIXUP{$value}{$self->SECTION} = $key ;
					next;
				}
			}
		}

		$self->_sub_builder($key);
		$self->$key($value);
	}

	no warnings;
	if (my $parent_def = $SUBSECTION_FIXUP{$self->SECTION}) {
		my ($parent_section, $parent_key) = each %$parent_def;
		$SECTIONCACHE{$parent_section}->{$parent_key} = $self;
		delete $SUBSECTION_FIXUP{$self->SECTION};
	}

	$SECTIONCACHE{$self->SECTION} = $self;

	return $self;
}

package OpenSRF::Utils::Config;

use vars qw/@ISA $AUTOLOAD $VERSION $OpenSRF::Utils::ConfigCache/;
push @ISA, qw/OpenSRF::Utils/;

use FileHandle;
use OpenSRF::Utils (':common');  
use OpenSRF::Utils::Log (':levels');

#use overload '""' => \&OpenSRF::Utils::Config::dump_ini;

sub import {
	my $class = shift;
	my $config_file = shift;

	return unless $config_file;

	$class->load( config_file => $config_file);
}

sub dump_ini {
	no warnings;
        my $self = shift;
        my $string;
	my $included = 0;
	if ($self->isa('OpenSRF::Utils::Config')) {
		if (UNIVERSAL::isa(scalar(caller()), 'OpenSRF::Utils::Config' )) {
			$included = 1;
		} else {
			$string = "# Main File:  " . $self->FILE . "\n\n" . $string;
		}
	}
        for my $section ( ('__id', grep { $_ ne '__id' } sort keys %$self) ) {
		next if ($section eq 'env' && $self->isa('OpenSRF::Utils::Config'));
                if ($section eq '__id') {
			$string .= '['.$self->SECTION."]\n" if ($self->isa('OpenSRF::Utils::Config::Section'));
		} elsif (ref($self->$section)) {
                        if (ref($self->$section) =~ /ARRAY/o) {
                                $string .= "list:$section = ". join(', ', @{$self->$section}) . "\n";
			} elsif (UNIVERSAL::isa($self->$section,'OpenSRF::Utils::Config::Section')) {
				if ($self->isa('OpenSRF::Utils::Config::Section')) {
					$string .= "subsection:$section = " . $self->$section->SECTION . "\n";
					next;
				} else {
					next if ($self->$section->{__sub} && !$included);
					$string .= $self->$section . "\n";
				}
                        } elsif (UNIVERSAL::isa($self->$section,'OpenSRF::Utils::Config')) {
				$string .= $self->$section . "\n";
			}
		} else {
			next if $section eq '__sub';
                       	$string .= "$section = " . $self->$section . "\n";
		}
        }
	if ($included) {
		$string =~ s/^/## /gm;
		$string = "# Subfile:  " . $self->FILE . "\n#" . '-'x79 . "\n".'#include "'.$self->FILE."\"\n". $string;
	}

        return $string;
}

=head1 NAME
 
OpenSRF::Utils::Config
 

=head1 SYNOPSIS

 
  use OpenSRF::Utils::Config;

  my $config_obj = OpenSRF::Utils::Config->load( config_file   => '/config/file.cnf' );

  my $attrs_href = $config_obj->attributes();

  $config_obj->attributes->no_db(0);

  open FH, '>'.$config_obj->FILE() . '.new';
  print FH $config_obj;
  close FH;

 

=head1 DESCRIPTION

 
This module is mainly used by other modules to load a configuration file.
 

=head1 NOTES

 
Hashrefs of sections can be returned by calling a method of the object of the same name as the section.
They can be set by passing a hashref back to the same method.  Sections will B<NOT> be autovivicated, though.

Here be a config file example, HAR!:

 [datasource]
 # backend=XMLRPC
 backend=DBI
 subsection:definition=devel_db

 [devel_db]
 dsn=dbi:Pg(RaiseError => 0, AutoCommit => 1):dbname=dcl;host=nsite-dev
 user=postgres
 pw=postgres
 #readonly=1
 
 [live_db]
 dsn=dbi:Pg(RaiseError => 0, AutoCommit => 1):dbname=dcl
 user=n2dcl
 pw=dclserver
 #readonly=1

 [devel_xmlrpc]
 subsection:definition=devel_rpc
 
 [logs]
 base=/var/log/nsite
 debug=debug.log
 error=error.log
 
 [debug]
 enabled=1
 level=ALL
 
 [devel_rpc]
 url=https://localhost:9000/
 proto=SSL
 SSL_cipher_list=ALL
 SSL_verify_mode=5
 SSL_use_cert=1
 SSL_key_file=client-key.pem
 SSL_cert_file=client-cert.pem
 SSL_ca_file=cacert.pem
 log_level=4
 
 [dirs]
 base_dir=/home/miker/cvs/NOC/monitor_core/
 cert_dir=certs/
 

=head1 METHODS


=cut


$VERSION = do { my @r=(q$Revision$=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };


=head2 OpenSRF::Utils::Config->load( config_file => '/some/config/file.cnf' )

Returns a OpenSRF::Utils::Config object representing the config file that was loaded.
The most recently loaded config file (hopefully the only one per app)
is stored at $OpenSRF::Utils::ConfigCache. Use OpenSRF::Utils::Config::current() to get at it.


=cut

sub load {
	my $pkg = shift;
	$pkg = ref($pkg) || $pkg;

	my %args = @_;

	(my $new_pkg = $args{config_file}) =~ s/\W+/_/g;
	$new_pkg .= "::$pkg";
	$new_section_pkg .= "${new_pkg}::Section";

	{	eval <<"		PERL";

			package $new_pkg;
			use base $pkg;
			sub section_pkg { return '$new_section_pkg'; }

			package $new_section_pkg;
			use base "${pkg}::Section";
	
		PERL
	}

	return $new_pkg->_load( %args );
}

sub _load {
	my $pkg = shift;
	$pkg = ref($pkg) || $pkg;
	my $self = {@_};
	bless $self, $pkg;

	no warnings;
	if ((exists $$self{config_file} and OpenSRF::Utils::Config->current) and (OpenSRF::Utils::Config->current->FILE eq $$self{config_file}) and (!$self->{force})) {
		delete $$self{force};
		return OpenSRF::Utils::Config->current();
	}

	$self->_sub_builder('__id');
	$self->FILE($$self{config_file});
	delete $$self{config_file};
	return undef unless ($self->FILE);

	$self->load_config();
	$self->load_env();
	$self->mangle_dirs();
	$self->mangle_logs();

	$OpenSRF::Utils::ConfigCache = $self unless $self->nocache;
	delete $$self{nocache};
	delete $$self{force};
	return $self;
}

sub sections {
	my $self = shift;
	my %filters = @_;

	my @parts = (grep { UNIVERSAL::isa($_,'OpenSRF::Utils::Config::Section') } values %$self);
	if (keys %filters) {
		my $must_match = scalar(keys %filters);
		my @ok_parts;
		foreach my $part (@parts) {
			my $part_count = 0;
			for my $fkey (keys %filters) {
				$part_count++ if ($part->$key eq $filters{$key});
			}
			push @ok_parts, $part if ($part_count == $must_match);
		}
		return @ok_parts;
	}
	return @parts;
}

sub current {
	return $OpenSRF::Utils::ConfigCache;
}

sub FILE {
	return shift()->__id(@_);
}

sub load_env {
	my $self = shift;
	my $host = `hostname -f`  || `uname -n`;
	chomp $host;
	$$self{env} = $self->section_pkg->new;
	$$self{env}{hostname} = $host;
}

sub mangle_logs {
	my $self = shift;
	return unless ($self->logs && $self->dirs && $self->dirs->log_dir);
	for my $i ( keys %{$self->logs} ) {
		next if ($self->logs->$i =~ /^\//);
		$self->logs->$i($self->dirs->log_dir."/".$self->logs->$i);
	}
}

sub mangle_dirs {
	my $self = shift;
	return unless ($self->dirs && $self->dirs->base_dir);
	for my $i ( keys %{$self->dirs} ) {
		if ( $i ne 'base_dir' ) {
			next if ($self->dirs->$i =~ /^\//);
			my $dir_tmp = $self->dirs->base_dir."/".$self->dirs->$i;
			$dir_tmp =~ s#//#/#go;
			$dir_tmp =~ s#/$##go;
			$self->dirs->$i($dir_tmp);
		}
	}
}

sub load_config {
	my $self = shift;
	my $config = new FileHandle $self->FILE, 'r';
	unless ($config) {
		OpenSRF::Utils::Log->error("Could not open ".$self->FILE.": $!\n");
		die "Could not open ".$self->FILE.": $!\n";
	}
	my @stripped_config = $self->__strip_comments($config) if (defined $config);

	my $chunk = [];
	for my $line (@stripped_config) {
		no warnings;
		next unless ($line);

		if ($line =~ /^\s*\[/ and @$chunk) {
			my $section = $self->section_pkg->new($chunk);

			my $sub_name = $section->SECTION;
			$self->_sub_builder($sub_name);
			$self->$sub_name($section);

			#$self->{$section->SECTION} = $section;

			$chunk = [];
			push @$chunk,$line;
			next;
		} 
		if ($line =~ /^#\s*include\s+"(\S+)"\s*$/o) {
                        my $included_file = $1;
			my $section = OpenSRF::Utils::Config->load(config_file => $included_file, nocache => 1);

			my $sub_name = $section->FILE;
			$self->_sub_builder($sub_name);
			$self->$sub_name($section);

			for my $subsect (keys %$section) {
				next if ($subsect eq '__id');

				$self->_sub_builder($subsect);
				$self->$subsect($$section{$subsect});

				#$self->$subsect($section->$subsect);
				$self->$subsect->{__sub} = 1;
			}
			next;
		}

		push @$chunk,$line;
	}
	my $section = $self->section_pkg->new($chunk) if (@$chunk);
	my $sub_name = $section->SECTION;
	$self->_sub_builder($sub_name);
	$self->$sub_name($section);

}


#------------------------------------------------------------------------------------------------------------------------------------

=head1 SEE ALSO

	OpenSRF::Utils

=head1 BUGS

No know bugs, but report any to miker@purplefrog.com.

=head1 COPYRIGHT AND LICENSING

Mike Rylander, Copyright 2000-2004

The OpenSRF::Utils::Config module is free software. You may distribute under the terms
of the GNU General Public License version 2 or greater.

=cut


1;
