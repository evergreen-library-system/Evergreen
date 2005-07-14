package OpenSRF::Utils;

=head1 NAME 

OpenSRF::Utils

=head1 DESCRIPTION 

This is a container package for methods that are useful to derived modules.
It has no constructor, and is generally not useful by itself... but this
is where most of the generic methods live.
 

=head1 METHODS 


=cut

use vars qw/@ISA $AUTOLOAD %EXPORT_TAGS @EXPORT_OK @EXPORT $VERSION/;
push @ISA, 'Exporter';

$VERSION = do { my @r=(q$Revision$=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

use Time::Local;
use Errno;
use POSIX;
use FileHandle;
#use Cache::FileCache;
#use Storable qw(dclone);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Exporter;

# This turns errors into warnings, so daemons don't die.
#$Storable::forgive_me = 1;

%EXPORT_TAGS = (common => [qw(interval_to_seconds seconds_to_interval sendmail)], daemon => [qw(safe_fork set_psname daemonize)]);

Exporter::export_ok_tags('common','daemon');  # add aa, cc and dd to @EXPORT_OK

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


sub _sub_builder {
	my $self = shift;
	my $class = ref($self) || $self;
	my $part = shift;
	unless ($class->can($part)) {
		*{$class.'::'.$part} =
			sub {
				my $self = shift;
				my $new_val = shift;
				if ($new_val) {
					$$self{$part} = $new_val;
				}
				return $$self{$part};
		};
	}
}

#sub standalone_ipc_cache {
#	my $self = shift;
#	my $class = ref($self) || $self;
#	my $uniquifier = shift || return undef;
#	my $expires = shift || 3600;

#	return new Cache::FileCache ( { namespace => $class.'::'.$uniquifier, default_expires_in => $expires } );
#}

sub sendmail {
	my $self = shift;
        my $message = shift || $self;

        open SM, '|/usr/sbin/sendmail -U -t' or return 0;
        print SM $message;
        close SM or return 0;
        return 1;
}

sub __strip_comments {
	my $self = shift;
	my $config_file = shift;
	my ($line, @done);
	while (<$config_file>) {
		s/^\s*(.*)\s*$/$1/o if (lc($$self{keep_space}) ne 'true');
		/^(.*)$/o;
		$line .= $1;
		# keep new lines if keep_space is true
		if ($line =~ /^$/o && (lc($$self{keep_space}) ne 'true')) {
			$line = '';
			next;
		}
		if (/^([^<]+)\s*<<\s*(\w+)\s*$/o) {
			$line = "$1 = ";
			my $breaker = $2;
			while (<$config_file>) {
				chomp;
				last if (/^$breaker/);
				$line .= $_;
			}
		}

		if ($line =~ /^#/ && $line !~ /^#\s*include\s+/o) {
			$line = '';
			next;
		}
		if ($line =~ /\\$/o) {
			chomp $line;
			$line =~ s/^\s*(.*)\s*\\$/$1/o;
			next;
		}
		push @done, $line;
		$line = '';
	}
	return @done;
}


=head2 $thing->encrypt(@stuff)

Returns a one way hash (MD5) of the values appended together.

=cut

sub encrypt {
	my $self = shift;
	return md5_hex(join('',@_));
}

=head2 $utils_obj->es_time('field') OR noo_es_time($timestamp)

Returns the epoch-second style timestamp for the value stored in
$utils_obj->{field}.  Returns B<0> for an empty or invalid date stamp, and
assumes a PostgreSQL style datestamp to be supplied.

=cut

sub es_time {
	my $self = shift;
	my $part = shift;
	my $es_part = $part.'_ES';
	return $$self{$es_part} if (exists($$self{$es_part}) && defined($$self{$es_part}) && $$self{$es_part});
	if (!$$self{$part} or $$self{$part} !~ /\d+/) {
		return 0;

	}
	my @tm = reverse($$self{$part} =~ /([\d\.]+)/og);
	if ($tm[5] > 0) {
		$tm[5] -= 1;
	}

        return $$self{$es_part} = noo_es_time($$self{$part});
}

=head2 noo_es_time($timestamp) (non-OO es_time)

Returns the epoch-second style timestamp for the B<$timestamp> passed
in.  Returns B<0> for an empty or invalid date stamp, and
assumes a PostgreSQL style datestamp to be supplied.

=cut

sub noo_es_time {
        my $timestamp = shift;

        my @tm = reverse($timestamp =~ /([\d\.]+)/og);
        if ($tm[5] > 0) {
                $tm[5] -= 1;
        }
        return timelocal(int($tm[1]), int($tm[2]), int($tm[3]), int($tm[4]) || 1, int($tm[5]), int($tm[6]) || 2002 );
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

        $interval =~ s/and/,/g;
        $interval =~ s/,/ /g;

        my $amount = 0;
        while ($interval =~ /\s*\+?\s*(\d+)\s*(\w{1})\w*\s*/g) {
                $amount += $1 if ($2 eq 's');
                $amount += 60 * $1 if ($2 eq 'm');
                $amount += 60 * 60 * $1 if ($2 eq 'h');
                $amount += 60 * 60 * 24 * $1 if ($2 eq 'd');
                $amount += 60 * 60 * 24 * 7 * $1 if ($2 eq 'w');
                $amount += ((60 * 60 * 24 * 365)/12) * $1 if ($2 eq 'M');
                $amount += 60 * 60 * 24 * 365 * $1 if ($2 eq 'y');
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
                $string = "Brand New!!!" unless ($string);
        }
        return $string;
}

sub full {
	my $self = shift;
	$$self{empty} = 0;
}

=head2 $utils_obj->set_psname('string') OR set_psname('string')

Sets the name of this process in a B<ps> listing to B<string>.


=cut

sub set_psname {
	my $self = shift;
	my $PS_NAME = shift || $self;
	$0 = $PS_NAME if ($PS_NAME);
}

sub clense_ISO8601 {
	my $self = shift;
	my $date = shift || $self;
	if ($date =~ /(\d{4})-?(\d{2})-?(\d{2}).?(\d{2}):(\d{2}):(\d{2})\.?\d*((?:-|\+)\d{2,4})?$/) {
		my $z = $7 || '-00';
		$date = "$1-$2-$3T$4:$5:$6$z";
	}
	return $date;
}

=head2 $utils_obj->daemonize('ps_name') OR daemonize('ps_name')

Turns the current process into a daemon.  B<ps_name> is optional, and is used
as the argument to I<< set_psname() >> if passed.


=cut

sub daemonize {
	my $self = shift;
	my $PS_NAME = shift || $self;
	my $pid;
	if ($pid = safe_fork($self)) {
		exit 0;
	} elsif (defined($pid)) {
		set_psname($PS_NAME);
		chdir '/';
		setsid;
		return $$;
	}
}

=head2 $utils_obj->safe_fork('ps_name') OR safe_fork('ps_name');

Forks the current process in a retry loop.  B<ps_name> is optional, and is used
as the argument to I<< set_psname() >> if passed.


=cut

sub safe_fork {
	my $self = shift;
	my $pid;

FORK:
	{
		if (defined($pid = fork())) {
			srand(time ^ ($$ + ($$ << 15))) unless ($pid);
			return $pid;
		} elsif ($! == EAGAIN) {
			$self->error("Can't fork()!  $!, taking 5 and trying again.") if (ref $self);
			sleep 5;
			redo FORK;
		} else {
			$self->error("Can't fork()! $!") if ($! && ref($self));
			exit $!;
		}
	}
}

#------------------------------------------------------------------------------------------------------------------------------------


1;
