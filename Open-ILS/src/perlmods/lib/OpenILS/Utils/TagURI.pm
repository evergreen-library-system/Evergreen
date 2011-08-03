use strict;
use warnings;

=over

use Data::Dumper;

sub test_parser {
    my $t = shift;
    print "$t\n" . Dumper( OpenILS::Utils::TagURI->new( $t ) ) . "\n\n";
}

test_parser('TAG::stuff');
test_parser('tag::stuff');
test_parser('tag:open-ils.org:U2@acn/59521');
test_parser('tag:fulfillment2.esilibrary.com,2010:U2@bre/6866[1,2]');
test_parser('tag:x:U2@bre/6866[1,2]{bre,auri}/br1/2');
test_parser('tag:x:U2@bre/6866{bre,auri}/br1/2');
test_parser('tag:x:U2@bre/6866{bre,auri}');
test_parser('tag:x:U2@bre/6866/br1/2/some/extra/data');
test_parser('tag:x:U2@bre/6866/br1/2');
test_parser('tag:x:U2@bre/6866/br1');
test_parser('tag:x:biblio-record_entry/6866');

=cut

package OpenILS::Utils::TagURI;

our $AUTOLOAD;
sub DESTROY { } # keeps AUTOLOAD from catching inherent DESTROY calls

sub AUTOLOAD {
    my $obj = shift;
    (my $field = $AUTOLOAD) =~ s/^.*://o;

    if (@_) {
        return $obj->{$field} = shift;
    } else {
        return $obj->{$field};
    }

}


sub new {
    my $class = shift;
    my $tag = shift;
    $class = ref($class) || $class;

    my $self = bless {} => $class;
    $self->parse($tag) if ($tag);

    return $self;
}

sub parse {
    my $self = shift;
    $self = $self->new() unless (ref($self));

    my $tag = shift;
    my $version = 1;

    (warn("!! invalid tag uri: $tag\n") && return undef) unless ($tag =~ s/^tag:(?:([^:,]*),?([^:]*))://); # valid?
    my ($host, $validity) = ($1, $2);
    $self->host($host);
    $self->validity($validity);

    my ($classname, $id, $paging, $inc, $loc, $depth, $mods) = ($1, $2, $3, $4, $5, $6, $7)
        if ($tag =~ /^
                        ([^\/]+)            # classname
                        (?:\/([^[\/]+?)     # id
                          (?:\[([^]]+)\])?  # paging
                          (?:\{([^}]+)\})?  # includes
                          (?:\/(\w+))?      # location
                          (?:\/(\w+))?      # depth
                          (?:\/(.+))?       # pathinfo
                        )?
                    $/x);

    (warn("!! missing class ($classname) or id ($id) in uri: $tag\n") && return undef) if (!defined($classname) && !defined($id));

    if (!defined($id)) {
        $version = -1;
        $self->data($classname);
    } else {
        if ($classname =~ /^U2\@/) {
            $classname =~ s/^U2\@//;
            $version = 2;
        }
    
        $self->classname($classname);
        $self->id($id);
        $self->paging(($paging ? [ map { s/^\s*//; s/\s*$//; $_ } split(',', $paging) ] : []));
        $self->includes(($inc ? { map { /:/ ? split(':') : ($_,undef) } map { s/^\s*//; s/\s*$//; $_ } split(',', $inc) } : {}));
        $self->location($loc);
        $self->depth($depth);
        $self->pathinfo($mods);
    }

    $self->version($version);
    return $self;
}

sub toURI {
    my $class = shift;
    my $parts = shift || {};

    my $self = ref($class) ? $class : $class->new;

    $self->$_($$parts{$_}) for keys %$parts;
    return undef unless (defined($self->classname) && defined($self->id));

    my $tag = 'tag:';

    if ($self->host) {
        $tag .= $self->host;
        $tag .= ',' . $self->validity if ($self->validity);
    }

    $tag .= ':';

    $tag .= 'U2@' if ($self->version == 2);
    $tag .= $self->classname . '/' . $self->id;
    $tag .= '['. join(',', @{ $self->paging }) . ']' if defined($self->paging);
    $tag .= '{'. join(',', map { $_ . ':' . $self->includes->{$_} } keys %{ $self->includes }) . '}' if defined($self->includes);
    $tag .= '/' . $self->location if defined($self->location);
    $tag .= '/' . $self->depth if defined($self->depth);
    $tag .= '/' . $self->pathinfo if defined($self->pathinfo);

    return $tag;
}

1;
