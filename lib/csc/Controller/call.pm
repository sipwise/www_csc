package csc::Controller::call;

use strict;
use warnings;
use base 'Catalyst::Controller';

use RPC::XML::Client;

=head1 NAME

csc::Controller::call - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays an error.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/notyet.tt';
    $c->stash->{funktion} = 'call';
}

=head2 click2dial

Initiates a call between the subscriber and a foreign party by calling
both of them.

=cut

sub click2dial : Local {
    my ( $self, $c ) = @_;

    my $announce_file = "click2dial";
    my %calldata = ();

    my ($callee_user, $callee_domain);
    my $callee = $c->request->param('d');
    if($callee =~ /^\+?\d+$/)
    {
        if($callee =~ /^0[1-9][0-9]+$/)
        {
            $callee =~ s/^0//;
            $callee = "00" . $c->session->{user}{data}{cc} . $callee;
        }
        elsif($callee =~ /^00[1-9][0-9]+$/)
        {
            # we're fine already
        }
        elsif($callee =~ /^\+[1-9][0-9]+$/)
        {
            $callee =~ s/^\+/00/;
        }
        elsif($callee =~ /^[1-9][0-9]+$/)
        {
            $callee = "00" . $c->session->{user}{data}{cc} . 
            $c->session->{user}{data}{ac} . $callee;
        }
        else
        {
            $c->log->error('***call::click2dial with invalid callee ' . $callee);

            # TODO: Error handling, invalid uri or number
            $c->response->redirect($c->uri_for('/desktop'));
            return;
        }
        $callee_user = $callee;
        $callee_domain = $c->session->{user}{data}{domain};
    }
    else
    {
        $callee =~ s/^sip://;
        $callee =~ s/:\d+(;.+)?//; # strip uri port and params like "sip:foo@bar.com:5060;line=xy"
        ($callee_user, $callee_domain) = $callee =~ /^(.+)@(.+)$/;
        unless(defined $callee_user && defined $callee_domain)
        {
            $c->log->error('***call::click2dial with invalid callee ' . $callee);

            # TODO: Error handling, invalid uri or number
            $c->response->redirect($c->uri_for('/desktop'));
            return;
        }
    }

    $calldata{username} = $c->session->{user}{username};
    $calldata{domain} = $c->session->{user}{domain};
    $calldata{callee_user} = $callee_user;
    $calldata{callee_domain} = $callee_domain;
    $calldata{caller_user} =  $c->session->{user}{data}{username};
    $calldata{caller_domain} = $c->session->{user}{data}{domain};
    $calldata{caller_pass} =  $c->session->{user}{data}{password};
    $calldata{announcement} =  $announce_file;

    return 1 unless $c->model('Provisioning')->call_prov($c, 'voip', 'dial_out',
                                                         \%calldata
                                                        );


    $c->response->redirect($c->request->referer);
    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The call controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
