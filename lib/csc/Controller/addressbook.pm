package csc::Controller::addressbook;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::addressbook - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***addressbook::index called');
    $c->stash->{template} = 'tt/addressbook.tt';

    return 1 unless $c->model('Provisioning')->get_usr_preferences($c);

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    unless($c->model('Provisioning')->get_formatted_contacts($c)) {
        delete $c->session->{user}{contacts} if exists $c->session->{user}{contacts};
        return 1;
    }

    my @display_contacts;
    my $bg = '';

    my $charsel = $c->request->params->{charsel};

    my $detail = $c->request->params->{detail};
    if(defined $detail and length $detail) {
        $charsel = $c->session->{contact_charsel};
        $c->stash->{detail} = $detail;
    }
    if(defined $charsel and length $charsel) {
        $c->stash->{docharsel} = 1;
        $c->stash->{charsel} = $charsel;
        $c->session->{contact_charsel} = $charsel;
    } else {
        $c->session->{contact_charsel} = undef;
    }

    $c->session->{contact_sortsel} = 'firstname' unless $c->session->{contact_sortsel};
    my $sortsel = $c->request->params->{sortsel};
    $c->session->{contact_sortsel} = $sortsel if defined $sortsel;
    $c->stash->{sortsel} = $c->session->{contact_sortsel};

    my $filter = $c->request->params->{filter};
    $c->session->{contact_filter} = $filter if defined $filter;
    $c->stash->{filter} = $c->session->{contact_filter};
    $filter = $c->session->{contact_filter};

    foreach my $contact (sort {$a->{$c->session->{contact_sortsel}} cmp $b->{$c->session->{contact_sortsel}}}
                              values %{$c->session->{user}{contacts}})
    {
        if($c->session->{contact_filter}) {
            next unless grep /$filter/i, @$contact{keys %$contact};
        }
        my $index = uc substr $$contact{$c->session->{contact_sortsel}}, 0, 1;
        if(@display_contacts and $display_contacts[-1]{index} eq $index) {
            $$contact{background} = $bg ? '' : 'alt';
            push @{$display_contacts[-1]{contacts}}, $contact;
        } else {
            $$contact{background} = 'alt';
            $bg = '';
            push @display_contacts, { index => $index, contacts => [($contact)] };
        }
        $bg = !$bg;
    }

    $c->stash->{subscriber}{contacts} = \@display_contacts;
}

sub edit : Local {
    my ( $self, $c, $contact ) = @_;

    $c->log->debug('***addressbook::edit called');
    $c->stash->{template} = 'tt/addressedit.tt';

    $c->stash->{subscriber}{active_number} = '0'. $c->session->{user}{data}{ac} .' '. $c->session->{user}{data}{sn};
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    my $id = $c->request->params->{addrbook_id};
    if($id) {
        foreach my $tmpcontact (values %{$c->session->{user}{contacts}}) {
            if($$tmpcontact{id} == $id) {
                $contact = $tmpcontact;
                last;
            }
        }
    }

    $c->stash->{contact} = $contact;
}

sub save : Local {
    my ( $self, $c) = @_;

    $c->log->debug('***addressbook::save called');
    my (%contact, %refill, %messages);

    $contact{firstname} = $c->request->params->{firstname};
    $contact{lastname} = $c->request->params->{lastname};
    unless(length $contact{firstname} or length $contact{lastname}) {
        $messages{name} = 'Client.Voip.MissingName';
    }
    $contact{company} = $c->request->params->{company};

    $contact{homephonenumber} = $c->request->params->{homephonenumber};
    $contact{phonenumber} = $c->request->params->{phonenumber};
    $contact{mobilenumber} = $c->request->params->{mobilenumber};
    $contact{faxnumber} = $c->request->params->{faxnumber};

    $contact{email} = $c->request->params->{email};
    $contact{homepage} = $c->request->params->{homepage};
    $contact{homepage} = 'http://'.$contact{homepage} if defined $contact{homepage} and length $contact{homepage}
                                                         and $contact{homepage} !~ m#^\w+://#i;

    %refill = %contact;

    my $user_cc = $c->session->{user}{data}{cc};

    for(qw(homephonenumber phonenumber mobilenumber faxnumber)) {
        if(defined $contact{$_} and length $contact{$_}) {
            $messages{$_} = 'Client.Voip.MalformedNumber'
                unless $contact{$_} =~ /^\+[1-9][0-9]+$/
                    or $contact{$_} =~ /^00[1-9][0-9]+$/
                    or $contact{$_} =~ /^0[1-9][0-9]+$/
                    or $contact{$_} =~ /^[1-9][0-9]+$/;
            if($contact{$_} =~ /^\+/ or $contact{$_} =~ s/^00/+/) {
            } elsif($contact{$_} =~ s/^0/+$user_cc/) {
            } else {
                $contact{$_} = '+'. $user_cc . $c->session->{user}{data}{ac} . $contact{$_};
            }
        } else {
            $contact{$_} = undef;
        }
    }

    unless(keys %messages) {
        if($c->request->params->{id}) {
            if($c->model('Provisioning')->update_contact($c, $c->request->params->{id}, \%contact)) {
                $messages{topmsg} = 'Server.Voip.SavedContact';
            }
        } else {
            if($c->model('Provisioning')->create_contact($c, \%contact)) {
                $messages{topmsg} = 'Server.Voip.SavedContact';
            }
        }
    } else {
        $messages{toperr} = 'Client.Voip.InputErrorFound';
        $c->session->{messages} = \%messages;
        $refill{id} = $c->request->params->{id};
        $self->edit($c, \%refill);
        return;
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect('/addressbook');
}

sub delete : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***addressbook::delete called');
    my %messages;

    my $id = $c->request->params->{addrbook_id};
    if($id) {
        if($c->model('Provisioning')->delete_contact($c, $id)) {
            $messages{topmsg} = 'Server.Voip.RemovedContact';
        }
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect('/addressbook');
}

=head1 BUGS AND LIMITATIONS

=over

=item - none so far

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The addressbook controller is Copyright (c) 2007 Sipwise GmbH, Austria.
All rights reserved.

=cut

# over and out
1;
