package OpenILS::Const;
use strict; use warnings;
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

# ---------------------------------------------------------------------
# CONSTANTS
# ---------------------------------------------------------------------



# ---------------------------------------------------------------------
# Copy Statuses
# ---------------------------------------------------------------------
econst OILS_COPY_STATUS_AVAILABLE     => 0;
econst OILS_COPY_STATUS_CHECKED_OUT   => 1;
econst OILS_COPY_STATUS_BINDERY       => 2;
econst OILS_COPY_STATUS_LOST          => 3;
econst OILS_COPY_STATUS_MISSING       => 4;
econst OILS_COPY_STATUS_IN_PROCESS    => 5;
econst OILS_COPY_STATUS_IN_TRANSIT    => 6;
econst OILS_COPY_STATUS_RESHELVING    => 7;
econst OILS_COPY_STATUS_ON_HOLDS_SHELF=> 8;
econst OILS_COPY_STATUS_ON_ORDER	     => 9;
econst OILS_COPY_STATUS_ILL           => 10;
econst OILS_COPY_STATUS_CATALOGING    => 11;
econst OILS_COPY_STATUS_RESERVES      => 12;
econst OILS_COPY_STATUS_DISCARD       => 13;
econst OILS_COPY_STATUS_DAMAGED       => 14;


# ---------------------------------------------------------------------
# Circ defaults for pre-cataloged copies
# ---------------------------------------------------------------------
econst OILS_PRECAT_COPY_FINE_LEVEL    => 2;
econst OILS_PRECAT_COPY_LOAN_DURATION => 2;
econst OILS_PRECAT_CALL_NUMBER        => -1;
econst OILS_PRECAT_RECORD			     => -1;


# ---------------------------------------------------------------------
# Circ constants
# ---------------------------------------------------------------------
econst OILS_CIRC_DURATION_SHORT       => 1;
econst OILS_CIRC_DURATION_NORMAL      => 2;
econst OILS_CIRC_DURATION_EXTENDED    => 3;
econst OILS_REC_FINE_LEVEL_LOW        => 1;
econst OILS_REC_FINE_LEVEL_NORMAL     => 2;
econst OILS_REC_FINE_LEVEL_HIGH       => 3;
econst OILS_STOP_FINES_CHECKIN        => 'CHECKIN';
econst OILS_STOP_FINES_RENEW          => 'RENEW';
econst OILS_STOP_FINES_LOST           => 'LOST';
econst OILS_STOP_FINES_CLAIMSRETURNED => 'CLAIMSRETURNED';
econst OILS_STOP_FINES_LONGOVERDUE    => 'LONGOVERDUE';
econst OILS_STOP_FINES_MAX_FINES      => 'MAXFINES';
econst OILS_UNLIMITED_CIRC_DURATION   => 'unlimited';

# ---------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------
econst OILS_SETTING_LOST_PROCESSING_FEE => 'circ.lost_materials_processing_fee';
econst OILS_SETTING_DEF_ITEM_PRICE => 'cat.default_item_price';
econst OILS_SETTING_ORG_BOUNCED_EMAIL => 'org.bounced_emails';
econst OILS_SETTING_CHARGE_LOST_ON_ZERO => 'circ.charge_lost_on_zero';
econst OILS_SETTING_VOID_OVERDUE_ON_LOST => 'circ.void_overdue_on_lost';
econst OILS_SETTING_HOLD_SOFT_STALL => 'circ.hold_stalling.soft';
econst OILS_SETTING_HOLD_HARD_STALL => 'circ.hold_stalling.hard';
econst OILS_SETTING_HOLD_SOFT_BOUNDARY => 'circ.hold_boundary.soft';
econst OILS_SETTING_HOLD_HARD_BOUNDARY => 'circ.hold_boundary.hard';
econst OILS_SETTING_HOLD_EXPIRE => 'circ.hold_expire_interval';



econst OILS_HOLD_TYPE_COPY        => 'C';
econst OILS_HOLD_TYPE_VOLUME      => 'V';
econst OILS_HOLD_TYPE_TITLE       => 'T';
econst OILS_HOLD_TYPE_METARECORD  => 'M';


econst OILS_BILLING_TYPE_OVERDUE_MATERIALS => 'Overdue materials';
econst OILS_BILLING_TYPE_COLLECTION_FEE => 'Long Overdue Collection Fee';

econst OILS_ACQ_DEBIT_TYPE_PURCHASE => 'purchase';
econst OILS_ACQ_DEBIT_TYPE_TRANSFER => 'xfer';



# ---------------------------------------------------------------------
# finally, export all the constants
# ---------------------------------------------------------------------
%EXPORT_TAGS = ( const => [ @EXPORT_OK ] );

