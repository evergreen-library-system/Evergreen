package OpenILS::Utils::X12;
sub new {
    my ($class, $thing) = @_;
    return bless $thing => $class;
}

sub Peers { # returns a thingList of prev,me,next from the original container, with "me" focused
    my $self = shift;
    return undef unless $self->container;

    my ($found, $p, $n);
    for my $e (@{$self->container->{entries}}) {
        if ($found) {
            $n = $e;
            last;
        } elsif ("$e" eq "$self") {
            $found = $e;
            next;
        } else {
            $p = $e;
        }
    }

    return ref($self->container)->new( [$p, $found, $n], currentIndex => 1 );
}

sub container : lvalue { return shift()->{container} } # content from the wire, to be parsed
sub content { return shift()->{content} } # content from the wire, to be parsed
sub msg { return shift()->{msg} }
sub eSepRE { my $X = $_[0]->msg->{eSep}; return qr/\Q$X\E/ }
sub rSepRE { my $X = $_[0]->msg->{rSep}; return qr/\Q$X\E/ }
sub cSepRE { my $X = $_[0]->msg->{cSep}; return qr/\Q$X\E/ }
sub sSepRE { my $X = $_[0]->msg->{sSep}; return qr/\Q$X\E/ }

sub elementsAreRepeatable {
    my $self = shift;
    return $self->msg->{rSep} && $self->msg->{rSep} ne 'U';
}

package OpenILS::Utils::X12::message;
use base OpenILS::Utils::X12;
use Data::Dumper qw/Dumper/;

sub msg { return shift; }
sub remainder { return shift()->{remainder} }

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my $proto = $class->SUPER::new({
        type => 'X12',
        remainder => undef,
        head => undef,
        tail => undef,
        groups => OpenILS::Utils::X12::groupList->new,
        @_
    });

    $proto->{msg} = $proto; # self-ref to share subs

    return $proto->parse;
}

sub parse {
    my $self = shift;

    # pull out the envelope's configuration
    #                       123 4 5-82 83 84-04 05 06
    if ($self->content =~ /^ISA(.).{78}(.).{21}(.)(.)/) {
        $self->{eSep} = $1;
        $self->{rSep} = $2;
        $self->{cSep} = $3;
        $self->{sSep} = $4;
    }

    my $current_group = undef;
    my $current_xact = undef; 
    my $current_seg = undef; 
    my $current_el = undef; 

    my @segs = split($self->sSepRE, $self->content);
    while (my $seg_data = shift @segs) {
        my $seg = $self->createSegment($seg_data);

        if ($seg->type eq 'ISA') { # message start
            $self->head = $seg;

        } elsif ($seg->type eq 'IEA') { # message start
            $self->tail = $seg;
            last;

        } elsif ($seg->type eq 'GS') { # group start
            $current_group = $seg->makeGroup;

        } elsif ($seg->type eq 'GE') { # group end
            $self->groups->push($current_group);

        } elsif ($seg->type eq 'ST') { # xact start
            $current_xact = $seg->makeTransaction;

        } elsif ($seg->type eq 'SE') { # xact end
            $current_group->transactions->push($current_xact);

        } else { # data segment inside transaction
            $current_xact->segments->push($seg);
        }

    }

    if (@segs) {
        $self->{remainder} = join($self->{sSep}, @segs);
    }

    return $self;
}

sub createSegment {
    my $self = shift;
    my $content = shift;

    return OpenILS::Utils::X12::segment->new($self, content => $content, @_);
}

sub head : lvalue { return shift()->{head} }
sub tail : lvalue { return shift()->{tail} }
sub groups : lvalue { return shift()->{groups} }

package OpenILS::Utils::X12::segment;
use base OpenILS::Utils::X12;
use Data::Dumper qw/Dumper/;

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my $msg = shift;

    my $proto = {
        elements => OpenILS::Utils::X12::elementList->new,
        lastElementIndex => 0,
        msg => $msg,
        @_
    };

    bless $proto => $class;

    return $proto->parse;
}

sub makeTransaction {
    my $self = shift;
    $self->{segments} = OpenILS::Utils::X12::segmentList->new;
    $self->{tail} = undef;
    return bless $self => OpenILS::Utils::X12::transaction;
}

sub makeGroup {
    my $self = shift;
    $self->{transactions} = OpenILS::Utils::X12::transactionList->new;
    $self->{tail} = undef;
    return bless $self => OpenILS::Utils::X12::group;
}

sub type : lvalue { return shift()->{type} }
sub elements { return shift()->{elements} }

sub nextElementIndex {
    my $self = shift;
    return ++$self->{lastElementIndex};
}

sub createElement {
    my $self = shift;
    my $content = shift;

    return OpenILS::Utils::X12::element->new($self, content => $content, @_);
}

sub parse {
    my $self = shift;
    my $content = $self->content;

    my @els = split($self->eSepRE, $content);
    $self->type = shift(@els);

    for my $el_content (@els) {
        my $el_index = $self->nextElementIndex;
        my @repeat_data = $self->elementsAreRepeatable ? split($self->rSepRE, $el_content) : ($el_content);

        $self->elements->push(map {
            $self->createElement($_, index => $el_index)
        } @repeat_data);

    }

    return $self;
}

package OpenILS::Utils::X12::group;
use base OpenILS::Utils::X12::segment;
use Data::Dumper qw/Dumper/;

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my $proto = $class->SUPER::new(
        @_, tail => undef,
        transactions => OpenILS::Utils::X12::transactionList->new
    );

    return $proto->parse;
}

sub transactions : lvalue { return shift()->{transactions} }

package OpenILS::Utils::X12::transaction;
use base OpenILS::Utils::X12::segment;
use Data::Dumper qw/Dumper/;

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my $proto = $class->SUPER::new(
        @_, tail => undef,
        segments => OpenILS::Utils::X12::segment->new
    );

    return $proto->parse;
}

sub segments : lvalue { return shift()->{segments} }

package OpenILS::Utils::X12::element;
use base OpenILS::Utils::X12;
use Data::Dumper qw/Dumper/;

sub new {
    my $self = shift;
    my $class = ref($self) || $self;

    my $seg = shift;

    my $proto = {
        segment => $seg,
        msg => $seg->msg,
        data => undef,
        @_
    };

    bless $proto => $class;

    if (!$proto->index) {
        $proto->index = $seg->nextElementIndex;
    }

    return $proto->parse;
}

sub dataMatches {
    my $self = shift;
    my $match = shift;
    if ($self->isComposite) {
        return grep {/$match/} @{$$self{data}};
    }
    return $$self{data} =~ /$match/;
}

sub isComposite {
    my $self = shift;
    return ref($self->data) ? 1 : 0;
}

sub segment : lvalue { return shift()->{segment} }
sub label : lvalue { return shift()->{label} }
sub data : lvalue { return shift()->{data} }
sub index : lvalue { return shift()->{'index'} }

sub parse {
    my $self = shift;
    my $content = $self->content;
    $self->label = sprintf('%s%02d', $self->segment->type, $self->index);

    if ($self->segment->type ne 'ISA' and $content =~ $self->cSepRE) { # composite field
        $self->data = [split($self->cSepRE, $content)];
    } else {
        $self->data = $content;
    }

    return $self
}

package OpenILS::Utils::X12::thingList;
use base OpenILS::Utils::X12;

sub new {
    my $self = shift;
    my $list = shift || [];
    my $class = ref($self) || $self;

    return $class->SUPER::new({currentIndex => -1, entries => $list, @_})
}

sub push {
    my $self = shift;
    for my $new_e (@_) {
        $new_e->container = $self;
        push @{$$self{entries}}, $new_e;
    }
}

sub byField {
    my $self = shift;
    my $class = ref($self) || $self;

    my $field = shift;
    my $needle = shift;
    $needle = [$needle] unless ref($needle);

    my @pile;
    for my $n (@$needle) {
        CORE::push @pile, grep { $$_{$field} =~ /$n/ } @{$$self{entries}};
    }
    return $class->new(\@pile);
}

sub CurrentIndex {
    my $self = shift;
    return $$self{currentIndex};
}

sub Decrement {
    my $self = shift;
    $$self{currentIndex}-- if ($$self{currentIndex} > 0);
    return $self;
}

sub Size {
    my $self = shift;
    return scalar(@{$$self{entries}});
}

sub First {
    my $self = shift;
    return $self->Reset(0)->Current;
}

sub Last {
    my $self = shift;
    return $self->Reset($self->Size - 1)->Current;
}

sub Increment {
    my $self = shift;
    $$self{currentIndex}++ if ($$self{currentIndex} < $self->Size);
    return $self;
}

sub Current {
    my $self = shift;
    return undef if ($$self{currentIndex} < 0 or $$self{currentIndex} >= $self->Size);
    return $$self{entries}[$$self{currentIndex}];
}

sub Next {
    my $self = shift;
    return undef if ($$self{currentIndex} >= $self->Size);
    return $self->Increment->Current;
}

sub Prev {
    my $self = shift;
    return undef if ($$self{currentIndex} <= 0);
    return $self->Decrement->Current;
}

sub Reset {
    my $self = shift;
    $$self{currentIndex} = shift // -1;
    return $self;
}

sub Peek { # clone list, retain currentIndex
    my $self = shift;
    my $class = ref($self);
    return undef unless $class;

    return $class->new([@{$$self{entries}}], currentIndex => $$self{currentIndex});
}

package OpenILS::Utils::X12::elementList;
use base OpenILS::Utils::X12::thingList;

sub findByLabel {
    my $self = shift;
    my $needle = shift;

    return $self->byField('label', $needle);
}

sub findByData {
    my $self = shift;
    my $needle = shift;
    my $class = ref($self) || $self;

    $needle = [$needle] unless ref($needle);

    my @pile;
    for my $n (@$needle) {
        push @pile, grep { $_->dataMatches($n) } @{$$self{entries}};
    }
    return $class->new(\@pile);
}

package OpenILS::Utils::X12::segmentList;
use base OpenILS::Utils::X12::thingList;

sub untilNext {
    my $self = shift;
    my $type = shift;
    my $class = ref($self) || $self;

    my @pile = ($self->Current); # include Current as the "set leader". IOW, left-inclusive, right-exclusive

    my $ci = $self->{currentIndex} + 1;
    while ($ci < scalar(@{$$self{entries}})) {
        last if ($$self{entries}[$ci]->type eq $type);
        push @pile, $$self{entries}[$ci];
        $ci++;
    }

    return $class->new(\@pile);
}

sub findByType {
    my $self = shift;
    my $needle = shift;

    return $self->byField('type', $needle);
}

package OpenILS::Utils::X12::groupList;
use base OpenILS::Utils::X12::segmentList;

package OpenILS::Utils::X12::transactionList;
use base OpenILS::Utils::X12::segmentList;

1;

