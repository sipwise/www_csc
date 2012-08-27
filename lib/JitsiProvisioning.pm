package Sipwise::JitsiProvisioning;

use strict;
use warnings;
  
use Apache2::Request;
use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::Const;
use XML::Simple;

my $cfg_file = '/etc/ngcp-www-csc/csc.conf';

my $cfg = XML::Simple->new()->XMLin($cfg_file)
	or die "Failed to read config file '$cfg_file'";

sub handler {
	my $r = shift;
	my $req = Apache2::Request->new($r);
	$r->content_type('text/plain');

	my $uri = $req->param("user") || '';
	my ($user, $domain) = split /\@/, $uri;
	my $pass = $req->param("pass");
	my $uuid = $req->param("uuid");

	unless(defined $user && defined $domain && defined $pass && defined $uuid) {
		$r->custom_response(Apache2::Const::NOT_FOUND, "invalid credentials");
		return Apache2::Const::NOT_FOUND;
	}

	my $acc = 'accngcp'.$uuid.$user.$domain;
	$acc =~ s/[^a-zA-Z0-9]//g;
	my $server_ip = $cfg->{uaprovisioning}->{sip}->{host};
	my $server_port;
	my $server_proto;
	if($cfg->{uaprovisioning}->{sip}->{tls_enabled} eq 'yes') {
		$server_port = $cfg->{uaprovisioning}->{sip}->{tls_port};
		$server_proto = 'TLS';
	} else {
		$server_port = $cfg->{uaprovisioning}->{sip}->{plain_port};
		$server_proto = 'UDP';
	}
	my $xcap_proto = $cfg->{uaprovisioning}->{xcap}->{proto};
	my $xcap_ip = $cfg->{uaprovisioning}->{xcap}->{host};
	my $xcap_port = $cfg->{uaprovisioning}->{xcap}->{port};

	my $config = <<"EOF";
net.java.sip.communicator.impl.protocol.sip.$acc=$acc
net.java.sip.communicator.impl.protocol.sip.$acc.ACCOUNT_UID=SIP\:$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$acc.PROTOCOL_NAME=SIP
net.java.sip.communicator.impl.protocol.sip.$acc.IS_ACCOUNT_DISABLED=false

net.java.sip.communicator.impl.protocol.sip.$acc.USER_ID=$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$acc.PASSWORD=$pass
net.java.sip.communicator.impl.protocol.sip.$acc.DISPLAY_NAME=
net.java.sip.communicator.impl.protocol.sip.$acc.SERVER_ADDRESS=$domain

net.java.sip.communicator.impl.protocol.sip.$acc.PROXY_AUTO_CONFIG=false
net.java.sip.communicator.impl.protocol.sip.$acc.PROXY_ADDRESS=$server_ip
net.java.sip.communicator.impl.protocol.sip.$acc.PROXY_PORT=$server_port
net.java.sip.communicator.impl.protocol.sip.$acc.PREFERRED_TRANSPORT=$server_proto

net.java.sip.communicator.impl.protocol.sip.$acc.VOICEMAIL_CHECK_URI=sip\:voicebox\@$domain
net.java.sip.communicator.impl.protocol.sip.$acc.VOICEMAIL_URI=

net.java.sip.communicator.impl.protocol.sip.$acc.FORCE_P2P_MODE=false
net.java.sip.communicator.impl.protocol.sip.$acc.IS_PRESENCE_ENABLED=true
net.java.sip.communicator.impl.protocol.sip.$acc.XCAP_ENABLE=true
net.java.sip.communicator.impl.protocol.sip.$acc.XCAP_SERVER_URI=$xcap_proto\://$xcap_ip\:$xcap_port/xcap
net.java.sip.communicator.impl.protocol.sip.$acc.XCAP_USE_SIP_CREDETIALS=true
net.java.sip.communicator.impl.protocol.sip.$acc.SUBSCRIPTION_EXPIRATION=3600

net.java.sip.communicator.impl.protocol.sip.$acc.KEEP_ALIVE_INTERVAL=25
net.java.sip.communicator.impl.protocol.sip.$acc.KEEP_ALIVE_METHOD=OPTIONS

net.java.sip.communicator.impl.protocol.sip.$acc.DTMF_METHOD=AUTO_DTMF
net.java.sip.communicator.impl.protocol.sip.$acc.DEFAULT_ENCRYPTION=true
net.java.sip.communicator.impl.protocol.sip.$acc.DEFAULT_SIPZRTP_ATTRIBUTE=true
net.java.sip.communicator.impl.protocol.sip.$acc.POLLING_PERIOD=30
net.java.sip.communicator.impl.protocol.sip.$acc.SAVP_OPTION=0
net.java.sip.communicator.impl.protocol.sip.$acc.SDES_ENABLED=false
net.java.sip.communicator.impl.protocol.sip.$acc.ACCOUNT_ICON_PATH=resources/images/protocol/sip/sip32x32.png
net.java.sip.communicator.impl.protocol.sip.$acc.XIVO_ENABLE=false

EOF
	
	$r->print($config);
	return Apache2::Const::OK;
}

1;

