package DAIA::Item;
#ABSTRACT: Holds information about an item of a L<DAIA::Document>
#VERSION

use strict;
use base 'DAIA::Object';

use DAIA;
use JSON;

our %PROPERTIES = (
    id          => $DAIA::Object::COMMON_PROPERTIES{id},
    href        => $DAIA::Object::COMMON_PROPERTIES{href},
    message     => $DAIA::Object::COMMON_PROPERTIES{message},
    part       => {
        filter => sub {
            my $status = shift or return;
            return unless $status eq 'broader' or $status eq 'narrower';
            return $status;
        }
    },
    label       => {
        default => '',
        filter => sub { # label can be specified as array or as element
            my $v = $_[0];
            if (ref($v)) {
                $v = (ref($v) eq 'ARRAY') ? $v->[0] : ''; 
            }
            return "$v";
        },
    },
    department  => { type => 'DAIA::Department' },
    storage     => { type => 'DAIA::Storage' },
    available   => { type => 'DAIA::Available', repeatable => 1 }, 
    unavailable => { type => 'DAIA::Unavailable', repeatable => 1 },
);

=head1 PROPERTIES

=over 

=item id

The unique identifier of this item (optional). Must be an URI if given.

=item href

A link to the item or to additional information about it.

=item message

An optional list of L<DAIA::Message> objects. You can get/set message(s) with
the C<message> accessor.

=item part

Set to C<narrower> if the item only contains a part of the document or
to C<broader> if the item contains more than the document.

=item label

A label that helps to identify and/or find the item (signature etc.).

=item department

A L<DAIA::Department> object with an administrative sub-entitity of the
institution that is connected to this item (for instance the holding
library branch).

=item storage

A L<DAIA::Storage> object with the physical location of the item (stacks, floor etc.).

=item available

An optional list of L<DAIA::Available> objects with available services that can
be performed with this item.

=item unavailable

An optional list of L<DAIA::Unavailable> objects with unavailable services 
that can (currently or in general) not be performed with this item.

=head1 METHODS

=head2 Standard methods

DAIA::Item provides the L<standard methods|DAIA/"DAIA OBJECTS"> and accessor
methods for its properties as listed above.

=head2 Additional appender methods

=over

=item C<< addMessage ( $message | ... ) >>

Add a given or a new L<DAIA::Message>.

=item C<< addAvailable ( $available | ... ) >>

Add a given or a new L<DAIA::Available>.

=item C<< addUnavailable ( $unavailable | ... ) >>

Add a given or a new L<DAIA::Unavailable>.

=item C<< addAvailability ( $availability | ... ) >>

Add a given or a new L<DAIA::Availability>.

=item C<< addService ( $availability | ... ) >>

Add a given or a new L<DAIA::Availability> (alias for addAvailability).

=back

=cut

sub addAvailability {
    my $self = shift;
    return $self unless @_ > 0;
    return $self->add(
        UNIVERSAL::isa( $_[0], 'DAIA::Availability' ) 
          ? $_[0] 
          : DAIA::Availability->new( @_ )
    );
}

*addService = *addAvailability;

=head2 Additional query methods

=over

=item C<< services ( [ @services ] ) >>

Returns a (possibly empty) hash of services mapped to lists
of L<DAIA::Availability> objects for the given services. If
you provide a list of wanted services (each specified by its 
URI or by its short name), you only get those services.

=back

=cut

sub services {
    my $self = shift;

    my %wanted = map { $_ => 1 }
                 map { $DAIA::Availability::SECIVRES{$_} ? 
                       $DAIA::Availability::SECIVRES{$_} : $_ } @_;

    my %services;
    foreach my $a ( ($self->available, $self->unavailable) ) {
        my $s = $a->service;
        next if %wanted and not $wanted{$s};
        if ( $services{$s} ) {
            push @{ $services{$s} }, $a;
        } else {
            $services{$s} = [ $a ];
        }
    }

    return %services;
}

sub rdfhash {
    my $self = shift;
    my $me = { };

    $me->{'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'} = [{
        type => 'uri', value => 'http://purl.org/vocab/frbr/core#Item',
    }];

    $me->{'http://xmlns.com/foaf/0.1/page'} = [{
        value => $self->{href}, type => "uri"
    }] if $self->{href};

    $me->{'http://purl.org/dc/terms/description'} = [
        map { $_->rdfhash } @{$self->{message}}
    ] if $self->{message};

    $me->{'http://purl.org/ontology/daia/label'} = [{
        type => 'literal', value => $self->{label}
    }] if $self->{label};

    my $rdf = { };

    # TODO: department
    
    if ($self->{storage}) {
        my $storage = $self->{storage}->rdfhash;
        if ( $storage->{type} ) { # plain literal
            $me->{'http://purl.org/dc/terms/spatial'} = [$storage];
        } else {
            my ($uri => $data) = %$storage;
            $rdf->{$uri} = $data;
            $me->{'http://purl.org/dc/terms/spatial'} = [{
                type => 'uri', value => $uri
            }];
        }
        my $r = $self->{storage}->rdfhash;
    }

    if ($self->{available}) {
        foreach my $s ( @{$self->{available}} ) {
            my $r = $s->rdfhash;
            $rdf->{$_} = $r->{$_} for keys %$r;
        }
        $me->{'http://purl.org/ontology/daia/availableFor'} = [
            map { { type => 'uri', value => $_->rdfuri } } @{$self->{available}}
        ];
        # TODO: providedBy
    }
    if ($self->{unavailable}) {
        foreach my $s ( @{$self->{unavailable}} ) {
            my $r = $s->rdfhash;
            $rdf->{$_} = $r->{$_} for keys %$r;
        }
        $me->{'http://purl.org/ontology/daia/unavailableFor'} = [
            map { { type => 'uri', value => $_->rdfuri } } @{$self->{unavailable}}
        ];
        # TODO: providedBy
    }

    $rdf->{ $self->rdfuri } = $me;
    return $rdf;
}

1;

=encoding utf8
