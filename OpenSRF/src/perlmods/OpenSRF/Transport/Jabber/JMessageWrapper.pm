package OpenSRF::Transport::Jabber::JMessageWrapper;
use Jabber::NodeFactory;
use Net::Jabber qw(Client);
use Net::Jabber::Message;
use base qw/ Net::Jabber::Message OpenSRF /;
use OpenSRF::Utils::Logger qw(:level);
use strict; use warnings;

=head1 Description

OpenSRF::Transport::Jabber::JMessageWrapper

Provides a means to extract information about a Jabber
message when all you have is the raw XML.  The API
implemented here should be implemented by any Transport
helper/MessageWrapper class.

=cut

sub DESTROY{}

my $logger = "OpenSRF::Utils::Logger";
my $_node_factory = Jabber::NodeFactory->new( fromstr => 1 );


=head2 new( Net::Jabber::Message/$raw_xml )

Pass in the raw Jabber message as XML and create a new 
JMessageWrapper

=cut

sub new {
	my( $class, $xml ) = @_;
	$class = ref( $class ) || $class;

	return undef unless( $xml );
	
	my $self;

	if( ref( $xml ) ) {
		$self = $xml;
	} else {
		$logger->transport( "MWrapper got: " . $xml, INTERNAL );
		my $node = $_node_factory->newNodeFromStr( $xml );
		$self = $class->SUPER::new();
		$self->SetFrom( $node->attr('from') );
		$self->SetThread( $node->getTag('thread')->data );
		$self->SetBody( $node->getTag('body')->data );
	}

	bless( $self, $class );

	$logger->transport( "MessageWrapper $self after blessing", INTERNAL );

	return $self;

}

=head2 get_remote_id

Returns the JID (user@host/resource) of the remote user

=cut
sub get_remote_id {
	my( $self ) = @_;
	return $self->GetFrom();
}

=head2 get_sess_id

Returns the Jabber thread associated with this message

=cut
sub get_sess_id {
	my( $self ) = @_;
	return $self->GetThread();
}

=head2 get_body

Returns the message body of the Jabber message

=cut
sub get_body {
	my( $self ) = @_;
	return $self->GetBody();
}


1;
