package csc::Controller::Root;

use strict;
use warnings;
use base 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

csc::Controller::Root - Root Controller for csc

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 default

=cut

# Note that 'auto' runs after 'begin' but before your actions and that
# 'auto' "chain" (all from application path to most specific class are run)
sub auto : Private {
    my ($self, $c) = @_;

    $c->log->debug('***Root::auto called');

    # set default template to avoid error screens
    $c->stash->{template} = 'tt/error.tt';

    $c->log->debug('***Root::auto controller is: '. $c->controller);

    # Allow unauthenticated users to reach the front page and login.
    if ($c->controller =~ /^csc::Controller::Login\b/
        or $c->controller =~ /^csc::Controller::autoconf\b/
        or $c->controller =~ /^csc::Controller::payment\b/)
    {
        $c->log->debug('***Root::auto login access granted.');
        return 1;
    }

    # If a user doesn't exist, force login
    if (!$c->user_exists) {
        $c->log->debug('***Root::auto User not found, forwarding to /login');
        $c->response->redirect($c->uri_for('/login'));
        return 0;
    }

    return 1;
}

sub default : Private {
    my ( $self, $c ) = @_;

    $c->log->debug("***Root::default path is: ". $c->req->path);
    if($c->req->path =~ m#/#) {
        $c->response->redirect($c->uri_for('/'));
    }

    if($c->req->path =~ /\.html$/) {
        $c->stash->{template} = $c->req->path;
    } else {
        $c->stash->{template} = 'index.html';
    }
}

=head2 end

Attempt to render a view, if needed.

=cut 

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;
    # set default View to CSC
    $c->stash->{current_view} = 'TT';

    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->session->{messages}{prov_error} = $c->session->{prov_error};
            delete $c->session->{prov_error};
        }

        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c->session->{messages});
            delete $c->session->{messages};
        }
    }

    $c->stash->{subscriber}{username} = $c->session->{user}{username};
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

The Root controller is Copyright (c) 2007 Sipwise GmbH,
Austria. All rights reserved.

=cut

# over and out
1;
