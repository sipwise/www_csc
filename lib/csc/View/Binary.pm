package csc::View::Binary;

use strict;
use base 'Catalyst::View';

=head1 NAME

csc::View::Binary - TT View for binary data

=head1 DESCRIPTION

Binary View for csc. It will output binary data with the corresponding
content-type header set.

=cut

sub new {
    return bless {}, shift;
}

sub process {
    my ( $self, $c ) = @_;

    $c->response->content_type($c->stash->{content_type});
    $c->response->body($c->stash->{content});

    return 1;
}

=head1 BUGS AND LIMITATIONS

=over

=item none I know.

=back

=head1 SEE ALSO

Catalyst, csc

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Binary view is Copyright (c) 2007-2010 Sipwise GmbH, Austria. You
should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
