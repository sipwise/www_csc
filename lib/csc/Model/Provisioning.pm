package csc::Model::Provisioning;

use strict;
use warnings;
use base 'Catalyst::Model';
use Scalar::Util;

use Sipwise::Provisioning::Voip;
use Sipwise::Provisioning::Billing;

=head1 NAME

csc::Model::Provisioning - Sipwise provisioning catalyst model

=head1 DESCRIPTION

Catalyst Model that uses Sipwise::Provisioning::Voip to get and set VoIP
user data.

=cut

sub new {
    my $class = shift;

    my $self = {};
    $$self{voip} = $$self{prov} = Sipwise::Provisioning::Voip->new();
    $$self{billing} = Sipwise::Provisioning::Billing->new();

    return bless $self, $class;
}

#TODO: this function should replace most other functions here.
sub call_prov {
    # model, catalyst, scalar, scalar, hash-ref, scalar-ref
    my ($self, $c, $backend, $function, $parameter, $result) = @_;

    $c->log->debug("***Provisioning::call_prov calling '$backend\::$function'");

    eval {
        $$result = $$self{$backend}->handle_request( $function,
                                                     {
                                                       authentication => {
                                                                           type     => 'system',
                                                                           username => $c->config->{prov_user},
                                                                           password => $c->config->{prov_pass},
                                                                         },
                                                       parameters => $parameter,
                                                   });
    };

    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::call_prov: $backend\::$function failed: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub login {
    my ($self, $c, $user, $password) = @_;

    $c->log->debug('***Provisioning::login called, authenticating...');

    unless(defined $user and length $user) {
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingUsername';
        return;
    }
    unless(defined $password and length $password) {
        $c->session->{prov_error} = 'Client.Syntax.LoginMissingPass';
        return;
    }

    unless(Scalar::Util::blessed($user)
           and ($Catalyst::Plugin::Authentication::VERSION < 0.10003
                ? $user->isa("Catalyst::Plugin::Authentication::User")
                : $user->isa("Catalyst::Authentication::User")))
    {
        if(my $user_obj = $self->_get_user($c, $user)) {
            $user = $user_obj;
        } else {
            if($c->session->{prov_error} and $c->session->{prov_error} eq 'Client.Voip.NoSuchSubscriber') {
                $c->log->info("***Provisioning::login authentication failed for '$user', unknown user.");
                $c->session->{prov_error} = 'Client.Voip.AuthFailed';
            }
            return;
        }
    }
    if($self->_auth_user($c, $user, $password)) {
        $c->set_authenticated($user);
        $c->log->debug('***Provisioning::login authentication succeeded.');
        $$user{password} = $password;
        $c->session->{user} = $user;
        return 1;
    }

    $c->log->info("***Provisioning::login authentication failed for '$$user{username}', wrong password.");
    $c->session->{prov_error} = 'Client.Voip.AuthFailed';
    return;
}

sub add_subscriber {
    my ($self, $c, $settings) = @_;

    $c->log->debug("***Provisioning::add_subscriber called");

    eval {
        $$self{billing}->add_voip_account_subscriber({ id         => $c->session->{user}{account_id},
                                                       subscriber => $settings,
                                                    });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::add_subscriber failed to create subscriber '$$settings{username}\@".
                           $$settings{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::add_subscriber failed to create subscriber '$$settings{username}\@".
                           $$settings{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }
    return 1;
}

sub get_subscriber_byid {
    my ($self, $c, $subscriber_id) = @_;

    $c->log->debug("***Provisioning::get_subscriber_byid: called");

    eval {
        $c->session->{user}{data} =
            $$self{prov}->get_subscriber_byid({subscriber_id => $subscriber_id});
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_subscriber_byid failed to get subscriber for id $subscriber_id: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_subscriber_byid failed to get subscriber for id $subscriber_id: $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }
    return 1;
}

sub get_usr_preferences {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_usr_preferences: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_usr_preferences: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{data} =
            $$self{prov}->get_subscriber({username => $c->session->{user}{username},
                                          domain => $c->session->{user}{domain}});
        $c->session->{user}{preferences} =
            $$self{prov}->get_subscriber_preferences({username => $c->session->{user}{username},
                                                      domain => $c->session->{user}{domain}});
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_usr_preferences failed to get preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_usr_preferences failed to get preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub set_subscriber_preferences {
    my ($self, $c, $username, $domain, $preferences) = @_;

    $c->log->debug("***Provisioning::set_subscriber_preferences: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::set_subscriber_preferences: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval { $$self{prov}->set_subscriber_preferences({ username    => $username,
                                                      domain      => $domain,
                                                      preferences => $preferences,
                                                   })
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::set_subscriber_preferences failed to set preferences for '".
                           $username .'@'. $domain ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::set_subscriber_preferences failed to set preferences for '".
                           $username .'@'. $domain ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_usr_voicebox_preferences {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_usr_voicebox_preferences: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_usr_voicebox_preferences: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{voicebox_preferences} =
            $$self{prov}->get_subscriber_voicebox_preferences({username => $c->session->{user}{username},
                                                               domain => $c->session->{user}{domain}});
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_usr_voicebox_preferences failed to get voicebox preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_usr_voicebox_preferences failed to get voicebox preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub set_usr_voicebox_preferences {
    my ($self, $c, $preferences) = @_;

    $c->log->debug("***Provisioning::set_usr_voicebox_preferences: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::set_usr_voicebox_preferences: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval { $$self{prov}->set_subscriber_voicebox_preferences(
                             { username => $c->session->{user}{username},
                               domain => $c->session->{user}{domain},
                               preferences => $preferences,
                             }) };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::set_usr_voicebox_preferences failed to set voicebox preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::set_usr_voicebox_preferences failed to set voicebox preferences for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_free_numbers {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_free_numbers called");
    my $return = eval { $$self{billing}->get_free_numbers({domain => $c->config->{site_domain},
                                                           limit  => 30,
                                                         }) };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_free_numbers failed to get free numbers for '".
                           $c->config->{site_domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_free_numbers failed to get free numbers for '".
                           $c->config->{site_domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $return;
}

sub update_subscriber {
    my ($self, $c, $settings) = @_;

    $c->log->debug("***Provisioning::update_subscriber called");
    eval {
        $$self{billing}->update_voip_account_subscriber({ id         => $c->session->{user}{account_id},
                                                          subscriber => {
                                                                          username => $c->session->{user}{username},
                                                                          domain   => $c->session->{user}{domain},
                                                                          %$settings,
                                                                        },
                                                       });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::update_subscriber failed to update subscriber '".
                           $c->session->{user}{username} .'@'. $c->config->{site_domain} .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::update_subscriber failed to update subscriber '".
                           $c->session->{user}{username} .'@'. $c->config->{site_domain} .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub force_update_subscriber_password {
    my ($self, $c, $username, $domain, $password) = @_;

    $c->log->debug("***Provisioning::force_update_subscriber_password called");
    eval {
        $$self{prov}->update_subscriber_password({username => $username,
                                                  domain   => $domain,
                                                  password => $password
                                                });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::force_update_subscriber_password failed to update password for '".
                           $username .'@'. $domain .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::force_update_subscriber_password failed to update password for '".
                           $username .'@'. $domain .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub force_update_webuser_password {
    my ($self, $c, $username, $domain, $password) = @_;

    $c->log->debug("***Provisioning::force_update_webuser_password called");
    eval {
        $$self{prov}->update_webuser_password({webusername => $username,
                                                  domain   => $domain,
                                                  webpassword => $password
                                                });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::force_update_webuser_password failed to update password for '".
                           $username .'@'. $domain .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::force_update_webuser_password failed to update password for '".
                           $username .'@'. $domain .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}


sub terminate_subscriber {
    my ($self, $c, $username, $domain) = @_;

    $c->log->debug("***Provisioning::terminate_subscriber called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::terminate_subscriber: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }
    eval {
        $$self{billing}->terminate_voip_account_subscriber({ id       => $c->session->{user}{account_id},
                                                             username => $username,
                                                             domain   => $domain,
                                                          });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::terminate_subscriber failed to terminate subscriber '".
                           $username .'@'. $domain .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::terminate_subscriber failed to terminate subscriber '".
                           $username .'@'. $domain .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub delete_subscriber {
    my ($self, $c, $username, $domain) = @_;

    $c->log->debug("***Provisioning::delete_subscriber called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::delete_subscriber: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }
    eval {
        $$self{billing}->delete_voip_account_subscriber({ id       => $c->session->{user}{account_id},
                                                          username => $username,
                                                          domain   => $domain,
                                                       });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_subscriber failed to delete subscriber '".
                           $username .'@'. $domain .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_subscriber failed to delete subscriber '".
                           $username .'@'. $domain .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_voip_account_subscribers {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_voip_account_subscribers: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_voip_account_subscribers: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{subscribers} =
            $$self{prov}->get_voip_account_subscribers({ id => $c->session->{user}{account_id} });

        foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
            $subscriber =
                $$self{prov}->get_subscriber({
                                               username => $$subscriber{username},
                                               domain   => $$subscriber{domain}
                                            });
            $$subscriber{preferences} =
                $$self{prov}->get_subscriber_preferences({
                                                           username => $$subscriber{username},
                                                           domain   => $$subscriber{domain}
                                                        });
            
            $$subscriber{groups} =
                $$self{prov}->get_subscriber_groups({
                                                           username => $$subscriber{username},
                                                           domain   => $$subscriber{domain}
                                                        });
        }
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_voip_account_subscribers failed to get subscribers for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} .": ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_voip_account_subscribers failed to get subscribers for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} .": $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_call_list {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_call_list: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_call_list: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    #TODO: enable call listing of different subscribers for admin accounts
    eval {
        $c->session->{user}{call_list} =
            $$self{prov}->get_subscriber_calls({ username => $c->session->{user}{username},
                                                 domain   => $c->session->{user}{domain},
                                                 filter   => {
                                                               limit    => 10,
                                                             },
                                              });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_call_list failed to get calls for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_call_list failed to get calls for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_calls_by_date {
    my ($self, $c, $sdate, $edate) = @_;

    $c->log->debug("***Provisioning::get_calls_by_date: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_calls_by_date: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    #TODO: enable call listing of different subscribers for admin accounts
    eval {
        $c->session->{user}{call_list} =
            $$self{prov}->get_subscriber_calls({ username => $c->session->{user}{username},
                                                 domain   => $c->session->{user}{domain},
                                                 filter   => {
                                                               start_date => $sdate,
                                                               end_date   => $edate,
                                                             },
                                              });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_calls_by_date failed to get calls for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_calls_by_date failed to get calls for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_voicemails_by_date {
    my ($self, $c, $sdate, $edate) = @_;

    $c->log->debug("***Provisioning::get_voicemails_by_date: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_voicemails_by_date: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{voicemail_list} =
            $$self{prov}->get_subscriber_voicemails({ username => $c->session->{user}{username},
                                                      domain   => $c->session->{user}{domain},
                                                      filter   => {
                                                                    start_date => $sdate,
                                                                    end_date   => $edate,
                                                                  },
                                                   });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_voicemails_by_date failed to get voicemails for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_voicemails_by_date failed to get voicemails for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_voicemails_by_limit {
    my ($self, $c, $limit, $offset) = @_;

    $c->log->debug("***Provisioning::get_voicemails_by_limit: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_voicemails_by_limit: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{voicemail_list} =
            $$self{prov}->get_subscriber_voicemails({ username => $c->session->{user}{username},
                                                      domain   => $c->session->{user}{domain},
                                                      filter   => {
                                                                    limit  => $limit,
                                                                    offset => $offset,
                                                                  },
                                                   });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_voicemails_by_limit failed to get voicemails for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_voicemails_by_limit failed to get voicemails for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub delete_voicemail {
    my ($self, $c, $id) = @_;

    $c->log->debug("***Provisioning::delete_voicemail: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::delete_voicemail: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $$self{prov}->delete_subscriber_voicemail({ username => $c->session->{user}{username},
                                                    domain   => $c->session->{user}{domain},
                                                    id       => $id,
                                                 });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_voicemail failed to delete voicemail '$id' for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_voicemail failed to delete voicemail '$id' for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_voicemail {
    my ($self, $c, $id) = @_;

    $c->log->debug("***Provisioning::get_voicemail: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_voicemail: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    my $vm = eval {
          $$self{prov}->get_subscriber_voicemail({ username => $c->session->{user}{username},
                                                   domain   => $c->session->{user}{domain},
                                                   id       => $id,
                                                });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_voicemail failed to get voicemail '$id' for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_voicemail failed to get voicemail '$id' for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    # TODO: hack. this should be covered by the provisioning library
    if(ref $$vm{recording} eq 'SOAP::Data') {
        $$vm{recording} = $$vm{recording}->value();
    }

    return $vm;
}

sub get_account_balance {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_account_balance: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_account_balance: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $c->session->{user}{account} =
            $$self{billing}->get_voip_account_balance({ id => $c->session->{user}{account_id},
                                                     });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_account_balance failed to get balance for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_account_balance failed to get balance for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub update_account_balance {
    my ($self, $c, $amount) = @_;

    $c->log->debug("***Provisioning::update_account_balance: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::update_account_balance: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $$self{billing}->update_voip_account_balance({ id   => $c->session->{user}{account_id},
                                                       data => { cash => $amount },
                                                    });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::update_account_balance failed to update balance for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::update_account_balance failed to update balance for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub create_contact {
    my ($self, $c, $contact) = @_;

    $c->log->debug("***Provisioning::create_contact: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::create_contact: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $$self{prov}->create_subscriber_contact({ username => $c->session->{user}{username},
                                                  domain   => $c->session->{user}{domain},
                                                  data     => $contact,
                                               });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::create_contact failed to create contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::create_contact failed to create contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub update_contact {
    my ($self, $c, $id, $contact) = @_;

    $c->log->debug("***Provisioning::update_contact: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::update_contact: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $$self{prov}->update_subscriber_contact({ username => $c->session->{user}{username},
                                                  domain   => $c->session->{user}{domain},
                                                  id       => $id,
                                                  data     => $contact,
                                               });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::update_contact failed to update contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::update_contact failed to update contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub get_contacts {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_contacts: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_contacts: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    my $contacts = eval {
            $$self{prov}->get_subscriber_contacts({ username => $c->session->{user}{username},
                                                    domain   => $c->session->{user}{domain},
                                                 });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_contacts failed to get contacts for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_contacts failed to get contacts for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    delete $c->session->{user}{contacts};

    foreach my $contact (@$contacts) {
        $c->session->{user}{contacts}{$$contact{id}} = $contact;
    }

    return 1;
}

sub get_formatted_contacts {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_formatted_contacts: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_formatted_contacts: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    $self->get_contacts($c);

    my $user_cc = $c->session->{user}{data}{cc};

    foreach my $contact (values %{$c->session->{user}{contacts}}) {
        for(qw(phonenumber homephonenumber mobilenumber faxnumber)) {
            if(defined $$contact{$_} and
               length $$contact{$_})
            {
                $$contact{$_} =~ s/^\+$user_cc/0/;
            }
        }
        if(defined $$contact{firstname} and length $$contact{firstname}) {
            $$contact{displayname} = $$contact{firstname};
            $$contact{displayname} .= ' ' . $$contact{lastname}
                if defined $$contact{lastname} and length $$contact{lastname};
        } elsif(defined $$contact{lastname} and length $$contact{lastname}) {
            $$contact{displayname} = $$contact{lastname};
        } elsif(defined $$contact{company} and length $$contact{company}) {
            $$contact{displayname} = $$contact{company};
        }
    }

    return 1;
}

sub get_contacts_for_numbers {
    my ($self, $c) = @_;

    $c->log->debug("***Provisioning::get_contacts_for_numbers: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_contacts_for_numbers: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    $self->get_formatted_contacts($c)
        unless exists $c->session->{user}{contacts};

    delete $c->session->{user}{contacts_for_numbers};

    foreach my $contact (values %{$c->session->{user}{contacts}}) {
        # hmm, shall we really include faxnumber here?
        for(qw(homephonenumber phonenumber mobilenumber faxnumber)) {
            if(defined $$contact{$_} and length $$contact{$_}) {
                $c->session->{user}{contacts_for_numbers}{$$contact{$_}} = $$contact{id};
            }
        }
    }

    return 1;
}

sub delete_contact {
    my ($self, $c, $id) = @_;

    $c->log->debug("***Provisioning::delete_contact: called");
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::delete_contact: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    eval {
        $$self{prov}->delete_subscriber_contact({ username => $c->session->{user}{username},
                                                  domain   => $c->session->{user}{domain},
                                                  id       => $id,
                                               });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_contact failed to delete contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_contact failed to delete contact for '".
                           $c->session->{user}{username} .'@'. $c->session->{user}{domain} ."': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

sub localize {
    my ($self, $c, $messages) = @_;

    return unless defined $messages;

    if(ref $messages eq 'HASH') {
        my %translations;
        foreach my $msgname (keys %$messages) {
            $translations{$msgname} = eval { $$self{prov}->get_localized_string({language => $c->language, code => $$messages{$msgname}}) };
            unless(defined $translations{$msgname}) {
                $translations{$msgname} = eval { $$self{prov}->get_localized_string({language => $c->language, code => 'Server.Internal'}) };
            }
        }
        return \%translations;
    } elsif(!ref $messages) {
        return eval { $$self{prov}->get_localized_string({language => $c->language, code => $messages}) };
    }

    return;
}

sub get_autoconf_device_by_vendormodel {
    my ($self, $c, $vendor, $model) = @_;
    
    my $dev = eval { $$self{prov}->get_autoconf_device_by_vendormodel({
					 username => $c->session->{user}{username},
					 domain   => $c->session->{user}{domain},
					 vendor => $vendor,
					 model => $model}); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_autoconf_device_by_vendormodel failed to fetch device: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_autoconf_device_by_vendormodel failed to fetch device: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $dev;
}

sub save_autoconf_unit{
    my ($self, $c, $unit) = @_;
    
    my $dev = eval { $$self{prov}->save_autoconf_unit({
					 username => $c->session->{user}{username},
					 domain   => $c->session->{user}{domain},
					 unit => $unit}); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::save_autoconf_unit failed to save device unit: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::save_autoconf_unit failed to save device unit: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $dev;
}

sub get_autoconf_unit{
    my ($self, $c, $ext) = @_;
    
    my $dev = eval { $$self{prov}->get_autoconf_unit({
					 username => $c->session->{user}{username},
					 domain   => $c->session->{user}{domain},
					 ext => $ext}); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_autoconf_unit failed to fetch device unit: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_autoconf_unit failed to fetch device unit: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $dev;
}

sub delete_autoconf_unit {
    my ($self, $c, $ext) = @_;
    
    my $ret = eval { $$self{prov}->delete_autoconf_unit({
					 username => $c->session->{user}{username},
					 domain   => $c->session->{user}{domain},
					 ext => $ext}); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_autoconf_unit failed to delete device unit: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_autoconf_unit failed to delete device unit: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $ret;
}

sub delete_autoconf_group {
    my ($self, $c, $group_id) = @_;
    
    my $ret = eval { $$self{prov}->delete_autoconf_group({
					 username => $c->session->{user}{username},
					 domain   => $c->session->{user}{domain},
					 group_id => $group_id}); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_autoconf_group failed to delete group: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_autoconf_group failed to delete group: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $ret;
}

sub get_autoconf_options_bymac {
    my ($self, $c, $mac) = @_;
    
    my $opts = eval { $$self{prov}->get_autoconf_options_bymac(
            { mac => $mac }
                ); };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_autoconf_options_bymac failed to fetch options: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_autoconf_options_bymac failed to fetch options: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $opts;
}

sub get_registered_contacts {
    my ($self, $c) = @_;
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::get_registered_contacts: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }
    
    my $contacts = eval { $$self{prov}->get_registered_contacts({
                username => $c->session->{user}{username}, 
                domain   => $c->session->{user}{domain}
            })};
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::get_registered_contacts failed to fetch contact list: ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::get_registered_contacts failed to fetch contact list: $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return $contacts;
}

sub delete_registered_contact {
    my ($self, $c, $id) = @_;
    if (!$c->user_exists) {
        $c->log->error("***Provisioning::delete_registered_contact: no user stored.");
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }
    
    eval { $$self{prov}->delete_registered_contact({
                username => $c->session->{user}{username}, 
                domain   => $c->session->{user}{domain},
                id => $id
            })};
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::delete_registered_contact failed to delete contact '$id': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::delete_registered_contact failed to delete contact '$id': $@");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}





####################
# helper functions #
####################

sub _get_user {
    my ($self, $c, $user) = @_;

    my ($loc, $dom) = split /\@/, $user;
    my $user_obj = eval {
        my $tmpobj = $$self{prov}->get_subscriber({username => $loc, domain => $dom});
        my $tmpref = $$self{prov}->get_subscriber_preferences({username => $loc, domain => $dom});
        $$tmpobj{extension} = $$tmpref{extension};
        return $tmpobj;
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::_get_user failed to get user '$loc\@$dom' from DB: ". $@->faultstring)
                unless $@->faultcode eq 'Server.Voip.NoSuchSubscriber';
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::_get_user failed to get user '$loc\@$dom' from DB: $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }
    my $return = { id => $user, store => $self,
                   username => $loc, domain => $dom,
                   admin => $$user_obj{admin}, account_id => $$user_obj{account_id},
                   extension => $$user_obj{extension}
                 };
    if($Catalyst::Plugin::Authentication::VERSION < 0.10003) {
        return bless $return, "Catalyst::Plugin::Authentication::User::Hash";
    } else {
        return bless $return, "Catalyst::Authentication::User::Hash";
    }
}

sub _auth_user {
    my ($self, $c, $user, $pass) = @_;

    eval { $$self{prov}->authenticate_webuser({ webusername => $$user{username},
                                                domain      => $$user{domain},
                                                webpassword => $pass,
                                             });
    };
    if($@) {
        if(ref $@ eq 'SOAP::Fault') {
            $c->log->error("***Provisioning::_auth_user failed to auth user '$$user{username}\@$$user{domain}': ". $@->faultstring);
            $c->session->{prov_error} = $@->faultcode;
        } else {
            $c->log->error("***Provisioning::_auth_user failed to auth user '$$user{username}\@$$user{domain}': $@.");
            $c->session->{prov_error} = 'Server.Internal';
        }
        return;
    }

    return 1;
}

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

=back

=head1 SEE ALSO

Sipwise::Provisioning::Voip

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>
Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The Sipwise::Provisioning module is Copyright (c) 2007-2010 Sipwise
GmbH, Austria. All rights reserved.

=cut

# over and out
1;
