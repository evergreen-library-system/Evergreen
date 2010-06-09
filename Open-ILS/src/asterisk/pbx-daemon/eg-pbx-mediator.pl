#!/usr/bin/perl -w
#
# Copyright (C) 2009 Equinox Software, Inc.
# Author: Lebbeous Fogle-Weekley
# Author: Joe Atzberger
#
# License:
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# Overview:
#
#   This script is to be used on an asterisk server as an RPC::XML
#   daemon targeted by Evergreen.
#
# Configuration:
#
#   See the eg-pbx-daemon.conf and extensions.conf.example files.
#
# Usage:
#
#   perl mediator.pl -c /path/to/eg-pbx-daemon.conf
#
# TODO:
#
# ~ Server retrieval of done files.
# ~ Option to archive (/etc/asterisk/spool/outgoing_really_done) instead of delete?
# ~ Accept globby prefix for filtering files to be retrieved.
# ~ init.d startup/shutdown/status script.
# ~ More docs.
# ~ perldoc/POD
# - command line usage and --help
#

use warnings;
use strict;

use RPC::XML::Server;
use Config::General qw/ParseConfig/;
use Getopt::Std;
use File::Basename qw/basename fileparse/;
use Sys::Syslog qw/:standard :macros/;

our %config;
our %opts = (c => "/etc/eg-pbx-daemon.conf");
our $last_n = 0;
our $universal_prefix = 'EG';

my $failure = sub {
    syslog LOG_ERR, $_[0];

    return new RPC::XML::fault(
        faultCode => 500,
        faultString => $_[0])
};

my $bad_request = sub {
    syslog LOG_WARNING, $_[0];

    return new RPC::XML::fault(
        faultCode => 400,
        faultString => $_[0])
};

sub load_config {
    %config = ParseConfig($opts{c});

    # validate
    foreach my $opt (qw/staging_path spool_path done_path/) {
        if (not -d $config{$opt}) {
            die $config{$opt} . " ($opt): no such directory";
        }
    }

    if ($config{port} < 1 || $config{port} > 65535) {
        die $config{port} . ": not a valid port number";
    }

    if (!($config{owner} = getpwnam($config{owner})) > 0) {
        die $config{owner} . ": invalid owner";
    }

    if (!($config{group} = getgrnam($config{group})) > 0) {
        die $config{group} . ": invalid group";
    }

    my $path = $config{done_path};
    (chdir $path) or die "Cannot open dir '$path': $!";

    if ($config{universal_prefix}) {
        $universal_prefix = $config{universal_prefix};
        $universal_prefix =~ /^\D/
            or die "Config error: universal_prefix ($universal_prefix) must start with non-integer character";
    }
}

sub replace_match_possible {
# arguments: a string (requested_filename), parsed to see if it has the necessary
#            components to use for finding possible queued callfiles to delete
# returns: (userid, $noticetype) if either or both is found, else undef;
    my $breakdown = shift or return;
    $breakdown =~ s/\..*$//;    # cut everything at the 1st period
    $breakdown =~ /([^_]*)_([^_]*)$/ or return;
    return ($1, $2);
}

sub replace_match_files {
# arguments: (id_string1, id_string2)
# returns: array of pathnames (files to be deleted)
# currently we will only find at most 1 file to replace,
# but you can see how this could be extended w/ additional namespace and globbing
    my $userid     = shift or return;   # doesn't have to be userid,     could be any ID string
    my $noticetype = shift or return;   # doesn't have to be noticetype, could be any extra dimension of uniqueness
    my $pathglob   = $config{spool_path} . "/" . compose_filename($userid, $noticetype);
    # my $pathglob = $config{spool_path} . "/$universal_prefix" . "_$userid" . "_$noticetype" . '*.call';
    my @matches    = grep {-f $_} <${pathglob}>;    # don't use <$pathglob>, that looks like ref to HANDLE
    warn               scalar(@matches) . " match(es) for path: $pathglob";
    syslog LOG_NOTICE, scalar(@matches) . " match(es) for path: $pathglob";
    return @matches;
}

sub compose_filename {
    return sprintf "%s_%s_%s.call", $universal_prefix, (@_?shift:''), (@_?shift:'');
}
sub auto_filename {
    return sprintf("%s_%d-%05d.call", $universal_prefix, time, $last_n++);
}
sub prefixer {
    # guarantee universal prefix on string (but don't add it again)
    my $string = @_ ? shift : '';
    $string =~ /^$universal_prefix\_/ and return $string;
    return $universal_prefix . '_' . $string;
}

sub inject {
    my ($data, $requested_filename, $timestamp) = @_;
# Sender can specify filename: [PREFIX . '_' .] id_string1 . '_' . id_string2 [. '.' . time-serial . '.call']
# TODO: overwrite based on id_strings, possibly controlled w/ extra arg?

    my $ret = {
        code => 200,    # optimism
        use_allocator => $config{use_allocator},
    };
    my $fname;
    $requested_filename = fileparse($requested_filename || ''); # no fair trying to get us to write in other dirs
    if ($requested_filename and $requested_filename ne 'default') {
        # Check for possible replacement of files
        my ($userid, $noticetype) = replace_match_possible($requested_filename);
        $ret->{replace_match} = ($userid and $noticetype) ? 1 : 0;
        $ret->{userid}        = $userid     if $userid;
        $ret->{noticetype}    = $noticetype if $noticetype;
        if ($ret->{replace_match}) {
            my @hits = replace_match_files($userid, $noticetype);
            $ret->{replace_match_count} = scalar @hits;
            $ret->{replace_match_files} = join ',', map {$_=fileparse($_)} @hits;  # strip leading dirs from fullpaths
            my @fails = ();
            foreach (@hits) {
                unlink and next;
                (-f $_) and push @fails, (fileparse($_))[0] . ": $!";
                # TODO: refactor to use cleanup() or core of cleanup?
                # We check again for the file existing since it might *just* have been picked up and finished.
                # In that case, too bad, the user is going to get our injected call soon also.
            }
            if (@fails) {
                $ret->{replace_match_fails} = join ',', map {$_=fileparse($_)} @fails;  # strip leading dirs from fullpaths
                syslog LOG_ERR, $_[0];
                # BAIL OUT?  For now, we treat failure to overwrite matches as non-fatal
            }
            $data .= sprintf("; %d of %d queued files replaced\n", scalar(@hits) - scalar(@fails), scalar(@hits));
        }
        $fname = $requested_filename;
    } else {
        $fname = auto_filename;
    }

    $fname = prefixer($fname);                  # guarantee universal prefix
    $fname =~ /\.call$/  or $fname .= '.call';  # guarantee .call suffix

    my $stage_name         = $config{staging_path} . "/" . $fname;
    my $finalized_filename = $config{spool_path}   . "/" . $fname;

    $data .= ";; added by inject() in the mediator\n";
    $data .= "Set: callfilename=$fname\n";

    # And now, we're finally ready to begin the actual insertion process
    open  FH, ">$stage_name" or return &$failure("cannot open $stage_name: $!");
    print FH $data           or return &$failure("cannot write $stage_name: $!");
    close FH                 or return &$failure("cannot close $stage_name: $!");

    chown($config{owner}, $config{group}, $stage_name) or
        return &$failure(
            "error changing $stage_name to $config{owner}:$config{group}: $!"
        );

    if ($timestamp and $timestamp > 0) {
        utime $timestamp, $timestamp, $stage_name or
            return &$failure("error utime'ing $stage_name to $timestamp: $!");
    }

    # note: EG doesn't have to care whether the spool is the "real" one or the allocator "pre" spool,
    #       so the filename is returned under the same key.  EG can check use_allocator though if it
    #       wants to know for sure.

    if ($config{use_allocator}) {
        $ret->{spooled_filename} = $stage_name;
        syslog LOG_NOTICE, "Left $stage_name for allocator";
    } elsif (rename $stage_name, $finalized_filename) {     # else the rename happens here
        $ret->{spooled_filename} = $finalized_filename;
        syslog LOG_NOTICE, "Spooled $finalized_filename sucessfully";
    } else {
        syslog LOG_ERR,  "rename $stage_name ==> $finalized_filename: $!";
        return &$failure("rename $stage_name ==> $finalized_filename: $!");
    }

    return $ret;
}


sub retrieve {
    my $globstring = prefixer(@_ ? shift : '*');
    # We depend on being in the correct (done) directory already, thanks to the config step
    # This prevents us from having to chdir for each request..

    my @matches = grep {-f $_ } <'./' . ${globstring}>;    # don't use <$pathglob>, that looks like ref to HANDLE

    my $ret = {
        code => 200,
        glob_used   => $globstring,
        match_count => scalar(@matches),
    };
    my $i = 0;
    foreach my $match (@matches) {
        $i++;
        # warn "file $i '$match'";
        unless (open (FILE, "<$match")) {
            syslog LOG_ERR, "Cannot read done file $i of " . scalar(@matches) . ": '$match'";
            $ret->{error_count}++;
            next;
        }
        my @content = <FILE>;   #slurpy
        close FILE;

        $ret->{'file_' . sprintf("%06d",$i++)} = {
            filename => fileparse($match),
            content  => join('', @content),
        };
    }
    return $ret;
}


# cleanup: deletes files
# arguments: string (comma separated filenames), optional int flag
# returns: struct reporting success/failure
#
# The list of files to delete must be explicit, in a comma-separated string.
# We cannot use globs or any other
# pattern matching because there might be additional files that match.  Asterisk
# might be making calls for other people and prodcesses (i.e., non-EG calls) or
# might have made more calls for us since the last time we checked matches.

sub cleanup {
    my $targetstring = shift or return &$bad_request(
        "Must supply at least one filename to cleanup()"     # not empty string!
    );
    my $dequeue = @_ ? shift : 0;  # default is to target done files.
    my @targets = split ',', $targetstring;
    my $path = $dequeue ? $config{spool_path} : $config{done_path};
    (-r $path and -d $path) or return &$failure("Cannot open dir '$path': $!");

    my $ret = {
        code => 200,    # optimism
        request_count => scalar(@targets),
        from_queue    => $dequeue,
        match_count   => 0,
        delete_count  => 0,
    };

    my %problems;
    my $i = 0;
    foreach my $target (@targets) {
        $i++;
        $target = fileparse($target);    # no fair trying to get us to delete in other directories!
        my $file = $path . '/' . prefixer($target);
        unless (-f $file) {
            $problems{$target} = {
                code => 404,        # NOT FOUND: may or may not be a true error, since our purpose was to delete it anyway.
                target => $target,
            };
            syslog LOG_NOTICE, "Delete request $i of " . $ret->{request_count} . " for file '$file': File not found";
            next;
        }

        $ret->{match_count}++;
        if (unlink $file) {
            $ret->{delete_count}++;
            syslog LOG_NOTICE, "Delete request $i of " . $ret->{request_count} . " for file '$file' successful";
        } else {
            syslog LOG_ERR,    "Delete request $i of " . $ret->{request_count} . " for file '$file' FAILED: $!";
            $problems{$target} = {
                code => 403,        # FORBIDDEN: permissions problem
                target => $target,
            };
            next;
        }
    }

    my $prob_count = scalar keys %problems;
    if ($prob_count) {
        $ret->{error_count} = $prob_count;
        if ($prob_count == 1 and $ret->{request_count} == 1) {
             # We had exactly 1 error and no successes
            my $one = (values %problems)[0];
            $ret->{code} = $one->{code};     # So our code is the error's code
        } else {
            $ret->{code} = 207;              # otherwise, MULTI-STATUS
            $ret->{multistatus} = \%problems;
        }
    }
    return $ret;
}


sub main {
    getopt('c:', \%opts);
    load_config;    # dies on invalid/incomplete config
    openlog basename($0), 'ndelay', LOG_USER;
    my $server = RPC::XML::Server->new(port => $config{port}) or die "Failed to get new RPC::XML::Server: $!";

    # Regarding signatures:
    #  ~ the first datatype  is  for RETURN value,
    #  ~ any other datatypes are for INCOMING args
    #
    # Everything here returns a struct.

    $server->add_proc({
        name => 'inject',   code => \&inject,   signature => ['struct string', 'struct string string', 'struct string string int']
    });
    $server->add_proc({
        name => 'retrieve', code => \&retrieve, signature => ['struct string', 'struct']
    });
    $server->add_proc({
        name => 'cleanup',  code => \&cleanup,  signature => ['struct string', 'struct string int']
    });

    $server->add_default_methods;
    $server->server_loop;
    0;
}

exit main @ARGV;    # do it all!
