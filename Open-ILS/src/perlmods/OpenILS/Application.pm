package OpenILS::Application;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

sub ils_version {
    # version format is "x-y-z-p", for example "1-2-1-0" for Evergreen 1.2.1.0
    return "1-3";
}

__PACKAGE__->register_method(
    api_name    => 'opensrf.open-ils.system.ils_version',
    api_level   => 1,
    method      => 'ils_version',
);

1;

