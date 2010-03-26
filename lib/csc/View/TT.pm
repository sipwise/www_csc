package csc::View::TT;

use strict;
use base 'Catalyst::View::TT';

## __PACKAGE__->config(TEMPLATE_EXTENSION => '.tt');
__PACKAGE__->config(
    INCLUDE_PATH => [
        csc->path_to( 'root' ),
#        csc->path_to( 'root', 'src' ),
    ],
    PRE_PROCESS  => 'config/main',
    WRAPPER      => 'layout/wrapper',
    ERROR        => 'tt/error.tt',
#    TEMPLATE_EXTENSION => '.tt',
    CATALYST_VAR => 'Catalyst',
    ENCODING     => 'utf-8',
);

=head1 NAME

csc::View::TT - TT View for csc

=head1 DESCRIPTION

TT View for csc. 

=head1 BUGS AND LIMITATIONS

=over

=item none.

=back

=head1 SEE ALSO

Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The TT view is Copyright (c) 2007 Sipwise GmbH, Austria. All rights
reserved.

=cut

# over and out
1;
