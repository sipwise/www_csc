package Sipwise::JitsiProvisioning;

use strict;
use warnings;
  
use Apache2::Request;
use Apache2::RequestRec;
use Apache2::RequestIO;
use Apache2::Const;
use XML::Simple;

use Log::Log4perl;
Log::Log4perl::init('/etc/ngcp-panel/logging.conf');
my $log = Log::Log4perl->get_logger('csc');
$log->info('jitsiprov starting up');

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
		$log->error("jitsiprov invalid credentials for user='$user', domain='$domain', pass='$pass', uuid='$uuid'");
		$r->custom_response(Apache2::Const::NOT_FOUND, "invalid credentials");
		return Apache2::Const::NOT_FOUND;
	}
	$log->info("jitsiprov generating config for user='$user', domain='$domain', uuid='$uuid'");

	my $sipacc = 'accsipngcp'.$user.$domain;
	my $xmppacc = 'accxmppngcp'.$user.$domain;
	$sipacc =~ s/[^a-zA-Z0-9]//g;
	$xmppacc =~ s/[^a-zA-Z0-9]//g;
	my $provserver = $r->hostname;
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
	my $xcap_ip = $domain;
	my $xcap_port = $cfg->{uaprovisioning}->{xcap}->{port};

	$log->info("jitsiprov gathered required information, sipacc=$sipacc, xmppacc=$xmppacc");

	my $config = <<"EOF";
net.java.sip.communicator.plugin.provisioning.URL=https\://$provserver/jitsi?user\=\${username}&pass\=\${password}&uuid\=\${uuid}
net.java.sip.communicator.impl.protocol.sip.$sipacc=$sipacc
net.java.sip.communicator.impl.protocol.sip.$sipacc.ACCOUNT_UID=SIP\:$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.DEFAULT_ENCRYPTION=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.DEFAULT_SIPZRTP_ATTRIBUTE=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.DTMF_METHOD=AUTO_DTMF
net.java.sip.communicator.impl.protocol.sip.$sipacc.DTMF_MINIMAL_TONE_DURATION=70
net.java.sip.communicator.impl.protocol.sip.$sipacc.PASSWORD=$pass
net.java.sip.communicator.impl.protocol.sip.$sipacc.ENCRYPTION_PROTOCOL.ENCRYPTION_PROTOCOL.ZRTP=0
net.java.sip.communicator.impl.protocol.sip.$sipacc.ENCRYPTION_PROTOCOL_STATUS.ENCRYPTION_PROTOCOL_STATUS.ZRTP=true
net.java.sip.communicator.impl.protocol.sip.$sipacc.FORCE_P2P_MODE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.VOICEMAIL_CHECK_URI=sip\:voicebox\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.VOICEMAIL_URI=
net.java.sip.communicator.impl.protocol.sip.$sipacc.IS_PRESENCE_ENABLED=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.KEEP_ALIVE_INTERVAL=25
net.java.sip.communicator.impl.protocol.sip.$sipacc.KEEP_ALIVE_METHOD=OPTIONS
net.java.sip.communicator.impl.protocol.sip.$sipacc.OVERRIDE_ENCODINGS=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.POLLING_PERIOD=30
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROTOCOL_NAME=SIP
net.java.sip.communicator.impl.protocol.sip.$sipacc.SAVP_OPTION=0
net.java.sip.communicator.impl.protocol.sip.$sipacc.SERVER_ADDRESS=$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_AUTO_CONFIG=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_ADDRESS=$server_ip
net.java.sip.communicator.impl.protocol.sip.$sipacc.PROXY_PORT=$server_port
net.java.sip.communicator.impl.protocol.sip.$sipacc.PREFERRED_TRANSPORT=$server_proto
net.java.sip.communicator.impl.protocol.sip.$sipacc.SUBSCRIPTION_EXPIRATION=3600
net.java.sip.communicator.impl.protocol.sip.$sipacc.USER_ID=$user\@$domain
net.java.sip.communicator.impl.protocol.sip.$sipacc.XCAP_ENABLE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.XIVO_ENABLE=false
net.java.sip.communicator.impl.protocol.sip.$sipacc.cusax.XMPP_ACCOUNT_ID=$xmppacc
net.java.sip.communicator.impl.protocol.jabber.$xmppacc=$xmppacc
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ACCOUNT_UID=Jabber\:$user\@$domain\@$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ALLOW_NON_SECURE=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_DISCOVER_JINGLE_NODES=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_DISCOVER_STUN=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.AUTO_GENERATE_RESOURCE=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.BYPASS_GTALK_CAPABILITIES=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.CALLING_DISABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DEFAULT_ENCRYPTION=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DEFAULT_SIPZRTP_ATTRIBUTE=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DTMF_METHOD=AUTO_DTMF
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.DTMF_MINIMAL_TONE_DURATION=70
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.PASSWORD=$pass
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL.SDES=1
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL.ZRTP=0
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL_STATUS.SDES=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ENCRYPTION_PROTOCOL_STATUS.ZRTP=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GMAIL_NOTIFICATIONS_ENABLED=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GOOGLE_CONTACTS_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.GTALK_ICE_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.ICE_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.IS_PREFERRED_PROTOCOL=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.IS_SERVER_OVERRIDDEN=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.JINGLE_NODES_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.OVERRIDE_ENCODINGS=false
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.OVERRIDE_PHONE_SUFFIX=
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.PROTOCOL_NAME=Jabber
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.RESOURCE=sipwise
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.RESOURCE_PRIORITY=30
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SDES_CIPHER_SUITES=AES_CM_128_HMAC_SHA1_80,AES_CM_128_HMAC_SHA1_32
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SERVER_ADDRESS=$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.SERVER_PORT=5222
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.TELEPHONY_BYPASS_GTALK_CAPS=
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.UPNP_ENABLED=true
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.USER_ID=$user\@$domain
net.java.sip.communicator.impl.protocol.jabber.$xmppacc.USE_DEFAULT_STUN_SERVER=true
EOF

	$r->print($config);
	return Apache2::Const::OK;
}

1;

