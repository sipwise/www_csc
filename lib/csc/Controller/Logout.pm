package csc::Controller::Logout;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::Logout - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Clears an authentication session.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->logout;
    $c->response->redirect('/');
}


=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Logout controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
