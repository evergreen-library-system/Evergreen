#!/bin/bash

# You may not want this.
#
# If and only if your telephony A/T templates ...
#
# 1. generate callfiles that include the token 'DAHDI' for notifications that
#   the system should actually dial
# 2. generate callfiles that include the token 'noop' when notifications
#   should NOT be attempted
#
# ... would you want this.  If you meet these conditions, read on.

cd /var/tmp

# This heuristic finds call files that don't containt 'DAHDI' but do contain
# 'noop', and appends a line to those files for the benefit of the
# get_failures() method of eg-pbx-mediator.pl, and moves these files to the
# directory where they would land if they were call files which Asterisk
# had attempted and failed.
#
# The purpose of this is to support a special case of the "rollover failed
# phone notices to print notices" functionality.  Notices that never reach
# Asterisk because of a lack of patron phone number are still expected to
# rollover to print notices.

# XXX todo: get rid of this script, and incorporate into eg-pbx-allocator.pl,
# or at least don't have hardcoded paths here

grep -L DAHDI EG*.call 2>/dev/null |
    xargs grep -l noop |
    xargs -I X sh -c 'echo "Status: Untried" >> X ; mv X /var/spool/asterisk/outgoing_done' 2>&1 > /dev/null

# If you know your deployment doesn't use the "rollover failed phone notices
# to print notices" functionality, you could comment out the chain of commands
# above, and uncomment the simpler one below.  This assumes you still meet
# the two initial requirements in the top comments in this script.

# grep -L DAHDI EG*.call 2>/dev/null |
#     xargs grep -l noop | xargs rm -f 2>&1 > /dev/null
