package csc::Controller::autosubscriber;

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
	
    $c->stash->{active_number} = csc::Utils::get_active_number_string($c);

    $c->log->debug('***autosubscriber::index called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    $c->stash->{template} = 'tt/autoconf_subscriber.tt';
    $c->session->{autoindex} = undef;
    my %messages;


    my $gid = -1;
    if(defined $c->request->params->{'editgrp.x'})
    {
        if(defined $c->request->params->{fgroup} && int($c->request->params->{fgroup}) > 0)
        {
            $gid = int($c->request->params->{fgroup});
            $pref->{addgrp} = 1;
        }
    }
    elsif(defined $c->request->params->{'editext.x'})
    {
        $c->stash->{eext}{display} = $c->request->params->{fdisplay};
        $c->stash->{eext}{ext} = $c->request->params->{feditext};
        $c->stash->{eext}{sipuser} = $c->request->params->{feditsipuser};
        $pref->{addext} = 1;
    }
    elsif(!(defined $pref->{nodelgrp} && $pref->{nodelgrp} == 1) &&
            defined $c->request->params->{'delgrp.x'})
    {
        $self->delgroup($c);
    }
    elsif(defined $c->request->params->{'doaddgrp.x'})
    {
        my $ret = $self->doaddgroup($c);
        $pref->{addext} = 1;
        $pref->{addgrp} = 1 if($ret == 1);
    }
    elsif(defined $c->request->params->{'doaddext.x'})
    {
        my $ret = $self->doaddext($c);
        $pref->{addext} = 1;
    }
    
    return 1 unless $c->model('Provisioning')->get_voip_account_subscribers($c);

    $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages, $gid);

    unless(defined $pref->{addext} && $pref->{addext} == 0)
    {
	    $c->stash->{addext} = 1
            if(defined $c->request->params->{addext} && $c->request->params->{addext} eq "1" ||
                $pref->{addext} && $pref->{addext} == 1);
    }
    unless(defined $pref->{addgrp} && $pref->{addgrp} == 0)
    {
        if(defined $c->request->params->{'addgrp.x'} ||
            $pref->{addgrp} && $pref->{addgrp} == 1)
        {
	        $c->stash->{addgrp} = 1;
	        $c->stash->{addext} = 1;
        }
    }

}

sub doaddgroup : Local
{
    my ( $self, $c) = @_;
    $c->stash->{active_number} = csc::Utils::get_active_number_string($c);

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    my %messages = ();

    $c->log->debug('***autosubscriber::doaddgroup called');
    
    unless($c->request->params->{sid} && $c->request->params->{sid} =~ /^\d+/)
    {
        $messages{toperr} = 'Server.Internal';
        $c->session->{messages} = \%messages;
        $c->log->error('***autosubscriber:doaddgroup: no subscriber id given');
        return 1;
    }
    my $subscriber_id = int($c->request->params->{sid});
        
    unless($c->request->params->{fgruppe} && length($c->request->params->{fgruppe}) > 0)
    {
        $messages{toperr} = 'Client.Voip.NoGroupName';
        $c->session->{messages} = \%messages;
        $c->log->error('***autosubscriber:doaddgroup: no group name given');
        return 1;
    }
    my $gname = $c->request->params->{fgruppe};

    unless($c->request->params->{fgruppendurchwahl} && $c->request->params->{fgruppendurchwahl} =~ /^\d+/)
    {
        $messages{toperr} = 'Client.Voip.NoGroupExt';
        $c->log->error('***autosubscriber:doaddgroup: no valid group extension given');
        return 1;
    }
    my $gext = $c->request->params->{fgruppendurchwahl};

    my $gid = 0;    
    if($c->request->params->{fgrpid} && $c->request->params->{fgrpid} =~ /^\d+/)
    {
        $gid = int($c->request->params->{fgrpid});
    }

    unless($c->model('Provisioning')->call_prov($c, 'voip', 'save_autoconf_group', 
        { subscriber_id => $subscriber_id, group => {ext => $gext, name => $gname, id => $gid}}, 
        undef))
    {
        $c->log->error('***autosubscriber:doaddgroup: failed to save group');
        return 1;
    }

    return 0;
}

sub delgroup : Local
{
    my ( $self, $c) = @_;
    $c->stash->{active_number} = csc::Utils::get_active_number_string($c);

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    my %messages = ();

    $c->log->debug('***autosubscriber::delgroup called');
    
    unless($c->request->params->{sid} && $c->request->params->{sid} =~ /^\d+/)
    {
        $messages{toperr} = 'Server.Internal';
        $c->session->{messages} = \%messages;
        $c->log->error('***autosubscriber:delgroup: no subscriber id given');
        $self->index($c, {addext => 1, addgrp => 0, nodelgrp => 1});
        return;
    }
    my $subscriber_id = int($c->request->params->{sid});
        
    unless($c->request->params->{fgroup} && $c->request->params->{fgroup} =~ /^\d+/)
    {
        $messages{toperr} = 'Server.Internal';
        $c->log->error('***autosubscriber:delgroup: no valid group id given');
        $self->index($c, {addext => 1, addgrp => 0, nodelgrp => 1});
        return;
    }
    my $gid = int($c->request->params->{fgroup});

    unless($c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_group', 
        { username => $c->session->{user}{username},
          domain => $c->session->{user}{domain},
          subscriber_id => $subscriber_id,
          group_id => $gid }, undef))
        
    {
        $c->log->error('***autosubscriber:delgroup: failed to delete group');
        $self->index($c, {addext => 1, addgrp => 0, nodelgrp => 1});
        return;
    }

    $self->index($c, {addext => 1, addgrp => 0, nodelgrp => 1});
}


sub doaddext : Local {
    my ( $self, $c ) = @_;
    $c->stash->{active_number} = csc::Utils::get_active_number_string($c);
    
    $c->log->debug('***autosubscriber::doaddext called');

#print Dumper $c->request->params;
#    return;

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }
    
    $c->stash->{template} = 'tt/autoconf_subscriber.tt';

    my (%settings, %messages);

    my $base_cli = $c->request->params->{base_cli};
    my $extension = $c->request->params->{fextension};
    if(defined $extension) {
        $messages{msgnumber} = 'Web.Syntax.Numeric'
            unless $extension =~ /^\d+$/;
    } else {
        $messages{msgnumber} = 'Client.Voip.ChooseNumber';
    }

    my $sipuri = lc($c->request->params->{fsipuri});
    if(!defined $sipuri or length $sipuri == 0) {
        $messages{msgsipuri} = 'Client.Syntax.MissingUsername';
    } elsif($sipuri !~ /^[a-z0-9_.-]+$/) {
        $messages{msgsipuri} = 'Client.Syntax.MalformedUsername';
    }
    $settings{sipuri} = $sipuri;
    
    my $group= $c->request->params->{fgroup};
    if(defined $group and length $group > 0 and int($group) > 0) {
        $settings{autoconf_group_id} = int($group);
    }
    
    my $display = $c->request->params->{fdisplay};
    if(defined $display and length $display > 0) {
        $settings{autoconf_displayname} = $display;
    }

    my $passwd1 = $c->request->params->{fpasswort1};
    my $passwd2 = $c->request->params->{fpasswort2};
    if(!defined $passwd1 or length $passwd1 == 0) {
        $messages{msgpasswd} = 'Client.Voip.MissingPass';
    } elsif(length $passwd1 < 6) {
        $messages{msgpasswd} = 'Client.Voip.PassLength';
    } elsif(!defined $passwd2) {
        $messages{msgpasswd} = 'Client.Voip.MissingPass2';
    } elsif($passwd1 ne $passwd2) {
        $messages{msgpasswd} = 'Client.Voip.PassNoMatch';
    }

    unless(keys %messages) {
        my %create_settings = %settings;
        delete $create_settings{sipuri};

        $create_settings{webusername} = $settings{sipuri};
        $create_settings{username} = $settings{sipuri};
        $create_settings{domain} = $c->session->{user}{domain};
        $create_settings{webpassword} = $passwd1;
        # TODO: sip password should be auto-generated
        $create_settings{password} = $passwd1;
        $create_settings{autoconf_displayname} = $settings{autoconf_displayname}
            if(exists $settings{autoconf_displayname});
        $create_settings{autoconf_group_id} = $settings{autoconf_group_id}
            if(exists $settings{autoconf_group_id});

        if($c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber',
                                                { id         => $c->session->{user}{account_id},
                                                  subscriber => \%create_settings,
                                                },
                                               ))
        {
            if($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_preferences',
                                                    { username    => $settings{sipuri},
                                                      domain      => $c->session->{user}{domain},
                                                      preferences => { base_cli  => $base_cli,
                                                                       extension => $extension
                                                                     },
                                                    },
                                                   ))
            {
                $messages{topmsg} = 'Server.Voip.SubscriberCreated';
                $c->session->{messages} = \%messages;
                $c->response->redirect($c->uri_for('/autosubscriber'));
            } else {
                if($c->session->{prov_error} eq 'Client.Voip.ExistingAlias') {
                    $messages{msgnumber} = 'Client.Voip.AssignedExtension';
                    $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
                }
                $c->model('Provisioning')->delete_subscriber($c, $settings{sipuri}, $c->session->{user}{domain});
            }
        } else {
            if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') {
                $messages{msgsipuri} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            } elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') {
                $messages{msgnumber} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            }
        }
    } else {
        $messages{toperr} = "Client.Voip.InputErrorFound";
    }
    
    $c->session->{messages} = \%messages;
}

sub delsubscriber : Local {
    my ( $self, $c ) = @_;
    $c->stash->{active_number} = csc::Utils::get_active_number_string($c);

    $c->log->debug('***autosubscriber::delsubscriber called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/desktop'));
        return;
    }

    my $username = lc($c->request->params->{username});

    $c->model('Provisioning')->call_prov($c, 'voip', 'delete_autoconf_unit', 
        { 
            username => $username,
            domain   => $c->session->{user}{domain},
        }, 
        undef);
    if($c->model('Provisioning')->terminate_subscriber($c, $username, $c->session->{user}{domain})) {
        $c->session->{messages}{topmsg} = 'Server.Voip.SubscriberDeleted';
    }

    $c->response->redirect($c->uri_for('/autosubscriber'));
}

sub _load_subscribers : Private
{
    my ($self, $c, $m, $gid) = @_;

    my %groups;
    
    my %subscribers;
    return undef unless $c->model('Provisioning')->get_voip_account_subscribers($c);
    foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
        if($$subscriber{preferences}{base_cli}) {
            push @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}}, $subscriber;
            #TODO: fixme, this is terrible inefficient
            @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}} =
                sort {$a->{preferences}{extension} cmp $b->{preferences}{extension}}
                     @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}};

                my $tmpext = $subscriber->{preferences}{base_cli} . $subscriber->{preferences}{extension};
                return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                    { 
                        username => $subscriber->{username},
                        domain => $c->session->{user}{domain},
                        check_fxs => 1
                    }, 
                    \$subscriber->{unit});

        } elsif($$subscriber{sn}) {
            my $tmp_num = $$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn};
            $$subscriber{extensions} = $subscribers{$tmp_num}{extensions}
                if exists $subscribers{$tmp_num};
            $subscribers{$tmp_num} = $subscriber;

            return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                { 
                    username => $subscriber->{username},
                    domain => $c->session->{user}{domain},
                },
                \$c->stash->{unit});
        } else {
            #TODO: subscribers without number?
            $c->log->error('***account::subscriber: subscriber without E.164 number found: '.
                           $$subscriber{username} .'@'. $$subscriber{domain});
            return undef;
        }
        
        #if($gid > 0)
        if(1)
        {
            # search for group to edit
            foreach my $group (@{$subscriber->{groups}})
            {
                unless(exists $groups{$group->{id}})
                {
                    my %g = ('ext', $group->{ext}, 'name', $group->{name});
                    $groups{$group->{id}} = \%g;
                }
                if($gid > 0 && $group->{id} == $gid)
                {
                    $c->stash->{egroup}{name} = $group->{name};
                    $c->stash->{egroup}{ext} = $group->{ext};
                    $c->stash->{egroup}{id} = $group->{id};
                    last;
                }
            }
        }
    }

    foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
        if(defined $subscriber->{autoconf_group_id} && exists $groups{$subscriber->{autoconf_group_id}})
        {
            my $g = $groups{$subscriber->{autoconf_group_id}};
            $subscriber->{autoconf_group_ext} = $g->{ext};
            $subscriber->{autoconf_group_name} = $g->{name};
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

    return [sort {$a->{username} cmp $b->{username}} values %subscribers];
}


1;
