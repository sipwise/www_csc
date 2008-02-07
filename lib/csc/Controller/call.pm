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

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->stash->{template} = 'tt/notyet.tt';
    $c->stash->{funktion} = 'call';
}

sub click2dial : Local {
    my ( $self, $c ) = @_;

	my ($callee_user, $callee_domain);
	my ($caller_user, $caller_domain, $caller_pass);

	my $proxy = "192.168.101.162";
	my $xmlrpc_url = "http://192.168.102.162:8090";
	my $announce_file = "click2dial";

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

        ## dtiefnig 08.01.2008 - should use SIP user and pass, shouldn't it?
        ## $c->session->{user}{username} now is webusername!
	# $caller_user =  $c->session->{user}{username};
	# $caller_domain = $c->session->{user}{domain};
	# $caller_pass =  $c->session->{user}{password};
	$caller_user =  $c->session->{user}{data}{username};
	$caller_domain = $c->session->{user}{data}{domain};
	$caller_pass =  $c->session->{user}{data}{password};
	
	$c->log->error('***call::click2dial with caller ' . $caller_user . ':' . $caller_pass . '@' . $caller_domain);
	$c->log->error('***call::click2dial with callee ' . $callee_user . '@' . $callee_domain);

	my $cli = RPC::XML::Client->new($xmlrpc_url);
	my $resp = $cli->send_request('dial_auth_b2b', 'click2dial', $announce_file,
		'sip:'.$caller_user.'@'.$caller_domain,
		'sip:'.$callee_user.'@'.$callee_domain,
		'sip:'.$caller_user.'@'.$proxy.';sw_domain='.$caller_domain,
		'sip:'.$callee_user.'@'.$proxy.';sw_domain='.$callee_domain,
		$caller_domain, $caller_user, $caller_pass);
	
	# TODO: Error handling, check if XMLRPC was successful, and if not, try antoher proxy?
	
	$c->response->redirect($c->request->referer);
	return;
}

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

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
