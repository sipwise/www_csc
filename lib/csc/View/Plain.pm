package csc::View::Plain;

use strict;

=head1 NAME

csc::View::Plain - TT View for plain text

=head1 DESCRIPTION

Plain View for csc. It will output plain data with the corresponding
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
Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The Plain view is Copyright (c) 2007-2010 Sipwise GmbH, Austria. You
should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
