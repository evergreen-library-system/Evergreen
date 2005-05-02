package OpenILS::Application::Circ::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;

my $apputils = "OpenILS::Application::AppUtils";
sub _d { warn "Patron:\n" . Dumper(shift()); }


__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.circ.patron.create",
);

