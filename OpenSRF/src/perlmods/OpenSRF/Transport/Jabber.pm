package OpenSRF::Transport::Jabber;
use base qw/OpenSRF::Transport/;


sub get_listener { return "OpenSRF::Transport::Jabber::JInbound"; }

sub get_peer_client { return "OpenSRF::Transport::Jabber::JPeerConnection"; }

sub get_msg_envelope { return "OpenSRF::Transport::Jabber::JMessageWrapper"; }

1;
