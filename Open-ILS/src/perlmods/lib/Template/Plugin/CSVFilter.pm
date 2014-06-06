# ---------------------------------------------------------------
# Copyright © 2014 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package Template::Plugin::CSVFilter;
use Template::Plugin::Filter;

use base qw(Template::Plugin::Filter);

our $VERSION = "1.00";

sub init {
    my $self = shift;

    $self->{_DYNAMIC} = 1;
    $self->install_filter($self->{_ARGS}->[0] || 'CSVFilter');

    return $self;
}

sub filter {
    my ($self, $text, $args, $conf) = @_;

    $args = $self->merge_args($args);
    $conf = $self->merge_config($conf);

    my $quote_char = $conf->{quote_char} || '"';
    my $delim = $conf->{separator} || ',';
    my $force_quotes = grep {$_ eq 'force_quotes'} @$args;
    if ($text) {
        $text =~ s/$quote_char/$quote_char$quote_char/g;
        $text = $quote_char . $text . $quote_char
            if ($force_quotes || $text =~ /[$delim$quote_char\r\n]/);
    }
    $text .= $delim unless(grep {$_ eq 'last'} @$args);

    return $text;
}

1;
__END__

=pod

=head1 NAME

Template::Plugin::CSVFilter - Template Toolkit2 Filter for CSV fields

=head1 SYNOPSIS

    [%- USE CSVFilter 'csv';
        FOREACH row IN rows;
          FOREACH field IN row;
            IF loop.count == loop.size;
              field | csv 'last';
            ELSE;
              field | csv;
            END;
          END; %]
    [%  END -%]

You can use the above as a template for a CSV output file,
provided that you arrange your data variable to have a 'rows' member
that is an array ref containing array refs of the fields for each row:

    $var = {rows => [[...], ...]};

If you want headers in the first row of the output, then make sure the
header fields make up the first sub array of 'rows' array.

=head1 DESCRIPTION

Template::Plugin::CSVFilter adds a filter that you can use in Template
Toolkit2 templates to output data that is suitably formatted for
inclusion in a CSV type file.  The filter will see to it that the
field is properly quoted and that any included quote symbols are
properly escaped.  It will also add the separator character after the
field's text.

=head1 OPTIONS

CSVFilter accepts the following configuration options that require a
single character argument:

=over

=item *

C<separator> - The argument is the character to use as the field
delimiter.  If this is not specified, a default of , is used.

=item *

C<quote_char> - The argument is the character to for quoting fields.
If this is not specified, a default of " is used.

=back

The above are best set when you use the filter in your template.
However, you can set them at any or every time you use the filter in
your template.

Each call to the filter can be modified by the following two arguments
that do not themselves take an argument:

=over

=item *

C<force_quotes> - If present, this argument causes the field output to
be quoted even if it would not ordinarily be.  If you use this where
you C<USE> the filter, you will need to specify a name for the filter or
the name of the filter will be C<force_quotes>.  If you specify this
option when initializing the filter, then every output field will be
quoted.

=item *

C<last> - This argument must be used on the last field in an output
row in order to suppress output of the C<separator> character.  This
argument must never be used when initializing the filter.

=back

=head1 SEE ALSO

    Template
    Template::Plugin
    Template::Plugin::Filter

=head1 AUTHOR

Jason Stephenson <jstephenson@mvlc.org>


=cut
