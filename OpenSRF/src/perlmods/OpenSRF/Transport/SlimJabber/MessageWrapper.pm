package OpenSRF::Transport::SlimJabber::MessageWrapper;
use OpenSRF::DOM;

sub new {
	my $class = shift;
	$class = ref($class) || $class;

	my $xml = shift;

	my ($doc, $msg);
	if ($xml) {
		$doc = OpenSRF::DOM->new->parse_string($xml);
		$msg = $doc->documentElement;
	} else {
		$doc = OpenSRF::DOM->createDocument;
		$msg = $doc->createElement( 'message' );
		$doc->documentElement->appendChild( $msg );
	}

	
	my $self = { msg_node => $msg };

	return bless $self => $class;
}

sub toString {
	my $self = shift;
	return $self->{msg_node}->toString(@_);
}

sub get_body {
	my $self = shift;
	my ($t_body) = grep {$_->nodeName eq 'body'} $self->{msg_node}->childNodes;
	if( $t_body ) {
		my $body = $t_body->textContent;
		return $body;
	}
	return "";
}

sub get_sess_id {
	my $self = shift;
	my ($t_node) = grep {$_->nodeName eq 'thread'} $self->{msg_node}->childNodes;
	if( $t_node ) {
		return $t_node->textContent;
	}
	return "";
}

sub get_msg_type {
	my $self = shift;
	$self->{msg_node}->getAttribute( 'type' );
}

sub get_remote_id {
	my $self = shift;

	#
	my $rid = $self->{msg_node}->getAttribute( 'router_from' );
	return $rid if $rid;

	return $self->{msg_node}->getAttribute( 'from' );
}

sub setType {
	my $self = shift;
	$self->{msg_node}->setAttribute( type => shift );
}

sub setTo {
	my $self = shift;
	$self->{msg_node}->setAttribute( to => shift );
}

sub setThread {
	my $self = shift;
	$self->{msg_node}->appendTextChild( thread => shift );
}

sub setBody {
	my $self = shift;
	my $body = shift;
	$self->{msg_node}->appendTextChild( body => $body );
}

sub set_router_command {
	my( $self, $router_command ) = @_;
	if( $router_command ) {
		$self->{msg_node}->setAttribute( router_command => $router_command );
	}
}
sub set_router_class {
	my( $self, $router_class ) = @_;
	if( $router_class ) {
		$self->{msg_node}->setAttribute( router_class => $router_class );
	}
}

1;
