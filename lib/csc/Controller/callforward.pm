package csc::Controller::callforward;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

=head1 NAME

csc::Controller::callforward - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays call forward settings.

=cut

sub index : Private {
    my ( $self, $c, $preferences ) = @_;

    $c->log->debug('***callforward::index called');

    if(defined $preferences and ref $preferences eq 'HASH') {
        for(keys %$preferences) {
            $c->session->{user}{preferences}{$_} = $$preferences{$_};
        }
    } else {
        unless($c->model('Provisioning')->get_usr_preferences($c)) {
            $c->stash->{template} = 'tt/callforward.tt';
            return 1;
        }
    }

    $c->stash->{subscriber}{active_number} = csc::Utils::get_active_number_string($c);
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    my $subscriber_cc = $c->session->{user}{data}{cc};

    $c->stash->{subscriber}{fw}{active} = 0;

    for(qw(cfu cfna cft cfb)) {
        if(defined $c->session->{user}{preferences}{$_}) {
            $c->stash->{subscriber}{fw}{$_} = _parse_forward($c, $c->session->{user}{preferences}{$_});
            $c->stash->{subscriber}{fw}{active} = 1;
        } else {
            $c->stash->{subscriber}{fw}{$_}{disabled_checked} = 'checked="checked"';
        }
    }

    if(defined $c->session->{user}{preferences}{ringtimeout}) {
        $c->stash->{subscriber}{fw}{ringtimeout} = $c->session->{user}{preferences}{ringtimeout};
    }

    $c->stash->{template} = 'tt/callforward.tt';
}

=head2 save

Stores call forward settings.

=cut

sub save : Local {
    my ( $self, $c ) = @_;
    my (%preferences, %messages);
    	
    foreach my $fwtype (qw(cfu cfna cft cfb)) {
        my $fw_target_select = $c->request->params->{$fwtype .'_fw_target'};
        unless($fw_target_select) {
            $messages{$fwtype .'_target'} = 'Client.Voip.MalformedTargetClass';
        }

        if($fw_target_select eq 'disabled') {
            $preferences{$fwtype} = undef;
            next;
        } elsif($fw_target_select eq 'voicebox') {
            $preferences{$fwtype} = 'sip:vmu'.$c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn}.'@'.$c->config->{voicebox_domain};
        } elsif($fw_target_select eq 'fax2mail') {
            $preferences{$fwtype} = 'sip:'.$c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn}.'@'.$c->config->{fax2mail_domain};
        } elsif($fw_target_select eq 'conference') {
            $preferences{$fwtype} = 'sip:conf='.$c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn}.'@'.$c->config->{conference_domain};
        } elsif($fw_target_select eq 'sipuri') {
            my $fw_target;
            $fw_target = $c->request->params->{$fwtype .'_fw_sipuri'};

            # normalize, so we can do some checks.
            $fw_target =~ s/^sip://i;
            if($fw_target =~ /^\+?\d+\@[a-z0-9.-]+$/i) {
                $fw_target =~ s/\@.+$//;
            }

            if($fw_target =~ /^\+?\d+$/) {
                $fw_target = csc::Utils::get_qualified_number_for_subscriber($c, $fw_target);
                my $checkresult;
                return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $fw_target, \$checkresult);
                $messages{$fwtype .'_target'} = 'Client.Voip.MalformedNumber'
                    unless $checkresult;
            } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+$/i) {
                $fw_target = 'sip:'. lc $fw_target;
            } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
                $fw_target = 'sip:'. lc($fw_target) .'@'. $c->session->{user}{domain};
            } else {
                $messages{$fwtype .'_target'} = 'Client.Voip.MalformedTarget';
            }
            $preferences{$fwtype} = $messages{$fwtype .'_target'} ? $c->request->params->{$fwtype .'_fw_sipuri'}
                                                                  : $fw_target;
        } else {
            # wtf?
        }
    }

    if(defined $preferences{cft}) {
        my $fw_ringtimeout = $c->request->params->{fw_ringtimeout};
        $preferences{ringtimeout} = $fw_ringtimeout;
        unless(defined $fw_ringtimeout and length $fw_ringtimeout
           and $fw_ringtimeout =~ /^\d+$/ and $fw_ringtimeout < 301 and $fw_ringtimeout > 4)
        {
            $messages{ringtimeout} = 'Client.Voip.MissingRingtimeout';
        }
    }

    unless(keys %messages) {
        if($c->model('Provisioning')->set_subscriber_preferences($c, $c->session->{user}{username},
                                                                 $c->session->{user}{domain}, \%preferences))
        {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
        }
    } else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $self->index($c, \%preferences);
#    $c->response->redirect($c->uri_for('/callforward'));
}

sub _parse_forward : Private {
    my ($c, $target) = @_;
    my $return;

    if(defined $target and length $target) { # FIXME: "and ! $c->session->{messages}{target}"?
        my $vbdom = $c->config->{voicebox_domain};
        my $fmdom = $c->config->{fax2mail_domain};
        my $confdom = $c->config->{conference_domain};
        if($target =~ /$vbdom$/) {
            $$return{voicebox_checked} = 'checked="checked"';
        } elsif($target =~ /$fmdom$/) {
            $$return{fax2mail_checked} = 'checked="checked"';
        } elsif($target =~ /$confdom$/) {
            $$return{conference_checked} = 'checked="checked"';
        } else {
            $$return{sipuri_checked} = 'checked="checked"';

            $target =~ s/^sip://i;
            $target =~ s/\@.*$// if $target =~ /^\+?\d+\@/;
            if($target =~ /^\+?\d+$/) {
                $$return{sipuri} = csc::Utils::get_qualified_number_for_subscriber($c, $target);
            } else {
                $$return{sipuri} = $target;
            }
        }
        return $return;
    }

    return;
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

The callforward controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. All rights reserved.

=cut

# over and out
1;
