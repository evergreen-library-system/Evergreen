package OpenILS::Application::Acq;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;

use OpenILS::Application::Acq::Picklist;
use OpenILS::Application::Acq::Financials;

1;
