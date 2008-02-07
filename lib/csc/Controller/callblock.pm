package csc::Controller::callblock;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::callblock - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c, $preferences ) = @_;

    if(defined $preferences and ref $preferences eq 'HASH') {
        $c->session->{user}{preferences} = $preferences;
        $c->stash->{refill} = $$preferences{refill};
    } else {
        unless($c->model('Provisioning')->get_usr_preferences($c)) {
            $c->stash->{template} = 'tt/callblock.tt';
            return 1;
        }
    }

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    my $subscriber_cc = $c->session->{user}{data}{cc};

    if(defined $c->session->{user}{preferences}{block_in_mode}
       and $c->session->{user}{preferences}{block_in_mode})
    {
        $c->stash->{subscriber}{blk}{inmode1_checked} = 'checked="checked"';
    } else {
        $c->stash->{subscriber}{blk}{inmode0_checked} = 'checked="checked"';
    }

    if(defined $c->session->{user}{preferences}{block_in_list}) {
        my $block_in_list = ref $c->session->{user}{preferences}{block_in_list} ? $c->session->{user}{preferences}{block_in_list}
                                                                                : [ $c->session->{user}{preferences}{block_in_list} ];
        my @block_in_list_to_sort;
        foreach my $blockentry (@$block_in_list) {
            my $active = $blockentry =~ s/^#// ? 0 : 1;
            $blockentry =~ s/^$subscriber_cc/0/;
            $blockentry =~ s/^([1-9])/00$1/;
            push @block_in_list_to_sort, { entry => $blockentry, active => $active };
        }
        my $bg = '';
        my $i = 1;
        foreach my $blockentry (sort {$a->{entry} cmp $b->{entry}} @block_in_list_to_sort) {
            push @{$c->stash->{subscriber}{block_in_list}}, { number     => $$blockentry{entry},
                                                              background => $bg ? '' : 'alt',
                                                              id         => $i++,
                                                              active     => $$blockentry{active},
                                                            };
            $bg = !$bg;
        }
    }
    if(defined $c->session->{user}{preferences}{block_in_clir}
       and $c->session->{user}{preferences}{block_in_clir})
    {
        push @{$c->stash->{subscriber}{block_in_list}}, { number     => 'anonymous',
                                                          background => $#{$c->stash->{subscriber}{block_in_list}} % 2 ? 'alt' : '',
                                                          id         => $#{$c->stash->{subscriber}{block_in_list}} + 2,
                                                          active     => -1,
                                                        };
    }

    if(defined $c->session->{user}{preferences}{block_out_mode}
       and $c->session->{user}{preferences}{block_out_mode})
    {
        $c->stash->{subscriber}{blk}{outmode1_checked} = 'checked="checked"';
    } else {
        $c->stash->{subscriber}{blk}{outmode0_checked} = 'checked="checked"';
    }

    if(defined $c->session->{user}{preferences}{clir}
       and $c->session->{user}{preferences}{clir})
    {
        $c->stash->{subscriber}{clir} = 1;
    }

    if(defined $c->session->{user}{preferences}{block_out_list}) {
        my $block_out_list = ref $c->session->{user}{preferences}{block_out_list} ? $c->session->{user}{preferences}{block_out_list}
                                                                                  : [ $c->session->{user}{preferences}{block_out_list} ];
        my @block_out_list_to_sort;
        foreach my $blockentry (@$block_out_list) {
            my $active = $blockentry =~ s/^#// ? 0 : 1;
            $blockentry =~ s/^$subscriber_cc/0/;
            $blockentry =~ s/^([1-9])/00$1/;
            push @block_out_list_to_sort, { entry => $blockentry, active => $active };
        }
        my $bg = '';
        my $i = 1;
        foreach my $blockentry (sort { $a->{entry} cmp $b->{entry} } @block_out_list_to_sort) {
            push @{$c->stash->{subscriber}{block_out_list}}, { number     => $$blockentry{entry},
                                                               background => $bg ? '' : 'alt',
                                                               id         => $i++,
                                                               active     => $$blockentry{active},
                                                             };
            $bg = !$bg;
        }
    }

    $c->stash->{template} = 'tt/callblock.tt';
}

sub save : Local {
    my ( $self, $c ) = @_;

    my (%preferences, %messages, %keeppreferences);

    unless($c->model('Provisioning')->get_usr_preferences($c)) {
        $c->stash->{template} = 'tt/callblock.tt';
        return 1;
    }

    # radio buttons for block in mode
    my $inmode = $c->request->params->{block_in_mode};
    if(defined $inmode) {
        $preferences{block_in_mode} = $inmode;
    }

    # input text field to add new entry to block in list
    my $inadd = $c->request->params->{block_in_add};
    if(defined $inadd) {
        $keeppreferences{blockinaddtxt} = $inadd;
        if($inadd =~ /^\+?[?*0-9]+$/) {
            if($inadd =~ /^[1-9]/) {
                $messages{msginadd} = 'Client.Voip.MalformedNumberPattern';
            } elsif($inadd =~ /^0[1-9?*]/) {
                $inadd =~ s/^0/$c->session->{user}{data}{cc}/e;
            }
            $inadd =~ s/^\+/00/;
            $inadd =~ s/^00+//;
            my $blockinlist = $c->session->{user}{preferences}{block_in_list};
            $blockinlist = [] unless defined $blockinlist;
            $blockinlist = [ $blockinlist ] unless ref $blockinlist;
            $preferences{block_in_list} = [ @$blockinlist, $inadd ];
        } elsif(! length $inadd) {
            $preferences{block_in_clir} = 1;
        } else {
            $messages{msginadd} = 'Client.Voip.MalformedNumberPattern';
        }
    }

    # delete link next to entries in block in list
    my $indel = $c->request->params->{block_in_del};
    if(defined $indel) {
        if($indel eq 'anonymous') {
            $preferences{block_in_clir} = undef;
        } else {
            my $blockinlist = $c->session->{user}{preferences}{block_in_list};
            if(defined $blockinlist) {
                $indel =~ s/^00//;
                $indel =~ s/^0/$c->session->{user}{data}{cc}/e;
                $blockinlist = [ $blockinlist ] unless ref $blockinlist;
                if($c->request->params->{block_in_stat}) {
                    $preferences{block_in_list} = [ grep { $_ ne $indel } @$blockinlist ];
                } else {
                    $preferences{block_in_list} = [ grep { $_ ne '#'.$indel } @$blockinlist ];
                }
            }
        }
    }

    # activate/deactivate link next to entries in block in list
    my $inact = $c->request->params->{block_in_act};
    if(defined $inact) {
        my $blockinlist = $c->session->{user}{preferences}{block_in_list};
        if(defined $blockinlist) {
            $inact =~ s/^00//;
            $inact =~ s/^0/$c->session->{user}{data}{cc}/e;
            $blockinlist = [ $blockinlist ] unless ref $blockinlist;
            if($c->request->params->{block_in_stat}) {
                $preferences{block_in_list} = [ grep { $_ ne $inact } @$blockinlist ];
                push @{$preferences{block_in_list}}, '#'.$inact;
            } else {
                $preferences{block_in_list} = [ grep { $_ ne '#'.$inact } @$blockinlist ];
                push @{$preferences{block_in_list}}, $inact;
            }
        }
    }

    # checkbox for CLIR
    my $clir = $c->request->params->{clir};
    if(defined $clir) {
        $preferences{clir} = 1;
    } else {
        $preferences{clir} = undef;
    }

    # radio buttons for block out mode
    my $outmode = $c->request->params->{block_out_mode};
    if(defined $outmode) {
        $preferences{block_out_mode} = $outmode;
    }

    # input text field to add new entry to block out list
    my $outadd = $c->request->params->{block_out_add};
    if(defined $outadd) {
        $keeppreferences{blockoutaddtxt} = $outadd;
        if($outadd =~ /^\+?[?*0-9]+$/) {
            if($outadd =~ /^[1-9]/) {
                $messages{msgoutadd} = 'Client.Voip.MalformedNumberPattern';
            } elsif($outadd =~ /^0[1-9?*]/) {
                $outadd =~ s/^0/$c->session->{user}{data}{cc}/e;
            }
            $outadd =~ s/^\+/00/;
            $outadd =~ s/^00+//;
            my $blockoutlist = $c->session->{user}{preferences}{block_out_list};
            $blockoutlist = [] unless defined $blockoutlist;
            $blockoutlist = [ $blockoutlist ] unless ref $blockoutlist;
            $preferences{block_out_list} = [ @$blockoutlist, $outadd ];
        } else {
            $messages{msgoutadd} = 'Client.Voip.MalformedNumberPattern';
        }
    }

    # delete link next to entries in block out list
    my $outdel = $c->request->params->{block_out_del};
    if(defined $outdel) {
        my $blockoutlist = $c->session->{user}{preferences}{block_out_list};
        if(defined $blockoutlist) {
            $outdel =~ s/^00//;
            $outdel =~ s/^0/$c->session->{user}{data}{cc}/e;
            use Data::Dumper;
            $blockoutlist = [ $blockoutlist ] unless ref $blockoutlist;
            if($c->request->params->{block_out_stat}) {
                $preferences{block_out_list} = [ grep { $_ ne $outdel } @$blockoutlist ];
            } else {
                $preferences{block_out_list} = [ grep { $_ ne '#'.$outdel } @$blockoutlist ];
            }
        }
    }

    # activate/deactivate link next to entries in block out list
    my $outact = $c->request->params->{block_out_act};
    if(defined $outact) {
        my $blockoutlist = $c->session->{user}{preferences}{block_out_list};
        if(defined $blockoutlist) {
            $outact =~ s/^00//;
            $outact =~ s/^0/$c->session->{user}{data}{cc}/e;
            $blockoutlist = [ $blockoutlist ] unless ref $blockoutlist;
            if($c->request->params->{block_out_stat}) {
                $preferences{block_out_list} = [ grep { $_ ne $outact } @$blockoutlist ];
                push @{$preferences{block_out_list}}, '#'.$outact;
            } else {
                $preferences{block_out_list} = [ grep { $_ ne '#'.$outact } @$blockoutlist ];
                push @{$preferences{block_out_list}}, $outact;
            }
        }
    }

    unless(keys %messages or ! keys %preferences) {
        unless($c->model('Provisioning')->set_subscriber_preferences($c, $c->session->{user}{username},
                                                                     $c->session->{user}{domain}, \%preferences))
        {
            %preferences = ();
        } else {
            $messages{topmsg} = 'Server.Voip.SavedSettings';
            if($c->model('Provisioning')->get_usr_preferences($c)) {
                %preferences = %{$c->session->{user}{preferences}};
            }
        }
    } else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
        if($c->model('Provisioning')->get_usr_preferences($c)) {
            %preferences = %{$c->session->{user}{preferences}};
        }
        $preferences{refill} = \%keeppreferences;
    }

    $c->session->{messages} = \%messages;
    $self->index($c, \%preferences);
}

=head1 BUGS AND LIMITATIONS

=over

=item - syntax checks should be improved.

=item - logging should be improved.

=item - error handling should be improved.

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The callblock controller is Copyright (c) 2007 Sipwise GmbH, Austria.
All rights reserved.

=cut

# over and out
1;
