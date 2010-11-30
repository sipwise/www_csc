package csc::Controller::autoconf;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

use Data::Dumper;

=head1 NAME

csc::Controller::autoconf - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub init : Local {
    my ( $self, $c ) = @_;
    my %messages;

    $c->log->debug('***autoconf::init called');

    my $mac = $c->request->params->{mac};
    my $conf;
    
    $c->log->debug('***autoconf::init fetching config for mac '.$mac);
    if(defined $mac)
    {
        $mac = lc($mac);
        
		if($c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_options_bymac', 
												{ mac => $mac }, \$conf) &&  $conf->{autoconf} == 1)
        {
			$c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber_by_id', 
												{ subscriber_id => $conf->{unit}{subscriber_id}},
											   	\$c->session->{user}{data});
            my $data = $c->session->{user}{data};
            my $pass = $c->session->{user}{data}{password};

            my $user = $c->model('Provisioning')->_get_user($c, $c->session->{user}{data}{username}.'@'.$c->session->{user}{data}{domain});
            if($user)
            {
                $c->session->{user} = $user;
                $c->set_authenticated($c->session->{user});
                $c->session->{user}{data} = $data;
            }
            $c->model('Provisioning')->get_usr_preferences($c);
            $c->session->{user}{data}{password} = $pass;

	    
            if(defined $c->session->{user}{preferences}{has_extension} && 
                    $c->session->{user}{preferences}{has_extension} eq '1')
            {
                $c->stash->{subscribers} = $self->_load_subscribers($c, \%messages);

                my %groups = ();
                my @extensions = ();
                $c->stash->{ext_pattern} = "";
                if(defined $c->stash->{subscribers})
                {
                    foreach my $ext (@{@{$c->stash->{subscribers}}[0]->{extensions}})
                    {
		    	if(defined $conf->{unit}{fxs1_subscriber_id} && 
				$ext->{subscriber_id} == $conf->{unit}{fxs1_subscriber_id})
			{
				$c->stash->{ext_fxs1} = $ext->{preferences}{extension};
				$c->stash->{name_fxs1} = $ext->{autoconf_displayname};
			}
		    	elsif(defined $conf->{unit}{fxs2_subscriber_id} && 
				$ext->{subscriber_id} == $conf->{unit}{fxs2_subscriber_id})
			{
				$c->stash->{ext_fxs2} = $ext->{preferences}{extension};
				$c->stash->{name_fxs2} = $ext->{autoconf_displayname};
			}
                        next unless(defined $ext->{unit});
                        if(defined $ext->{autoconf_group_id} && int($ext->{autoconf_group_id}) > 0)
                        {
                            foreach my $grp(@{@{$c->stash->{subscribers}}[0]->{groups}})
                            {
                                if($ext->{autoconf_group_id} == $grp->{id})
                                {
                                    if(exists $groups{$grp->{ext}})
                                    {
                                        my $tmp = $groups{$grp->{ext}};
                                        push @$tmp, $ext->{preferences}{extension};
                                    }
                                    else
                                    {
                                        my @tmp = ($ext->{preferences}{extension});
                                        $groups{$grp->{ext}} = \@tmp;
                                    }
                                }
                            }
                        }
                        push @extensions, $ext->{preferences}{extension};
                    }
                } 


                $c->stash->{ext_pattern} = "";
			    foreach my $k(keys %groups)
    			{
	    				$c->stash->{ext_pattern} .= '*'.$k.':';
		    			foreach my $e(@{$groups{$k}})
			    		{
				    			$c->stash->{ext_pattern} .= $e.',';
					    }
    					$c->stash->{ext_pattern} .= 'hunt=ne;15;0,cfwd=0|';
	    		}

                @extensions = sort {int($b) <=> int($a)} @extensions;
                foreach my $ext(@extensions)
                {
                    $c->stash->{ext_pattern} .= '*' . $ext . ":" . $ext . "|";
                }
                if(@extensions)
                {
                    $c->stash->{ext_pattern} .= $extensions[$#extensions];
                }
            }


    		$c->log->error('***autoconf::init ext_pattern='.$c->stash->{ext_pattern});


            $c->stash->{ext_user} = $c->session->{user}{data}{username};
            $c->stash->{ext_password} = "";

            if(defined $c->session->{user}{preferences}{base_cli})
            {
				my $base_cli = $c->session->{user}{preferences}{base_cli};
                $c->stash->{ext_cli} = $base_cli . $c->session->{user}{preferences}{extension};
                $c->stash->{ext_mwi_id} = '1'.$c->stash->{ext_cli};
            }
            else
            {
                $c->stash->{ext_cli} = $c->session->{user}{data}{cc} . $c->session->{user}{data}{ac} . $c->session->{user}{data}{sn};
            }

			# for phones with a parent, set the ext_ext parameter
			if(defined $c->session->{user}{preferences}{extension})
			{
				$c->stash->{ext_ext} = $c->session->{user}{preferences}{extension};
			}
			else
			{
				$c->stash->{ext_ext} = '';
			}

			# set display name if given
			if(defined $c->session->{user}{data}{autoconf_displayname})
			{
				$c->stash->{ext_name} = $c->session->{user}{data}{autoconf_displayname};
			}
			else
			{
				$c->stash->{ext_name} = '';
			}

            my $opts = $conf->{options};
            foreach my $o(@$opts)
            {
                $o->{value} =
                    $self->_fix_replacement_vars($c, $o->{value});
            }

            $c->stash->{current_view} = 'Plain';
            $c->stash->{content} = '';

            $self->_write_xml($c, $conf);
			return;
        }
    }

    # on error:
    $c->response->redirect($c->uri_for('/'));
}

sub _load_subscribers : Private
{
    my ($self, $c, $m) = @_;
    
    my %subscribers;
    return undef unless $c->model('Provisioning')->get_voip_account_subscribers($c);
    foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
        if($$subscriber{preferences}{base_cli}) {
            push @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}}, $subscriber;
            #TODO: fixme, this is terrible inefficient
            @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}} =
                sort {$a->{preferences}{extension} cmp $b->{preferences}{extension}}
                     @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}};

                my $tmpext = $subscriber->{preferences}{base_cli} . $subscriber->{preferences}{extension};
                return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                    { 
                        username => $subscriber->{username},
                        domain => $c->session->{user}{domain},
                        check_fxs => 1
                    }, 
                    \$subscriber->{unit});
        } elsif($$subscriber{sn}) {
            my $tmp_num = $$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn};
            $$subscriber{extensions} = $subscribers{$tmp_num}{extensions}
                if exists $subscribers{$tmp_num};
            $subscribers{$tmp_num} = $subscriber;

            return undef unless $c->model('Provisioning')->call_prov($c, 'voip', 'get_autoconf_unit', 
                { 
                    username => $subscriber->{username},
                    domain => $c->session->{user}{domain},
                },
                \$c->stash->{unit});
        } else {
            #TODO: subscribers without number?
            $c->log->error('***account::subscriber: subscriber without E.164 number found: '.
                           $$subscriber{username} .'@'. $$subscriber{domain});
            return undef;
        }
    }

    if(defined $c->stash->{unit})
    {
        my $sid1 = $c->stash->{unit}{fxs1_subscriber_id};
        my $sid2 = $c->stash->{unit}{fxs2_subscriber_id};
        foreach my $sub (values %subscribers)
        {
            foreach my $ext (@{$sub->{extensions}})
            {
                if(defined $sid1 && $ext->{subscriber_id} == $sid1)
                {
                    $c->stash->{unit}{fxs1_subscriber_ext} = $ext->{preferences}{extension};
                    $c->stash->{unit}{fxs1_subscriber_name} = $ext->{autoconf_displayname};
                }
                elsif(defined $sid2 && $ext->{subscriber_id} == $sid2)
                {
                    $c->stash->{unit}{fxs2_subscriber_ext} = $ext->{preferences}{extension};
                    $c->stash->{unit}{fxs2_subscriber_name} = $ext->{autoconf_displayname};
                }
            }
        }
    }

    return [sort {$a->{preferences}{extension} <=> $b->{preferences}{extension}} values %subscribers];
}

sub _write_xml
{
    my ($self, $c, $conf) = @_;

    $c->stash->{content_type} = 'text/xml';
    $c->stash->{content} .= "<?xml version=\'1.0\'?>\n";
    $c->stash->{content} .= "<flat-profile>\n";

    my $opts = $conf->{options};
    foreach my $o(@$opts)
    {
        $c->stash->{content} .= "  <".$o->{name}.">".$o->{value}."</".$o->{name}.">\n"
    }
    
    $c->stash->{content} .= "</flat-profile>";
}

sub _write_flat
{
    my ($self, $c, $conf) = @_;
    
    $c->stash->{content_type} = 'text/plain';
                
    $c->log->error('***autoconf::_write_flat: TODO: NOT IMPLEMENTED YET!');
    $c->stash->{content} = "NOT IMPLEMENTED YET\n";
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    if(defined $c->stash->{current_view} and 
            ($c->stash->{current_view} eq 'Binary' || $c->stash->{current_view} eq 'Plain')) {
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

sub _fix_replacement_vars
{
    my ($self, $c, $var) = @_;
    
    my %patterns = (
        '^\$SIP_USER$' => $c->session->{user}{data}{username},
        '^\$SIP_DOMAIN$' => $c->session->{user}{data}{domain},
        '^\$SIP_PASSWORD$' => defined($c->session->{user}{data}{password}) ? $c->session->{user}{data}{password} : '',
        '^\$SIP_CLI$' => defined($c->session->{user}{data}{ac}) ? '0'. $c->session->{user}{data}{ac} . $c->session->{user}{data}{sn} : '',
        '^\$SIP_SPA9K_EXT$' => $c->stash->{ext_pattern},
        '^\$SIP_FXS1_EXT$' => $c->stash->{ext_fxs1},
        '^\$SIP_FXS1_NAME$' => $c->stash->{name_fxs1},
        '^\$SIP_FXS2_EXT$' => $c->stash->{ext_fxs2},
        '^\$SIP_FXS2_NAME$' => $c->stash->{name_fxs2},
        '^\$SIP_USER_EXT$' => $c->stash->{ext_user},
        '^\$SIP_PASSWORD_EXT$' => $c->stash->{ext_password},
        '^\$SIP_CLI_EXT$' => $c->stash->{ext_cli},
        '^\$SIP_EXT_EXT$' => $c->stash->{ext_ext},
        '^\$SIP_EXT_NAME$' => $c->stash->{ext_name},
        '^\$SIP_MWI_ID$' => $c->stash->{ext_mwi_id},
    );

    foreach my $k(keys %patterns)
    {
        if($var =~ /$k/)
        {
            return $patterns{$k};
        }
    }
    return $var;
}

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Andreas Granig <agranig@sipwise.com>

=head1 COPYRIGHT

The autoconf controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. You should have received a copy of the licences terms together
with the software.

=cut

1;
