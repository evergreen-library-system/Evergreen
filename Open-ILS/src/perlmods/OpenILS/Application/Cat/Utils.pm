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

	for my $child (@$nodeset) {
		next unless ($child and defined($child->parent_node));
		my $parent = $nodeset->[$child->parent_node];
		if( ! $parent ) {
			warn "No Parent For " . $child->intra_doc_id() . "\n";
		}
		$parent->children([]) unless defined($parent->children); 
		$child->isnew(0);
		$child->isdeleted(0);
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


# Removes any deleted nodes from the tree
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




# ---------------------------------------------------------------------------
# Grabs the data 'we want' from the MODS doc and returns it in hash form
# ---------------------------------------------------------------------------
sub mods_perl_to_mods_slim {
	my( $self, $modsperl ) = @_;

	my $title = "";
	my $author = "";

	my $tmp = $modsperl->{titleInfo};
	if($tmp) { 
		if(ref($tmp) eq "ARRAY" ) {
			$tmp = $tmp->[0];
		}
		$title = $tmp->{title};
	}
	if( $title and ref($title) eq "ARRAY" ) {
		$title = $title->[0];
	}

	$tmp = $modsperl->{name};
	if($tmp) { 
		if(ref($tmp) eq "ARRAY" ) {
			$tmp = $tmp->[0];
		}
		$author = $tmp->{namePart}; 
	}
	if($author and ref($author) eq "ARRAY") {
		$author = $author->[0];
	}

	return { "title" => $title, "author" => $author };

}

sub _marcxml_to_perl {
	my($self, $marcxml) = @_;
	my $xmldoc = $parser->parse_string( $marcxml );
	my $mods = $mods_sheet->transform($xmldoc);
	my $perl = OpenSRF::Utils::SettingsParser::XML2perl( $mods->documentElement );
	return $perl->{mods} if exists($perl->{mods});
	return $perl;
}


# ---------------------------------------------------------------------------
# Initializes a MARC -> Unified MODS batch process
# ---------------------------------------------------------------------------
sub start_mods_batch {
	my( $self, $master_doc ) = @_;
	$self->{master_doc} = $self->_marcxml_to_perl( $master_doc );
}

# ---------------------------------------------------------------------------
# Takes a MARCXML string an adds it to the growing MODS doc
# ---------------------------------------------------------------------------
sub push_mods_batch {
	my( $self, $marcxml ) = @_;
	my $xmlperl = $self->_marcxml_to_perl( $marcxml );
	for my $subject( @{$xmlperl->{subject}} ) {
		push @{$self->{master_doc}->{subject}}, $subject;
	}
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




1;
