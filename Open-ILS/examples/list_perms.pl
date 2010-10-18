#!/usr/bin/perl -w

# Extract permission names from the output of the dump_idl utility.

# The logic necessarily makes assumptions about the format of
# dump_idl's output.  If that format changes, the logic may no longer work.

# In the output: each permission name appears on a separate line, 
# flush left.  Normally the output should be piped into sort -u in
# order to eliminate duplicates.

use strict;

my $in_perms = 0;
my $perm_indent;

# Return the number of leading white space characters.
# We do not distinguish between tabs and spaces.
sub indent_level {
	my $str = shift;
	return 0 unless (defined( $str ));
	$str =~ s/\S.*//;       # Remove everything after the leading white space
	return length $str;     # Take the length of what's left
}

while(<>) {
	if( $in_perms ) {
		
		# Check the indentation to see if we're still
		# inside the list of permissions.

		if ( indent_level( $_ ) > $perm_indent ) {

			# This line contains a permission name.
			# Strip off the leading white space and write it.

			s/^\s*//;
			print;
		} else {

			# We're no longer inside the list of permissions.

			$in_perms = 0;
		}
	} elsif (/\s+permission [(]string array[)]$/) {

		# We are entering a list of permissions, each of which is
		# indented further than this line.  When we see a line that
		# is *not* further indented, that will end the list.

		# The indentation is defined as the number of leading white
		# space characters, be they tabs or spaces.  If the format of
		# the dump_idl output is changed to involve some bizarre and
		# perverse mixture of tabs and spaces, this logic may not work.

		$in_perms = 1;
		$perm_indent = indent_level( $_ );
	}
}
