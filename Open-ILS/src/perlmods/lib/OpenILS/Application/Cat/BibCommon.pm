package OpenILS::Application::Cat::BibCommon;
use strict; use warnings;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger qw($logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
use OpenSRF::AppSession;
use OpenILS::Event;
my $U = 'OpenILS::Application::AppUtils';
my $MARC_NAMESPACE = 'http://www.loc.gov/MARC21/slim';


# ---------------------------------------------------------------------------
# Shared bib mangling code.  Do not publish methods from here.
# ---------------------------------------------------------------------------

my $__bib_sources;
sub bib_source_from_name {
	my $name = shift;
	$logger->debug("searching for bib source: $name");

	fetch_bib_sources();

	my ($s) = grep { lc($_->source) eq lc($name) } @$__bib_sources;

	return $s->id if $s;
	return undef;
}

sub fetch_bib_sources {
	$__bib_sources = new_editor()->retrieve_all_config_bib_source()
		unless $__bib_sources;
	return $__bib_sources;
}


sub biblio_record_replace_marc  {
	my($class, $e, $recid, $newxml, $source, $fixtcn, $override) = @_;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

	my $rec = $e->retrieve_biblio_record_entry($recid)
		or return $e->die_event;

    # See if there is a different record in the database that has our TCN value
    # If we're not updating the TCN, all we care about it the marcdoc
    # XXX should .update even bother with the tcn_info if it's not going to replace it?
    # there is the potential for returning a TCN_EXISTS event, even though no replacement happens

	my( $tcn, $tsource, $marcdoc, $evt);

    if($fixtcn or $override->{all} or $override->{events}) {

	    ($tcn, $tsource, $marcdoc, $evt) = 
		    _find_tcn_info($e, $newxml, $override, $recid);

	    return $evt if $evt;

		$rec->tcn_value($tcn) if ($tcn);
		$rec->tcn_source($tsource);

    } else {

        $marcdoc = __make_marc_doc($newxml);
    }


	$rec->source(bib_source_from_name($source)) if $source;
	$rec->editor($e->requestor->id);
	$rec->edit_date('now');
	$rec->marc( $U->entityize( $marcdoc->documentElement->toString ) );
	$e->update_biblio_record_entry($rec) or return $e->die_event;

	return $rec;
}

sub biblio_record_xml_import {
	my($class, $e, $xml, $source, $auto_tcn, $override) = @_;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

	my( $evt, $tcn, $tcn_source, $marcdoc );

    my $use_id = $e->retrieve_config_global_flag('cat.bib.use_id_for_tcn');
    $use_id = ($use_id and $U->is_true($use_id->enabled));

	if( $auto_tcn or $use_id ) {
		# auto_tcn forces a blank TCN value so the DB will have to generate one for us
		$marcdoc = __make_marc_doc($xml);
	} else {
		( $tcn, $tcn_source, $marcdoc, $evt ) = _find_tcn_info($e, $xml, $override);
		return $evt if $evt;
	}

	# Silence warnings when _find_tcn_info() fails
	$tcn ||= '';
	$tcn_source ||= '';
	$logger->info("user ".$e->requestor->id.
		" creating new biblio entry with tcn=$tcn and tcn_source $tcn_source");

	my $record = Fieldmapper::biblio::record_entry->new;

	$record->source(bib_source_from_name($source)) if $source;
	$record->tcn_source($tcn_source);
	$record->tcn_value($tcn) if ($tcn);
	$record->creator($e->requestor->id);
	$record->editor($e->requestor->id);
	$record->create_date('now');
	$record->edit_date('now');
	$record->marc($U->entityize($marcdoc->documentElement->toString));

    $record = $e->create_biblio_record_entry($record) or return $e->die_event;

    if($use_id) {
        my $existing = $e->search_biblio_record_entry(
            {   
                tcn_value => $record->id,
                deleted => 'f'
            }, { 
                idlist => 1 
            }
        );

        if(@$existing) {
            # leave the auto-generated tcn_value in place
            $logger->warn("Collision using internal ID as tcn_value for record " . $record->id);
        } else {
            $record->tcn_value($record->id);
            $e->update_biblio_record_entry($record) or return $e->die_event;
        }
    }

	$logger->info("marc create/import created new record ".$record->id);
	return $record;
}

sub __make_marc_doc {
	my $xml = shift;
	my $marcxml = XML::LibXML->new->parse_string($xml);
	$marcxml->documentElement->setNamespace($MARC_NAMESPACE, "marc", 1 );
	$marcxml->documentElement->setNamespace($MARC_NAMESPACE);
	__remove_empty_marc_nodes($marcxml);
	return $marcxml;
}

# remove empty control fields, subfields, and variable data fields, which
# can creep in via less-than-correct imported MARC records or issues
# with templates
sub __remove_empty_marc_nodes {
	my $marcxml = shift;

	__remove_if_childless($_) foreach $marcxml->documentElement->getElementsByTagNameNS($MARC_NAMESPACE, 'controlfield');
	__remove_if_childless($_) foreach $marcxml->documentElement->getElementsByTagNameNS($MARC_NAMESPACE, 'subfield');
	__remove_if_childless($_) foreach $marcxml->documentElement->getElementsByTagNameNS($MARC_NAMESPACE, 'datafield');
}

sub __remove_if_childless {
	my $node = shift;
	my @children = $node->childNodes();
	my $has_nonblank_children = 0;
	# can do this more concisely by requiring XML::LibXML >= 1.70 and using nonBlankChildNodes()
	foreach my $node ($node->childNodes()) {
		if ($node->nodeType != XML::LibXML::XML_TEXT_NODE || $node->nodeValue !~ /^\s*$/) {
			$has_nonblank_children = 1;
			last;
		}
	}
	$node->parentNode->removeChild($node) unless $has_nonblank_children;
}

sub _find_tcn_info { 
	my $editor		= shift;
	my $xml			= shift;
	my $override	= shift;
	my $existing_rec	= shift || 0;

    $override = { all => 1 } if($override && !ref $override);
    $override = { all => 0 } if(!ref $override);

	# parse the XML
	my $marcxml = __make_marc_doc($xml);

	my $xpath = '//marc:controlfield[@tag="001"]';
	my $tcn = $marcxml->documentElement->findvalue($xpath);
	$logger->info("biblio import located 001 (tcn) value of $tcn");

	$xpath = '//marc:controlfield[@tag="003"]';
	my $tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";

	if(my $rec = _tcn_exists($editor, $tcn, $tcn_source, $existing_rec) ) {

		my $origtcn = $tcn;
		$tcn = find_free_tcn( $marcxml, $editor, $existing_rec );

		# if we're overriding, try to find a different TCN to use
		if( $override->{all} || grep { $_ eq 'TCN_EXISTS' } @{$override->{events}} ) {

         # XXX Create ALLOW_ALT_TCN permission check support 

			$logger->info("tcn value $tcn already exists, attempting to override");

			if(!$tcn) {
				return ( 
					undef, 
					undef, 
					undef,
					OpenILS::Event->new(
						'OPEN_TCN_NOT_FOUND', 
							payload => $marcxml->toString())
					);
			}

		} else {

			$logger->warn("tcn value $origtcn already exists in import/create");

			# otherwise, return event
			return ( 
				undef, 
				undef, 
				undef,
				OpenILS::Event->new( 
					'TCN_EXISTS', payload => { 
						dup_record	=> $rec, 
						tcn			=> $origtcn,
						new_tcn		=> $tcn
						}
					)
				);
		}
	}

	return ($tcn, $tcn_source, $marcxml);
}

sub find_free_tcn {

	my $marcxml = shift;
	my $editor = shift;
	my $existing_rec = shift;

	my $xpath = '//marc:datafield[@tag="901"]/marc:subfield[@code="a"]';
	my ($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;

    if (!$tcn) {
	    $xpath = '//marc:datafield[@tag="039"]/marc:subfield[@code="a"]';
	    ($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
    }

	$xpath = '//marc:datafield[@tag="901"]/marc:subfield[@code="b"]';
	my ($tcn_source) = $marcxml->documentElement->findvalue($xpath);
    if (!$tcn_source) {
	    $xpath = '//marc:datafield[@tag="039"]/marc:subfield[@code="b"]';
    	$tcn_source = $marcxml->documentElement->findvalue($xpath) || "System Local";
    }

	if(_tcn_exists($editor, $tcn, $tcn_source, $existing_rec)) {
		$tcn = undef;
	}


	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="020"]/marc:subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISBN";
		if(_tcn_exists($editor, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) { 
		$xpath = '//marc:datafield[@tag="022"]/marc:subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "ISSN";
		if(_tcn_exists($editor, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="010"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "LCCN";
		if(_tcn_exists($editor, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}
	}

	if(!$tcn) {
		$xpath = '//marc:datafield[@tag="035"]/marc:subfield[@code="a"]';
		($tcn) = $marcxml->documentElement->findvalue($xpath) =~ /(\w+)\s*$/o;
		$tcn_source = "System Legacy";
		if(_tcn_exists($editor, $tcn, $tcn_source, $existing_rec)) {$tcn = undef;}

		if($tcn) {
			$marcxml->documentElement->removeChild(
				$marcxml->documentElement->findnodes( '//marc:datafield[@tag="035"]' )
			);
		}
	}

	return undef unless $tcn;
	return $tcn;
}



sub _tcn_exists {
	my $editor = shift;
	my $tcn = shift;
	my $source = shift;
	my $existing_rec = shift || 0;

	if(!$tcn) {return 0;}

	$logger->debug("tcn_exists search for tcn $tcn and source $source and id $existing_rec");

	# XXX why does the source matter?
#	my $req = $session->request(      
#		{ tcn_value => $tcn, tcn_source => $source, deleted => 'f' } );

    my $recs = $editor->search_biblio_record_entry(
        {tcn_value => $tcn, deleted => 'f', id => {'!=' => $existing_rec}}, {idlist =>1});

	if(@$recs) {
		$logger->debug("_tcn_exists is true for tcn : $tcn ($source)");
		return $recs->[0];
	}

	$logger->debug("_tcn_exists is false for tcn : $tcn ($source)");
	return 0;
}


sub delete_rec {
   my($class, $editor, $rec_id ) = @_;

   my $rec = $editor->retrieve_biblio_record_entry($rec_id)
      or return $editor->event;

   return undef if $U->is_true($rec->deleted);
   
   $rec->deleted('t');
   $rec->active('f');
   $rec->editor( $editor->requestor->id );
   $rec->edit_date('now');

   # Set the leader/05 to indicate that the record has been deleted
   my $marc = $rec->marc();
   $marc =~ s{(<leader>.{5}).}{$1d};
   $rec->marc($marc);

   $editor->update_biblio_record_entry($rec) or return $editor->event;

    my $holds = $editor->search_action_hold_request({
        target => $rec->id,
        hold_type => 'T',
        cancel_time => undef,
        fulfillment_time => undef
    });

    for my $hold (@$holds) {

        $hold->cancel_time('now');
        $hold->cancel_cause(1); # un-targeted expiration.
        $editor->update_action_hold_request($hold) or return $editor->die_event;

        my $maps = $editor->search_action_hold_copy_map({hold => $hold->id});
        for(@$maps) {
            $editor->delete_action_hold_copy_map($_) 
                or return $editor->die_event;
        }

        my $at_ses = OpenSRF::AppSession->create('open-ils.trigger');
        $at_ses->request(
            'open-ils.trigger.event.autocreate',
            'hold_request.cancel.expire_no_target', 
            $hold, $hold->pickup_lib);
    }

   return undef;
}


# ---------------------------------------------------------------------------
# returns true if the given title (id) has no un-deleted volumes or 
# copies attached.  If a context volume is defined, a record
# is considered empty only if the context volume is the only
# remaining volume on the record.  
# ---------------------------------------------------------------------------
sub title_is_empty {
	my($class, $editor, $rid, $vol_id) = @_;

	return 0 if $rid == OILS_PRECAT_RECORD;

	my $cnlist = $editor->search_asset_call_number(
		{ record => $rid, deleted => 'f' }, { idlist => 1 } );

	return 1 unless @$cnlist; # no attached volumes
    return 0 if @$cnlist > 1; # multiple attached volumes
    return 0 unless $$cnlist[0] == $vol_id; # attached volume is not the context vol.

    # see if the sole remaining context volume has any attached copies
	for my $cn (@$cnlist) {
		my $copylist = $editor->search_asset_copy(
			[
				{ call_number => $cn, deleted => 'f' }, 
				{ limit => 1 },
			], { idlist => 1 });
		return 0 if @$copylist; # false if we find any copies
	}

	return 1;
}
1;
