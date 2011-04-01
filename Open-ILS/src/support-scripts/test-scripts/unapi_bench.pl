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
    #my $res = $node->findnodes($path);
    my $res = $node->find($path);
    return '' unless $res and $res->[0];
    return $res->[0]->textContent;
}

sub get_bib_attrs {
    my $xml = shift;
    return {
        isbn => xptext($xml, '*[@tag="020"]/*[@code="a"]'),
        upc => xptext($xml,'*[@tag="024"]/*[@code="a"]'),
        issn => xptext($xml,'*[@tag="022"]/*[@code="a"]'),
        title => xptext($xml,'*[@tag="245"]/*[@code="a"]'),
        author => xptext($xml,'*[@tag="100"]/*[@code="a"]'),
        publisher => xptext($xml,'*[@tag="260"]/*[@code="b"]'),
        pubdate => xptext($xml,'*[@tag="260"]/*[@code="c"]'),
        edition => xptext($xml,'*[@tag="250"]/*[@code="a"]'),
    };
}

sub unapi {
    my @recs = @_;
    my $start = time();

    my $ses1 = OpenSRF::AppSession->create('open-ils.cstore');
    my $ses2 = OpenSRF::AppSession->create('open-ils.cstore');
    my $ses3 = OpenSRF::AppSession->create('open-ils.cstore');
    my ($req1, $req2, $req3);

    my %records;
    while(@recs) {
        my ($id1, $id2, $id3) = (pop @recs, pop @recs, pop @recs);

        for my $r ($req1, $req2, $req3) {
            if($r) {
                my $data = $r->gather(1);
                my $xml = XML::LibXML->new->parse_string($data->{'unapi.bre'});
                $xml = $xml->documentElement;
                my $attrs = get_bib_attrs($xml);
                my $rec_id =  xptext($xml,'*[@tag="901"]/*[@code="c"]');
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
        }

        $req1 = ($id1) ? $ses1->request('open-ils.cstore.json_query', {from => ['unapi.bre', $id1, 'marcxml', 'record', '{holdings_xml,acp}', 'CONS']}) : undef;
        $req2 = ($id2) ? $ses1->request('open-ils.cstore.json_query', {from => ['unapi.bre', $id2, 'marcxml', 'record', '{holdings_xml,acp}', 'CONS']}) : undef;
        $req3 = ($id3) ? $ses1->request('open-ils.cstore.json_query', {from => ['unapi.bre', $id3, 'marcxml', 'record', '{holdings_xml,acp}', 'CONS']}) : undef;
    }


    for my $r ($req1, $req2, $req3) {
        if($r) {
            my $data = $r->gather(1);
            my $xml = XML::LibXML->new->parse_string($data->{'unapi.bre'});
            $xml = $xml->documentElement;
            my $attrs = get_bib_attrs($xml);
            my $rec_id =  xptext($xml,'*[@tag="901"]/*[@code="c"]');
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
    }

    my $duration = time() - $start;

    for my $rec_id (keys %records) {
        my $rec = $records{$rec_id};
        print sprintf("%d [%s] has %d volumes and %d copies\n",
            $rec_id, $rec->{title}, 
            scalar(@{$rec->{volumes}}),
            scalar(map { @{$_->{copies}} } @{$rec->{volumes}}));
    }

    #note, unapi.biblio_record_entry_feed per record performs the same as unapi.bre pre record
    print "\nunapi 'unapi.bre' duration is $duration\n\n";
}

sub unapi_spread {
    my @recs = @_;
    my %records;
    my $start = time();

    my @reqs;
    for my $rec_id (@recs) {

        my $ses = OpenSRF::AppSession->create('open-ils.cstore');
        my $req = $ses->request(
            'open-ils.cstore.json_query', 
            {from => ['unapi.bre', $rec_id, 'marcxml', 'record', '{holdings_xml,acp}', 'CONS']});

        push(@reqs, $req);
    }

    for my $req (@reqs) {

        my $data = $req->gather(1);
        my $xml = XML::LibXML->new->parse_string($data->{'unapi.bre'});
        $xml = $xml->documentElement;
        my $attrs = get_bib_attrs($xml);
        my $rec_id =  xptext($xml,'*[@tag="901"]/*[@code="c"]');
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

    #note, unapi.biblio_record_entry_feed per record performs the same as unapi.bre pre record
    print "\nunapi 'unapi.bre' spread duration is $duration\n\n";
}



sub unapi_batch {
    my @recs = @_;
    my $start = time();

    my $data = $e->json_query({from => ['unapi.biblio_record_entry_feed', "{".join(',',@recs)."}", 'marcxml', '{holdings_xml,acp}', 'CONS']})->[0];
    my $xml = XML::LibXML->new->parse_string($data->{'unapi.biblio_record_entry_feed'});

    my %records;
    for my $rec_xml ($xml->documentElement->getElementsByLocalName('record')) { 

        my $attrs = get_bib_attrs($rec_xml);
        my $rec_id =  xptext($rec_xml,'*[@tag="901"]/*[@code="c"]');
        #print "REC = $rec_xml : $rec_id : " . $attrs->{title} . "\n" . $rec_xml->toString . "\n";
        $records{$rec_id}{$_} = $attrs->{$_} for keys %$attrs;

        my $rvols = [];
        for my $volnode ($rec_xml->findnodes('//*[local-name()="volumes"]/*[local-name()="volume"]')) {
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
    print "\nunapi 'batch feed' duration is $duration\n\n";
}

sub direct_spread {
    my @recs = @_;
    my %records;
    my $start = time();

    my $query = {
        flesh => 4, 
        flesh_fields => {
            bre => ['call_numbers'], 
            acn => ['copies', 'uris'], 
            acp => ['location', 'stat_cat_entries', 'parts'],
            ascecm => ['stat_cat', 'stat_cat_entry'],
            acpm => ['part']
        }
    };

    my @reqs;
    for my $rec_id (@recs) {
        my $ses = OpenSRF::AppSession->create('open-ils.cstore');
        my $req = $ses->request(
            'open-ils.cstore.direct.biblio.record_entry.search', {id => $rec_id}, $query);
        push(@reqs, $req);
    }

    $records{$_}{counts} = $e->json_query({from => ['asset.record_copy_count', 1, $_, 0]})->[0] for @recs;
    for my $req (@reqs) {
        my $bre = $req->gather(1);
        my $xml = XML::LibXML->new->parse_string($bre->marc)->documentElement;
        my $attrs = get_bib_attrs($xml);
        $records{$bre->id}{record} = $bre;
        $records{$bre->id}{$_} = $attrs->{$_} for keys %$attrs;
    }

    my $duration = time() - $start;

    for my $rec_id (keys %records) {
        my $rec = $records{$rec_id};
        print sprintf("%d [%s] has %d volumes and %d copies\n",
            $rec_id, $rec->{title}, 
            scalar(@{$rec->{record}->call_numbers}), 
            scalar(map { @{$_->copies} } @{$rec->{record}->call_numbers}));
    }

    print "\n'direct' spread calls processing duration is $duration\n\n";
}


sub direct {
    my @recs = @_;
    my %records;

    my $start = time();

    my $ses1 = OpenSRF::AppSession->create('open-ils.cstore');
    my $ses2 = OpenSRF::AppSession->create('open-ils.cstore');
    my $ses3 = OpenSRF::AppSession->create('open-ils.cstore');
    my ($req1, $req2, $req3);

    my $query = {
        flesh => 5, 
        flesh_fields => {
            bre => ['call_numbers'], 
            acn => ['copies', 'uris'], 
            acp => ['location', 'stat_cat_entries', 'parts'],
            ascecm => ['stat_cat', 'stat_cat_entry'],
            acpm => ['part']
        }
    };

    my $first = 1;
    while(@recs) {
        my ($id1, $id2, $id3) = (pop @recs, pop @recs, pop @recs);

        for my $r ($req1, $req2, $req3) {
            last unless $r;
            my $bre = $r->gather(1);
            my $xml = XML::LibXML->new->parse_string($bre->marc)->documentElement;
            my $attrs = get_bib_attrs($xml);
            $records{$bre->id}{record} = $bre;
            $records{$bre->id}{$_} = $attrs->{$_} for keys %$attrs;
        }

        $req1 = ($id1) ? $ses1->request('open-ils.cstore.direct.biblio.record_entry.search', {id => $id1}, $query) : undef;
        $req2 = ($id2) ? $ses1->request('open-ils.cstore.direct.biblio.record_entry.search', {id => $id2}, $query) : undef;
        $req3 = ($id3) ? $ses1->request('open-ils.cstore.direct.biblio.record_entry.search', {id => $id3}, $query) : undef;
        
        if($first) {
            $records{$_}{counts} = $e->json_query({from => ['asset.record_copy_count', 1, $_, 0]})->[0] for @recs;
            $first = 0;
        }
    }

    for my $r ($req1, $req2, $req3) {
        last unless $r;
        my $bre = $r->gather(1);
        my $xml = XML::LibXML->new->parse_string($bre->marc)->documentElement;
        my $attrs = get_bib_attrs($xml);
        $records{$bre->id}{record} = $bre;
        $records{$bre->id}{$_} = $attrs->{$_} for keys %$attrs;
    }


    my $duration = time() - $start;

    for my $rec_id (keys %records) {
        my $rec = $records{$rec_id};
        print sprintf("%d [%s] has %d volumes and %d copies\n",
            $rec_id, $rec->{title}, 
            scalar(@{$rec->{record}->call_numbers}), 
            scalar(map { @{$_->copies} } @{$rec->{record}->call_numbers}));
    }

    print "\n'direct' calls processing duration is $duration\n\n";
}

for (0..1) { direct(@recs); unapi(@recs); unapi_batch(@recs); unapi_spread(@recs); direct_spread(@recs); }
