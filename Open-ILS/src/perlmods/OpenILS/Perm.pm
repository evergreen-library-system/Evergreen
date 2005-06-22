package OpenILS::Perm;
use strict; use warnings;
use Template qw(:template);
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;

# ----------------------------------------------------------------------------------
# These permission strings
# ----------------------------------------------------------------------------------

# returns a new fieldmapper::perm_ex

sub new {

	my($class, $type) = @_;
	$class = ref($class) || $class;

	my $self = new Fieldmapper::perm_ex;

	$self->err_msg(_find_perm_string($type));
	$self->type($type);
	warn "perm type is $type\n";
	return $self;
}


sub _find_perm_string  {

	my $type = shift;

	my $result;
	my $conf = OpenSRF::Utils::SettingsClient->new;

	my $script = $conf->config_value("perm_script");

	my $template = Template->new(
		{ 
			ABSOLUTE		=> 1, 
			OUTPUT		=> \$result,
		}
	);

	my $status = $template->process($script, { type => $type });

	if(!$status) {
		throw OpenSRF::EX::ERROR 
			("Unable to process exception script.  No meaningful data to return..." .
			" Error is:\n" . $template->error() . "\n");
	}

	$result =~ s/^\s*//og;
	warn " -|-|-|- Perm Exception result [$result]\n";

	return $result;
}





1;
