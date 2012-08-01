package csc::Controller::fax;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;
use Data::Dumper;

sub base :Chained('/') PathPrefix CaptureArgs(0) {
    my ($self, $c) = @_;
    return unless ($c->stash->{subscriber} = $c->forward('_load_subscriber'));
    $c->stash->{filetypes} = [qw/PS PDF PDF14 TIFF/];
}

sub view_preferences : Chained('base') PathPart('view') Args(0) {
    my ($self, $c) = @_;
    return unless ($c->stash->{fax_preferences} = $c->forward ('_load_fax_preferences'));
    $c->stash->{template} = 'tt/fax.tt';
    $c->stash->{mode} = 'view';
}

sub edit_preferences : Chained('base') PathPart('edit') Args(0) {
    my ($self, $c) = @_;
    return unless ($c->stash->{fax_preferences} = $c->forward ('_load_fax_preferences'));
    $c->stash->{template} = 'tt/fax.tt';
    $c->stash->{mode} = 'edit';
}

sub save_preferences : Chained('base') PathPart('save') Args(0) {
    my ($self, $c) = @_;

    my $messages;
    my $password = undef;
    
    if (defined $c->req->params->{password}) {
        if (defined $c->req->params->{password2}) {
            if ($c->req->params->{password} eq $c->req->params->{password2}) {
                $password = $c->req->params->{password};
            } else {
                $c->session->{messages}->{pwerr} = 'Client.Voip.PassNoMatch';
            }
        } else {
            $c->session->{messages}->{pwerr} = 'Client.Voip.MissingPass2';
        }
    }

    my $preferences = {
        name        => $c->req->params->{name},
        active      => $c->req->params->{active}      eq 'on' ? 1 : 0,
        send_status => $c->req->params->{send_status} eq 'on' ? 1 : 0,
        send_copy   => $c->req->params->{send_copy}   eq 'on' ? 1 : 0,
    };

    # only if given
    $preferences->{password} = $password if (defined $password);

    my $i = 0;
    my $count = scalar @{$c->req->params->{destination}};
    
    ($c->req->params->{destination}->[$count - 1] eq '') and $count--; # this would be the 'add-line'

    for (my $i = 0; $i < $count; $i++) {
        push @{ $preferences->{destinations} }, {
            destination => $c->req->params->{destination}->[$i],
            filetype    => $c->req->params->{filetype}->[$i],
            # checkboxes mustn't be present if not checked
            cc          => $c->req->params->{"cc_$i"}       eq 'on' ? 1 : 0,
            incoming    => $c->req->params->{"incoming_$i"} eq 'on' ? 1 : 0,
            outgoing    => $c->req->params->{"outgoing_$i"} eq 'on' ? 1 : 0,
            status      => $c->req->params->{"status_$i"}   eq 'on' ? 1 : 0,
        } 
        # remove from %$preferences if that delete-button was clicked
        unless $c->req->params->{delete_destination} eq $i;
    }


    if ($c->session->{messages}) {
        $c->session->{messages}->{toperr} = 'Client.Voip.InputErrorFound';
        $c->response->redirect($c->uri_for ('edit'));
    }
    else {
        if ($c->model('Provisioning')->call_prov( $c, 'voip', 'set_subscriber_fax_preferences',
            { username => $c->stash->{subscriber}->{username},
              domain =>   $c->stash->{subscriber}->{domain},
              preferences => $preferences
            },
            undef,
        )) {
            $c->session->{messages}->{topmsg} = 'Server.Voip.SavedSettings';
            $c->response->redirect($c->uri_for ('view'));
        } else {
            $c->session->{messages}->{toperr} = 'Client.Voip.InputErrorFound';
            $c->response->redirect($c->uri_for ('edit'));
        }
    }
}

sub _load_subscriber :Private {
    my ( $self, $c ) = @_;

    my $subscriber;

    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_voip_account_subscriber_by_id',
        { subscriber_id => $c->session->{user}->{data}->{subscriber_id} },
        \$subscriber,
    );
    
    $subscriber->{active_number} = csc::Utils::get_active_number_string($c);
    return $subscriber;
}

sub _load_fax_preferences :Private {
    my ( $self, $c ) = @_;

    my $prefs;
    return unless $c->model('Provisioning')->call_prov( $c, 'voip', 'get_subscriber_fax_preferences',
        { username => $c->stash->{subscriber}->{username},
          domain =>   $c->stash->{subscriber}->{domain},
        },
        \$prefs,
    );
    
    delete $prefs->{password};
    return $prefs;
}

1;
