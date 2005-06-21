package OpenILS::EX;
use strict; use warnings;
use Template qw(:template);
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;

# ----------------------------------------------------------------------------------
# These exceptions are not thrown.  They are returned as request result objects
# ----------------------------------------------------------------------------------

my %ex_types = (
	UNKNOWN									=> 1,
	SEARCH_TOO_LARGE						=> 2,
	UNKNOWN_BARCODE						=> 3,
	DUPLICATE_INVALID_USER_BARCODE	=> 4,
	DUPLICATE_USER_USERNAME				=> 5,
	USER_WRONG_PASSWORD					=> 6,
);

use overload ( '""' => sub { $_[0]->ex()->err_msg(); } );

sub new {

	my($class, $type) = @_;
	$class = ref($class) || $class;

	my $self = {};
	bless($self, $class);

	$self->{ex} = new Fieldmapper::ex;
	$self->{ex}->type($ex_types{$type});
	$self->{ex}->err_msg($self->run());
	warn "type is $type\n";

	return $self;
}


sub ex { return shift()->{ex}; }

sub run {

	my $self = shift;

	my $result;
	my $conf = OpenSRF::Utils::SettingsClient->new;

	my $script = $conf->config_value("ex_script");

	my $template = Template->new(
		{ 
			ABSOLUTE		=> 1, 
			OUTPUT		=> \$result,
			PRE_CHOMP	=> 1,
			POST_CHOMP	=> 1,
		}
	);

	my $status = $template->process($script, 
			{ ex_types => \%ex_types, type => $self->{ex}->type });

	if(!$status) {
		return "Unable to process exception script.  No meaningful data to return..." .
			" Error is:\n" . $template->error() . "\n";
	}

	$result =~ s/^\s*//og;
	warn " -|-|-|- Exception result [$result]\n";

	return $result;
}






