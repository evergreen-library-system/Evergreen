package OpenILS::Utils::MFHDParser;
use strict;
use warnings;

use OpenSRF::EX qw/:try/;
use Time::HiRes qw(time);
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/$logger/;

use OpenILS::Utils::MFHD;
use MARC::File::XML (BinaryEncoding => 'utf8');
use Data::Dumper;

sub new { return bless({}, shift()); }

=head1 Subroutines

=over

=item * format_textual_holdings($field)

=back

Returns concatenated subfields $a with $z for textual holdings (866-868)

=cut

sub format_textual_holdings {
    my ($self, $field) = @_;
    my $holdings;
    my $public_note;

    $holdings = $field->subfield('a');
    if (!$holdings) {
        return undef;
    }

    $public_note = $field->subfield('z');
    if ($public_note) {
        return "$holdings -- $public_note";
    }
    return $holdings;
}

=over

=item * mfhd_to_hash($mfhd_xml)

=back

Returns a Perl hash containing fields of interest from the MFHD record

=cut

sub mfhd_to_hash {
    my ($self, $mfhd_xml, $skip_all_computable) = @_;

    my $marc;
    my $mfhd;

    my $location                = '';
    my $basic_holdings          = [];
    my $supplement_holdings     = [];
    my $index_holdings          = [];
    my $basic_holdings_add      = [];
    my $supplement_holdings_add = [];
    my $index_holdings_add      = [];
    my $online                  = [];    # Laurentian extension to MFHD standard
    my $missing                 = [];    # Laurentian extension to MFHD standard
    my $incomplete              = [];    # Laurentian extension to MFHD standard

    try {
        $marc = MARC::Record->new_from_xml($mfhd_xml);
    }
    otherwise {
        $logger->error("Failed to convert MFHD XML to MARC: " . shift());
        $logger->error("Failed MFHD XML: $mfhd_xml");
    };

    if (!$marc) {
        return undef;
    }

    try {
        $mfhd = MFHD->new($marc);
    }
    otherwise {
        $logger->error("Failed to parse MFHD: " . shift());
        $logger->error("Failed MFHD XML: $mfhd_xml");
    };

    if (!$mfhd) {
        return undef;
    }

    try {
        foreach my $field ($marc->field('852')) {
            foreach my $subfield_ref ($field->subfields) {
                my ($subfield, $data) = @$subfield_ref;
                $location .= $data . " -- ";
            }
        }
    }
    otherwise {
        $logger->error("MFHD location parsing error: " . shift());
    };

    $location =~ s/ -- $//;

    # TODO: for now, we will assume that textual holdings are in addition to the 
    # computable holdings (that is, they have link IDs greater than the 85X fields)
    # or that they fully replace the computable holdings (checking for link ID '0').
    # Eventually this may be handled better by format_holdings() in MFHD.pm
    my %skip_computable;
    try {
        foreach my $field ($marc->field('866')) {
            my $textual_holdings = $self->format_textual_holdings($field);
            if ($textual_holdings) {
                push @$basic_holdings_add, $textual_holdings;
                if ($field->subfield('8') eq '0') {
                   $skip_computable{'basic'} = 1; # link ID 0 trumps computable fields
                }
            }
        }
        foreach my $field ($marc->field('867')) {
            my $textual_holdings = $self->format_textual_holdings($field);
            if ($textual_holdings) {
                push @$supplement_holdings_add, $textual_holdings;
                if ($field->subfield('8') eq '0') {
                   $skip_computable{'supplement'} = 1; # link ID 0 trumps computable fields
                }
            }
        }
        foreach my $field ($marc->field('868')) {
            my $textual_holdings = $self->format_textual_holdings($field);
            if ($textual_holdings) {
                push @$index_holdings_add, $textual_holdings;
                if ($field->subfield('8') eq '0') {
                   $skip_computable{'index'} = 1; # link ID 0 trumps computable fields
                }
            }
        }

        if (!$skip_all_computable) {
            if (!exists($skip_computable{'basic'})) {
                foreach my $cap_id ($mfhd->caption_link_ids('853')) {
                    my @holdings = $mfhd->holdings('863', $cap_id);
                    next unless scalar @holdings;
                    foreach (@holdings) {
                        push @$basic_holdings, $_->format();
                    }
                }
                if (!@$basic_holdings) { # no computed holdings found
                    $basic_holdings = $basic_holdings_add;
                    $basic_holdings_add = [];
                }
            } else { # textual are non additional, but primary
                $basic_holdings = $basic_holdings_add;
                $basic_holdings_add = [];
            }

            if (!exists($skip_computable{'supplement'})) {
                foreach my $cap_id ($mfhd->caption_link_ids('854')) {
                    my @supplements = $mfhd->holdings('864', $cap_id);
                    next unless scalar @supplements;
                    foreach (@supplements) {
                        push @$supplement_holdings, $_->format();
                    }
                }
                if (!@$supplement_holdings) { # no computed holdings found
                    $supplement_holdings = $supplement_holdings_add;
                    $supplement_holdings_add = [];
                }
            } else { # textual are non additional, but primary
                $supplement_holdings = $supplement_holdings_add;
                $supplement_holdings_add = [];
            }

            if (!exists($skip_computable{'index'})) {
                foreach my $cap_id ($mfhd->caption_link_ids('855')) {
                    my @indexes = $mfhd->holdings('865', $cap_id);
                    next unless scalar @indexes;
                    foreach (@indexes) {
                        push @$index_holdings, $_->format();
                    }
                }
                if (!@$index_holdings) { # no computed holdings found
                    $index_holdings = $index_holdings_add;
                    $index_holdings_add = [];
                }
            } else { # textual are non additional, but primary
                $index_holdings = $index_holdings_add;
                $index_holdings_add = [];
            }
        }

        # Laurentian extensions
        foreach my $field ($marc->field('530')) {
            my $online_stmt = $self->format_textual_holdings($field);
            if ($online_stmt) {
                push @$online, $online_stmt;
            }
        }

        foreach my $field ($marc->field('590')) {
            my $missing_stmt = $self->format_textual_holdings($field);
            if ($missing_stmt) {
                push @$missing, $missing_stmt;
            }
        }

        foreach my $field ($marc->field('591')) {
            my $incomplete_stmt = $self->format_textual_holdings($field);
            if ($incomplete_stmt) {
                push @$incomplete, $incomplete_stmt;
            }
        }
    }
    otherwise {
        $logger->error("MFHD statement parsing error: " . shift());
    };

    return {
        location                => $location,
        basic_holdings          => $basic_holdings,
        basic_holdings_add      => $basic_holdings_add,
        supplement_holdings     => $supplement_holdings,
        supplement_holdings_add => $supplement_holdings_add,
        index_holdings          => $index_holdings,
        index_holdings_add      => $index_holdings_add,
        missing                 => $missing,
        incomplete              => $incomplete,
        online                  => $online
    };
}

=over

=item * init_holdings_virtual_record()

=back

Initialize the serial virtual record (svr) instance

=cut

sub init_holdings_virtual_record {
    my $record = Fieldmapper::serial::virtual_record->new;
    $record->sre_id();
    $record->location();
    $record->owning_lib();
    $record->basic_holdings([]);
    $record->basic_holdings_add([]);
    $record->supplement_holdings([]);
    $record->supplement_holdings_add([]);
    $record->index_holdings([]);
    $record->index_holdings_add([]);
    $record->online([]);
    $record->missing([]);
    $record->incomplete([]);
    return $record;
}

=over

=item * init_holdings_virtual_record($mfhd)

=back

Given an MFHD record, return a populated svr instance

=cut

sub generate_svr {
    my ($self, $id, $mfhd, $owning_lib, $skip_all_computable) = @_;

    if (!$mfhd) {
        return undef;
    }

    my $record   = init_holdings_virtual_record();
    my $holdings = $self->mfhd_to_hash($mfhd, $skip_all_computable);

    $record->sre_id($id);
    $record->owning_lib($owning_lib);

    if (!$holdings) {
        return $record;
    }

    $record->location($holdings->{location});
    $record->basic_holdings($holdings->{basic_holdings});
    $record->basic_holdings_add($holdings->{basic_holdings_add});
    $record->supplement_holdings($holdings->{supplement_holdings});
    $record->supplement_holdings_add($holdings->{supplement_holdings_add});
    $record->index_holdings($holdings->{index_holdings});
    $record->index_holdings_add($holdings->{index_holdings_add});
    $record->online($holdings->{online});
    $record->missing($holdings->{missing});
    $record->incomplete($holdings->{incomplete});

    return $record;
}

1;

# vim: ts=4:sw=4:noet
