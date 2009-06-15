package OpenILS::Utils::MFHDParser;
use strict; use warnings;

use OpenSRF::EX qw/:try/;
use Time::HiRes qw(time);
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/$logger/;

use OpenILS::Utils::MFHD;
use MARC::File::XML (BinaryEncoding => 'utf8');
use Data::Dumper;

sub new { return bless( {}, shift() ); }

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
		return "$holdings - $public_note";
	}
	return $holdings;
}

=over

=item * mfhd_to_hash($mfhd_xml)

=back

Returns a Perl hash containing fields of interest from the MFHD record

=cut
sub mfhd_to_hash {
	my ($self, $mfhd_xml) = @_;

	my $marc;
	my $mfhd;

	my $location = '';
	my $holdings = [];
	my $supplements = [];
	my $indexes = [];
	my $current_holdings = [];
	my $current_supplements = [];
	my $current_indexes = [];
	my $online = []; # Laurentian extension to MFHD standard
	my $missing = []; # Laurentian extension to MFHD standard
	my $incomplete = []; # Laurentian extension to MFHD standard

	try {
		$marc = MARC::Record->new_from_xml($mfhd_xml);
	} otherwise {
		$logger->error("Failed to convert MFHD XML to MARC: " . shift());
		$logger->error("Failed MFHD XML: $mfhd_xml");
	};

	if (!$marc) {
		return undef;
	}

	try {
		$mfhd = MFHD->new($marc);
	} otherwise {
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
	} otherwise {
		$logger->error("MFHD location parsing error: " . shift());
	};

	$location =~ s/ -- $//;

	try {
		foreach my $field ($marc->field('866')) {
			my $textual_holdings = $self->format_textual_holdings($field);
			if ($textual_holdings) {
				push @$holdings, $textual_holdings;
			}
		}
		foreach my $field ($marc->field('867')) {
			my $textual_holdings = $self->format_textual_holdings($field);
			if ($textual_holdings) {
				push @$supplements, $textual_holdings;
			}
		}
		foreach my $field ($marc->field('868')) {
			my $textual_holdings = $self->format_textual_holdings($field);
			if ($textual_holdings) {
				push @$indexes, $textual_holdings;
			}
		}

		foreach my $cap_id ($mfhd->captions('853')) {
			my @curr_holdings = $mfhd->holdings('863', $cap_id);
			next unless scalar @curr_holdings;
			foreach (@curr_holdings) {
				push @$current_holdings, $_->format();
			}
		}

		foreach my $cap_id ($mfhd->captions('854')) {
			my @curr_supplements = $mfhd->holdings('864', $cap_id);
			next unless scalar @curr_supplements;
			foreach (@curr_supplements) {
				push @$current_supplements, $_->format();
			}
		}

		foreach my $cap_id ($mfhd->captions('855')) {
			my @curr_indexes = $mfhd->holdings('865', $cap_id);
			next unless scalar @curr_indexes;
			foreach (@curr_indexes) {
				push @$current_indexes, $_->format();
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
	} otherwise {
		$logger->error("MFHD statement parsing error: " . shift());
	};

	return { location => $location, holdings => $holdings, current_holdings => $current_holdings,
			supplements => $supplements, current_supplements => $current_supplements,
			indexes => $indexes, current_indexes => $current_indexes,
			missing => $missing, incomplete => $incomplete, };
}

=over

=item * init_holdings_virtual_record()

=back

Initialize the serial virtual record (svr) instance

=cut
sub init_holdings_virtual_record {
	my $record = Fieldmapper::serial::virtual_record->new;
	$record->id();
	$record->location();
	$record->owning_lib();
	$record->holdings([]);
	$record->current_holdings([]);
	$record->supplements([]);
	$record->current_supplements([]);
	$record->indexes([]);
	$record->current_indexes([]);
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
	my ($self, $id, $mfhd, $owning_lib) = @_;

	if (!$mfhd) {
		return undef;
	}

	my $record = init_holdings_virtual_record();
	my $holdings = $self->mfhd_to_hash($mfhd);

	$record->id($id);
	$record->owning_lib($owning_lib);

	if (!$holdings) {
		return $record;
	}

	$record->location($holdings->{location});
	$record->holdings($holdings->{holdings});
	$record->current_holdings($holdings->{current_holdings});
	$record->supplements($holdings->{supplements});
	$record->current_supplements($holdings->{current_supplements});
	$record->indexes($holdings->{indexes});
	$record->current_indexes($holdings->{current_indexes});
	$record->online($holdings->{online});
	$record->missing($holdings->{missing});
	$record->incomplete($holdings->{incomplete});

	return $record;
}

1;

# vim: ts=4:sw=4:noet
