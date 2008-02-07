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

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->logout;
    $c->response->redirect('http://'.$c->config->{www_server}.'/');
}


=head1 BUGS AND LIMITATIONS

=over

=item - syntax checks should be improved.

=item - logging should be improved.

=item - error handling should be improved.

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Logout controller is Copyright (c) 2007 Sipwise GmbH,
Austria. All rights reserved.

=cut

# over and out
1;
