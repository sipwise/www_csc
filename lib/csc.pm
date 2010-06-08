package csc;

use strict;
use warnings;

use Catalyst::Runtime '5.70';
use XML::Simple;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root 
#                 directory

use Catalyst::Log::Log4perl;

use Catalyst qw/-Debug ConfigLoader Static::Simple Unicode I18N
                Authentication Authentication::Store::Minimal Authentication::Credential::Password
                Session Session::Store::FastMmap Session::State::Cookie
               /;

our $VERSION = '2';

# Configure the application. 
#
# Note that settings in csc.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

# load configuration from admin.conf XML
my $xs = new XML::Simple;
my $xc = $xs->XMLin( '/usr/local/etc/csc.conf', ForceArray => 0);
$$xc{site_config}{default_language} = 'en' unless $$xc{site_config}{default_language} =~ /^\w+$/;

__PACKAGE__->config( authentication => {}, %$xc );

if(__PACKAGE__->config->{log4perlconf}) {
  __PACKAGE__->log( Catalyst::Log::Log4perl->new(
      __PACKAGE__->config->{log4perlconf}
  ));
}

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


# Start the application
__PACKAGE__->setup;


=head1 NAME

csc - Catalyst based application

=head1 DESCRIPTION

The core module of the csc framework.

=head1 BUGS AND LIMITATIONS

=over

=item none so far

=back

=head1 SEE ALSO

L<csc::Controller::Root>, L<Catalyst>

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The csc module is Copyright (c) 2007-2010 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
