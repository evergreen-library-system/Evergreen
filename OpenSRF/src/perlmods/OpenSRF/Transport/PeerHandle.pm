package OpenSRF::Transport::PeerHandle;
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::EX;
use base 'OpenSRF';
use vars '@ISA';

my $peer;

=head2 peer_handle( $handle )

Assigns the object that will act as the peer connection handle.

=cut
sub peer_handle {
	my( $class, $handle ) = @_;
	if( $handle ) { $peer = $handle; }
	return $peer;
}


=head2 set_peer_client( $peer )

Sets the class that will act as the superclass of this class.
Pass in a string representing the module to be used as the superclass,
and that module is 'used' and unshifted into @ISA.  We now have that
classes capabilities.  

=cut
sub set_peer_client {
	my( $class, $peer ) = @_;
	if( $peer ) {
		eval "use $peer;";
		if( $@ ) {
			throw OpenSRF::EX::PANIC ( "Unable to set peer client: $@" );
		}
		unshift @ISA, $peer;
	}
}

1;
