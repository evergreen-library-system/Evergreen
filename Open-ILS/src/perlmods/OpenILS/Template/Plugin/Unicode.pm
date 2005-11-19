package OpenILS::Template::Plugin::Unicode;
use Unicode::Normalize;

sub new { return bless {}, __PACKAGE__ }
sub load { return __PACKAGE__ }

sub C { shift; return NFC(@_); }
sub D { shift; return NFD(@_); }
sub entityDecode { shift; $_ = shift; s/&#x([0-9a-fA-F]+);/chr(hex($1))/egos; return $_ }
sub entityEncode { shift; $_ = shift; s/(\PM\pM+)/sprintf('&#x%0.4x;',ord(NFC($1)))/sgoe; return $_ }

1;
