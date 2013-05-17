package Sipwise::JitsiRedirect;

# This is a package meant to be run on some central place where
# Jitsi is hardcodedly configured to get its provisioning from.
# The package redirects Jitsi to the domain identified by the
# domain part of the username, using a 302 redirect.
# 
# Install this script in /usr/share/perl5/Sipwise/.
#
# Place a configuration like this (for Apache) into the
# server running this script (assuming that Jitsi is configured to
# contact "https://server/jitsiprov?..."):
#
#
#        <Location /jitsiprov>
#               SetEnv no-gzip 1
#               SetHandler perl-script
#               PerlResponseHandler Sipwise::JitsiRedirect
#               Allow from all
#       </Location>


use strict;
use warnings;

use Apache2::Request;
use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::Const;
use XML::Simple;
use Net::DNS;
use Data::Validate::IP qw(is_ipv4 is_ipv6);

use Log::Log4perl;
Log::Log4perl::init('/etc/ngcp-ossbss/logging.conf');
my $log = Log::Log4perl->get_logger('csc');
$log->info('jitsiredir starting up');

my $cfg_file = '/etc/ngcp-www-csc/csc.conf';

my $cfg = XML::Simple->new()->XMLin($cfg_file)
	or die "Failed to read config file '$cfg_file'";

my $res = Net::DNS::Resolver->new;
my $srv_prefix = '_sip._udp.';

sub handler {
	my $r = shift;
	my $req = Apache2::Request->new($r);
	$r->content_type('text/plain');

	$log->info('jitsiprov got request with params user=' . $req->param("user") . ' and pass=' . $req->param("pass") . ' and uuid=' . $req->param("uuid"));
	my $uri = $req->param("user") || '';
	my ($user, $domain) = split /\@/, $uri;
	my $pass = $req->param("pass");
	my $uuid = $req->param("uuid");

	unless(defined $user && defined $domain && defined $pass && defined $uuid) {
		$log->error("jitsiredir invalid credentials for user='$user', domain='$domain', pass='$pass', uuid='$uuid'");
		$r->custom_response(Apache2::Const::NOT_FOUND, "invalid credentials");
		return Apache2::Const::NOT_FOUND;
	}
	my $dnsdomain = $domain;
	$dnsdomain =~ s/^\[//; $dnsdomain =~ s/\]$//g;
	$log->info("jitsiredir generating config for user='$user', dnsdomain='$dnsdomain', pass='$pass', uuid='$uuid'");

	my $provserver;
	my @hosts;
	if(is_ipv4($dnsdomain) || is_ipv6($dnsdomain)) {
		$provserver = $dnsdomain;
	} else {
		my $srv = $res->query($srv_prefix.$dnsdomain, 'SRV');
		unless(defined $srv) {
		if($res->errorstring eq 'NOERROR' || $res->errorstring eq 'NXDOMAIN') {
			push @hosts, new Net::DNS::RR(
				name => $dnsdomain,
				type => 'SRV',
				priority => 10,
				weight => 10,
				port => 443,
				target => $dnsdomain);
			} else {
				$log->error("Failed to resolve '$dnsdomain' for SRV: ". $res->errorstring);
				$r->custom_response(Apache2::Const::NOT_FOUND, "invalid domain");
				return Apache2::Const::NOT_FOUND;
			}
		} else {
			@hosts = $srv->answer;
		}

		@hosts = sort { $a->priority <=> $b->priority || $a->weight <=> $b->weight } @hosts;
	}

	unless($provserver) {
		unless(@hosts) {
			$r->custom_response(Apache2::Const::NOT_FOUND, "invalid domain");
			return Apache2::Const::NOT_FOUND;
		}
		$provserver = $hosts[0]->target;
	}
	if(is_ipv6($provserver)) {
		$provserver= "[$provserver]";
	}
	
	$log->info("redirecting user '$user\@$domain' to provserver '$provserver'");
	$r->headers_out->set('Location' => "https://$provserver/jitsi?user=$user\@$domain&pass=$pass&uuid=$uuid");
	return Apache2::Const::REDIRECT;
}

1;

