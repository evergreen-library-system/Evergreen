package OpenILS::Application::Acq;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Application::Acq::Picklist;
use OpenILS::Application::Acq::Financials;
use OpenILS::Application::Acq::Provider;
use OpenILS::Application::Acq::Lineitem;
use OpenILS::Application::Acq::Order;
use OpenILS::Application::Acq::EDI;
use OpenILS::Application::Acq::Search;
use OpenILS::Application::Acq::Claims;
use OpenILS::Application::Acq::Invoice;

1;
