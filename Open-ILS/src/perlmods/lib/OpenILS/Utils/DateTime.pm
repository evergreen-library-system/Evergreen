package OpenILS::Utils::DateTime;

use Time::Local;
use Errno;
use POSIX;
use FileHandle;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Exporter;
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::TimeZone;

=head1 NAME

OpenILS::Utils::DateTime;

=head1 DESCRIPTION

This contains several routines for doing date and time calculation. This
is derived from the date/time routines from OpenSRF::Utils.

=head1 VERSION

=cut

our $VERSION = 1.000;

use vars qw/@ISA $AUTOLOAD %EXPORT_TAGS @EXPORT_OK @EXPORT/;
push @ISA, 'Exporter';

%EXPORT_TAGS = (
	datetime	=> [qw(clean_ISO8601 gmtime_ISO8601 interval_to_seconds seconds_to_interval)],
);
Exporter::export_ok_tags('datetime');  # add aa, cc and dd to @EXPORT_OK

our $date_parser = DateTime::Format::ISO8601->new;

=head1 METHODS


=cut

sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self) or return undef;

	my $name = $AUTOLOAD;
	$name =~ s/.*://;   # strip fully-qualified portion

	if (defined($_[0])) {
		return $self->{$name} = shift;
	}
	return $self->{$name};
}

=head2 $thing->interval_to_seconds('interval') OR interval_to_seconds('interval')

=head2 $thing->seconds_to_interval($seconds) OR seconds_to_interval($seconds)

Returns the number of seconds for any interval passed, or the interval for the seconds.
This is the generic version of B<interval> listed below.

The interval must match the regex I</\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g>, for example
B<2 weeks, 3 d and 1hour + 17 Months> or
B<1 year, 5 Months, 2 weeks, 3 days and 1 hour of seconds> meaning 46148400 seconds.

	my $expire_time = time() + $thing->interval_to_seconds('17h 9m');

The time size indicator may be one of

=over 2

=item s[econd[s]]

for seconds

=item m[inute[s]]

for minutes

=item h[our[s]]

for hours

=item d[ay[s]]

for days

=item w[eek[s]]

for weeks

=item M[onth[s]]

for months (really (365 * 1d)/12 ... that may get smarter, though)

=item y[ear[s]]

for years (this is 365 * 1d)

=back

=cut
sub interval_to_seconds {
	my $self = shift;
        my $interval = shift || $self;

	$interval =~ s/(\d{2}):(\d{2}):(\d{2})/ $1 h $2 min $3 s /go;

        $interval =~ s/and/,/g;
        $interval =~ s/,/ /g;

        my $amount = 0;
        while ($interval =~ /\s*([\+-]?)\s*(\d+)\s*(\w+)\s*/g) {
		my ($sign, $count, $type) = ($1, $2, $3);
		$count = "$sign$count" if ($sign);
                $amount += $count if ($type =~ /^s/);
                $amount += 60 * $count if ($type =~ /^m(?!o)/oi);
                $amount += 60 * 60 * $count if ($type =~ /^h/);
                $amount += 60 * 60 * 24 * $count if ($type =~ /^d/oi);
                $amount += 60 * 60 * 24 * 7 * $count if ($type =~ /^w/oi);
                $amount += ((60 * 60 * 24 * 365)/12) * $count if ($type =~ /^mo/io);
                $amount += 60 * 60 * 24 * 365 * $count if ($type =~ /^y/oi);
        }
        return $amount;
}

sub seconds_to_interval {
	my $self = shift;
        my $interval = shift || $self;

        my $limit = shift || 's';
        $limit =~ s/^(.)/$1/o;

        my ($y,$ym,$M,$Mm,$w,$wm,$d,$dm,$h,$hm,$m,$mm,$s,$string);
        my ($year, $month, $week, $day, $hour, $minute, $second) =
                ('year','Month','week','day', 'hour', 'minute', 'second');

        if ($y = int($interval / (60 * 60 * 24 * 365))) {
                $string = "$y $year". ($y > 1 ? 's' : '');
                $ym = $interval % (60 * 60 * 24 * 365);
        } else {
                $ym = $interval;
        }
        return $string if ($limit eq 'y');

        if ($M = int($ym / ((60 * 60 * 24 * 365)/12))) {
                $string .= ($string ? ', ':'')."$M $month". ($M > 1 ? 's' : '');
                $Mm = $ym % ((60 * 60 * 24 * 365)/12);
        } else {
                $Mm = $ym;
        }
        return $string if ($limit eq 'M');

        if ($w = int($Mm / 604800)) {
                $string .= ($string ? ', ':'')."$w $week". ($w > 1 ? 's' : '');
                $wm = $Mm % 604800;
        } else {
                $wm = $Mm;
        }
        return $string if ($limit eq 'w');

        if ($d = int($wm / 86400)) {
                $string .= ($string ? ', ':'')."$d $day". ($d > 1 ? 's' : '');
                $dm = $wm % 86400;
        } else {
                $dm = $wm;
        }
        return $string if ($limit eq 'd');

        if ($h = int($dm / 3600)) {
                $string .= ($string ? ', ' : '')."$h $hour". ($h > 1 ? 's' : '');
                $hm = $dm % 3600;
        } else {
                $hm = $dm;
        }
        return $string if ($limit eq 'h');

        if ($m = int($hm / 60)) {
                $string .= ($string ? ', ':'')."$m $minute". ($m > 1 ? 's' : '');
                $mm = $hm % 60;
        } else {
                $mm = $hm;
        }
        return $string if ($limit eq 'm');

        if ($s = int($mm)) {
                $string .= ($string ? ', ':'')."$s $second". ($s > 1 ? 's' : '');
        } else {
                $string = "0s" unless ($string);
        }
        return $string;
}

sub gmtime_ISO8601 {
	my $self = shift;
	my @date = gmtime;

	my $y = $date[5] + 1900;
	my $M = $date[4] + 1;
	my $d = $date[3];
	my $h = $date[2];
	my $m = $date[1];
	my $s = $date[0];

	return sprintf('%d-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d+00:00', $y, $M, $d, $h, $m, $s);
}

sub clean_ISO8601 {
	my $self = shift;
	my $date = shift || $self;
	if ($date =~ /^\s*(\d{4})-?(\d{2})-?(\d{2})/o) {
		my $new_date = "$1-$2-$3";

		if ($date =~/(\d{2}):(\d{2}):(\d{2})/o) {
			$new_date .= "T$1:$2:$3";

			my $z;
			if ($date =~ /([-+]{1})([0-9]{1,2})(?::?([0-9]{1,2}))*\s*$/o) {
				$z = sprintf('%s%0.2d%0.2d',$1,$2,$3)
			} else {
				$z =  DateTime::TimeZone::offset_as_string(
					DateTime::TimeZone
						->new( name => 'local' )
						->offset_for_datetime(
							$date_parser->parse_datetime($new_date)
						)
				);
			}

			if (length($z) > 3 && index($z, ':') == -1) {
				substr($z,3,0) = ':';
				substr($z,6,0) = ':' if (length($z) > 6);
			}
		
			$new_date .= $z;
		} else {
			$new_date .= "T00:00:00";
		}

		return $new_date;
	}
	return $date;
}

1;
