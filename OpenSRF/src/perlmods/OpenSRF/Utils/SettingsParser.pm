use strict; use warnings;
package OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::Config;
use OpenSRF::EX qw(:try);



use XML::LibXML;

sub DESTROY{}
our $log = 'OpenSRF::Utils::Logger';
my $parser;
my $doc;

sub new { return bless({},shift()); }


# returns 0 if the config file could not be found or if there is a parse error
# returns 1 if successful
sub initialize {

	my ($self,$bootstrap_config) = @_;
	return 0 unless($self and $bootstrap_config);

	$parser = XML::LibXML->new();
	$parser->keep_blanks(0);
	try {
		$doc = $parser->parse_file( $bootstrap_config );
	} catch Error with {
		return 0;
	};
	return 1;
}

sub _get { _get_overlay(@_) }

sub _get_overlay {
	my( $self, $xpath ) = @_;
	my @nodes = $doc->documentElement->findnodes( $xpath );
	
	my $base = XML2perl(shift(@nodes));
	my @overlays;
	for my $node (@nodes) {
		push @overlays, XML2perl($node);
	}

	for my $ol ( @overlays ) {
		$base = merge_perl($base, $ol);
	}
	
	return $base;
}

sub _get_all {
	my( $self, $xpath ) = @_;
	my @nodes = $doc->documentElement->findnodes( $xpath );
	
	my @overlays;
	for my $node (@nodes) {
		push @overlays, XML2perl($node);
	}

	return \@overlays;
}

sub merge_perl {
	my $base = shift;
	my $ol = shift;

	if (ref($ol)) {
		if (ref($ol) eq 'HASH') {
			for my $key (keys %$ol) {
				if (ref($$ol{$key}) and ref($$ol{$key}) eq ref($$base{$key})) {
					merge_perl($$base{$key}, $$ol{$key});
				} else {
					$$base{$key} = $$ol{$key};
				}
			}
		} else {
			for my $key (0 .. scalar(@$ol) - 1) {
				if (ref($$ol[$key]) and ref($$ol[$key]) eq ref($$base[$key])) {
					merge_perl($$base[$key], $$ol[$key]);
				} else {
					$$base[$key] = $$ol[$key];
				}
			}
		}
	} else {
		$base = $ol;
	}

	return $base;
}


sub XML2perl {
	my $node = shift;
	my %output;

	return undef unless($node);

	for my $attr ( ($node->attributes()) ) {
		next unless($attr);
		$output{$attr->nodeName} = $attr->value;
	}

	my @kids = $node->childNodes;
	if (@kids == 1 && $kids[0]->nodeType == 3) {
			return $kids[0]->textContent;
	} else {
		for my $kid ( @kids ) {
			next if ($kid->nodeName eq 'comment');
			if (exists $output{$kid->nodeName}) {
				if (ref $output{$kid->nodeName} ne 'ARRAY') {
					$output{$kid->nodeName} = [$output{$kid->nodeName}, XML2perl($kid)];
				} else {
					push @{$output{$kid->nodeName}}, XML2perl($kid);
				}
				next;
			}
			$output{$kid->nodeName} = XML2perl($kid);
		}
	}

	return \%output;
}


# returns the full config hash for a given server
sub get_server_config {
	my( $self, $server ) = @_;
	my $xpath = "/opensrf/default|/opensrf/hosts/$server";
	return $self->_get( $xpath );
}

sub get_bootstrap_config {
	my( $self ) = @_;
	my $xpath = "/opensrf/bootstrap";
	return $self->_get( $xpath );
}

sub get_router_config {
	my( $self, $router ) = @_;
	my $xpath = "/opensrf/routers/$router";
	return $self->_get($xpath );
}




1;
