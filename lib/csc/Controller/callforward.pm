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

    $c->stash->{subscriber}{fw}{active} = 1;
    my $target;

    if(defined $c->session->{user}{preferences}{cfu}) {
        $target = $c->session->{user}{preferences}{cfu};
        $c->stash->{subscriber}{fw}{allways_checked} = 'checked="checked"';

    } elsif(defined $c->session->{user}{preferences}{cfb}
            or defined $c->session->{user}{preferences}{cfna}
            or defined $c->session->{user}{preferences}{cft})
    {
        $c->stash->{subscriber}{fw}{condition_checked} = 'checked="checked"';

        if(defined $c->session->{user}{preferences}{cfb}) {
            $target = $c->session->{user}{preferences}{cfb};
            $c->stash->{subscriber}{fw}{busy_checked} = 'checked="checked"';
        }
        if(defined $c->session->{user}{preferences}{cfna}) {
            $target = $c->session->{user}{preferences}{cfna};
            $c->stash->{subscriber}{fw}{na_checked} = 'checked="checked"';
        } 
        if(defined $c->session->{user}{preferences}{cft}) {
            $target = $c->session->{user}{preferences}{cft};
            $c->stash->{subscriber}{fw}{timeout_checked} = 'checked="checked"';
        }
    } else {
        $c->stash->{subscriber}{fw}{never_checked} = 'checked="checked"';
        $c->stash->{subscriber}{fw}{active} = 0;
    }

    if(defined $target) {
        if($target =~ /voicebox.local$/) {
            $c->stash->{subscriber}{fw}{voicebox_checked} = 'checked="checked"';
        } else {
            $c->stash->{subscriber}{fw}{sipuri} = $target;
            $c->stash->{subscriber}{fw}{sipuri_checked} = 'checked="checked"';
        }
    }

    if(defined $c->session->{user}{preferences}{ringtimeout}) {
        $c->stash->{subscriber}{fw}{ringtimeout} = $c->session->{user}{preferences}{ringtimeout};
    }

    if(defined $c->stash->{subscriber}{fw}{sipuri}
       and length $c->stash->{subscriber}{fw}{sipuri}
       and ! $c->session->{messages}{target})
    {
        $c->stash->{subscriber}{fw}{sipuri} =~  s/^sip://i;
        if($c->stash->{subscriber}{fw}{sipuri} =~ /^\+?\d+\@/) {
            $c->stash->{subscriber}{fw}{sipuri} =~ s/\@.*$//;
        }
        $c->stash->{subscriber}{fw}{sipuri_checked} = 'checked="checked"';
    }

    $c->stash->{template} = 'tt/callforward.tt';
}

=head2 save

Stores call forward settings.

=cut

sub save : Local {
    my ( $self, $c ) = @_;
    my (%preferences, %messages);
    	
    my $fw_target_select = $c->request->params->{fw_target};
    unless($fw_target_select) {
        $messages{target} = 'Client.Voip.MalformedTargetClass';
    }
    my $fw_target;
    if($fw_target_select eq 'sipuri') {
        $fw_target = $c->request->params->{fw_sipuri};

        # normalize, so we can do some checks.
        $fw_target =~ s/^sip://i;
        if($fw_target =~ /^\+?\d+\@[a-z0-9.-]+$/i) {
            $fw_target =~ s/\@.+$//;
        }

        if($fw_target =~ /^\+?\d+$/) {
            $fw_target = csc::Utils::get_qualified_number_for_subscriber($c, $fw_target);
            my $checkresult;
            return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'check_E164_number', $fw_target, \$checkresult);
            $messages{target} = 'Client.Voip.MalformedNumber'
                unless $checkresult;
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+\@[a-z0-9.-]+$/i) {
            $fw_target = 'sip:'. lc $fw_target;
        } elsif($fw_target =~ /^[a-z0-9&=+\$,;?\/_.!~*'()-]+$/) {
            $fw_target = 'sip:'. lc($fw_target) .'@'. $c->session->{user}{domain};
        } else {
            $messages{target} = 'Client.Voip.MalformedTarget';
            $fw_target = $c->request->params->{fw_sipuri};
        }
    } elsif($fw_target_select eq 'voicebox') {
        $fw_target = 'sip:vmu'.$c->session->{user}{data}{cc}.$c->session->{user}{data}{ac}.$c->session->{user}{data}{sn}.'@voicebox.local';
    } else {
        # wtf?
    }

    my $fw_active = $c->request->params->{fw_active};
    $fw_active = '' unless defined $fw_active;
    if($fw_active eq 'no') {
        # clear all forwards
        $preferences{cfu} = undef;
        $preferences{cft} = undef;
        $preferences{cfb} = undef;
        $preferences{cfna} = undef;
        $preferences{ringtimeout} = undef;
        delete $messages{target} if exists $messages{target} and !$fw_target;
    } elsif($fw_active eq 'yes') {
        # forward unconditionally
        $preferences{cfu} = $fw_target;
        $preferences{cft} = undef;
        $preferences{cfb} = undef;
        $preferences{cfna} = undef;
        $preferences{ringtimeout} = undef;
    } elsif($fw_active eq 'conditional') {
        # forward at specified confitions
        $preferences{cfu} = undef;
        $preferences{cft} = undef;
        $preferences{cfb} = undef;
        $preferences{cfna} = undef;
        $preferences{ringtimeout} = undef;
        my $fw_conditions = $c->request->params->{fw_condition};
        if(defined $fw_conditions) {
            $fw_conditions = [ $fw_conditions ] unless ref $fw_conditions;
            foreach my $fw_condition (@$fw_conditions) {
                if($fw_condition eq 'timeout') {
                    $preferences{cft} = $fw_target;
                } elsif($fw_condition eq 'busy') {
                    $preferences{cfb} = $fw_target;
                } elsif($fw_condition eq 'na') {
                    $preferences{cfna} = $fw_target;
                } else {
#                    die "Unknown conditional forward: '$fw_condition'\n";
                }
            }
        }
    } else {
        $messages{condition} = 'Client.Voip.ForwardSelect';
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
