package csc::View::Binary;

use strict;

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

The Binary view is Copyright (c) 2007 Sipwise GmbH, Austria. All rights
reserved.

=cut

# over and out
1;
