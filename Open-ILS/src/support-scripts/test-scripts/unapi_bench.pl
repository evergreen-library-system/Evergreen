#!/usr/bin/perl
require '../oils_header.pl';
use strict; use warnings;
use Time::HiRes qw/time usleep/;
use Data::Dumper;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::CStoreEditor;
use XML::LibXML;

#-----------------------------------------------------------------------------
# Does a checkout, renew, and checkin 
#-----------------------------------------------------------------------------

my @recs = (1,2,3,4,5,6,7,8,9,10);

osrf_connect(shift() || '/openils/conf/opensrf_core.xml');

my $e = OpenILS::Utils::CStoreEditor->new;

sub xptext {
    my($node, $path) = @_;
    my $res = $node->findnodes($path);
    return '' unless $res and $res->[0];
    return $res->[0]->textContent;
}

sub get_bib_attrs {
    my $xml = shift;
    return {
        isbn => xptext($xml, '//*[@tag="020"]/*[@code="a"]'),
        upc => xptext($xml,'//*[@tag="024"]/*[@code="a"]'),
        issn => xptext($xml,'//*[@tag="022"]/*[@code="a"]'),
        title => xptext($xml,'//*[@tag="245"]/*[@code="a"]'),
        author => xptext($xml,'//*[@tag="100"]/*[@code="a"]'),
        publisher => xptext($xml,'//*[@tag="260"]/*[@code="b"]'),
        pubdate => xptext($xml,'//*[@tag="260"]/*[@code="c"]'),
        edition => xptext($xml,'//*[@tag="250"]/*[@code="a"]'),
    };
}

sub unapi {
    my @recs = @_;
    my $start = time();

    my %records;
    for my $rec_id (@recs) {
        #my $ustart = time;
        # Note, fetching all 10 recs from unapi.biblio_record_entry_feed in 1 feed takes considerably longer (2+ seconds)
        my $data = $e->json_query({from => ['unapi.biblio_record_entry_feed', "{$rec_id}", 'marcxml', '{holdings_xml,acp}', 'CONS']})->[0];
        #print "unapi query duration " . (time() - $ustart) . "\n";
        my $xml = XML::LibXML->new->parse_string($data->{'unapi.biblio_record_entry_feed'});
        my $attrs = get_bib_attrs($xml);
        $records{$rec_id}{$_} = $attrs->{$_} for keys %$attrs;

        my $rvols = [];
        for my $volnode ($xml->findnodes('//*[local-name()="volumes"]/*[local-name()="volume"]')) {
            my $vol = {}; 
            $vol->{copies} = [];
            $vol->{label} = $volnode->getAttribute('label');
            for my $copynode ($volnode->getElementsByLocalName('copy')) {
                my $copy = {};   
                $copy->{barcode} = $copynode->getAttribute('barcode');
                push(@{$vol->{copies}}, $copy);
            }
            push(@{$records{$rec_id}->{volumes}}, $vol);
        }
    }

    my $duration = time() - $start;

    for my $rec_id (keys %records) {
        my $rec = $records{$rec_id};
        print sprintf("%d [%s] has %d volumes and %d copies\n",
            $rec_id, $rec->{title}, 
            scalar(@{$rec->{volumes}}),
            scalar(map { @{$_->{copies}} } @{$rec->{volumes}}));
    }
    print "\nunapi processing duration is $duration\n\n";
}

sub direct {
    my @recs = @_;
    my %records;

    my $start = time();

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    my $cstore2 = OpenSRF::AppSession->create('open-ils.cstore');
    my $bre_req = $cstore->request(
        'open-ils.cstore.direct.biblio.record_entry.search', 
        {id => \@recs},
        {flesh => 2, flesh_fields => {bre => ['call_numbers'], acn => ['copies']}}
        # in practice, ^-- this might be a separate, paged json_query
    );

    my @data;
    while (my $resp = $bre_req->recv) {
        my $bre = $resp->content;

        my $cc_req = $cstore2->request(
            'open-ils.cstore.json_query', 
            {from => ['asset.record_copy_count', 1, $bre->id, 0]}
        );

        my $xml = XML::LibXML->new->parse_string($bre->marc);
        my $attrs = get_bib_attrs($xml);
        $records{$bre->id}{record} = $bre;
        $records{$bre->id}{$_} = $attrs->{$_} for keys %$attrs;

        $records{$bre->id}->{counts} = $cc_req->gather(1);
    }

    my $duration = time() - $start;

    for my $rec_id (keys %records) {
        my $rec = $records{$rec_id};
        print sprintf("%d [%s] has %d volumes and %d copies\n",
            $rec_id, $rec->{title}, 
            scalar(@{$rec->{record}->call_numbers}), 
            scalar(map { @{$_->copies} } @{$rec->{record}->call_numbers}));
    }

    print "\ndurect calls processing duration is $duration\n\n";
}

for (0..3) { direct(@recs); unapi(@recs); }
