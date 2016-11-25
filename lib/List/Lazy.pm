package List::Lazy; 
# ABSTRACT: Generate lists lazily

=head1 SYNOPSIS

    use List::Lazy qw/ lazy_range /;

    my $range = lazy_range( 1, undef )->grep(sub{ $_ % 2})->map( sub { '!' x $_ } );

    say $_ for $range->next(3); # prints ! !!! !!!!!


=head1 DESCRIPTION

C<List::Lazy> creates lists that lazily evaluate their next values on-demand.

=head1 EXPORTED FUNCTIONS

Lazy::List doesn't export any function by default, but will export the two following 
functions on request.

=head2 lazy_list

    my $list  = lazy_list $generator_sub, $state;

A convenience shortcut for the List::Lazy constructor. The C<$state> will be available
(and can be changed) by the generator subroutine. The generator subroutine is expected
to return a list of one or more next items of the list. Returning an empty list means
that the list has reached its end.

    my $even_numbers = lazy_list { $_ += 2 } 0; # will return 2, 4, 6, ...

=head2 lazy_range

    my $range = lazy_range $min, $max, $iterator;

Creates a list iterating over a range of values. C<$min> and C<$max> are required, but C<$max>  can be 
C<undef> (meaning no upper limit). The C<$iterator> is optional and defaults to the value C<1>. 
The C<$iterator> can be a number, which will be the step at which the numbers are increased, or a coderef that will 
be passed the previous value as C<$_>, and is expected to return the next value.

    my $palinumbers = lazy_range 99, undef, sub { do { $_++ } until $_ eq reverse $_; $_ };

    say join ' ', $palinumbers->next(3); # 99 101 111

=head1 CLASS

=head2 new

    my $list = List::Lazy->new(
        state => 1,
        generator => sub {
            $_++;
        },
    );

Creates a lazy list.

=head3 arguments

=over state

The state will be passed to the generator as C<$_>. If it is modified by the generator,
its new value will be saved for the next invocation.

=over generator

A coderef that generates one or more next items for the list. If it returns an empty list,
the stream will be considered to be exhausted.


=back

=head2 is_done

Returns C<true> is the list is exhausted.

=head2 next($num)

Returns the next C<$num> items of the list (or less if the list doesn't have
that many items left). C<$num> defaults to C<1>.

    my $range = lazy_range 1, 100;

    while( my $next = $range->next ) {
        ...
    }

=head2 reduce

    my $value = $list->reduce( $reducing_sub, $initial_value );

Iterates through the list and reduces its values via the C<$reducing_sub>, which
will be passed the cumulative value and the next item via C<$::a> and C<$::b>. 
If C<$initial_value> is not given, it defaults to the first element of the list.

    my $sum = lazy_range( 1, 100 )->reduce( sub { $::a + $::b } );

=head2 map

    my $new_list = $list->map( $mapper_sub );

Creates a new list by applying the transformation given by C<$mapper_sub> to the
original list. The sub ill be passed the original next item via C<$_>
and is expected to return its transformation, which 
can modify the item, explode it into many items, or suppress it,


Note that the new list do a deep clone of the original list's state, so reading
from the new list won't affect the original list.

    my $recount = ( lazy_range 1, 100 )->map( sub { 1..$_ } );
    # will return 1 1 2 1 2 3 1 2 3 4 ...


=head2 grep

    my $new_list = $list->grep( $filter_sub );

Creates a new list by applying the filtering given by C<$filter_sub> to the
original list. The sub will be passed the original next item via C<$_>
and is expected to return a boolean indicating if the item should be kept or not.


Note that the new list do a deep clone of the original list's state, so reading
from the new list won't affect the original list.

    my $odd = ( lazy_range 1, 100 )->grep( sub { $_ % 2 } );

=cut



use Moo;
use MooX::HandlesVia;

use Clone qw/ clone /;

use 5.20.0;

use experimental 'signatures';

extends 'Exporter::Tiny';

our @EXPORT_OK = qw/ lazy_list lazy_range /;

sub lazy_list :prototype(&@) ($generator,$state=undef) {
    return List::Lazy->new(
        generator => $generator,
        state     => $state,
    );
}

sub lazy_range :prototype($$@) ($min,$max,$step=1) {
    my $it = ref $step ? $step : sub { $_ + $step };

    return scalar lazy_list { 
        return if defined $max and  $_ > $max;
        my $current = $_;
        $_ = $it->();
        return $current;
    } $min;
}

has generator => (
    is => 'ro',
    required => 1, 
);

has state => (
    is => 'rw'
);

has _next => (
    is => 'rw',
    handles_via => 'Array',
    handles => {
        has_next   => 'count', 
        shift_next => 'shift',
        push_next => 'push',
    },
    default => sub { [] },
);

has is_done => (
    is => 'rw',
    default => sub { 0 },
);

sub generate_next($self) {
    local $_ = $self->state;

    my @values = $self->generator->();

    $self->state($_);

    $self->is_done(1) unless @values;

    return @values;
}

sub next($self,$num=1) {
    my @returns;

    while( @returns < $num and not $self->is_done ) {
        $self->push_next( $self->generate_next ) unless $self->has_next;
        push @returns, $self->shift_next;
    }

    return @returns;
}

sub reduce($self,$reducer,$reduced=undef) {
    $reduced = $self->next if @_ < 3;

    while( my $next = $self->next ) {
        local ( $::a, $::b ) = ( $reduced, $next );
        $reduced = $reducer->();
    }

    return $reduced;
}

sub map($self,$map) {
    my $gen = $self->generator;

    return List::Lazy->new(
        state => clone( $self->state ),
        generator => sub {
            while( my @next = $gen->() ) {
                @next = map { $map->() } @next;
                return @next if @next;
            }
            return;
        },
    );
}

sub grep($self,$filter) {
    $self->map(sub{ $filter->() ? $_ : () })
}

sub spy($self,$sub) {
    $self->map(sub{ $sub->(); $_ } ); 
}

1;
