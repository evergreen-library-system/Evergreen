package OpenILS::Utils::DateTime;

use Time::Local;
use Errno;
use POSIX;
use FileHandle;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Exporter;
use DateTime;
use DateTime::Duration;
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

=head2 $thing->interval_to_seconds('interval', ['context']) OR interval_to_seconds('interval', ['context'])

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

Passing in an optional 'context' (DateTime object) will give you the number of seconds for the passed interval *starting from* the given date (e.g. '1 month' from a context of 'February 1' would return the number of seconds needed to get to 'March 1', not the generic calculation of 1/12 of the seconds in a normal year).

=back

=cut
sub interval_to_seconds {
    my $class = shift; # throwaway
    my $interval = ($class eq __PACKAGE__) ? shift : $class;
    my $context = shift;

    $interval =~ s/(\d{2,}):(\d{2}):(\d{2})/ $1 h $2 min $3 s /go;

    $interval =~ s/and/,/g;
    $interval =~ s/,/ /g;

    my $amount;
    if ($context) {
        my $dur = DateTime::Duration->new();
        while ($interval =~ /\s*([\+-]?)\s*(\d+)\s*(\w+)\s*/g) {
            my ($sign, $count, $type) = ($1, $2, $3);
            my $func = ($sign eq '-') ? 'subtract' : 'add';
            if ($type =~ /^s/) {
                $type = 'seconds';
            } elsif ($type =~ /^m(?!o)/oi) {
                $type = 'minutes';
            } elsif ($type =~ /^h/) {
                $type = 'hours';
            } elsif ($type =~ /^d/oi) {
                $type = 'days';
            } elsif ($type =~ /^w/oi) {
                $type = 'weeks';
            } elsif ($type =~ /^mo/io) {
                $type = 'months';
            } elsif ($type =~ /^y/oi) {
                $type = 'years';
            }
            $dur->$func($type => $count);
        }
        my $later = $context->clone->add_duration($dur);
        $amount = $later->subtract_datetime_absolute($context)->in_units( 'seconds' );
    } else {
        $amount = 0;
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

=head2 clean_ISO8601($date_string)

Given a date string or a date/time string in a variety of ad-hoc
formats, returns an ISO8601-formatted date/time string.

The date portion of the input is expected to consist of a four-digit
year, followed by a two-digit month, followed by a two-digit year,
with each part optionally separated by a hyphen.  If there is
only a date portion, it will be normalized to use hyphens.

If there is no time portion in the input, "T00:00:00" is appended
before the results are returned.

For example, "20180917" would become "2018-09-17T00:00:00".

If the input does not have a recognizable date, it is simply
returned as is.

If there is a time portion, it is expected to consist of two-digit
hour, minutes, and seconds delimited by colons.  That time is
appended to the return with "T" separting the date and time
portions.

If there is an ISO8601-style numeric timezone offset, it is
normalized and appended to the return. If there is no timezone
offset supplied in the input, the offset of the server's
time zone is append to the return. Note that as implied above,
if only a date is supplied, the return value does not include a
timezone offset.

For example, for a server running in U.S. Eastern Daylight
Savings time, "20180917 08:31:15" would become "2018-09-17T08:31:15-04:00".

=cut

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
			} elsif ($date =~ /Z\s*$/) {
				$z = "+00:00";
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
