package csc::Utils;
use strict;
use warnings;

use Time::Local;
use POSIX;

# takes a catalyst session with a call list as returned
# by the prov. interface and returns a reference to an
# array (if $classifytime is false) or a hash (if
# $classifytime is true) suited for TT display
sub prepare_call_list {
    my ($c, $call_list, $classifytime, $filter, $only_unseen) = @_;
    my $callentries = $classifytime ? {} : [];

    my @time = localtime time;
    my $tmtdy = timelocal(0,0,0,$time[3],$time[4],$time[5]);

    if(defined $filter and length $filter) {
        $filter =~ s/\*/.*/g;
    } else {
        undef $filter;
    }

    my $user_cc = $c->session->{user}{data}{cc};
    my $b = '';
    my $ccdp = $c->config->{cc_dial_prefix};

    foreach my $call (@$call_list) {
        my %callentry;
        $callentry{background} = $b ? '' : 'alt';

        my @date = localtime $$call{start_time};
        $date[5] += 1900;
        $date[4]++;
        $callentry{date} = sprintf("%02d.%02d.%04d %02d:%02d:%02d", @date[3,4,5,2,1,0]);

        if($$call{duration}) {
            my $duration = ceil($$call{duration});
            while($duration > 59) {
                my $left = sprintf("%02d", $duration % 60);
                $callentry{duration} = ":$left". (defined $callentry{duration} ? $callentry{duration} : '');
                $duration = int($duration / 60);
            }
            $callentry{duration} = defined $callentry{duration} ? sprintf("%02d", $duration) . $callentry{duration}
                                                                : sprintf("00:%02d", $duration);
        } elsif($$call{call_status} eq 'ok') {
            $callentry{duration} = '00:00';
        }

        if(defined $$call{call_fee}) {
            # money is allways returned as a hundredth of whatever currency
            $callentry{call_fee} = sprintf "%.04f", $$call{call_fee}/100;
        } else {
            $callentry{call_fee} = '';
        }

        if(defined $$call{source_user}
           and $$call{source_user} eq $c->session->{user}{username}
           and $$call{source_domain} eq $c->session->{user}{domain})
        {
            if($$call{call_status} eq 'ok') {
                if($$call{call_type} =~ /^cf/) { # any kind of call forwarding
                    $callentry{direction_icon} = 'anruf_cf_small.gif';
                } else {
                    $callentry{direction_icon} = 'anruf_aus_small.gif';
                }
            } else {
                if($$call{call_type} =~ /^cf/) { # any kind of call forwarding
                    $callentry{direction_icon} = 'anruf_cf_err_small.gif';
                } else {
                    $callentry{direction_icon} = 'anruf_aus_err_small.gif';
                }
            }
            if($$call{destination_user} =~ /^\+?\d+$/) {
                my $partner = $$call{destination_user};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
            } elsif($$call{destination_domain} eq $c->config->{voicebox_domain}) {
                $callentry{is_voicebox} = 1;
            } elsif($$call{destination_domain} eq $c->config->{fax2mail_domain}) {
                $callentry{is_fax2mail} = 1;
            } else {
                $callentry{partner} = $$call{destination_user} .'@'. $$call{destination_domain};
            }
            $callentry{partner_number} = $callentry{partner};

        } elsif(defined $$call{destination_user}
                and $$call{destination_user} eq $c->session->{user}{username}
                and $$call{destination_domain} eq $c->session->{user}{domain})
        {
            if($$call{call_status} eq 'ok') {
                $callentry{direction_icon} = 'anruf_ein_small.gif';
            } else {
                $callentry{direction_icon} = 'anruf_ein_err_small.gif';
            }

            if($$call{source_user} eq $c->config->{reminder_user}
               and $$call{source_domain} eq $c->config->{reminder_domain})
            {
                $callentry{is_reminder} = 1;
            }

            if(!defined $$call{source_cli} or !length $$call{source_cli}
               or $$call{source_cli} !~ /^\+?\d+$/)
            {
                if(!defined $$call{source_user} or !length $$call{source_user}) {
                    $callentry{partner} = 'anonym';
                } elsif($$call{source_user} =~ /^\+?\d+$/) {
                    my $partner = $$call{source_user};
                    $partner =~ s/^$ccdp/+/;
                    $partner =~ s/^\+*/+/;
                    $callentry{partner} = $partner;
                } else {
                    $callentry{partner} = $$call{source_user} .'@'. $$call{source_domain};
                }
            } else {
                my $partner = $$call{source_cli};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
            }
            $callentry{partner_number} = $callentry{partner};

        } elsif(defined $$call{callerid}) { # voicemail!
            if($$call{callerid} =~ /^\+?\d+$/) {
                my $partner = $$call{callerid};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
            } else {
                $callentry{partner} = $$call{callerid};
            }
            $callentry{partner_number} = $callentry{partner};
            $callentry{id} = $$call{id};
            $callentry{background} = 'abgehoert'
                unless $$call{unseen};
            $callentry{unseen} = $$call{unseen};
        } else {
            $c->log->error("***Utils::prepare_call_list no match on user in call list");
            next;
        }

        if(exists $c->session->{user}{contacts_for_numbers}{$callentry{partner}}) {
            my $contact = $c->session->{user}{contacts}{$c->session->{user}{contacts_for_numbers}{$callentry{partner}}};
            $callentry{partner} = $$contact{displayname};
            if(defined $$contact{phonenumber} and $$contact{phonenumber} eq $callentry{partner_number}) {
                $callentry{partner_info} = $c->model('Provisioning')->localize('Web.Addressbook.Office');
            } elsif(defined $$contact{homephonenumber} and $$contact{homephonenumber} eq $callentry{partner_number}) {
                $callentry{partner_info} = $c->model('Provisioning')->localize('Web.Addressbook.Home');
            } elsif(defined $$contact{mobilenumber} and $$contact{mobilenumber} eq $callentry{partner_number}) {
                $callentry{partner_info} = $c->model('Provisioning')->localize('Web.Addressbook.Mobile');
            } elsif(defined $$contact{faxnumber} and $$contact{faxnumber} eq $callentry{partner_number}) {
                $callentry{partner_info} = $c->model('Provisioning')->localize('Web.Addressbook.Fax');
            }
        }

        if(defined $filter) {
            next unless $callentry{partner} =~ /$filter/i;
        }
        if(defined $only_unseen and $only_unseen) {
            next unless defined $callentry{unseen} and $callentry{unseen};
        }

        if($classifytime) {
            if($$call{start_time} >= $tmtdy) {
                push @{$$callentries{today}}, \%callentry;
            } elsif($$call{start_time} >= $tmtdy - 86400) {
                push @{$$callentries{yesterday}}, \%callentry;
            } elsif($$call{start_time} >= $tmtdy - 86400 * 6) {
                push @{$$callentries{lastweek}}, \%callentry;
            } else {
                push @{$$callentries{previous}}, \%callentry;
            }
        } else {
            push @$callentries, \%callentry;
        }

        $b = !$b;
    }

    return $callentries;
}

sub get_active_number_string {
    my ($c) = @_;

    if($c->session->{user}{data}{sn}) {
        return '+'. $c->session->{user}{data}{cc} .
               ' '. $c->session->{user}{data}{ac} .
               ' '. $c->session->{user}{data}{sn};
    } else {
        return $c->session->{user}{webusername};
    }
}

sub get_qualified_number_for_subscriber {
    my ($c, $number) = @_;

    my $ccdp = $c->config->{cc_dial_prefix};
    my $acdp = $c->config->{ac_dial_prefix};

    if($number =~ /^\+/ or $number =~ s/^$ccdp/+/) {
        # nothing more to do
    } elsif($number =~ s/^$acdp//) {
        $number = '+'. $c->session->{user}{data}{cc} . $number;
    } else {
        $number = '+' . $c->session->{user}{data}{cc} . $c->session->{user}{data}{ac} . $number;
    }

    return $number;
}

sub normalize_blockentry_for_subscriber {
    my ($c, $entry) = @_;

    my $ccdp = $c->config->{cc_dial_prefix};
    my $acdp = $c->config->{ac_dial_prefix};

    if($entry =~ /^\*/ or $entry =~ /^\?/ or $entry =~ /^\[/) {
        # do nothing
    } elsif($entry =~ s/^\+// or $entry =~ s/^$ccdp//) {
        # nothing more to do
    } elsif($entry =~ s/^$acdp//) {
        $entry = $c->session->{user}{data}{cc} . $entry;
    } else {
        $entry = $c->session->{user}{data}{cc} . $c->session->{user}{data}{ac} . $entry;
    }

    return $entry;
}
sub validate_password{
    my ($c, $opt, $passwd1, $passwd2, $oldpasswd) = @_;
    use Data::Dumper;
    $c->log->debug(Dumper [caller()]);
    $c->log->debug(Dumper [$opt, $passwd1, $passwd2, $oldpasswd]);
    #$opt - possible keys are: no_old, no_second, messages_unified. All three are boolean and default undef.
    #foreach(qw/no_old no_second messages_oldasnew messages_newasold/){
    #    $opt->{$_} //= 0;
    #}
    $opt->{messages_newasold} //= 1;
    my $messages = {
        msgoldpass => [],
        msgpasswd => [],
    };
    my $cfg_passwd = $c->config->{security};
    
    if(!$opt->{no_old} && ( !defined $oldpasswd or length $oldpasswd == 0 ) ) {
        push @{$messages->{msgoldpass}}, 'MissingOldPass';
    }    

    if($cfg_passwd->{password_min_length} && length($passwd1) < $cfg_passwd->{password_min_length}) {
        #Use old  messages where is possible, if other not requested explicitly 
        if( !$opt->{messages_oldasnew} ) {
            if( !defined $passwd1 or length $passwd1 == 0 ) {
                push @{$messages->{msgpasswd}}, 'MissingPass';
            } else {
                push @{$messages->{msgpasswd}}, 'PassLength';
            }
        } else {
            push @{$messages->{msgpasswd}},'password_min_length';
        }
    }
    
    #save old priority of the checking
    if(!$opt->{no_second}) {
        if(!defined $passwd2 or length $passwd2 == 0) {
            push @{$messages->{msgpasswd}}, 'MissingPass2';
        } elsif($passwd1 ne $passwd2) {
            push @{$messages->{msgpasswd}}, 'PassNoMatch';
        }    
    }
    
    if($cfg_passwd->{password_max_length} && length($passwd1) > $cfg_passwd->{password_max_length}) {
        push @{$messages->{msgpasswd}},'password_max_length';
    }
    
    if($cfg_passwd->{password_musthave_lowercase} && $passwd1 !~ /[a-z]/) {
        push @{$messages->{msgpasswd}},'password_musthave_lowercase';
    }
    if($cfg_passwd->{password_musthave_uppercase} && $passwd1 !~ /[A-Z]/) {
        push @{$messages->{msgpasswd}},'password_musthave_uppercase';
    }
    if($cfg_passwd->{password_musthave_digit} && $passwd1 !~ /[0-9]/) {
        push @{$messages->{msgpasswd}},'password_musthave_digit';
    }
    if($cfg_passwd->{password_musthave_specialchar} && $passwd1 !~ /[^0-9a-zA-Z]/) {
        push @{$messages->{msgpasswd}},'password_musthave_specialchar';
    }
    $c->log->debug( Dumper ['messages 1=', $messages] );

    my %messages = map {
        if(@{$messages->{$_}}) {
            my $msg = $messages->{$_}->[0];
            if($opt->{messages_newasold}) {
                $msg =~s/[_\.]+([a-z])/'\.'.uc($1)/gei;
                $msg = ucfirst($msg);
            }
            $_ => 'Client.Voip.'.$msg;
        }else{
            ();
        }
    } keys %$messages;
    $c->log->debug( Dumper ['messages 2=', $messages] );
    return \%messages;
}
# finito, l'amore
1;
