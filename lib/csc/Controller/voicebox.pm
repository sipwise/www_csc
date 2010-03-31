package csc::Controller::voicebox;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

=head1 NAME

csc::Controller::voicebox - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays stored voicemail recordings for a subscriber.

=cut

# TODO: this doubles a lot of code from calllist.pm
# so maybe this should be outsourced to ../Utils.pm
sub index : Private {
    my ( $self, $c, $preferences) = @_;

    $c->log->debug('***voicebox::index called');
    $c->stash->{template} = 'tt/voicebox.tt';
    my @localized_months = ( "foo" );

    return 1 unless $c->model('Provisioning')->get_usr_preferences($c);

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    my $cts = $c->session->{user}{data}{create_timestamp};
    if($cts =~ s/^(\d{4}-\d\d)-\d\d \d\d:\d\d:\d\d/$1/) {
        my ($cyear, $cmonth) = split /-/, $cts;
        my ($nyear, $nmonth) = (localtime)[5,4];
        $nyear += 1900;
        $nmonth++;

        for(1 .. 12) {
            my $amon = sprintf("%02d", $_);
            push @localized_months, $c->model('Provisioning')->localize($c, "Web.Months.".$amon) || $amon;
        }

        my @selectmonths;

        while($cyear < $nyear) {
            my @yearmon;
            for($cmonth .. 12) {
                my $amon = sprintf("%02d", $_);
                unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
            }
            unshift @selectmonths, { year => $cyear, months => \@yearmon };
            $cmonth = 1;
            $cyear++;
        }

        my @yearmon;
        for($cmonth .. $nmonth) {
            my $amon = sprintf("%02d", $_);
            unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
        }
        unshift @selectmonths, { year => $cyear, months => \@yearmon };

        $c->stash->{subscriber}{selectmonths} = \@selectmonths;
    }

    my $listfilter = $c->request->params->{list_filter};
    if(defined $listfilter) {
        if(length $listfilter) {
            $listfilter =~ s/^\*//;
            $listfilter =~ s/\*$//;
            $c->session->{user}{calls}{filter} = $listfilter;
        } else {
            delete $c->session->{user}{calls}{filter};
            undef $listfilter;
        }
    }

    my @localtime = localtime;

    my ($callmonth, $callyear);
    my $monthselect = $c->request->params->{listmonth};
    if(defined $monthselect and $monthselect =~ /^(\d{4})(\d{2})$/) {
        $callyear = $1;
        $callmonth = $2;
        $listfilter = $c->session->{user}{calls}{filter};
        $c->session->{user}{calls}{callyear} = $callyear;
        $c->session->{user}{calls}{callmonth} = $callmonth;
    } else {
        if($c->session->{keep_list_filter}) {
            $listfilter = $c->session->{user}{calls}{filter};
            $callyear = $c->session->{user}{calls}{callyear} ? $c->session->{user}{calls}{callyear} : $localtime[5] + 1900;
            $callmonth = $c->session->{user}{calls}{callmonth} ? $c->session->{user}{calls}{callmonth} : $localtime[4] + 1;
            delete $c->session->{keep_list_filter};
        } else {
            $callyear = $localtime[5] + 1900;
            $callmonth = $localtime[4] + 1;
            delete $c->session->{user}{calls}{filter};
            delete $c->session->{user}{calls}{start};
            delete $c->session->{user}{calls}{end};
            delete $c->session->{user}{calls}{callyear};
            delete $c->session->{user}{calls}{callmonth};
        }
    }

    my $liststart = $c->request->params->{list_start};
    if(defined $liststart) {
        if(length $liststart) {
            $c->stash->{subscriber}{list_start} = $liststart;
            if($liststart =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{user}{calls}{start} = $liststart;
            } else {
                $liststart = $c->session->{user}{calls}{start};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{user}{calls}{start};
            undef $liststart;
        }
    } else {
        $c->stash->{subscriber}{list_start} = $c->session->{user}{calls}{start};
    }

    my $listend = $c->request->params->{list_end};
    if(defined $listend) {
        if(length $listend) {
            $c->stash->{subscriber}{list_end} = $listend;
            if($listend =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{user}{calls}{end} = $listend;
            } else {
                $listend = $c->session->{user}{calls}{end};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{user}{calls}{end};
            undef $listend;
        }
    } else {
        $c->stash->{subscriber}{list_end} = $c->session->{user}{calls}{end};
    }

    my ($sdate, $edate);
    if(!defined $liststart and !defined $listend) {
        $sdate = $edate = { year => $callyear, month => $callmonth };
        $c->stash->{subscriber}{call_range} = $localized_months[$callmonth] .' '. $callyear;
    } else {
        if(defined $liststart) {
            my ($day, $month, $year) = split /\./, $liststart;
            $sdate = { year => $year, month => $month, day => $day };
            if(defined $listend) {
                $c->stash->{subscriber}{call_range} = "$liststart";
            } else {
                $c->stash->{subscriber}{call_range}
                    = "$liststart - ". sprintf("%02d.%02d.%04d", $localtime[3],
                                                                 $localtime[4] + 1,
                                                                 $localtime[5] + 1900);
            }
        }
        if (defined $listend) {
            my ($day, $month, $year) = split /\./, $listend;
            $edate = { year => $year, month => $month, day => $day };
            if(defined $liststart) {
                $c->stash->{subscriber}{call_range} .= " - $listend";
            } else {
                my $cts = $c->session->{user}{data}{create_timestamp};
                $cts =~ /^(\d{4})-(\d\d)-(\d\d).+/;
                $c->stash->{subscriber}{call_range} = "$3.$2.$1 - $listend";
            }
        }
    }

    unless($c->model('Provisioning')->get_voicemails_by_date($c, $sdate, $edate)) {
        delete $c->session->{user}{voicemail_list} if exists $c->session->{user}{voicemail_list};
        return 1;
    }
    unless($c->model('Provisioning')->get_contacts_for_numbers($c)) {
        delete $c->session->{user}{voicemail_list} if exists $c->session->{user}{voicemail_list};
        return 1;
    }

    if($callyear == (localtime)[5] + 1900
       and $callmonth == (localtime)[4] + 1)
    {
        $c->stash->{subscriber}{voicemail_list} = csc::Utils::prepare_call_list($c, $c->session->{user}{voicemail_list}, 1, $listfilter)
            if @{$c->session->{user}{voicemail_list}};
    } else {
        $c->stash->{subscriber}{voicemail_list}{previous} = csc::Utils::prepare_call_list($c, $c->session->{user}{voicemail_list}, 0, $listfilter)
            if @{$c->session->{user}{voicemail_list}};
        $c->stash->{subscriber}{voicemail_list} = undef
            unless defined $c->stash->{subscriber}{voicemail_list}{previous};
    }

    delete $c->session->{user}{voicemail_list} if exists $c->session->{user}{voicemail_list};

    if(defined $listfilter and length $listfilter) {
        $c->stash->{subscriber}{call_filter} = "*$listfilter*";
        $c->stash->{subscriber}{list_filter} = "$listfilter";
    }
    $c->stash->{subscriber}{list_month} = sprintf("%04d%02d", $callyear, $callmonth);

    if(defined $preferences) {
        $c->stash->{subscriber}{vbox} = $preferences;
    } else {
        return 1 unless $c->model('Provisioning')->get_usr_voicebox_preferences($c);
        $c->stash->{subscriber}{vbox} = $c->session->{user}{voicebox_preferences};
    }
}

=head2 delete

Removes a recording from the server.

=cut

sub delete : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***voicebox::delete called');
    my %messages;

    $c->session->{keep_list_filter} = 1;

    my $id = $c->request->params->{voicemail_id};
    if($id and $c->model('Provisioning')->delete_voicemail($c, $id)) {
        $messages{topmsg} = 'Server.Voip.RemovedVoicemail';
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect('/voicebox');
}

=head2 listen

Tries to stream the recording to the users HTTP client.

=cut

sub listen : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***voicebox::listen called');

    my $id = $c->request->params->{mailid};
    my $vm;
    if($id and $vm = $c->model('Provisioning')->get_voicemail($c, $id)) {
        $c->stash->{current_view} = 'Binary';
        $c->stash->{content_type} = 'audio/x-wav';
        $c->stash->{content} = $$vm{recording};
        return;
    }
    $c->response->redirect('/voicebox');
}

=head2 settings

Changes voicebox settings like PIN and voice2mail address.

=cut

sub settings : Local {
    my ( $self, $c ) = @_;

    my (%messages, %preferences);

    $c->session->{keep_list_filter} = 1;

    $preferences{email} = $c->request->params->{email};
    $messages{msgemail} = 'Client.Syntax.Email'
        unless !defined $preferences{email} or !length $preferences{email}
               or $preferences{email} =~ /^[a-z0-9=+,;_.~'()-]+\@(?:[a-z0-9]+(?:-[a-z0-9]+)*\.)+[a-z]+$/i;

    $preferences{attach} = $c->request->params->{attach};
    $preferences{attach} = defined $preferences{attach} && $preferences{attach} ? 1 : 0;

    $preferences{password} = $c->request->params->{password};
    $messages{msgpassword} = 'Client.Syntax.VoiceBoxPin'
        unless !defined $preferences{password} or !length $preferences{password}
               or $preferences{password} =~ /^\d{4}$/;

    unless(keys %messages) {
        if($c->model('Provisioning')->set_usr_voicebox_preferences($c, \%preferences)) {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect($c->uri_for('/voicebox'));
            return;
        }
    } else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $self->index($c, \%preferences);
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    if(defined $c->stash->{current_view} and $c->stash->{current_view} eq 'Binary') {
        return 1;
    }

    $c->stash->{current_view} = 'TT';
    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->session->{messages}{prov_error} = $c->session->{prov_error};
            delete $c->session->{prov_error};
        }

        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c, $c->session->{messages});
            delete $c->session->{messages};
        }
    }

    $c->stash->{subscriber}{username} = $c->session->{user}{username};

    return 1; # shouldn't matter
}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The voicebox controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. All rights reserved.

=cut

1;
