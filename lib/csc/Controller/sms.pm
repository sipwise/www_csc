package csc::Controller::sms;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::sms - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/notyet.tt';
    $c->stash->{funktion} = 'sms';
}

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

none so far

=head1 COPYRIGHT

The sms controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
