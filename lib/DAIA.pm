use strict;
use warnings;
package DAIA;
#ABSTRACT: Document Availability Information API
#VERSION

# we do not want depend on the following modules
our ($TRINE_MODEL, $TRINE_SERIALIZER, $RDF_NS, $GRAPHVIZ);
BEGIN {
    # optionally use RDF::Trine::Serializer
    $TRINE_MODEL = 'RDF::Trine::Model';
    $TRINE_SERIALIZER = 'RDF::Trine::Serializer';
    eval "use $TRINE_MODEL; use $TRINE_SERIALIZER";
    if ($@) {
        $TRINE_MODEL = undef;
        $TRINE_SERIALIZER = undef;
    }
    # optionally use RDF::NS
    eval "use RDF::NS";
    $RDF_NS = eval "RDF::NS->new('any')" unless $@;
    # optionally use RDF::Trine::Exporter::GraphViz
    eval "use RDF::Trine::Exporter::GraphViz";
    $GRAPHVIZ = 'RDF::Trine::Exporter::GraphViz' unless $@;
}

use base 'Exporter';
our %EXPORT_TAGS = (
    core => [qw(response document item available unavailable availability)],
    entities => [qw(institution department storage limitation)],
);
our @EXPORT_OK = qw(is_uri parse guess);
Exporter::export_ok_tags;
$EXPORT_TAGS{all} = [@EXPORT_OK, 'message'];
Exporter::export_tags('all');

use Carp; # use Carp::Clan; # qw(^DAIA::);
use IO::File;
use LWP::Simple ();
use XML::LibXML::Simple qw(XMLin);

use DAIA::Response;
use DAIA::Document;
use DAIA::Item;
use DAIA::Availability;
use DAIA::Available;
use DAIA::Unavailable;
use DAIA::Message;
use DAIA::Entity;
use DAIA::Institution;
use DAIA::Department;
use DAIA::Storage;
use DAIA::Limitation;

use Data::Validate::URI qw(is_uri);

=head1 DESCRIPTION

The Document Availability Information API (DAIA) defines a model of information
about the current availability of documents, for instance in a library. DAIA
includes a specification of serializations in JSON, XML, and RDF. More details
can be found in the DAIA specification at L<http://purl.org/NET/DAIA> and at
the developer repository at L<http://daia.sourceforge.net/>.

This package provides Perl classes and functions to easily create and manage
DAIA information in any form. It can be used to quickly implement DAIA servers,
clients, and other programs that handle availability information of documents.

The most important concepts of the DAIA model are:

=over 4

=item B<documents>

These abstract works or editions are implemented as objects of class
L<DAIA::Document>.

=item B<items>

These particular copies of documents (physical or digital) are
implemented as objects of class L<DAIA::Item>.

=item B<services> and C<availability status>

A service is something that can be provided with an item. A particular
service has a particular availability status, that is implemented as
object of class L<DAIA::Available> or L<DAIA::Unavailable>.

=item B<availability status>

A boolean value and a service that indicates I<for what> an item is 
available or not available. Implemented as L<DAIA::Availability> with 
the subclasses L<DAIA::Available> and L<DAIA::Unavailable>.

=item B<responses>

A response contains information about the availability of documents at 
a given point in time, optionally at some specific institution. It is
implemented as object of class L<DAIA::Response>.

=back

Additional L<DAIA objects|/"DAIA OBJECTS"> include B<institutions>
(L<DAIA::Institution>), B<departments> (L<DAIA::Department>), storages
(L<DAIA::Storage>), messages and errors (L<DAIA::Message>).  All these objects
provide standard methods for creation, modification, and serialization. This
package also L<exports functions|/"FUNCTIONS"> as shorthand for object
constructors, for instance the following two result in the same:

  item( id => $id );
  DAIA::Item->new( id => $id );

=head1 SYNOPSIS

This package includes and installs the client program C<daia> to fetch,
validate and convert DAIA data (both command line and CGI). See also the
C<clients> directory for an XML Schema of DAIA/XML and an XSLT script to 
transform DAIA/XML to HTML.

=head2 A DAIA client

  use DAIA;  # or: use DAIA qw(parse);

  $daia = DAIA::parse( $url );
  $daia = DAIA::parse( file => $file );
  $daia = DAIA::parse( data => $string ); # $string must be Unicode

=head2 A DAIA server

See L<Plack:App::DAIA>.

=head1 FUNCTIONS

By default constructor functions are exported for all objects.
To disable exporting, include DAIA like this:

  use DAIA qw();       # do not export any functions
  use DAIA qw(:core);  # only export core functions

You can select two groups, both are exported by default:

=over 4

=item C<:core>

C<response>, C<document>, C<item>, C<available>, C<unavailable>, 
C<availability>

=item C<:entities>

C<institution>, C<department>, C<storage>, C<limitation>

=back

Additional functions is C<message> as object constructor.
The other functions below are not exported by default.
You can call them as method or as function, for instance:

  DAIA->parse_xml( $xml );
  DAIA::parse_xml( $xml );

=cut

sub response     { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Response->new( @_ ) }
sub document     { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Document->new( @_ ) }
sub item         { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Item->new( @_ ) }
sub available    { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Available->new( @_ ) }
sub unavailable  { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Unavailable->new( @_ ) }
sub availability { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Availability->new( @_ ) }
sub message      { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Message->new( @_ ) }
sub institution  { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Institution->new( @_ ) }
sub department   { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Department->new( @_ ) }
sub storage      { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Storage->new( @_ ) }
sub limitation   { local $Carp::CarpLevel = $Carp::CarpLevel + 1; return DAIA::Limitation->new( @_ ) }

=head2 parse ( $from [ %parameters ] )

Parse DAIA/XML or DAIA/JSON from a file or string. You can specify the source
as filename, string, or L<IO::Handle> object as first parameter or with the
named C<from> parameter. Alternatively you can either pass a filename or URL with
parameter C<file> or a string with parameter C<data>. If C<from> or C<file> is an
URL, its content will be fetched via HTTP. The C<format> parameter (C<json> or C<xml>)
is required unless the format can be detected automatically the following way:

=over

=item *

A scalar starting with C<E<lt>> and ending with C<E<gt>> is parsed as DAIA/XML.

=item *

A scalar starting with C<{> and ending with C<}> is parsed as DAIA/JSON.

=item *

A scalar ending with C<.xml> is is parsed as DAIA/XML file.

=item *

A scalar ending with C<.json> is parsed as DAIA/JSON file.

=item *

A scalar starting with C<http://> or C<https://> is used to fetch data via HTTP.
The resulting data is interpreted again as DAIA/XML or DAIA/JSON.

=back

Normally this function or method returns a single DAIA object. When parsing 
DAIA/XML it may also return a list of objects. It is recommended to always
expect a list unless you are absolutely sure that the result of parsing will
be a single DAIA object.

=cut

sub parse {
    shift if UNIVERSAL::isa( $_[0], __PACKAGE__ );
    my ($from, %param) = (@_ % 2) ? (@_) : (undef,@_);
    $from = $param{from} unless defined $from;
    $from = $param{data} unless defined $from;
    my $format = lc( $param{format} || '' );
    my $file = $param{file};
    $file = $from if defined $from and $from =~ /^http(s)?:\/\//;
    if (not defined $file and defined $from and not defined $param{data}) {
        if( ref($from) eq 'GLOB' or UNIVERSAL::isa($from, 'IO::Handle')) {
            $file = $from;
        } elsif( $from eq '-' ) {
            $file = \*STDIN;
        } elsif( $from =~ /\.(xml|json)$/ ) {
            $file = $from ;
            $format = $1 unless $format;
        }
    }
    if ( $file ) {
        if ( $file =~ /^http(s)?:\/\// ) {
            $from = LWP::Simple::get($file) or croak "Failed to fetch $file via HTTP"; 
        } else {
            if ( ! (ref($file) eq 'GLOB' or UNIVERSAL::isa( $file, 'IO::Handle') ) ) {
                $file = do { IO::File->new($file, '<:encoding(UTF-8)') or croak("Failed to open file $file") };
            }
            # Enable :encoding(UTF-8) layer unless it or some other encoding has already been enabled
            # foreach my $layer ( PerlIO::get_layers( $file ) ) {
            #    return if $layer =~ /^encoding|^utf8/;
            #}
            binmode $file, ':encoding(UTF-8)';
            $from = do { local $/; <$file> };
        }
        croak "DAIA serialization is empty" unless $from;
    }

    croak "Missing source to parse from " unless defined $from;

    $format = guess($from) unless $format;

    my $value;
    my @objects;
    my $root = 'Response';

    if ( $format eq 'xml' ) {
        # do not look for filename (security!)
        if (defined $param{data} and guess($from) ne 'xml') {
            croak("XML is not well-formed (<...>)");
        }

        if (guess($from) eq 'xml') {
            utf8::encode($from);;
            #print "IS UTF8?". utf8::is_utf8($from) . "\n";
        }

        my $xml = _parse_daia_xml($from);

        croak $@ if $@;
        croak "XML does not contain DAIA elements" unless $xml;

        while (my ($root,$value) = each(%$xml)) {
            $root =~ s/{[^}]+}//;
            $root = ucfirst($root);
            $root = 'Response' if $root eq 'Daia';

            _filter_xml( $value ); # filter out all non DAIA elements and namespaces

            $value = [ $value ] unless ref($value) eq 'ARRAY';

            foreach my $v (@$value) {
                # TODO: croak of $root is not known!
                my $object = eval 'DAIA::'.$root.'->new( $v )';  ##no critic
                croak $@ if $@;
                push @objects, $object;
            }
        }

    } elsif ( $format eq 'json' ) {
        eval { $value = JSON->new->decode($from); };
        croak $@ if $@;

        if ( (keys %$value) == 1 ) {
            my ($k => $v) = %$value;
            if (not $k =~ /^(timestamp|message|institution|document)$/ and ref($v) eq 'HASH') {
                ($root, $value) = (ucfirst($k), $v);
            }
        }

        # outdated variants
        $root = "Response" if $root eq 'Daia';
        delete $value->{'xmlns:xsi'};

        delete $value->{schema} if $root eq 'Response'; # ignore schema attribute

        croak "JSON does not contain DAIA elements" unless $value;
        push @objects, eval('DAIA::'.$root.'->new( $value )');  ##no critic
        croak $@ if $@;

    } else {
        croak "Unknown DAIA serialization format $format";
    }

    return if not wantarray and @objects > 1;
    return wantarray ? @objects : $objects[0];
}

=head2 parse_xml( $xml )

Parse DAIA/XML from a file or string. The first parameter must be a 
filename, a string of XML, or a L<IO::Handle> object.

Parsing is more lax then the specification so it silently ignores 
elements and attributes in foreign namespaces. Returns either a DAIA 
object or croaks on uncoverable errors.

=cut

sub parse_xml {
    shift if UNIVERSAL::isa( $_[0], __PACKAGE__ );
    DAIA::parse( shift, format => 'xml', @_ );
}

=head2 parse_json( $json )

Parse DAIA/JSON from a file or string. The first parameter must be a 
filename, a string of XML, or a L<IO::Handle> object.

=cut

sub parse_json {
    shift if UNIVERSAL::isa( $_[0], __PACKAGE__ );    
    DAIA::parse( shift, format => 'json' );
}

=head2 guess ( $string )

Guess serialization format (DAIA/JSON or DAIA/XML) and return C<json>, C<xml> 
or the empty string.

=cut

sub guess {
    shift if UNIVERSAL::isa( $_[0], __PACKAGE__ );    
    my $data = shift;
    return '' unless $data;
    return 'xml' if $data =~ m{^\s*\<.*?\>\s*$}s;
    return 'json' if $data =~ m{^\s*\{.*?\}\s*$}s;
    return '';
}

=head2 formats

Return a has with allowed serialization formats and their mime types.

=cut

sub formats {
    shift if UNIVERSAL::isa( $_[0], __PACKAGE__ );
    my %formats = (
        xml  => 'application/xml; charset=utf-8',
        json => 'application/javascript; charset=utf-8',
        rdfjson => 'application/javascript; charset=utf-8',
    );

    if ($TRINE_SERIALIZER) {
        $formats{'rdfxml'} = 'application/rdf+xml; charset=utf-8',;
        $formats{'turtle'} = 'text/turtle; charset=utf-8';
        $formats{'ntriples'} = 'text/plain';
    }
    if ($GRAPHVIZ) {
        $formats{'svg'} = 'image/svg+xml';
        $formats{'dot'} = 'text/plain; charset=utf-8';
    }

    return %formats;
}

=head2 is_uri ( $value )

Checks whether the value is a well-formed URI. This function is imported from
L<Data::Validate::URI> into the namespace of this package as C<DAIA::is_uri>.
On request the function can be exported into the default namespace.

=head1 DAIA OBJECTS

All objects (documents, items, availability status, institutions, departments,
limitations, storages, messages) are implemented as subclass of
L<DAIA::Object>, which is just another Perl meta-class framework.  All objects
have the following methods:

=head2 item

Constructs a new object.

=head2 add

Adds typed properties.

=head2 xml, struct, json, rdfhash

Returns several serialization forms.

=cut

#### internal methods (subject to be changed)

my $NSEXPDAIA    = qr/{http:\/\/(ws.gbv.de|purl.org\/ontology)\/daia\/}(.*)/;

sub _parse_daia_xml {
    my ($from) = @_;
    my $xml = eval { XMLin( $from, KeepRoot => 1, NSExpand => 1, KeyAttr => [ ], NormalizeSpace => 2 ); };
    daia_xml_roots($xml);
}

sub daia_xml_roots {
    my $xml = shift; # hash reference
    my $out = { };

    return { } unless UNIVERSAL::isa($xml,'HASH');

    foreach my $key (keys %$xml) {
        my $value = $xml->{$key};

        if ( $key =~ /^{([^}]*)}(.*)/ and !($key =~ $NSEXPDAIA) ) {
            # non DAIA element
            my $children = UNIVERSAL::isa($value,'ARRAY') ? $value : [ $value ];
            @$children = grep {defined $_} map { daia_xml_roots($_) } @$children;
            foreach my $n (@$children) {
                while ( my ($k,$v) = each(%{$n}) ) {
                    next if $k =~ /^xmlns/;
                    $v = [$v] unless UNIVERSAL::isa($v,'ARRAY');
                    if ($out->{$k}) {
                        push @$v, (UNIVERSAL::isa($out->{$k},'ARRAY') ? 
                                @{$out->{$k}} : $out->{$k});
                    }
                    # filter out scalars
                    @$v = grep {ref($_)} @$v unless $k =~ $NSEXPDAIA;
                    if (@$v) {
                        $out->{$k} = (@$v > 1 ? $v : $v->[0]); 
                    }
                }
            }
        } else { # DAIA element or element without namespace
            $out->{$key} = $value;
        }
    }

    return $out;
}

# filter out non DAIA XML elements, 'xmlns' attributes and empty values
sub _filter_xml { 
    my $xml = shift;
    map { _filter_xml($_) } @$xml if ref($xml) eq 'ARRAY';
    return unless ref($xml) eq 'HASH';

    my (@del,%add);
    foreach my $key (keys %$xml) {
        my $value = $xml->{$key};
        if ($key =~ /^{([^}]*)}(.*)/) {
            my $local = $2;
            if ($1 =~ /^http:\/\/(ws.gbv.de|purl.org\/ontology)\/daia\/$/ and $value ne '') {
                $xml->{$local} = $xml->{$key};
            }
            push @del, $key;
        } elsif ($key =~ /^xmlns/ or $key =~ /:/ or $value eq '') {
            push @del, $key;
        }
    }

    # remove non-daia elements
    foreach (@del) { delete $xml->{$_}; }

    # recurse
    map { _filter_xml($xml->{$_}) } keys %$xml;
}

1;

=encoding utf8
