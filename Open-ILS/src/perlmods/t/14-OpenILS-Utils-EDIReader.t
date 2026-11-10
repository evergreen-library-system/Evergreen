use strict;
use warnings;

use Test::More tests => 2;

use_ok( 'OpenILS::Utils::EDIReader' );

# In this test, we separate each EDI segment into its own line
# for readability.  This subroutine concatenates everything back
# into the sort of message we would actually receive.
sub concatenate_message {
  my $raw = shift;
  $raw =~ s/\s*[\r\n]+\s*//g;
  return $raw;
}

subtest 'when PO name has a / in it (RFF segment with LI info)', sub {
  plan tests => 1;
  my $message = <<~'END_MESSAGE';
    UNA:+.? '
    UNB+UNOB:3+:31B+9876543 0121:31B+8761234:1415+1'
    UNH+1+ORDERS:D:96A:UN'
    BGM+220+462+9'
    DTM+137:20300101:102'
    NAD+BY+::31B'
    NAD+SU+9876543 0121::31B'
    NAD+SU+123::92'
    CUX+2:USD:9'
    LIN+25549++9781578262724:EN'
    PIA+5+9781578262724:EN+1578262720:IB+25549:IN'
    IMD+F+BTI+:::THE CAPTAIN?'S GUIDE TO WRECKS AND R:EEFS ?: Florida?'s East &amp; West Co'
    IMD+F+BTI+:::ast, Florida?'s Keys, the Bahamas'
    IMD+F+BPU+:::Random House Inc'
    IMD+F+BPD+:::2013'
    IMD+F+BPH+:::208 p. ;'
    QTY+21:4'
    FTX+LIN+1'
    PRI+AAB:9'
    RFF+LI:ENF/JNF 5-29-26/203687'
    LIN+25556++9780762786534:EN'
    PIA+5+9780762786534:EN+25556:IN'
    IMD+F+BTI+:::SCENIC ROUTES &amp; BYWAYS VIRGINIA'
    IMD+F+BPU'
    IMD+F+BPD'
    IMD+F+BPH'
    QTY+21:8'
    FTX+LIN+1'
    PRI+AAB:11.97'
    RFF+LI:SF/M/C 6-25-26/25556'
    LIN+25562++9780848739621:EN'
    PIA+5+9780848739621:EN+123123123:IB+25562:IN'
    IMD+F+BTI+:::Southern living no taste like home.'
    IMD+F+BPU'
    IMD+F+BPD'
    IMD+F+BPH+:::319 pages'
    QTY+21:2'
    FTX+LIN+1'
    PRI+AAB:14.95'
    RFF+LI:SF/M/C 6-25-26/25562'
    LIN+25576++9780789315458:EN'
    PIA+5+9780789315458:EN+25576:IN'
    IMD+F+BTI+:::TENNIS ?: HOW TO MASTER THE GAME'
    IMD+F+BPU'
    IMD+F+BPD'
    IMD+F+BPH'
    QTY+21:6'
    FTX+LIN+1'
    PRI+AAB:19.5'
    RFF+LI:93345/25576'
    UNS+S'
    CNT+2:19'
    UNT+51+1'
    UNZ+1+1'
  END_MESSAGE

  my $reader = OpenILS::Utils::EDIReader->new;
  my $parsed = $reader->read(concatenate_message($message));

  my @ids = map { $_->{id} } @{$parsed->[0]->{lineitems}};
  is_deeply \@ids, ['203687', '25556', '25562', '25576'],
    'it can find the line item ids';
}
