package csc::Controller::Login;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::Login - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays a login form.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***Login::index called');

    $c->stash->{template} = 'tt/login.tt';
}

=head2 do_login 

Verifies username and password.

=cut

sub do_login : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***Login::do_login called');

    my $username = $c->request->params->{benutzer} || "";
    my $password = $c->request->params->{passwort} || "";
    # strip leading/trailing whitespaces
    $username =~ s/^\s+//;
    $username =~ s/\s+$//;

    $c->log->debug('***Login::do_login username: >>'. $username .'<< password: >>'. $password .'<<');

    if(defined $c->session->{fake_auth} and ref $c->session->{fake_auth} eq 'HASH' and !$username) {
        $username = $c->session->{fake_auth}{username};
        $password = $c->session->{fake_auth}{password};
        delete $c->session->{fake_auth};
        $c->log->debug('***Login::do_login AUTO LOGIN: username: >>'. $username .'<< password: >>'. $password .'<<');
    }

    if ($username && $password) {
#        if ($c->login($username, $password)) {
        $username .= '@'. $c->config->{site_domain} if $username !~ /\@/;
        if($c->model('Provisioning')->login($c, $username, $password)) {
            $c->log->debug('***Login::do_login login successfull, redirecting to default URI');
            $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
            return;
        }
    } else {
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingPass'
            unless $password;
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingUsername'
            unless $username;
    }
    $c->response->redirect($c->uri_for('/login'));
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    $c->stash->{current_view} = 'Frontpage';

    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->session->{messages}{prov_error} = $c->session->{prov_error};
            delete $c->session->{prov_error};
        }
        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c, $c->session->{messages});
            delete $c->session->{messages};
        }
    }
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

The Login controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
