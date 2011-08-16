#!/bin/bash
#
# A wrapper for the ruby-script


function die_msg {
    echo $1;
    exit 1;
}

lib='./acq_edi/lib';
script='./edi_webrick.rb';

[ -r "$script" ] || die_msg "Cannot read script at $script";
#[ -d "$lib"    ] || die_msg "Cannot find lib at $lib";
# This doesn't work?
#      export RUBYLIB=$lib

echo -n Starting translator in background with logging...

# This is necessary 
export RUBYOPT=rubygems

# Instead of logging to file, one could pipe to the logger command.
ruby $script --verbose >> /openils/var/log/edi_webrick.log 2>&1 &

echo done.
