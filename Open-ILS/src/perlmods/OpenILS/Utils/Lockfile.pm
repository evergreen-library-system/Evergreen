package OpenILS::Utils::Lockfile;

# ---------------------------------------------------------------
# Copyright (C) 2010 Equinox Software, Inc
# Author: Joe Atzberger <jatzberger@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

# The purpose of this module is to consolidate 
# non-duplicative processing, i.e. lockfiles and lockfile checking

use strict;
use warnings;
use Carp;

use File::Basename qw/fileparse/;

sub _tempdir {
    return $ENV{TEMP} || $ENV{TMP} || '/tmp';
}

our $debug =  0;

sub default_filename {
   my $tempdir = _tempdir;
   my $filename = fileparse($0, '.pl');
   return "$tempdir/$filename-LOCK";
}

sub new {
    my $class    = shift;
    my $lockfile = @_ ? shift : default_filename;
 
    croak "Script already running with lockfile $lockfile" if -e $lockfile;
    $debug and print "Writing lockfile $lockfile (PID: $$)\n";

    open (F, ">$lockfile") or croak "Cannot write to lockfile '$lockfile': $!";
    print F $$;
    close F;

    my $self = {
        filename => $lockfile,
        contents => $$,
    };
    return bless ($self, $class);
}

sub filename {
    my $self = shift;
    return $self->{filename};
}
sub contents {
    my $self = shift;
    return $self->{contents};
}

DESTROY {
    my $self = shift;
    # lockfile cleanup 
    if (-e $self->{filename}) {
        open LF, $self->{filename};
        my $contents = <LF>;
        close LF;
        $debug and print "deleting lockfile $self->{filename}\n";
        if ($contents == $self->{contents}) { 
            unlink $self->{filename} or carp "Failed to remove lockfile '$self->{filename}'";
        } else {
            carp "Lockfile contents '$contents' no longer match '$self->{contents}'.  Cannot remove $self->{filename}";
        }
        
    }
}

1;
