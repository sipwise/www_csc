package csc::Utils;
use strict;
use warnings;

use Time::Local;

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
            my $duration = $$call{duration};
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
            # money is allways returned as euro cents
            $callentry{call_fee} = sprintf "&euro; %.04f", $$call{call_fee}/100;
        } else {
            $callentry{call_fee} = '';
        }

        if(defined $$call{source_user}
           and $$call{source_user} eq $c->session->{user}{username}
           and $$call{source_domain} eq $c->session->{user}{domain})
        {
            if($$call{call_status} eq 'ok') {
                $callentry{direction_icon} = 'anruf_aus_small.gif';
            } else {
                $callentry{direction_icon} = 'anruf_aus_err_small.gif';
            }
            if($$call{destination_user} =~ /^\+?\d+$/) {
                my $partner = $$call{destination_user};
                $partner =~ s/^$ccdp/+/;
                $partner =~ s/^\+*/+/;
                $callentry{partner} = $partner;
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

    return '+'. $c->session->{user}{data}{cc} .
           ' '. $c->session->{user}{data}{ac} .
           ' '. $c->session->{user}{data}{sn};
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

# finito, l'amore
1;
