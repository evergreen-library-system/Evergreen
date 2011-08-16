package OpenILS::SIP::Msg;
use strict; use warnings;
# -------------------------------------------------------
# Defines the various screen messages
# Currently they are just constants.. they need to be
# moved to an external lang-specific source
# -------------------------------------------------------
use vars qw(@EXPORT_OK %EXPORT_TAGS);
use Exporter;
use base qw/Exporter/;


# ---------------------------------------------------------------------
# Shoves defined constants into the export array
# so they don't have to be listed twice in the code
# ---------------------------------------------------------------------
sub econst {
   my($name, $value) = @_;
   my $caller = caller;
   no strict;
   *{$name} = sub () { $value };
   push @{$caller.'::EXPORT_OK'}, $name;
}


econst OILS_SIP_MSG_CIRC_EXISTS => 'This item is already checked out';
econst OILS_SIP_MSG_CIRC_PERMIT_FAILED => 'Patron is not allowed to check out the selected item';
econst OILS_SIP_MSG_NO_BILL => 'Bill not found';
econst OILS_SIP_MSG_OVERPAYMENT => 'Overpayment not allowed';
econst OILS_SIP_MSG_BILL_ERR => 'An error occurred while retrieving bills';

%EXPORT_TAGS = ( const => [ @EXPORT_OK ] );


