package OpenSRF::Transport::Listener;
use base 'OpenSRF';
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Transport::SlimJabber::Inbound;
use base 'OpenSRF::Transport::SlimJabber::Inbound';

=head1 Description

This is the empty class that acts as the subclass of the transport listener.  My API
includes

new( $app )
	create a new Listener with appname $app

initialize()
	Perform any transport layer connections/authentication.

listen()
	Block, wait for, and process incoming messages

=cut

=head2 set_listener()

Sets my superclass.  Pass in a string representing the perl module
(e.g. OpenSRF::Transport::Jabber::JInbound) to be used as the
superclass and it will be pushed onto @ISA.

=cut

sub set_listener {
	my( $class, $listener ) = @_;
	OpenSRF::Utils::Logger->transport("Loading Listener $listener", INFO );
	if( $listener ) {
		$listener->use;
		if( $@ ) {
			OpenSRF::Utils::Logger->error(
					"Unable to set transport listener: $@", ERROR );
		}
		unshift @ISA, $listener;
	}
}


1;
