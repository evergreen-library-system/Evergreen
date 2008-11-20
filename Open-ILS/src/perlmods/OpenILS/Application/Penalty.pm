package OpenILS::Application::Penalty;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Application;
use OpenILS::Utils::Penalty;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use base 'OpenILS::Application';

__PACKAGE__->register_method (
	method	 => 'patron_penalty',
	api_name	 => 'open-ils.penalty.patron_penalty.calculate',
	signature => q/
		Calculates the patron's standing penalties
		@param args An object of named params including:
			patronid The id of the patron
			update True if this call should update the database
			background True if this call should return immediately,
				then go on to process the penalties.  This flag
				works only in conjunction with the 'update' flag.
		@return An object with keys 'fatal_penalties' and 
		'info_penalties' who are themeselves arrays of 0 or 
		more penalties.  Returns event on error.
	/
);

# --------------------------------------------------------------
# if $args->{background} is true, immediately respond complete 
# to the caller, then finish the calculation
# --------------------------------------------------------------
sub patron_penalty {
	my( $self, $conn, $args ) = @_;
	$conn->respond_complete(1) if $$args{background};
    my $e = new_editor(xact => 1);
    OpenILS::Utils::Penalty->calculate_penalties($e, $args->{patronid});
    my $p = OpenILS::Utils::Penalty->retrieve_penalties($e, $args->{patronid});
    $e->commit;
    return $p
}


1;
