package OpenILS::Application::Search::Serial;
use base qw/OpenILS::Application/;
use strict; use warnings;


use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::MFHDParser;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Cache;
use Encode;

use OpenSRF::Utils::Logger qw/:logger/;

use Data::Dumper;

use Time::HiRes qw(time);
use OpenSRF::EX qw(:try);
use Digest::MD5 qw(md5_hex);

use XML::LibXML;
use XML::LibXSLT;

use OpenILS::Const qw/:const/;

use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

my $pfx = "open-ils.search_";

=over

=item * mfhd_to_hash

=back

Takes an MFHD record ID and returns a hash of holdings statements

=cut

sub mfhd_to_hash {
    my ($self, $client, $id) = @_;
    
    my $session = OpenSRF::AppSession->create("open-ils.cstore");
    my $request = $session->request(
            "open-ils.cstore.direct.serial.record_entry.retrieve", $id )->gather(1);

    my $u = OpenILS::Utils::MFHDParser->new();
    my $mfhd_hash = $u->generate_svr( $request->id, $request->marc, $request->owning_lib );

    $session->disconnect();
    return $mfhd_hash;
}

__PACKAGE__->register_method(
    method  => "mfhd_to_hash",
    api_name    => "open-ils.search.serial.record.mfhd.retrieve",
    argc        => 1, 
    note        => "Given a serial record ID, return MFHD holdings"
);

=over

=item * bib_to_mfhd_hash 

=back

Given a bib record ID, returns a hash of holdings statements

=cut

# DEFUNCT ?
#sub bib_to_mfhd_hash {
#   my ($self, $client, $bib) = @_;
#   
#   my $mfhd_hash;
#
#   # XXX perhaps this? --miker
##  my $e = OpenILS::Utils::CStoreEditor->new();
##  my $mfhd = $e->search_serial_record_entry({ record => $bib });
##  return $u->generate_svr( $mfhd->[0] ) if (ref $mfhd);
##  return undef;
#
#   my @mfhd = $U->cstorereq( "open-ils.cstore.json_query.atomic", {
#       select  => { sre => 'marc' },
#       from    => 'sre',
#       where   => { record => $bib, deleted => 'f' },
#       distinct => 1
#   });
#   
#   if (!@mfhd or scalar(@mfhd) == 0) {
#       return undef;
#   }
#
#   my $u = OpenILS::Utils::MFHDParser->new();
#   $mfhd_hash = $u->generate_svr( $mfhd[0][0]->{id}, $mfhd[0][0]->{marc}, $mfhd[0][0]->{owning_lib} );
#
#   return $mfhd_hash;
#}
#
#__PACKAGE__->register_method(
#   method  => "bib_to_mfhd_hash",
#   api_name    => "open-ils.search.serial.record.bib_to_mfhd.retrieve",
#   argc        => 1, 
#   note        => "Given a bibliographic record ID, return MFHD holdings"
#);

sub bib_to_svr {
    my ($self, $client, $bib, $ou, $ou_depth) = @_;
    
    my $svrs = [];

    my $e = OpenILS::Utils::CStoreEditor->new();

    if (!$ou) {
        # Get the root of the org_tree
        my $aous = $e->search_actor_org_unit([{
            "parent_ou" => undef
        }]); 

        $ou = $aous->[0]->id();
    }

    # ou_depth can be undef in get_org_descendants
    my $orgs = $U->get_org_descendants($ou, $ou_depth);

    # TODO: 'deleted' ssub support
    my $sdists = $e->search_serial_distribution([
        {
            "+ssub" => {"record_entry" => $bib},
            "holding_lib" => { "in" => $orgs }
        },
        {
            "flesh" => 1,
            "flesh_fields" => {
                'sdist' => [ "record_entry", "holding_lib", "basic_summary", "supplement_summary", "index_summary" ]
            },
            "join" => {"ssub" => {}}
        }
    ]);
    my $sres = $e->search_serial_record_entry([
        {
            record => $bib,
            deleted => 'f',
            "owning_lib" => { "in" => $orgs },
            "+sdist" => {"id" => undef}
        },
        {
            "join" => { "sdist" => { 'type' => 'left' } } 
        }
    ]);
    if (!ref $sres and !ref $sdists) {
        return undef;
    }

    my $mfhd_parser = OpenILS::Utils::MFHDParser->new();
    foreach (@$sdists) {
        my $svr;
        if ($_->summary_method ne 'use_sdist_only' and ref $_->record_entry and !$U->is_true($_->record_entry->deleted)) {
            my $skip_all_computable = 0;
            if ($_->summary_method eq 'merge_with_sre') { # 'computable' (85x/86x combos) are handled by generated_coverage when attempting to merge
                $skip_all_computable = 1;
            }
            $svr = $mfhd_parser->generate_svr($_->record_entry->id, $_->record_entry->marc, $_->record_entry->owning_lib, $skip_all_computable);
        } else {
            $svr = Fieldmapper::serial::virtual_record->new;
            if (ref $_->record_entry and !$U->is_true($_->record_entry->deleted)) {
                $svr->sre_id($_->record_entry->id);
            } else {
                $svr->sre_id(-1);
            }
            $svr->location($_->holding_lib->name);
            $svr->owning_lib($_->holding_lib->id);
            $svr->basic_holdings([]);
            $svr->supplement_holdings([]);
            $svr->index_holdings([]);
            $svr->basic_holdings_add([]);
            $svr->supplement_holdings_add([]);
            $svr->index_holdings_add([]);
            $svr->online([]);
            $svr->missing([]);
            $svr->incomplete([]);
        }
        if ($_->summary_method ne 'use_sre_only') {
            if (ref $_->basic_summary) { #TODO: 'show-generated' boolean on summaries
                if ($_->basic_summary->generated_coverage) {
                    push(@{$svr->basic_holdings}, OpenSRF::Utils::JSON->JSON2perl($_->basic_summary->generated_coverage));
                }
                if ($_->basic_summary->textual_holdings) {
                    push(@{$svr->basic_holdings_add}, $_->basic_summary->textual_holdings);
                }
            }
            if (ref $_->supplement_summary) {
                if ($_->supplement_summary->generated_coverage) {
                    push(@{$svr->supplement_holdings}, OpenSRF::Utils::JSON->JSON2perl($_->supplement_summary->generated_coverage));
                }
                if ($_->supplement_summary->textual_holdings) {
                    push(@{$svr->supplement_holdings_add}, $_->supplement_summary->textual_holdings);
                }
            }
            if (ref $_->index_summary) {
                if ($_->index_summary->generated_coverage) {
                    push(@{$svr->index_holdings}, OpenSRF::Utils::JSON->JSON2perl($_->index_summary->generated_coverage));
                }
                if ($_->index_summary->textual_holdings) {
                    push(@{$svr->index_holdings_add}, $_->index_summary->textual_holdings);
                }
            }
        }
        push(@$svrs, $svr);
    }
    foreach (@$sres) {
        push(@$svrs, $mfhd_parser->generate_svr($_->id, $_->marc, $_->owning_lib));
    }

    # do a basic location sort for simple predictability
    @$svrs = sort { $a->location cmp $b->location } @$svrs;

    return $svrs;
}

__PACKAGE__->register_method(
    method  => "bib_to_svr",
    api_name    => "open-ils.search.serial.record.bib.retrieve",
    argc        => 1, 
    signature => {
        desc   => 'Given a bibliographic record ID, return holdings in svr form',
        params => [
            {   name => 'bibid',
                desc => 'ID of the bibliographic record to which serial holdings are attached',
                type => 'number'
            },
            {
                name => 'ou',
                desc => 'ID of the org_unit on which the search is based',
                type => 'number'
            },
            {
                name => 'ou_depth',
                desc => 'Depth of the org tree at which the search should occur', 
                type => 'number'
            }
        ]
    }
);

1;
