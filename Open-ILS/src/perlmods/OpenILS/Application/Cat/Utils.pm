package OpenILS::Application::Cat::Utils;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::SettingsParser;
use OpenILS::Utils::FlatXML;


my $parser		= XML::LibXML->new();
my $xslt			= XML::LibXSLT->new();
my $xslt_doc	=	$parser->parse_file( "/pines/cvs/ILS/Open-ILS/xsl/MARC21slim2MODS.xsl" );
my $mods_sheet = $xslt->parse_stylesheet( $xslt_doc );



sub new {
	my($class) = @_;
	$class = ref($class) || $class;
	return bless( {}, $class );
}


# ---------------------------------------------------------------------------
# Converts an XML nodeset into a tree
# This method expects a blessed Fieldmapper::biblio::record_node object 
sub nodeset2tree {
	my($class, $nodeset) = @_;

	#	my $x = 0;
	for my $child (@$nodeset) {
		next unless ($child and defined($child->parent_node));
		my $parent = $nodeset->[$child->parent_node];
		if( ! $parent ) {
			warn "No Parent For " . $child->intra_doc_id() . "\n";
		}
		$parent->children([]) unless defined($parent->children); 
		$child->isnew(0);
		$child->isdeleted(0);
		#$child->intra_doc_id($x++);
		push( @{$parent->children}, $child );
	}

	return $nodeset->[0];
}


# ---------------------------------------------------------------------------
# Converts a tree into an xml nodeset
# This method expects a blessed Fieldmapper::biblio::record_node object 

sub tree2nodeset {
	my($self, $node, $newnodes) = @_;

	return $newnodes unless $node;

	if(!$newnodes) { $newnodes = []; }

	push( @$newnodes, $node );

	if( $node->children() ) {

		for my $child (@{ $node->children() }) {

			new Fieldmapper::biblio::record_node ($child);
	
			if(!defined($child->parent_node)) {
				$child->parent_node($node->intra_doc_id);
				$child->ischanged(1); #just to be sure
			}
	
			$self->tree2nodeset( $child, $newnodes );
		}
	}

	$node->children([]); #we don't need them hanging around
	return $newnodes;
}

sub update_children_parents {
	my($self, $node)  = @_;
	if( $node->children ) {
		for my $child( @{$node->children()} ) {
			$child->parent_node( $node->intra_doc_id() );
		}
	}
}


sub clean_nodeset {

	my($self, $nodeset) = @_;
	my @newnodes = ();
	for my $node (@$nodeset) {
		if(!$node->isdeleted() ) {
			push @newnodes, $node;
		}
	}

	return \@newnodes;
}


# ---------------------------------------------------------------------------
# Walks a nodeset and checks for insert, update, and delete and makes 
# appropriate db calls
# This method expects a blessed Fieldmapper::biblio::record_node object 
=head comment
sub clean_nodeset {
	my($self, $nodeset) = @_;

	my @_deleted = ();
#my @_added = ();
#	my @_altered = ();

	my $size = @$nodeset;
	my $offset = 0;
#	my $doc_id = undef;

	for my $index (0..$size) {

		my $pos = $index + $offset;
		my $node = $nodeset->[$index];
		next unless $node;
		
#	if( !defined($doc_id) ) {
#			$doc_id = $node->owner_doc;
#		}

		if($node->isdeleted()) {
			$offset--;
			warn "Deleting Node " . $node->intra_doc_id() . "\n";
			push @_deleted, $node;
			next;
		}
	}

}

		if($node->isnew()) {
			$node->intra_doc_id($pos);
			warn "Adding Node $pos\n";
			$node->owner_doc($doc_id);
			$node->clear_id();
			push @_added, $node;
			next;
		}

		if(	($node->intra_doc_id() 
				and $node->intra_doc_id() != $pos) ||
			 $node->ischanged() ) {

			warn "Updating Node " . $node->intra_doc_id() . " to $pos\n";

			$node->intra_doc_id($pos);
			$self->update_children_parents( $node );
			push @_altered, $node;
			next;
		}


	my $d;
	my $al;
	my $added_stuff;
	my $status;

	warn "Building db session\n";
	my $session = $self->start_db_session();

	my $szz = @_deleted;
	warn "Deleting $szz\n";

	if(@_deleted) {
		warn "Sending deletes to db\n";
		my $del_req = $session->request( 
				"open-ils.storage.biblio.record_node.batch.delete", @_deleted );
		$status = $del_req->recv();
		if(ref($status) and $status->isa("Error")) { 
			warn " +++++++ Node Delete Failed in Cat";
			throw $status ("Node Delete Failed in Cat") ; 
		}
		warn "Delete Successful\n";
		$d = $status->content(); 
	}

	$szz = @_altered;
	warn "Updating $szz\n";

	if( @_altered ) {
		warn "Sending updates to db\n";
		@_altered = sort { $a->id <=> $b->id } @_altered;
		my $alt_req = $session->request( 
			"open-ils.storage.biblio.record_node.batch.update", @_altered );
		$status = $alt_req->recv();
		if(ref($status) and $status->isa("Error")) { 
			warn " +++++++ Node Update Failed in Cat";
			throw $status ("Node Update Failed in Cat"); 
		}
		warn "Update Successful\n";
		$al = $status->content(); 
	}

	$szz = @_added;
	warn "Adding $szz\n";

	if(@_added) {
		warn "Sending adds to db\n";
		my $add_req = $session->request( 
				"open-ils.storage.biblio.record_node.batch.create", @_added );
		$status = $add_req->recv();
		if(ref($status) and $status->isa("Error")) { 
			warn " +++++++ Node Create Failed in Cat";
			throw $status ("Node Create Failed in Cat"); 
		}
		$added_stuff = $status->content(); 
		warn "Add successful\n";
	}

	warn "done updating records\n";
	$self->commit_db_session( $session );

	my $hash = { added => $added_stuff, deleted => $d, updated =>  $al };
	use Data::Dumper;
	warn Dumper $hash;

	return $hash;
}
=cut

# on sucess, returns the created session, on failure throws ERROR exception
sub start_db_session {
	my $self = shift;
	my $session = OpenSRF::AppSession->connect( "open-ils.storage" );
	my $trans_req = $session->request( "open-ils.storage.transaction.begin" );
	my $trans_resp = $trans_req->recv();
	if(ref($trans_resp) and $trans_resp->isa("Error")) { throw $trans_resp; }
	if( ! $trans_resp->content() ) {
		throw OpenSRF::ERROR ("Unable to Begin Transaction with database" );
	}
	$trans_req->finish();
	return $session;
}

# commits and destroys the session
sub commit_db_session {
	my( $self, $session ) = @_;

	my $req = $session->request( "open-ils.storage.transaction.commit" );
	my $resp = $req->recv();
	if(ref($resp) and $resp->isa("Error")) { throw $resp; }

	$session->finish();
	$session->disconnect();
	$session->kill_me();
}


sub mods_perl_to_mods_slim {
	my( $self, $modsperl ) = @_;

	use Data::Dumper;
	warn Dumper $modsperl;

	my $title = $modsperl->{titleInfo}->{title};
	my $author	= $modsperl->{name}->{namePart};
	if(ref($author) eq "ARRAY") {
		$author = $author->[0];
	}

	return { "title" => $title, "author" => $author };

}



# ---------------------------------------------------------------------------
# Utility method for turning a nodes_array ($nodelist->nodelist) into
# a perl structure
# ---------------------------------------------------------------------------
sub _nodeset_to_perl {
	my($self, $nodeset) = @_;
	return undef unless ($nodeset);
	my $xmldoc = 
		OpenILS::Utils::FlatXML->new()->nodeset_to_xml($nodeset);

	# Evil, but for some reason necessary
	$xmldoc = $parser->parse_string( $xmldoc->toString() );
	my $perl = $self->marcxml_doc_to_mods_perl($xmldoc);
	return $perl;
}


# ---------------------------------------------------------------------------
# Initializes a MARC -> Unified MODS batch process
# ---------------------------------------------------------------------------
sub start_mods_batch {
	my( $self, $master_doc ) = @_;
	$self->{master_doc} = $self->_nodeset_to_perl( $master_doc );
}

# ---------------------------------------------------------------------------
# Completes a MARC -> Unified MODS batch process and returns the perl hash
# ---------------------------------------------------------------------------
sub finish_mods_batch {
	my $self = shift;
	my $perl = $self->{master_doc};
	$self->{master_doc} = undef;
	return $perl
}

# ---------------------------------------------------------------------------
# Pushes a marcxml nodeset into the current MODS batch
# ---------------------------------------------------------------------------
sub mods_push_nodeset {
	my( $self, $nodeset ) = @_;
	my $xmlperl	= $self->_nodeset_to_perl( $nodeset );
	for my $subject( @{$xmlperl->{subject}} ) {
		push @{$self->{master_doc}->{subject}}, $subject;
	}
}



# ---------------------------------------------------------------------------
# Transforms a MARC21SLIM XML document into a MODS formatted perl hash
# ---------------------------------------------------------------------------
sub marcxml_doc_to_mods_perl {
	my( $self, $marcxml_doc ) = @_;
	my $mods = $mods_sheet->transform($marcxml_doc);
	my $perl = OpenSRF::Utils::SettingsParser::XML2perl( $mods->documentElement );
	return $perl->{mods} if exists($perl->{mods});
	return $perl;
}



# ---------------------------------------------------------------------------
# Transforms a set of marcxml nodesets into a unified MODS perl hash.  The
# first doc is assumed to be the 'master'
# ---------------------------------------------------------------------------
sub marcxml_nodeset_list_to_mods_perl {
	my( $self, $nodeset_list ) = @_;
	my $master = $self->_nodeset_to_perl( shift(@$nodeset_list) );
	my $first;
	for my $nodes (@$nodeset_list) {
		my $xmlperl	= $self->_nodeset_to_perl( $nodes );
		for my $subject( @{$xmlperl->{subject}} ) {
			push @{$master->{subject}}, $subject;
		}
	}
	return $master;
}



# not really sure if we'll ever need this one...
sub marcxml_doc_to_mods_nodeset {
	my( $self, $marcxml_doc ) = @_;
	my $mods = $mods_sheet->transform($marcxml_doc);
	my $u = OpenILS::Utils::FlatXML->new();
	my $nodeset = $u->xmldoc_to_nodeset( $mods );
	return $nodeset->nodeset if $nodeset;
	return undef;
}







1;
