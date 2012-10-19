package csc::Controller::call;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

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

    my %calldata = ();

    my ($callee_user, $callee_domain);
    my $callee = $c->request->param('d');
    if($callee =~ /^\+?\d+$/)
    {
        $callee = csc::Utils::get_qualified_number_for_subscriber($c, $callee);
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', { e164number => $callee }, \$checkresult);
        unless($checkresult) {
            $c->log->error('***call::click2dial with invalid callee ' . $callee);

            # TODO: Error handling, invalid uri or number
            $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
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
            $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
            return;
        }
    }

    $calldata{callee_user} = $callee_user;
    $calldata{callee_domain} = $callee_domain;
    $calldata{username} =  $c->session->{user}{data}{username};
    $calldata{domain} = $c->session->{user}{data}{domain};
    $calldata{password} =  $c->session->{user}{data}{password};

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

The call controller is Copyright (c) 2007-2012 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

1;
