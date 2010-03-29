package csc::Controller::desktop;

use strict;
use warnings;
use base 'Catalyst::Controller';

use csc::Utils;

=head1 NAME

csc::Controller::desktop - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***desktop::index called');
    $c->stash->{template} = 'tt/desktop.tt';

    return 1 unless $c->model('Provisioning')->get_usr_preferences($c);
    return 1 unless $c->model('Provisioning')->get_call_list($c);
    return 1 unless $c->model('Provisioning')->get_voicemails_by_limit($c);

    if($c->session->{user}{admin}) {
        my $acct;
        return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_voip_account_by_id',
                                                             { id => $c->session->{user}{data}{account_id} },
                                                             \$acct
                                                            );
        my $bilprof = {};
        if(eval { defined $$acct{billing_profile} }) {
            return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_billing_profile',
                                                                 { handle => $$acct{billing_profile} },
                                                                 \$bilprof
                                                                );
        }
        return 1 unless $c->model('Provisioning')->get_account_balance($c);
        # set cash balance if account or billing profile depends on or has some credits
        if($$bilprof{data}{prepaid}
           or $$bilprof{data}{interval_free_cash}
           or $c->session->{user}{account}{cash_balance})
        {
            $c->stash->{subscriber}{account}{cash_balance} = sprintf "%.2f", $c->session->{user}{account}{cash_balance} / 100;
            $c->stash->{show_cash_balance} = 1;
        }
        # set free time balance if account or billing profile has some free time
        if($$bilprof{data}{interval_free_time}
           or $c->session->{user}{account}{free_time_balance})
        {
            $c->stash->{subscriber}{account}{free_time_balance} = int($c->session->{user}{account}{free_time_balance} / 60);
            $c->stash->{show_free_time_balance} = 1;
        }
    }

    $c->stash->{subscriber}{call_list} = csc::Utils::prepare_call_list($c, $c->session->{user}{call_list}, 0)
        if @{$c->session->{user}{call_list}};
    delete $c->session->{user}{call_list} if exists $c->session->{user}{call_list};
    $c->stash->{subscriber}{fw}{active} = 1
        if defined $c->session->{user}{preferences}{cfu}
           or defined $c->session->{user}{preferences}{cfb}
           or defined $c->session->{user}{preferences}{cfna}
           or defined $c->session->{user}{preferences}{cft};
    $c->stash->{subscriber}{contacts} = 
        $c->model('Provisioning')->get_registered_contacts($c);

    $c->stash->{subscriber}{voicemail_list} = csc::Utils::prepare_call_list($c, $c->session->{user}{voicemail_list}, 0, undef, 1)
        if @{$c->session->{user}{voicemail_list}};
    delete $c->stash->{subscriber}{voicemail_list}
        unless ref $c->stash->{subscriber}{voicemail_list} eq 'ARRAY'
               and @{$c->stash->{subscriber}{voicemail_list}};
    delete $c->session->{user}{voicemail_list} if exists $c->session->{user}{voicemail_list};

    return 1 unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber_reminder',
                                                         { username => $c->session->{user}{username},
                                                           domain   => $c->session->{user}{domain},
                                                         },
                                                         \$c->stash->{subscriber}{reminder}
                                                        );

    return;
}

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The desktop controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
