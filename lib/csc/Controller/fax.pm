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

sub f2m_view_preferences : Chained('base') PathPart('fax2mail/view') Args(0) {
    my ($self, $c) = @_;
    return unless ($c->stash->{fax_preferences} = $c->forward ('_load_fax_preferences'));
    $c->stash->{template} = 'tt/fax2mail.tt';
    $c->stash->{mode} = 'view';
}

sub f2m_edit_preferences : Chained('base') PathPart('fax2mail/edit') Args(0) {
    my ($self, $c) = @_;
    return unless ($c->stash->{fax_preferences} = $c->forward ('_load_fax_preferences'));
    $c->stash->{template} = 'tt/fax2mail.tt';
    $c->stash->{mode} = 'edit';
}

sub f2m_save_preferences : Chained('base') PathPart('fax2mail/save') Args(0) {
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

    $preferences->{destinations} = []; # will be ignored by ossbss unless set

    my $idx = 1;
    while (exists $c->req->params->{"destination_$idx"}) {

        # remove from %$preferences if that delete-button was clicked
        if (not exists $c->req->params->{"delete_destination_$idx"} and $c->req->params->{"destination_$idx"} ne '') {
            push @{ $preferences->{destinations} }, {
                destination => $c->req->params->{"destination_$idx"},
                filetype    => $c->req->params->{"filetype_$idx"},
                cc          => $c->req->params->{"cc_$idx"}       eq 'on' ? 1 : 0,
                incoming    => $c->req->params->{"incoming_$idx"} eq 'on' ? 1 : 0,
                outgoing    => $c->req->params->{"outgoing_$idx"} eq 'on' ? 1 : 0,
                status      => $c->req->params->{"status_$idx"}   eq 'on' ? 1 : 0,
            }
        }

        $idx++;
    }

    if ($c->session->{messages}) {
        $c->session->{messages}->{toperr} = 'Client.Voip.InputErrorFound';
        $c->response->redirect($c->uri_for ('fax2mail/edit'));
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
            $c->response->redirect($c->uri_for ('fax2mail/view'));
        } else {
            $c->session->{messages}->{toperr} = 'Client.Voip.InputErrorFound';
            $c->response->redirect($c->uri_for ('fax2mail/edit'));
        }
    }
}

sub wf_view : Chained('base') PathPart('webfax/view') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/webfax.tt';
    $c->stash->{webfax} = $c->session->{webfax};
    delete $c->session->{webfax};
}

sub wf_send : Chained('base') PathPart('webfax/send') Args(0) {
    my ($self, $c) = @_;
    $c->stash->{template} = 'tt/webfax.tt';
    delete $c->session->{webfax};
    my $messages;

    my $ctypes = {
      'application/pdf' => 1,
      'application/x-pdf' => 1,
      'application/postscript' => 1,
      'image/tiff' => 1,
      'text/plain' => 1,
    };

    my $subscriber;
    return unless ($subscriber = $c->forward('_load_subscriber'));

    my $notify = $c->req->params->{notify};
    my $text = $c->req->params->{content} || '';
    my $file = $c->req->upload('sendfile');

    my $destination = $c->req->params->{destination};
    if($destination =~ /^\+?\d+$/) {
      $destination =  csc::Utils::get_qualified_number_for_subscriber(
        $c, $destination);
    }
    my $checkresult;
    unless($c->model('Provisioning')->call_prov($c, 'voip', 'check_E164_number',         { e164number => $destination}, \$checkresult) &&
        $checkresult) 
    {
      $messages->{dsterr} = 'Client.Voip.MalformedNumber';
    }

    my $data = $text; 
    if($data =~ /^$/) {
      $data = $file;
      if(!$data) {
        $messages->{cnterr} = 'Client.Voip.NoFaxData';
      } elsif(!exists($ctypes->{$data->type})) {
        $messages->{cnterr} = 'Client.Voip.InvalidFaxFileType';
      } else {
        $data = $data->slurp;
      }
    }

    my $source = $c->session->{user}{data}{cc}.
                 $c->session->{user}{data}{ac}.
                 $c->session->{user}{data}{sn};
   
    unless($messages) { 
      unless($c->model('Provisioning')->call_prov($c, 'voip', 'send_fax',
          { 
            number => $source,
            destination => $destination,
            data => $data,
            # options => { notification => $notify },
          },
          undef,
      )) {
        $messages->{toperr} = 'Client.Voip.InputErrorFound';
      }
    }

    if($messages) {
      $messages->{toperr} = 'Client.Voip.InputErrorFound';
      $c->session->{webfax}->{destination} = $destination;
      $c->session->{webfax}->{content} = $text;
      $c->session->{webfax}->{notify} = $notify;
    } else {
      #$messages->{topmsg} = 'Client.Voip.FaxQeueued';
      $messages->{topmsg} = 'Server.Voip.SavedSettings';
    }
    $c->session->{messages} = $messages;

    $c->response->redirect($c->uri_for ('webfax/view'));
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
