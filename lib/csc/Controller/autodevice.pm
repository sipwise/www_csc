package csc::Controller::autodevice;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

use Data::Dumper;

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
    my ( $self, $c, $pref) = @_;
    $c->stash->{active_number} = 0 . $c->session->{user}{data}{ac} . " " . $c->session->{user}{data}{sn};

    $c->log->debug('***autodevice::index called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }
    my %messages;

    $c->stash->{template} = 'tt/autoconf_device.tt';

    $c->session->{autoindex} = 0;
	
    my $ext = $c->session->{user}{data}{cc} . 
		$c->session->{user}{data}{ac} . $c->session->{user}{data}{sn};
    

#    print Dumper $c->session->{user}{subscribers};
#    return;

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);
}

sub savespa : Local
{
    my ( $self, $c, $pref) = @_;
    $c->stash->{active_number} = 0 . $c->session->{user}{data}{ac} . " " . $c->session->{user}{data}{sn};

    $c->log->debug('***autodevice::savespa called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    $c->stash->{template} = 'tt/autoconf_device.tt';

    my %messages;

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);

    my %spa;

    return unless($self->_check_mac($c, \%messages));
    $spa{mac} = $c->request->params->{mac};
    $c->log->debug('***device::spa mac='.$spa{mac});

    return unless($self->_check_ip($c, \%messages));
    $spa{ip} = $c->request->params->{ip};
    $c->log->debug('***device::spa ip='.$spa{ip});

    my ($num1, $num2);
    if ($c->request->params->{fieldset} eq "head") {
    	$num1 = $c->session->{user}->{data}->{subscriber_id};
	undef($num2);
    }
    else {
	    $num1 = $c->request->params->{fieldset} eq "small" ? $c->request->params->{fxs1} : $c->request->params->{fullnum1};
	    $num2 = $c->request->params->{fieldset} eq "small" ? $c->request->params->{fxs2} : $c->request->params->{fullnum2};
    }
    return;
    $spa{fxs1_subscriber_id} = int($num1) if($num1 && $num1 =~ /^\d+$/);
    $spa{fxs2_subscriber_id} = int($num2) if($num2 && $num2 =~ /^\d+$/);
    if(defined $spa{fxs1_subscriber_id} && defined $spa{fxs2_subscriber_id} &&
            $spa{fxs1_subscriber_id} == $spa{fxs2_subscriber_id})
    {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = \%messages;
        $c->log->debug('***device::savespa has two identical fxs subscriber ids');
        return undef;
    }
    unless(defined $c->request->params->{fmodel} && length($c->request->params->{fmodel}) > 0)
    {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = \%messages;
        $c->log->debug('***device::savespa has no model');
        return undef;
    }
    my $model = $c->request->params->{fmodel};

    my $dev;
    return 1 unless
        $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_device_by_vendormodel',
                {
                    username => $c->session->{user}{username},
                    domain   => $c->session->{user}{domain},
                    vendor => 'Linksys', model => $model
                },
                \$dev);
    $spa{device_id} = $dev->{id};

#    print Dumper \%spa;

    my $unit;
    return 1 unless
        $c->model('Provisioning')->call_prov($c, 'voip', 'save_autoconf_unit',
                { 
                    username => $c->session->{user}{username},
                    domain   => $c->session->{user}{domain},
                    unit => \%spa
                },
                \$unit);

    if($model eq 'PAP2T-EU')
    {
        $messages{topmsg} = 'Server.Voip.SavedSettings';
        $c->session->{messages} = \%messages;
        $c->response->redirect($c->uri_for('/autodevice'));
        return;
    }


    my $editid = 0;
    if(defined $c->request->params->{'editphone.x'})
    {
        if(defined $c->request->params->{editid} && int($c->request->params->{editid}) > 0)
        {
            $editid = int($c->request->params->{editid});
        }
    }

    my $i = -1;
    foreach my $ext (@{@{$c->stash->{subscribers}[0]}{extensions}})
    {
        $i++;

        if($editid > 0)
        {
            if($ext->{unit}{id} eq $editid)
            {
                $c->log->debug('***autodevice::savephone using unit mac '.$ext->{unit}{mac}.' for next phone edit config');
                $c->stash->{cphone}{ip} = $ext->{unit}{ip};
                $c->stash->{cphone}{mac} = $ext->{unit}{mac};
                $c->stash->{cphone}{extid} = $ext->{subscriber_id};
                last;
            }
            else
            {
                next;
            }
        }
        else
        {
            # TODO: horrible inefficient, start after last index!
            next 
                if($i < $c->session->{autoindex});

            if($ext->{unit} && $ext->{subscriber_id} == $ext->{unit}{subscriber_id}) # might be assigned to FXS as well, where we don't care
            {
                $c->log->debug('***autodevice::savephone using unit mac '.$ext->{unit}{mac}.' for next phone config');
                $c->stash->{cphone}{ip} = $ext->{unit}{ip};
                $c->stash->{cphone}{mac} = $ext->{unit}{mac};
                $c->stash->{cphone}{extid} = $ext->{subscriber_id};
                last;
            }
        }
    }
    $c->session->{autoindex} = $i+1;

    my $free_ext = 0;
    foreach my $ext (@{@{$c->stash->{subscribers}[0]}{extensions}})
    {
        $free_ext++
            unless(defined $ext->{unit});

    }

    my $all_ext = $#{@{$c->stash->{subscribers}[0]}{extensions}};
    if(defined $unit->{fsx1_subscriber_id} && int($unit->{fsx1_subscriber_id} > 0))
    {
        --$free_ext;
        --$all_ext;
    }
    if(defined $unit->{fsx2_subscriber_id} && int($unit->{fsx2_subscriber_id} > 0))
    {
        --$free_ext;
        --$all_ext;
    }

   
    if($all_ext < 1)
    {
        $messages{topmsg} = 'Server.Voip.SavedSettings';
        $c->session->{messages} = \%messages;
        $c->response->redirect($c->uri_for('/autodevice'));
        return;
    }    

    if($free_ext > 1 || $c->session->{autoindex} <= $#{@{$c->stash->{subscribers}[0]}{extensions}}) 
    {
        $c->stash->{morephones} = 1;
    }

    $messages{topmsg} = 'Server.Voip.SavedSettings';
    $c->session->{messages} = \%messages;

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);
    $c->stash->{template} = 'tt/autoconf_phone.tt';
}

sub savephone: Local
{
    my ( $self, $c, $pref) = @_;
    $c->stash->{active_number} = 0 . $c->session->{user}{data}{ac} . " " . $c->session->{user}{data}{sn};


    $c->log->debug('***autodevice::savephone called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    $c->stash->{template} = 'tt/autoconf_phone.tt';

    my %messages;

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);

    my %phone;

    return unless($self->_check_mac($c, \%messages));
    $phone{mac} = $c->request->params->{mac};
    $c->log->debug('***device::savephone mac='.$phone{mac});

    return unless($self->_check_ip($c, \%messages));
    $phone{ip} = $c->request->params->{ip};
    $c->log->debug('***device::savephone ip='.$phone{ip});

    unless(defined $c->request->params->{fdw} && length($c->request->params->{fdw}) > 0)
    {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = \%messages;
        $c->log->debug('***device::savephone has no extension username');
        return undef;
    }
    my $usr = $c->request->params->{fdw};

    my $dev;
    return 1 unless
        $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_device_by_vendormodel',
                {
                    username => $c->session->{user}{username},
                    domain   => $c->session->{user}{domain},
                    vendor => 'Linksys', model => 'SPA922'
                },
                \$dev);
    $phone{device_id} = $dev->{id};

#    print Dumper \%spa;

    my $unit;
    return 1 unless
        $c->model('Provisioning')->call_prov($c, 'voip', 'save_autoconf_unit',
                { 
                    username => $usr,
                    domain   => $c->session->{user}{domain},
                    unit => \%phone
                },
                \$unit);

#    print Dumper $unit;

    if(defined $c->request->params->{'fdone.x'})
    {
        $c->response->redirect($c->uri_for('/autodevice'));
        return;
    }
    

    my $i = -1;
    foreach my $ext (@{@{$c->stash->{subscribers}[0]}{extensions}})
    {
        $i++;

        # TODO: horrible inefficient, start after last index!
        next 
            if($i < $c->session->{autoindex});

        if($ext->{unit} && $ext->{subscriber_id} == $ext->{unit}{subscriber_id}) # might be assigned to FXS as well, where we don't care
        {
            $c->log->debug('***autodevice::savephone using unit id '.$ext->{unit}{id}.' for next phone config');
            $c->stash->{cphone}{ip} = $ext->{unit}{ip};
            $c->stash->{cphone}{mac} = $ext->{unit}{mac};
            $c->stash->{cphone}{extid} = $ext->{subscriber_id};
            last;
        }
    }
    $c->session->{autoindex} = $i+1;
    
    
    my $free_ext = 0;
    foreach my $ext (@{@{$c->stash->{subscribers}[0]}{extensions}})
    {
        $free_ext++
            unless(defined $ext->{unit});

    }
    $free_ext--
    	if(defined $unit->{new} &&  $unit->{new} eq '1');
    my $lastindex = $#{@{$c->stash->{subscribers}[0]}{extensions}};

    $c->log->error('***autodevice::savephone free ext='.$free_ext);
    $c->log->error('***autodevice::savephone autoindex='.$c->session->{autoindex});
    $c->log->error('***autodevice::savephone lastindex=' . $lastindex);

    if($free_ext > 1 || $c->session->{autoindex} < $lastindex)
    {
    	$c->log->error('***autodevice::savephone morephones 1');
        $c->stash->{morephones} = 1;
    }
    elsif($free_ext == 1 && defined $c->stash->{cphone})
    {
    	$c->log->error('***autodevice::savephone morephones 2');
        $c->stash->{morephones} = 1;
    }

    $messages{topmsg} = 'Server.Voip.SavedSettings';
    $c->session->{messages} = \%messages;

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);
    $c->stash->{template} = 'tt/autoconf_phone.tt';
}

sub deldev : Local
{
    my ( $self, $c, $pref) = @_;
    $c->stash->{active_number} = 0 . $c->session->{user}{data}{ac} . " " . $c->session->{user}{data}{sn};
    my %messages;


    $c->log->debug('***autodevice::deldev called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

   unless(defined $c->request->params->{duser} && length($c->request->params->{duser}) > 0)
   {
        $messages{toperr} = 'Server.Internal';
        $c->log->error('***autodevice:deldev: no username given');
   }
   else
   {
        $c->log->error('***autodevice:deldev: deleting device for user '.$c->request->params->{duser});
        $c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_unit', 
            { 
                username => $c->request->params->{duser},
                domain   => $c->session->{user}{domain},
            }, 
            undef);
        $messages{topmsg} = 'Server.Voip.SavedSettings';
   }
        
   $c->session->{messages} = \%messages;
   $c->response->redirect($c->uri_for('/autodevice'));
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

sub _load_subscribers : Private
{
    my ($self, $c, $m) = @_;

    my @phones = ();
    
    my %subscribers;
    $c->session->{user}{subscribers} = undef;
    return undef unless $c->model('Provisioning')->get_voip_account_subscribers($c);
    foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
        if($$subscriber{preferences}{base_cli}) {
                
		return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                    { 
                        username => $subscriber->{username},
                        domain => $c->session->{user}{domain},
                        check_fxs => 1
                    }, 
                    \$subscriber->{unit});
            if(defined $subscriber->{unit} && $subscriber->{unit}{model} eq "SPA922")
            {
                $subscriber->{unit}{username} = $subscriber->{username};
                push @phones, $subscriber->{unit};
            }

            push @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}}, $subscriber;
            #TODO: fixme, this is terrible inefficient
            @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}} =
                sort {$a->{preferences}{extension} cmp $b->{preferences}{extension}}
                     @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}};

        } elsif($$subscriber{sn}) {
            
	    return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                { 
                    username => $subscriber->{username},
                    domain => $c->session->{user}{domain},
                },
                \$c->stash->{unit});
            if(defined $c->stash->{unit})
            {
                $c->stash->{unit}{username} = $subscriber->{username};
            }
            

            my $tmp_num = $$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn};
            $$subscriber{extensions} = $subscribers{$tmp_num}{extensions}
                if exists $subscribers{$tmp_num};
            $subscribers{$tmp_num} = $subscriber;

        } else {
            #TODO: subscribers without number?
            $c->log->error('***account::subscriber: subscriber without E.164 number found: '.
                           $$subscriber{username} .'@'. $$subscriber{domain});
            return undef;
        }
    }

    if(defined $c->stash->{unit})
    {
        my $sid1 = $c->stash->{unit}{fxs1_subscriber_id};
        my $sid2 = $c->stash->{unit}{fxs2_subscriber_id};
        foreach my $sub (values %subscribers)
        {
            foreach my $ext (@{$sub->{extensions}})
            {
                if(defined $sid1 && $ext->{subscriber_id} == $sid1)
                {
                    $c->stash->{unit}{fxs1_subscriber_ext} = $ext->{preferences}{extension};
                    $c->stash->{unit}{fxs1_subscriber_name} = $ext->{autoconf_displayname};
                }
                elsif(defined $sid2 && $ext->{subscriber_id} == $sid2)
                {
                    $c->stash->{unit}{fxs2_subscriber_ext} = $ext->{preferences}{extension};
                    $c->stash->{unit}{fxs2_subscriber_name} = $ext->{autoconf_displayname};
                }
            }
        }
    }
    if(@phones > 0)
    {
        $c->stash->{phones} = \@phones;
    }

    return [sort {$a->{username} cmp $b->{username}} values %subscribers];
}


1;

