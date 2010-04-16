package DAIA::Department;

=head1 NAME

DAIA::Department - Information about a department in a L<DAIA::Institution>

=cut

use strict;
use base 'DAIA::Entity';
our $VERSION = '0.25';
our %PROPERTIES = %DAIA::Entity::PROPERTIES;

1;

=head1 PROPERTIES AND METHODS

See L<DAIA::Entity> for a desciption of all properties and methods.

=head1 AUTHOR

Jakob Voss C<< <jakob.voss@gbv.de> >>

=head1 LICENSE

Copyright (C) 2009 by Verbundzentrale Goettingen (VZG) and Jakob Voss

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself, either Perl version 5.8.8 or, at
your option, any later version of Perl 5 you may have available.
option, any later version of Perl 5 you may have available.
