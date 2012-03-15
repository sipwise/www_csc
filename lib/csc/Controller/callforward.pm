package csc::Controller::callforward;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;
use HTML::Entities;
use POSIX;

sub base :Chained('/') PathPrefix CaptureArgs(0) {
    my ( $self, $c ) = @_;    
    return unless ( $c->stash->{subscriber} = $c->forward ('load_subscriber') );
    return unless ( $c->stash->{cf_maps} = $c->forward ('load_maps') );
    $c->stash->{subscriber}{active_number} = csc::Utils::get_active_number_string($c);
}

##############################################################################
### mapping ###

# 302 to old callforward-link 
sub mapping_oldskool : Chained('base') PathPart('') Args(0) {
    my ( $self, $c ) = @_;
    $c->response->redirect($c->uri_for ('/callforward/mapping'), 301);
}

sub mapping : Chained('base') PathPart('mapping') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/callforward_mapping.tt';
    
    return unless ( $c->stash->{cf_types} = $c->forward ('load_cf_types') );
    return unless ( $c->stash->{time_sets} = $c->forward ('load_time_sets') );
    return unless ( $c->stash->{destination_sets} = $c->forward ('load_destination_sets') );
}

sub mapping_list : Chained('mapping') PathPart('') Args(0) {
    my ( $self, $c ) = @_;
}

sub mapping_id : Chained('mapping') PathPart('') CaptureArgs(1) {
    my ( $self, $c, $map_id ) = @_;
    $c->stash->{map_id} = $map_id;
}

sub mapping_edit : Chained('mapping_id') PathPart('edit') Args(0) {
    my ( $self, $c ) = @_;
}

sub mapping_save : Chained('mapping') PathPart('save') Args(0) {
    my ( $self, $c ) = @_;

    my $map = {
        id => $c->request->params->{map_id},
        type => $c->request->params->{type},
        destination_set_id => ($c->request->params->{destset_id} != 0) ? $c->request->params->{destset_id}: undef,
        time_set_id => ($c->request->params->{timeset_id} != 0) ? $c->request->params->{timeset_id} : undef,
    };

    unless (defined $map->{destination_set_id}) {
        $c->session->{messages} = { toperr => 'Client.Syntax.MissingDestinationSet' }; 
        $c->response->redirect($c->uri_for ('/callforward/mapping'));
        $c->detach;
    }

    my $ret;
    if ($map->{id}) {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_map',
            { username => $c->stash->{subscriber}->{username},
              domain => $c->stash->{subscriber}->{domain},
              data => $map,
            },
            undef,
        );
    }
    else {
        delete $map->{id};
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_map',
            { username => $c->stash->{subscriber}->{username},
              domain => $c->stash->{subscriber}->{domain},
              data => $map,
            },
            undef,
        );
    }

    if ($ret) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' }; 
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.InputErrorFound' }; 
    }
    
    $c->response->redirect($c->uri_for ('/callforward/mapping'));
}

sub mapping_delete : Chained('mapping') PathPart('delete') Args(0) {
    my ( $self, $c ) = @_;
    
    if ($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_map',
        { username => $c->stash->{subscriber}->{username},
          domain => $c->stash->{subscriber}->{domain},
          id => $c->request->params->{map_id},
        },
        undef,
    )) {
      $c->session->{messages} =  { topmsg => 'Server.Voip.SavedSettings' } ;
    }
    else {
      $c->session->{messages} =  { toperr => 'Client.Voip.InputErrorFound' } ;
    }

    $c->response->redirect($c->uri_for ('/callforward/mapping'));
}

##############################################################################
### destination ###

sub destination : Chained('base') PathPart('destination') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    $c->stash->{template} = 'tt/callforward_destination.tt';
    return unless ( $c->stash->{destination_sets} = $c->forward ('load_destination_sets') );

    # collect data about different sets being mapped
    my $mapped = {};
    foreach my $set (@{$c->stash->{destination_sets}}) {
        $mapped->{$set->{id}} = 0; 
       
        if ($c->stash->{cf_maps}) {
            foreach my $map (values %{$c->stash->{cf_maps}}) {
                foreach my $part (@$map) {
                    $mapped->{$set->{id}}++ if ($part->{destination_set_id} == $set->{id});
                }
            }
        }
    }
    $c->stash->{mapped} = $mapped;

    # refill/update datastructure presented to template. necessary if user
    # edits, errs and form is redisplayed.
    #
    if (defined $c->session->{refill}) {
        
        foreach my $set (@{$c->stash->{destination_sets}}) {
            next if ($set->{id} != $c->session->{refill}->{set_id});
            delete $c->session->{refill}->{set_id};

            if (defined $c->session->{refill}->{item_id}) {
                foreach my $item (@{$set->{destinations}}) {
                    next if ($item->{id} != $c->session->{refill}->{item_id});
                    delete $c->session->{refill}->{item_id};
                
                    $c->stash->{dtarget_id} = $item->{id};
                    foreach my $key (keys %{$c->session->{refill}}) {
                        $item->{$key} = $c->session->{refill}->{$key};
                    }

                }

                # all new item
                if (exists $c->session->{refill}->{item_id}) {
                    delete $c->session->{refill}->{item_id};
                    
                    # indicate that this is not yet in the database
                    my $item = { id => -1 }; 
                    $c->stash->{dtarget_id} = $item->{id};

                    foreach my $key (keys %{$c->session->{refill}}) {
                        $item->{$key} = $c->session->{refill}->{$key};
                    }
                    push @{$set->{destinations}}, $item;
                }
            }

            foreach my $key (keys %{$c->session->{refill}}) {
                $set->{$key} = $c->session->{refill}->{$key};
            }
        }

        
        delete $c->session->{refill};
    }
}

sub destination_list : Chained('destination') PathPart('') Args(0) {
    my ( $self, $c ) = @_;
}

sub destination_set_get : Chained('destination') PathPart('set') CaptureArgs(1) {
    my ( $self, $c, $dset_id ) = @_;
    $c->stash->{dset_id} = $dset_id;
}

sub destination_set_post : Chained('destination') PathPart('set') CaptureArgs(0) {
    my ( $self, $c, $dset_id ) = @_;
    $c->stash->{dset_id} = $c->request->params->{dset_id};
}

### join with destination_set_get? 
sub destination_set_edit : Chained('destination_set_get') PathPart('edit') Args(0) {
    my ( $self, $c ) = @_;
}

sub destination_set_save : Chained('destination_set_post') PathPart('save') Args(0) {
    my ( $self, $c ) = @_;

    my $ret;
    if ($c->stash->{dset_id}) {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination_set',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              data     => { 
                name => $c->request->params->{dsetname}, 
                id => $c->stash->{dset_id},
              },
            },
            undef,
        );

        # only if user fiddeled with priorities
        if ($c->request->params->{priority_changed}) {
            foreach my $s (@{$c->stash->{destination_sets}}) {
                next if ($s->{id} != $c->stash->{dset_id});

                foreach my $d (@{$s->{destinations}}) {
                    my $prio = $c->request->params->{'priority-' . $d->{id}};
                    my $id = $d->{id};

                    $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination_by_id',
                        { id   => $id,
                          data => {  priority => $prio },
                        },
                        undef
                    );
                }
            }
        }
    }
    else {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_destination_set',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              data     => { 
                name => $c->request->params->{dsetname}, 
              },
            },
            undef,
        )
    } 

    if ($ret) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings'};
        $c->response->redirect($c->uri_for ('/callforward/destination'));
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.InputErrorFound'};
        $c->response->redirect($c->uri_for('/callforward/destination/set/' . $c->stash->{dset_id} . '/edit'));
    }
}

sub destination_set_delete : Chained('destination_set_post') PathPart('delete') Args(0) {
    my ( $self, $c )  = @_;

    if ($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_destination_set',
        { username => $c->stash->{subscriber}->{username},
          domain   => $c->stash->{subscriber}->{domain},
          id       => $c->stash->{dset_id},
        },
        undef,
    )) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' };
    }
    else {
        $c->session->{messages} = { toperr => 'Server.Voip.SavedSettings' };
    }

    $c->response->redirect($c->uri_for('/callforward/destination'));
}

### destination target ###

sub destination_target_get : Chained('destination') PathPart('target') CaptureArgs(1) {
    my ( $self, $c, $dtarget_id ) = @_;
    $c->stash->{dtarget_id} = $dtarget_id;
}

sub destination_target_post : Chained('destination') PathPart('target') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    $c->stash->{dset_id} = $c->request->params->{dset_id};
    $c->stash->{dtarget_id} = $c->request->params->{dtarget_id};
}

sub destination_target_edit : Chained('destination_target_get') PathPart('edit') Args(0) {
    my ( $self, $c ) = @_;
}

# does save and create
sub destination_target_save : Chained('destination_target_post') PathPart('save') Args(0) {
    my ( $self, $c ) = @_;

    my $prio = $c->request->params->{priority};
    my $fwtype = $c->request->params->{fwtype}; ###
    $c->stash->{type} = $fwtype;

    my %messages;
    my %dest;

    my $vbdom = $c->config->{voicebox_domain};
    my $fmdom = $c->config->{fax2mail_domain};
    my $confdom = $c->config->{conference_domain};

    my $fw_timeout = $c->request->params->{'dest_timeout'} || 300;
    my $fw_target_select = $c->request->params->{'dest_target'} || 'disable';
    my $fw_target;
    if ($fw_target_select eq 'sipuri') {
        $dest{timeout} = $fw_timeout;
        $fw_target = $c->request->params->{'dest_sipuri'};
  
        # normalize, so we can do some checks.
        $fw_target =~ s/^sip://i;
  
        if($fw_target =~ /^\+?\d+$/) {
            $fw_target = csc::Utils::get_qualified_number_for_subscriber($c, $fw_target);
            my $checkresult;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $fw_target, \$checkresult);
            unless($checkresult) {
                $messages{toperr} = 'Client.Voip.MalformedNumber'
                } else {
                $fw_target = 'sip:'.$fw_target.'@'.$c->stash->{subscriber}->{domain};
            }
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+(:\d{1,5})?$/i) {
            $fw_target = 'sip:'. lc $fw_target;
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
            $fw_target = 'sip:'. lc($fw_target) .'@'. $c->stash->{subscriber}->{domain};
        } else {
            $messages{err_target} = 'Client.Voip.MalformedTarget';
            $fw_target = $c->request->params->{'dest_sipuri'};
        } 
        
        if ($fw_timeout !~ /^\d+$/) {
            $messages{err_timeout} = 'Client.Voip.MalformedTimeout';
            $fw_timeout = $c->request->params->{'dest_timeout'};
        }
    } 
    elsif($fw_target_select eq 'voicebox') {
        $fw_target = 'sip:vmu'.$c->stash->{subscriber}->{cc}.$c->stash->{subscriber}->{ac}.$c->stash->{subscriber}->{sn}."\@$vbdom";
    } 
    elsif($fw_target_select eq 'fax2mail') {
        $fw_target = 'sip:'.$c->stash->{subscriber}->{cc}.$c->stash->{subscriber}->{ac}.$c->stash->{subscriber}->{sn}."\@$fmdom";
    } 
    elsif($fw_target_select eq 'conference') {
        $fw_target = 'sip:conf='.$c->stash->{subscriber}->{cc}.$c->stash->{subscriber}->{ac}.$c->stash->{subscriber}->{sn}."\@$confdom";
    }

    if (keys %messages) {
        $messages{topterr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = \%messages;
        $c->session->{refill} = { set_id => $c->stash->{dset_id}, item_id => $c->stash->{dtarget_id}, destination => $fw_target, timeout => $fw_timeout };

        if ($c->stash->{dtarget_id}) {
            $c->response->redirect($c->uri_for('/callforward/destination/target/'.$c->stash->{dtarget_id}.'/edit#dest-'.$c->stash->{dtarget_id}));
        } else { # XXX create a new target "inside" existing set
            $c->session->{refill}->{item_id} = -1;
            $c->response->redirect($c->uri_for('/callforward/destination#dset-'.$c->stash->{dset_id}));
        }

        $c->detach; 
    }

    $dest{destination} = $fw_target;
    $dest{priority} = $prio;
    
    my $ret;
    if ($c->stash->{dtarget_id})
    {
        $dest{id} = $c->stash->{dtarget_id};
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_destination',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              set_id   => $c->stash->{dset_id},
              data     => \%dest,
            },
            undef,
        )
    }
    else {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_destination',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              set_id   => $c->stash->{dset_id},
              data     => \%dest,
            },
            undef,
        )
    }
    
    if ($ret) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' };
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.InputErrorFound' } ;
    }
    
    $c->response->redirect($c->uri_for('/callforward/destination'));
}

sub destination_target_delete : Chained('destination_target_post') PathPart('delete') Args(0) {
    my ( $self, $c )  = @_;

    if ($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_destination',
        { username => $c->stash->{subscriber}->{username},
          domain   => $c->stash->{subscriber}->{domain},
          set_id   => $c->stash->{dset_id},
          id       => $c->stash->{dtarget_id},
        },
        undef,
    )) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' };
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.InputErrorFound' };
    }
    
    $c->response->redirect($c->uri_for('/callforward/destination'));
}

##############################################################################
### period ###

sub time : Chained('base') PathPart('time') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    $c->stash->{template} = 'tt/callforward_time.tt';
    return unless ( $c->stash->{time_sets} = $c->forward ('load_time_sets') );
    
    foreach my $tset (@{$c->stash->{time_sets}}) {
        foreach my $period (@{$tset->{periods}}) {
            $self->period_expand($period);
        }
    }
    
    my $year = strftime("%Y", localtime(time()));
    $c->stash->{years} = [ $year .. $year + 10 ];

    my $mapped = {};
    foreach my $set (@{$c->stash->{time_sets}}) {
        $mapped->{$set->{id}} = 0; 
       
        if ($c->stash->{cf_maps}) {
            foreach my $map (values %{$c->stash->{cf_maps}}) {
                foreach my $part (@$map) {
                    $mapped->{$set->{id}}++ if ($part->{time_set_id} == $set->{id});
                }
            }
        }
    }
    $c->stash->{mapped} = $mapped;
    
    if (defined $c->session->{refill}) {
        
        foreach my $set (@{$c->stash->{time_sets}}) {
            next if ($set->{id} != $c->session->{refill}->{set_id});
            delete $c->session->{refill}->{set_id};

            if (defined $c->session->{refill}->{item_id}) {
                foreach my $item (@{$set->{periods}}) {
                    next if ($item->{id} != $c->session->{refill}->{item_id});
                    delete $c->session->{refill}->{item_id};
                
                    foreach my $key (keys %{$c->session->{refill}}) {
                        $item->{$key} = $c->session->{refill}->{$key};
                    }
                }

                # all new item
                if (exists $c->session->{refill}->{item_id}) {
                    delete $c->session->{refill}->{item_id};

                    my $item = { id => -1 }; # indicate that this is not yet in the database
                    $c->stash->{tperiod_id} = $item->{id};

                    foreach my $key (keys %{$c->session->{refill}}) {
                        $item->{$key} = $c->session->{refill}->{$key};
                    }
                    push @{$set->{periods}}, $item;
                }
            }

            foreach my $key (keys %{$c->session->{refill}}) {
                $set->{$key} = $c->session->{refill}->{$key};
            }
        }

        delete $c->session->{refill};
    }
}

# sub time_list : Chained('time') PathPart('list') Args(0) {
sub time_list : Chained('time') PathPart('') Args(0) {
    my ( $self, $c ) = @_;
}

sub time_set_get : Chained('time') PathPart('set') CaptureArgs(1) {
    my ( $self, $c, $tset_id ) = @_;
    $c->stash->{tset_id} = $tset_id;
}

sub time_set_post : Chained('time') PathPart('set') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    $c->stash->{tset_id} = $c->request->params->{tset_id}; 
}

sub time_set_edit : Chained('time_set_get') PathPart('edit') Args(0) {
    my ( $self, $c ) = @_;
}

sub time_set_save : Chained('time_set_post') PathPart('save') Args(0) {
    my ( $self, $c ) = @_;
    my $ret;

    if (defined $c->stash->{tset_id}) {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_time_set',
            { username => $c->stash->{subscriber}->{username},
              domain => $c->stash->{subscriber}->{domain},
              data => {
                name => $c->request->params->{tsetname}, 
                id =>   $c->request->params->{tset_id},
              }
            },
            undef,
        )    
    } 
    else {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_time_set',
            { username => $c->stash->{subscriber}->{username},
              domain => $c->stash->{subscriber}->{domain},
              data => {
                  name => $c->request->params->{tsetname}, 
              }
            },
            undef,
        )
    }
    if ($ret) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' }
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.Client.Voip.InputErrorFound' }
    }
    
    $c->response->redirect($c->uri_for('/callforward/time'));
}

sub time_set_delete : Chained('time_set_post') PathPart('delete') Args(0) {
    my ( $self, $c ) = @_;

    if ($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_time_set',
        { username => $c->stash->{subscriber}->{username},
          domain   => $c->stash->{subscriber}->{domain},
          id       => $c->stash->{tset_id},
        },
        undef,
    )) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' }
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.Client.Voip.InputErrorFound' }
    }
    
    $c->response->redirect($c->uri_for('/callforward/time'));
}

sub time_period_get : Chained('time') PathPart('period') CaptureArgs(1) {
    my ( $self, $c, $tperiod_id ) = @_;
    $c->stash->{tperiod_id} = $tperiod_id;
}

sub time_period_post : Chained('time') PathPart('period') CaptureArgs(0) {
    my ( $self, $c ) = @_;
    $c->stash->{tset_id} = $c->request->params->{tset_id}; 
    $c->stash->{tperiod_id} = $c->request->params->{tperiod_id}; 
}

sub time_period_edit : Chained('time_period_get') PathPart('edit') Args(0) {
    my ( $self, $c ) = @_;
}

sub time_period_save : Chained('time_period_post') PathPart('save') Args(0) {
    my ( $self, $c ) = @_;

    my %period;
    $period{from_year} = $c->request->params->{from_year};
    $period{to_year} = $c->request->params->{to_year};
    $period{from_month} = $c->request->params->{from_month};
    $period{to_month} = $c->request->params->{to_month};
    $period{from_mday} = $c->request->params->{from_mday};
    $period{to_mday} = $c->request->params->{to_mday};
    $period{from_wday} = $c->request->params->{from_wday};
    $period{to_wday} = $c->request->params->{to_wday};
    $period{from_hour} = $c->request->params->{from_hour};
    $period{to_hour} = $c->request->params->{to_hour};
    $period{from_minute} = $c->request->params->{from_minute};
    $period{to_minute} = $c->request->params->{to_minute};

    $c->session->{messages} = $self->period_collapse(\%period);

    if (keys %{$c->session->{messages}}) {
        $c->session->{refill} = {
            set_id => $c->stash->{tset_id},
            item_id => $c->stash->{tperiod_id},

            from_year => $c->request->params->{from_year},
            to_year => $c->request->params->{to_year},
            from_month => $c->request->params->{from_month},
            to_month => $c->request->params->{to_month},
            from_mday => $c->request->params->{from_mday},
            to_mday => $c->request->params->{to_mday},
            from_wday => $c->request->params->{from_wday},
            to_wday => $c->request->params->{to_wday},
            from_hour => $c->request->params->{from_hour},
            to_hour => $c->request->params->{to_hour},
            from_minute => $c->request->params->{from_minute},
            to_minute => $c->request->params->{to_minute},
        };

        if ($c->stash->{tperiod_id}) {
            $c->response->redirect($c->uri_for('/callforward/time/period/' . $c->stash->{tperiod_id} . '/edit#tperiod-'.$c->stash->{tperiod_id}));
        } else {
            $c->session->{refill}->{item_id} = -1;
            $c->response->redirect($c->uri_for('/callforward/time#tset-'.$c->stash->{tset_id}));
        }
        
        $c->detach;
    }

    $period{id} = $c->stash->{tperiod_id} if ($c->stash->{tperiod_id});

    my $ret;
    if ($c->stash->{tperiod_id}) {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'update_subscriber_cf_time_period',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              set_id   => $c->stash->{tset_id},
              data     => \%period,
            },
            undef,
        );
    }
    else {
        $ret = $c->model('Provisioning')->call_prov( $c, 'voip', 'create_subscriber_cf_time_period',
            { username => $c->stash->{subscriber}->{username},
              domain   => $c->stash->{subscriber}->{domain},
              set_id   => $c->stash->{tset_id},
              data     => \%period,
            },
            undef,
        );
    }

    if ($ret) {
        $c->session->{messages}{topmsg} = 'Server.Voip.SavedSettings';
    }
    else {
        $c->session->{messages}{toperr} = 'Client.Voip.InputErrorFound';
    }

    $c->response->redirect($c->uri_for('/callforward/time'));
}

sub time_period_delete : Chained('time_period_post') PathPart('delete') Args(0) {
    my ( $self, $c ) = @_;

    if ($c->model('Provisioning')->call_prov( $c, 'voip', 'delete_subscriber_cf_time_period',
        { username => $c->stash->{subscriber}->{username},
          domain   => $c->stash->{subscriber}->{domain},
          set_id => $c->stash->{tset_id},
          id => $c->stash->{tperiod_id},
        },
        undef,
    )) {
        $c->session->{messages} = { topmsg => 'Server.Voip.SavedSettings' };
    }
    else {
        $c->session->{messages} = { toperr => 'Client.Voip.InputErrorFound' };
    }
    
    $c->response->redirect($c->uri_for('/callforward/time'));
}

### helpers ###

sub load_destination_sets :Private {
    my ( $self, $c ) = @_;

    my $destination_sets;

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_destination_sets',
        { username => $c->stash->{subscriber}->{username},
          domain => $c->stash->{subscriber}->{domain},
        },
        \$destination_sets,
    );
    
    my $vbdom = $c->config->{voicebox_domain};
    my $fmdom = $c->config->{fax2mail_domain};
    my $confdom = $c->config->{conference_domain};

    foreach my $set (@{$destination_sets}) {
        foreach my $dest (@{$set->{destinations}}) {
            if($dest->{destination} =~ /\@$vbdom$/) {
                $dest->{destination} = 'voicebox';
            } 
            elsif ($dest->{destination} =~ /\@$fmdom$/) {
                $dest->{destination} = 'fax2mail';
            } 
            elsif ($dest->{destination} =~ /\@$confdom$/) {
                $dest->{destination} = 'conference';
            } 
            elsif ($dest->{destination} =~ /^sip:\+?[0-9]+\@/) {
                $dest->{destination} =~ s/^sip:([^\@]+)\@.+$/$1/;
            }
            #else {
            #    die;
            #}
        }
    }

    return $destination_sets;
}

sub load_time_sets :Private {
    my ( $self, $c ) = @_;

    my $time_sets;

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_time_sets',
        { username => $c->session->{user}->{data}->{username},
          domain =>   $c->session->{user}->{data}->{domain},
        },
        \$time_sets,
    );

    return $time_sets;    
}

sub load_subscriber :Private {
    my ( $self, $c ) = @_;

    my $subscriber;

    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_voip_account_subscriber_by_id',
        { id => $c->session->{user}->{data}->{subscriber_id} },
        \$subscriber,
    );
    return $subscriber;
}

sub load_maps :Private {
    my ( $self, $c ) = @_;

    my $maps;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_cf_maps',
        { username => $c->stash->{subscriber}->{username},
          domain =>   $c->stash->{subscriber}->{domain},
        },
        \$maps,
    );
    return $maps;
}

sub load_cf_types :Private {
    my ( $self, $c ) = @_;

    return [ 
        { name => 'cfu', description => 'Call Forward Unconditional' },
        { name => 'cfb', description => 'Call Forward Busy' },
        { name => 'cft', description => 'Call Forward Timeout' },
        { name => 'cfna', description => 'Call Forward Unavailable' },
    ];
}

sub period_expand : Private {
    my ($self, $period) = @_;
    
    foreach my $part ('year', 'month', 'mday', 'wday', 'hour', 'minute') {
    
        if (defined $period->{$part} && $period->{$part} =~ /^(\d+)$/) {
            $period->{'from_' . $part} = $1;
        }
        elsif(defined $period->{$part} && $period->{$part} =~ /^(\d+)\-(\d+)$/) {
            $period->{'from_' . $part} = $1;
            $period->{'to_' . $part} = $2;
        }
        
        delete $period->{$part};
    }

    return 0;
}

sub period_collapse : Private {
    my ($self, $period) = @_;
    my %messages;

    foreach my $part ('year', 'month', 'mday', 'wday', 'hour', 'minute') {
        my $from = ( $period->{'from_' . $part} >= 0 ) ? $period->{'from_' . $part} : undef;
        my $to = ( $period->{'to_' . $part} >= 0 ) ? $period->{'to_' . $part} : undef;
        my $collapsed;

        if (defined $from) {
            $collapsed = $from;
            if (defined $to) {
                if ($part eq 'year' && $from > $to) {
                    $messages{err_year} = 'Client.Syntax.FromAfterTo';
                }
                $collapsed .= '-' . $to;
            }
        }
        elsif (defined $to) {
            $messages{'err_'.$part} = 'Client.Syntax.FromMissing'; 
        }


        delete $period->{'from_' . $part};
        delete $period->{'to_' . $part};
        $period->{$part} = $collapsed;
    }
    
    return \%messages;
}
    
1;
