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

This runs for every request and checks the authentication session.

=cut

# this is called once for every request unless overidden by a
# more specific "begin" in our Controllers
sub begin : Private {
    my ( $self, $c ) = @_;

    $c->response->headers->push_header( 'Vary' => 'Accept-Language' );  # hmm vary and param?

    # set default language
    $c->session->{lang} = $c->config->{site_config}{default_language} unless $c->session->{lang};

    if(defined $c->request->params->{lang} and $c->request->params->{lang} =~ /^\w+$/) {
        $c->languages([$c->request->params->{lang}]);
        if($c->language eq 'i_default') {
            $c->languages([$c->session->{lang}]);
        } else {
            $c->session->{lang} = $c->language;
        }
    } else {
        $c->languages([$c->session->{lang}]);
    }

    $c->log->debug('***csc::begin final language: '. $c->language);

    return;
}

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

=head2 default

This runs if no action is found for a request and redirects to the
server's document root.

=cut

sub default : Private {
    my ( $self, $c ) = @_;

    $c->log->debug("***Root::default path is: ". $c->req->path);

    if($c->req->path =~ /\.html$/
       and -e $c->config->{home} . '/root/' . $c->req->path)
    {
        $c->stash->{template} = $c->req->path;
    } else {
        if('/'.$c->req->path eq $c->config->{site_config}{default_uri}) {
            $c->log->error("***Root::default invalid default_uri setting in csc.conf");
        } else {
            $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
        }
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
            $c->stash->{messages} = $c->model('Provisioning')->localize($c, $c->session->{messages});
            delete $c->session->{messages};
        }
    }

    $c->stash->{subscriber}{username} = $c->session->{user}{username};
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

The Root controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
