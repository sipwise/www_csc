package csc::Controller::device;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

use Data::Dumper;

my $sync_url = 'http://autoconf.libratel.eu/autoconf/init';

=head1 NAME

csc::Controller::device - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Local
{
    my ( $self, $c, $preferences) = @_;

	$c->session->{dev} = undef;
	my $ext = $c->session->{user}{data}{cc} . 
		$c->session->{user}{data}{ac} . $c->session->{user}{data}{sn};
   
	$c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
					{ username => $c->session->{user}{username},
					  domain => $c->session->{user}{domain},
					  ext => $ext}, \$c->session->{dev}{spa});

	$c->session->{dev}{spa}{active} = 1;
	
	$c->stash->{dev} = $c->session->{dev};

#print Dumper $c->session->{dev};

	$self->spa($c);
}

sub spa : Local 
{
    my ( $self, $c, $preferences) = @_;

    $c->log->debug('***device::spa called');
    $c->stash->{template} = 'tt/device.tt';
    my %messages = ();
	
	$c->stash->{dev} = $c->session->{dev};

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

	# set marker, which phone is going to be configured next (-1 = none)	
	$c->session->{dev}{currentphone} = -1;

	# set stash in case we bail out early
	$c->stash->{dev} = $c->session->{dev};
	
	$c->session->{dev}{spa}{mac} =~ s/^(..)(..)(..)(..)(..)(..)$/$1:$2:$3:$4:$5:$6/g
			if(defined $c->session->{dev}{spa}{mac});
	if(defined $c->session->{dev}{spa}{children})
	{
		my $pref = $c->session->{dev}{spa}{children};
		foreach my $p(@$pref)
		{
			$p->{mac} =~ s/^(..)(..)(..)(..)(..)(..)$/$1:$2:$3:$4:$5:$6/g
					if(defined $p->{mac});
		}
	}

	if(defined $c->stash->{subscriber}{autoconf} &&
					$c->stash->{subscriber}{autoconf}{autoconf} == 1 &&
					$c->stash->{subscriber}{autoconf}{device}{model} eq 'SPA9000')
	{
			my $mac = $c->stash->{subscriber}{autoconf}{unit}{mac};
			$mac =~ s/(\d{2})/$1:/g;
			$mac =~ s/:$//g;
			$c->session->{dev}{spa}{mac} = $mac;
			
			$c->session->{dev}{spa}{ip} = $c->stash->{subscriber}{autoconf}{unit}{ip};
	}

	# fetch ip, mac, groups and extensions

	elsif($c->request->params->{savespa} || 
		$c->request->params->{addgrp} || 
		$c->request->params->{delgrp} || 
		$c->request->params->{addext} || 
		$c->request->params->{delext})
	{
		return unless($self->_check_mac($c, \%messages));
	    $c->session->{dev}{spa}{mac} = $c->request->params->{mac};
    	$c->log->debug('***device::spa mac='.$c->session->{dev}{spa}{mac});

		return unless($self->_check_ip($c, \%messages));
	    $c->session->{dev}{spa}{ip} = $c->request->params->{ip};
    	$c->log->debug('***device::spa ip='.$c->session->{dev}{spa}{ip});

		return unless $self->_process_fxs1($c);
		return unless $self->_process_fxs2($c);

		if($c->request->params->{addgrp})
		{
				my $grp = $c->request->params->{group} || '';
				unless($grp =~ /^\d+$/)
				{
						$messages{toperr} = 'Client.Voip.InputErrorFound';
						$c->session->{messages} = \%messages;
						$c->log->debug('***device::spa has invalid group '.$grp);
						return;
				}
				return unless($self->_check_uniqueness($c, $grp, \%messages));

				if(defined $c->session->{dev}{spa}{groups})
				{
					my $gref = $c->session->{dev}{spa}{groups};
					push @$gref, { ext => int($grp) };
					$c->session->{dev}{spa}{groups} = $gref;
				}
				else
				{
						my @g = ();
						push @g, { ext => int($grp) };
						$c->session->{dev}{spa}{groups} = \@g;
				}
		}
		elsif($c->request->params->{delgrp})
		{
				my $grp = $c->request->params->{delgrp} || '';
				unless($grp =~ /^\d+$/)
				{
						$messages{toperr} = 'Client.Voip.InputErrorFound';
						$c->session->{messages} = \%messages;
						$c->log->debug('***device::spa has invalid deletion group '.$grp);
				}
				else
				{
					$self->_load_phone_subscribers($c);

					# first delete phones in this group, then group itself
			
					if(defined $c->session->{dev}{spa}{fxs1}{group} && 
							$c->session->{dev}{spa}{fxs1}{group} == int($grp))
					{
						$self->_process_fxs1($c, 1);
					}
					if(defined $c->session->{dev}{spa}{fxs2}{group} && 
							$c->session->{dev}{spa}{fxs2}{group} == int($grp))
					{
						$self->_process_fxs2($c, 1);
					}
					
					my @tmp1 = ();
					my @tmp1del = ();
					if(defined $c->session->{dev}{spa}{children})
					{
						my $pref = $c->session->{dev}{spa}{children};
						foreach my $p(@$pref)
						{
							unless($p->{group} == int($grp))
							{
								push @tmp1, $p;
							}
							else
							{
								push @tmp1del, $p;
							}
						}
						foreach my $delphone(@tmp1del)
						{
							if(defined $delphone->{subscriber})
							{
								$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
												{ id => $c->session->{user}{account_id},
												  username => $delphone->{subscriber}{username},
												  domain => $delphone->{subscriber}{domain}}, 
												  undef);
							}
							$c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_unit', 
											{ username => $c->session->{user}{username},
											  domain   => $c->session->{user}{domain},
											  ext => $delphone->{ext}}, undef);

						}

						$c->session->{dev}{spa}{children} = \@tmp1;
					}

					my @tmp2 = ();
					my $gref = $c->session->{dev}{spa}{groups};
					foreach my $g(@$gref)
					{
							unless($g->{ext} == int($grp))
							{
								push @tmp2, $g 
							}
							else
							{
								$c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_group', 
											{ username => $c->session->{user}{username},
											  domain   => $c->session->{user}{domain},
											  group_id => $g->{id}}, undef);
							}
					}
					$c->session->{dev}{spa}{groups} = \@tmp2;
				}
		}
		if($c->request->params->{addext})
		{
				my $ext = $c->request->params->{ext} || '';
				unless($ext =~ /^\d+$/)
				{
						$messages{toperr} = 'Client.Voip.InputErrorFound';
						$c->session->{messages} = \%messages;
						$c->log->debug('***device::spa has invalid ext '.$ext);
						return;
				}
				return unless($self->_check_uniqueness($c, $ext, \%messages));
				my $grp = $c->request->params->{grp} || '';
				if(length($grp) > 0 && ! $grp =~ /^\d+$/)
				{
						$messages{toperr} = 'Client.Voip.InputErrorFound';
						$c->session->{messages} = \%messages;
						$c->log->debug('***device::spa has invalid ext grp '.$grp);
						return;
				}

				if(defined $c->session->{dev}{spa}{children})
				{
					my $pref = $c->session->{dev}{spa}{children};
					if(length($grp) > 0)
					{
						push @$pref, { ext => int($ext), group => int($grp) };
					}
					else
					{
						push @$pref, { ext => int($ext) };
					}
					$c->session->{dev}{spa}{children} = $pref;
				}
				else
				{
						my @p = ();
						if(length($grp) > 0)
						{
							push @p, { ext => int($ext), group => int($grp) };
						}
						else
						{
							push @p, { ext => int($ext) };
						}
						$c->session->{dev}{spa}{children} = \@p;
				}
		}
		elsif($c->request->params->{delext})
		{
				my $ext = $c->request->params->{delext} || '';
				unless($ext =~ /^\d+$/)
				{
						$messages{toperr} = 'Client.Voip.InputErrorFound';
						$c->session->{messages} = \%messages;
						$c->log->debug('***device::spa has invalid deletion ext '.$ext);
				}
				else
				{
					my @tmp2 = ();
					$self->_load_phone_subscribers($c);
					my $pref = $c->session->{dev}{spa}{children};
					my $delphone;
					foreach my $p(@$pref)
					{
							unless($p->{ext} eq $ext)
							{
								push @tmp2, $p;
							}
							else
							{
								$delphone = $p;
							}
					}
					$c->session->{dev}{spa}{children} = \@tmp2;
					if(defined $delphone->{subscriber})
					{
						$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
										{ id => $c->session->{user}{account_id},
										  username => $delphone->{subscriber}{username},
										  domain => $delphone->{subscriber}{domain}}, 
										  undef);
					}
					$c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_unit', 
									{ username => $c->session->{user}{username},
									  domain   => $c->session->{user}{domain},
									  ext => $ext}, undef);
				}
		}
		elsif($c->request->params->{savespa})
		{
			my $model = '';

			unless(defined $c->session->{dev}{spa}{device_id})
			{
				my $dev;
				$c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_device_by_vendormodel', 
								{ username => $c->session->{user}{username},
								  domain   => $c->session->{user}{domain},
								  vendor => 'Linksys', model => 'SPA9000'},
								  \$dev);
				$c->session->{dev}{spa}{device_id} = $dev->{id};
			}
			$c->session->{dev}{spa}{ext} = $c->session->{user}{data}{cc} . 
					$c->session->{user}{data}{ac} . $c->session->{user}{data}{sn};

			$c->model('Provisioning')->call_prov($c, 'voip', 'save_autoconf_unit', 
							{ username => $c->session->{user}{username},
							  domain   => $c->session->{user}{domain},
							  unit => $c->session->{dev}{spa}},
							  \$c->session->{dev}{spa});

			$c->session->{dev}{spa}{mac} =~ s/^(..)(..)(..)(..)(..)(..)$/$1:$2:$3:$4:$5:$6/g;
			if(defined $c->session->{dev}{spa}{children})
			{
				my $pref = $c->session->{dev}{spa}{children};
				foreach my $p(@$pref)
				{
					$p->{parent_id} = $c->session->{dev}{spa}{id};
				}
			}

			# show synch link and set config window inactive	
			$c->session->{dev}{spa}{sync} = 'http://'.$c->session->{dev}{spa}{ip}.
					'/admin/resync?'.$sync_url.'?mac=$MA';
			$c->session->{dev}{spa}{active} = 0;

			# now, show config of next phone if available
			$self->_load_phone_subscribers($c);

			if(defined $c->session->{dev}{spa}{children}[0])
			{
				$c->session->{dev}{currentphone} = 0;
				$c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}]->{active} = 1;
				$c->stash->{dev} = $c->session->{dev};
				$self->phone($c, 1);
				return;
			}
			else
			{
				$c->session->{dev}{currentphone} = -1;
				$messages{topmsg} = 'Server.Voip.SavedSettings';
				$c->session->{messages} = \%messages;
				$c->stash->{dev} = $c->session->{dev};
				return;
			}
		}
	}
	elsif($c->request->params->{confspa})
	{
		# just active spa config window 
	}
	

	# activate config window for spa and deactivate phone config windows

	$c->session->{dev}{spa}{active} = 1;
	if($c->session->{dev}{spa}{children})
	{
		foreach my $p($c->session->{dev}{spa}{children})
		{
				foreach my $pp(@$p)
				{
					$pp->{active} = 0;
				}
		}
	}
	$c->stash->{dev} = $c->session->{dev};

}

sub phone : Local 
{
    my ( $self, $c, $internal) = @_;
    $c->log->debug('***device::index called');
    $c->stash->{template} = 'tt/device.tt';
	
	$c->stash->{dev} = $c->session->{dev};

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }
	my $base_cli = $c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn};
	
	my $phone = $c->session->{dev}{spa}{children}[int($c->session->{dev}{currentphone})];
	unless(defined $phone->{subscriber})
	{
			$self->_load_phone_subscribers($c);
	}
	    
	# just render if we come from spa config
	return if($internal);

	my %messages = ();

		
	if($c->request->params->{confphone})
	{
			my $ext = int($c->request->params->{confphone});

			my $found = 0;
			my $lastphone = $c->session->{dev}{currentphone};
			for($c->session->{dev}{currentphone} = 0; 
					defined($c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}]);
					$c->session->{dev}{currentphone}++)
			{
				if($c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}]->{ext} == $ext)
				{
					$found = 1;
					last;
				}
			}
			unless($found == 1)
			{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::phone has invalid update config ext '.$ext);
				$c->session->{dev}{currentphone} = $lastphone;
			}
			else
			{
				foreach my $p($c->session->{dev}{spa}{children})
				{
					foreach my $pp(@$p)
					{
						$pp->{active} = 0;
					}
				}
				if(defined $c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}])
				{
					$phone = $c->session->{dev}{spa}{children}[int($c->session->{dev}{currentphone})];
					$phone->{active} = 1;
				}
			}
	}
	elsif($c->request->params->{savephone})
	{
		return unless($self->_check_mac($c, \%messages));
	    $phone->{mac} = $c->request->params->{mac};
    	$c->log->debug('***device::phone mac='.$phone->{mac});

		return unless($self->_check_ip($c, \%messages));
	    $phone->{ip} = $c->request->params->{ip};
    	$c->log->debug('***device::phone ip='.$phone->{ip});

		my $usr = $c->request->params->{usr} || '';
		unless(length $usr)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::phone has invalid config user '.$usr);
		}
		else
		{
	    	$phone->{usr} = $usr;
		}
		
		my $passwd1 = $c->request->params->{pass1};
		my $passwd2 = $c->request->params->{pass2};
	
	    if(!defined $passwd1 or length $passwd1 == 0) {
    	    $messages{msgpasswd} = 'Client.Voip.MissingPass';
	    } elsif(length $passwd1 < 6) {
    	    $messages{msgpasswd} = 'Client.Voip.PassLength';
	    } elsif(!defined $passwd2) {
    	    $messages{msgpasswd} = 'Client.Voip.MissingPass2';
	    } elsif($passwd1 ne $passwd2) {
    	    $messages{msgpasswd} = 'Client.Voip.PassNoMatch';
    	}
		if(keys %messages)
		{
        	$messages{toperr} = "Client.Voip.InputErrorFound";
	        $c->session->{messages} = \%messages;
			return;
    	}
	   	$phone->{passwd} = $passwd1;
		
		my $ext = $c->request->params->{savephone} || '';
		unless($ext =~ /^\d+$/)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::phone has invalid config ext '.$ext);
				return;
		}
    
			
		my %settings = ();
		my %create_settings = ();

		$settings{username} = $create_settings{username} = $c->session->{user}{username} . "-" . $ext;
		$settings{domain} = $create_settings{domain} = $c->session->{user}{domain};
		$settings{password} = $create_settings{password} = $passwd1;
		$settings{webusername} = $create_settings{webusername} = $c->session->{user}{username} . "-" . $ext;
		$settings{webpassword} = $create_settings{webpassword} = $passwd1;

		if(defined $phone->{subscriber})
		{
				unless($c->model('Provisioning')->call_prov($c, 'voip', 'update_subscriber_password', 
							{ username => $c->session->{user}{username},
							  domain   => $c->session->{user}{domain},
							  password => $settings{password}},
							  undef))
				{
					$messages{toperr} = 'Client.Voip.InputErrorFound';
					$c->session->{messages} = \%messages;
					$c->log->debug('***device::phone failed to force-update phone subscriber password for ext '.$ext);
					return;
				}
				unless($c->model('Provisioning')->call_prov($c, 'voip', 'update_webuser_password', 
							{ username => $c->session->{user}{username},
							  domain   => $c->session->{user}{domain},
							  webusername => $settings{webusername},
							  webpassword => $settings{webpassword}},
							  undef))
				{
					$messages{toperr} = 'Client.Voip.InputErrorFound';
					$c->session->{messages} = \%messages;
					$c->log->debug('***device::phone failed to force-update phone webuser password for ext '.$ext);
					return;
				}
		}
		else
		{
			if($c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber', 
							{ id =>  $c->session->{user}{account_id},
							  subscriber => \%create_settings},
							  undef))
			{
					unless($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_preferences', 
									{ username => $settings{username},
									  domain => $settings{domain},
									  preferences => { base_cli  => $base_cli, extension => $ext}},
									  undef))
					{
							if($c->session->{prov_error} eq 'Client.Voip.ExistingAlias') {
								$messages{msgnumber} = 'Client.Voip.AssignedExtension';
								$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
							}
							$c->model('Provisioning')->call_prov($c, 'billing', 'delete_voip_account_subscriber', 
									{ id => $c->session->{user}{account_id},
									  username => $settings{username},
									  domain => $settings{domain}},
									  undef);
							return;
					}
			}
			else
			{
				if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') {
					$messages{msgsipuri} = $c->session->{prov_error};
					$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
				} elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') {
					$messages{msgnumber} = $c->session->{prov_error};
					$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
				}
				return;
			}
		}

		$phone = $c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}];

		unless(defined $phone->{device_id})
		{
			my $dev;
			$c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_device_by_vendormodel', 
							{ username => $c->session->{user}{username},
							  domain   => $c->session->{user}{domain},
							  vendor => 'Linksys', model => 'SPA922'},
							  \$dev);
			$phone->{device_id} = $dev->{id};
		}

		$c->model('Provisioning')->call_prov($c, 'voip', 'save_autoconf_unit', 
						{ username => $c->session->{user}{username},
						  domain   => $c->session->{user}{domain},
						  unit => $phone},
						  \$phone);

		$phone->{mac} =~ s/^(..)(..)(..)(..)(..)(..)$/$1:$2:$3:$4:$5:$6/g;
				
		$phone->{configured} = 1;
		$phone->{active} = 0;
		$phone->{sync} = 'http://'.$phone->{ip}.
			'/admin/resync?'.$sync_url.'?mac=$MA';

		$c->session->{dev}{currentphone}++;
		if(defined $c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}])
		{
			$c->session->{dev}{spa}{children}[$c->session->{dev}{currentphone}]->{active} = 1;
		}
		else
		{
			# we're done with the phones
			$c->session->{dev}{currentphone} = -1;
			$messages{topmsg} = 'Server.Voip.SavedSettings';
			$c->session->{messages} = \%messages;
		}
	}
	
	$c->stash->{dev} = $c->session->{dev};

}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    if(defined $c->stash->{current_view} and 
            ($c->stash->{current_view} eq 'Binary' || $c->stash->{current_view} eq 'Plain')) {
        return 1;
    }

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

    return 1; # shouldn't matter
}

sub _check_mac : Private
{
	my ($self, $c, $m) = @_;

   	my $mac = $c->request->params->{mac};
    defined($mac) and $mac = lc($mac);
   	unless(defined($mac) && $mac =~ /^([0-9a-f]{2}:?){5}[0-9a-f]{2}$/)
    {
   	    $m->{toperr} = 'Client.Voip.InputErrorFound';
       	$c->session->{messages} = $m;
        $c->log->debug('***device::_check_mac has invalid mac '.$mac);
   	    return undef;
   	}
	return 1;
}

sub _check_ip : Private
{
	my ($self, $c, $m) = @_;

	my $ip = $c->request->params->{ip};
    unless(defined($ip) && $ip =~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/)
   {
   	    $m->{toperr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = $m;
   	    $c->log->debug('***device::_check_ip has invalid ip '.$ip);
       	return undef;
    }
	return 1;
}

sub _check_uniqueness_nofxs : Private
{
		my ($self, $c, $x, $m) = @_;
		
		if($x =~ /^9/)
		{
   	    	$m->{toperr} = 'Client.Voip.InputErrorFound';
			$c->session->{messages} = $m;
			$c->log->debug('***device::_check_uniqueness detected input starting with 9 - not allowed');
   	    	return undef;
		}

		foreach my $g($c->session->{dev}{spa}{groups})
		{
			foreach my $gg(@$g)
			{
				if($x eq $gg->{ext})
				{
   	    			$m->{toperr} = 'Client.Voip.InputErrorFound';
			        $c->session->{messages} = $m;
			   	    $c->log->debug('***device::_check_uniqueness detected group with ext '.$x);
   	    			return undef;
				}
			}
		}
		foreach my $g($c->session->{dev}{spa}{children})
		{
			foreach my $gg(@$g)
			{
				if($x eq $gg->{ext})
				{
   	    			$m->{toperr} = 'Client.Voip.InputErrorFound';
			        $c->session->{messages} = $m;
			   	    $c->log->debug('***device::_check_uniqueness detected phone with ext '.$x);
   	    			return undef;
				}
			}
		}

		return 1;

}

sub _check_uniqueness : Private
{
		my ($self, $c, $x, $m) = @_;

		if($x =~ /^9/)
		{
   	    	$m->{toperr} = 'Client.Voip.InputErrorFound';
			$c->session->{messages} = $m;
			$c->log->debug('***device::_check_uniqueness detected input starting with 9 - not allowed');
   	    	return undef;
		}

		if(defined $c->session->{dev}{spa}{fxs1} && 
						$x eq $c->session->{dev}{spa}{fxs1}{ext})
		{
   	    	$m->{toperr} = 'Client.Voip.InputErrorFound';
			$c->session->{messages} = $m;
			$c->log->debug('***device::_check_uniqueness detected fxs1 with ext '.$x);
   	    	return undef;
		}
		if(defined $c->session->{dev}{spa}{fxs2} && 
						$x eq $c->session->{dev}{spa}{fxs2}{ext})
		{
   	    	$m->{toperr} = 'Client.Voip.InputErrorFound';
			$c->session->{messages} = $m;
			$c->log->debug('***device::_check_uniqueness detected fxs2 with ext '.$x);
   	    	return undef;
		}

		return $self->_check_uniqueness_nofxs($c, $x, $m);
}

sub _load_phone_subscribers {
	my $self = shift;
	my $c = shift;

	if(defined  $c->session->{dev}{spa}{children} || 
					defined $c->session->{dev}{spa}{fxs1} ||
					defined $c->session->{dev}{spa}{fxs2})
	{
		$c->model('Provisioning')->get_voip_account_subscribers($c);
		foreach my $subscriber (@{$c->session->{user}{subscribers}}) 
		{
			my $pref = $c->session->{dev}{spa}{children};
			foreach my $p(@$pref)
			{
				if($$subscriber{preferences}{base_cli} && $$subscriber{preferences}{extension} eq $p->{ext})
				{
					$p->{subscriber} = $subscriber;
				}
			}
			if(defined $c->session->{dev}{spa}{fxs1} &&
					$$subscriber{preferences}{base_cli} && 
					$$subscriber{preferences}{extension} eq $c->session->{dev}{spa}{fxs1}{ext})
			{
					$c->session->{dev}{spa}{fxs1}{subscriber} = $subscriber;
			}
			if(defined $c->session->{dev}{spa}{fxs2} &&
					$$subscriber{preferences}{base_cli} && 
					$$subscriber{preferences}{extension} eq $c->session->{dev}{spa}{fxs2}{ext})
			{
					$c->session->{dev}{spa}{fxs2}{subscriber} = $subscriber;
			}
		}
	}
}

sub _process_fxs1 {
		my $self = shift;
		my $c = shift;
		my $delext = shift;

		my %messages = ();

		my $fxs1ext_old = $c->session->{dev}{spa}{fxs1}{ext} || '';

		my $fxs1ext;
		if(defined $delext && $delext == 1)
		{
			$fxs1ext = '';
		}
		else
		{
			$fxs1ext = $c->request->params->{spafxs1};
		}

		if(length($fxs1ext) > 0 && ! $fxs1ext =~ /^\d+$/)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::spa has invalid fxs1 ext '.$fxs1ext);
				return;
		}
		my $fxs1grp = $c->request->params->{fxs1grp} || '';
		if(length($fxs1ext) > 0 && length($fxs1grp) > 0 && ! $fxs1grp =~ /^\d+$/)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::spa has invalid fxs1 grp '.$fxs1grp);
				return;
		}

		if(length($fxs1ext) > 0)
		{
			unless($self->_check_uniqueness_nofxs($c, $fxs1ext, \%messages))
			{
				$c->stash->{dev} = $c->session->{dev};
				return;
			}

			if($fxs1ext_old ne $fxs1ext && defined $c->session->{dev}{spa}{fxs1}{subscriber})
			{
    			$c->log->debug('***device::spa terminating old fxs1 subscriber');
				$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
								{ id => $c->session->{user}{account_id},
								  username => $c->session->{dev}{spa}{fxs1}{subscriber}{username},
								  domain => $c->session->{dev}{spa}{fxs1}{subscriber}{domain}},
								  undef);
			}

			 if($fxs1ext_old ne $fxs1ext)
			 {
    			$c->log->debug('***device::spa fxs1 needs subscriber update');
				my %settings = ();
				my %create_settings = ();

				$settings{username} = $create_settings{username} = $c->session->{user}{data}{username} . "-" . $fxs1ext;
				$settings{domain} = $create_settings{domain} = $c->session->{user}{data}{domain};
				$settings{password} = $create_settings{password} = $c->session->{user}{data}{password};
				$settings{webusername} = $create_settings{webusername} = $c->session->{user}{data}{username} . "-" . $fxs1ext;
				$settings{webpassword} = $create_settings{webpassword} = $c->session->{user}{data}{password};
				my $base_cli = $c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn};

				if($c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber', 
								{ id =>  $c->session->{user}{account_id},
								  subscriber => \%create_settings},
								  undef))
				{
					unless($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_preferences', 
									{ username => $settings{username},
									  domain => $settings{domain},
									  preferences => { base_cli  => $base_cli, extension => $fxs1ext}},
									  undef))
					{
						if($c->session->{prov_error} eq 'Client.Voip.ExistingAlias') 
						{
							$messages{msgnumber} = 'Client.Voip.AssignedExtension';
							$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
						}
						$c->model('Provisioning')->call_prov($c, 'billing', 'delete_voip_account_subscriber', 
										{ id =>  $c->session->{user}{account_id},
										  username => $settings{username},
										  domain => $settings{domain}},
										  undef);
						return;
					}
				}
				else
				{
					if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') 
					{
						$messages{msgsipuri} = $c->session->{prov_error};
						$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
					} 
					elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') 
					{
						$messages{msgnumber} = $c->session->{prov_error};
						$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
					}
					return;
				}
			}
			
			if(length($fxs1grp) > 0)
			{
				$c->session->{dev}{spa}{fxs1} = { ext => int($fxs1ext), group => int($fxs1grp) };
			}
			else
			{
				$c->session->{dev}{spa}{fxs1} = { ext => int($fxs1ext) };
			}
		}
		else
		{
			if($fxs1ext_old ne $fxs1ext && defined $c->session->{dev}{spa}{fxs1}{subscriber})
			{
				$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
								{ id => $c->session->{user}{account_id},
								  username => $c->session->{dev}{spa}{fxs1}{subscriber}{username},
								  domain => $c->session->{dev}{spa}{fxs1}{subscriber}{domain}},
								  undef);
			}
			$c->session->{dev}{spa}{fxs1} = undef;
		}
		return 1;
}

sub _process_fxs2 {
		my $self = shift;
		my $c = shift;
		my $delext = shift;

		my %messages = ();

		my $fxs2ext_old = $c->session->{dev}{spa}{fxs2}{ext} || '';

		my $fxs2ext;
		if(defined $delext && $delext == 1)
		{
			$fxs2ext = '';
		}
		else
		{
			$fxs2ext = $c->request->params->{spafxs2};
		}

		if(length($fxs2ext) > 0 && ! $fxs2ext =~ /^\d+$/)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::spa has invalid fxs2 ext '.$fxs2ext);
				return;
		}
		my $fxs2grp = $c->request->params->{fxs2grp} || '';
		if(length($fxs2ext) > 0 && length($fxs2grp) > 0 && ! $fxs2grp =~ /^\d+$/)
		{
				$messages{toperr} = 'Client.Voip.InputErrorFound';
				$c->session->{messages} = \%messages;
				$c->log->debug('***device::spa has invalid fxs2 grp '.$fxs2grp);
				return;
		}

		if(length($fxs2ext) > 0)
		{
			unless($self->_check_uniqueness_nofxs($c, $fxs2ext, \%messages))
			{
				$c->stash->{dev} = $c->session->{dev};
				return;
			}

			if($fxs2ext_old ne $fxs2ext && defined $c->session->{dev}{spa}{fxs2}{subscriber})
			{
    			$c->log->debug('***device::spa terminating old fxs2 subscriber');
				$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
								{ id => $c->session->{user}{account_id},
								  username => $c->session->{dev}{spa}{fxs2}{subscriber}{username},
								  domain => $c->session->{dev}{spa}{fxs2}{subscriber}{domain}},
								  undef);
			}

			 if($fxs2ext_old ne $fxs2ext)
			 {
    			$c->log->debug('***device::spa fxs2 needs subscriber update');
				my %settings = ();
				my %create_settings = ();


				$settings{username} = $create_settings{username} = $c->session->{user}{data}{username} . "-" . $fxs2ext;
				$settings{domain} = $create_settings{domain} = $c->session->{user}{data}{domain};
				$settings{password} = $create_settings{password} = $c->session->{user}{data}{password};
				$settings{webusername} = $create_settings{webusername} = $c->session->{user}{data}{username} . "-" . $fxs2ext;
				$settings{webpassword} = $create_settings{webpassword} = $c->session->{user}{data}{password};
				my $base_cli = $c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn};

				if($c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber', 
								{ id =>  $c->session->{user}{account_id},
								  subscriber => \%create_settings},
								  undef))
				{
					unless($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_preferences', 
									{ username => $settings{username},
									  domain => $settings{domain},
									  preferences => { base_cli  => $base_cli, extension => $fxs2ext}},
									  undef))
					{
						if($c->session->{prov_error} eq 'Client.Voip.ExistingAlias') 
						{
							$messages{msgnumber} = 'Client.Voip.AssignedExtension';
							$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
						}
						$c->model('Provisioning')->call_prov($c, 'billing', 'delete_voip_account_subscriber', 
										{ id =>  $c->session->{user}{account_id},
										  username => $settings{username},
										  domain => $settings{domain}},
										  undef);
						return;
					}
				}
				else
				{
					if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') 
					{
						$messages{msgsipuri} = $c->session->{prov_error};
						$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
					} 
					elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') 
					{
						$messages{msgnumber} = $c->session->{prov_error};
						$c->session->{prov_error} = 'Client.Voip.InputErrorFound';
					}
					return;
				}
			}
			
			if(length($fxs2grp) > 0)
			{
				$c->session->{dev}{spa}{fxs2} = { ext => int($fxs2ext), group => int($fxs2grp) };
			}
			else
			{
				$c->session->{dev}{spa}{fxs2} = { ext => int($fxs2ext) };
			}
		}
		else
		{
			if($fxs2ext_old ne $fxs2ext && defined $c->session->{dev}{spa}{fxs2}{subscriber})
			{
				$c->model('Provisioning')->call_prov($c, 'billing', 'terminate_voip_account_subscriber', 
								{ id => $c->session->{user}{account_id},
								  username => $c->session->{dev}{spa}{fxs2}{subscriber}{username},
								  domain => $c->session->{dev}{spa}{fxs2}{subscriber}{domain}},
								  undef);
			}
			$c->session->{dev}{spa}{fxs2} = undef;
		}
		return 1;
}

1;
