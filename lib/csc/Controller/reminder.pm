package csc::Controller::reminder;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

=head1 NAME

csc::Controller::reminder - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays the reminder settings for a subscriber.

=cut

sub index : Private {
    my ( $self, $c, $preferences ) = @_;

    $c->log->debug('***reminder::index called');
    $c->stash->{template} = 'tt/reminder.tt';

    return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_voip_account_subscriber',
                                                         { id       => $c->session->{user}{account_id},
                                                           username => $c->session->{user}{username},
                                                           domain   => $c->session->{user}{domain},
                                                         },
                                                         \$c->session->{user}{data}
                                                        );
    return 1 unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber_preferences',
                                                         { username => $c->session->{user}{username},
                                                           domain   => $c->session->{user}{domain},
                                                         },
                                                         \$c->session->{user}{preferences}
                                                        );

    if(defined $preferences and ref $preferences eq 'HASH') {
        for(keys %$preferences) {
            $c->session->{user}{reminder}{$_} = $$preferences{$_};
        }
    } else {
        unless($c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber_reminder',
                                                    { username => $c->session->{user}{username},
                                                      domain   => $c->session->{user}{domain},
                                                    },
                                                    \$c->session->{user}{reminder}
                                                   )) {
            return 1;
        }
    }

    $c->stash->{subscriber} = $c->session->{user};

    $c->stash->{subscriber}{active_number} = csc::Utils::get_active_number_string($c);
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

}

=head2 save

Changes the reminder settings for a subscriber.

=cut

sub save : Local {
    my ( $self, $c ) = @_;
    my (%preferences, %messages);
    	
    $preferences{time} = $c->request->params->{time};
    if(defined $preferences{time} and $preferences{time} !~ /^\d\d?:\d\d?$/) {
        $messages{time} = 'Client.Syntax.MalformedReminderTime';
    }
    $preferences{recur} = $c->request->params->{recur} || 'never';

    unless(keys %messages) {
        if($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_reminder',
                                                { username => $c->session->{user}{username},
                                                  domain   => $c->session->{user}{domain},
                                                  data     => \%preferences
                                                },
                                                undef
                                               ))
        {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
            $c->session->{messages} = \%messages;
            $c->response->redirect('/reminder');
            return;
        }
    } else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
    }

    $c->session->{messages} = \%messages;
    $self->index($c, \%preferences);
}


=head1 BUGS AND LIMITATIONS

=over

=item none.

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The reminder controller is Copyright (c) 2010 Sipwise GmbH, Austria. You
should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
