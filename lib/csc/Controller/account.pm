package csc::Controller::account;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

=head1 NAME

csc::Controller::account - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller for account administration.

=head1 METHODS

=head2 index 

Does a redirect to /account/info or /account/pass depending on whether
display_account_info is set.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::index called');

    if($c->config->{display_account_info}) {
        $c->response->redirect('/account/info');
    } else {
        $c->response->redirect('/account/pass');
    }
}

=head2 info

Displays some basic information about the SIP account and server system
like username, phone number, SIP proxy server and TFTP boot server.

=cut

sub info : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::info called');

    if($c->session->{user}{username} eq 'demonstration' or ! $c->config->{display_account_info}) {
        $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
        return;
    }

    unless($c->model('Provisioning')->get_usr_preferences($c)) {
        $c->stash->{template} = 'tt/account_info.tt';
        return 1;
    }

    $c->stash->{subscriber}{active_number} = csc::Utils::get_active_number_string($c);
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    $c->stash->{sip_domain} = $c->config->{site_domain};
    $c->stash->{sip_server} = $c->config->{sip_server};
    $c->stash->{tftp_server} = $c->config->{tftp_server};

    $c->stash->{template} = 'tt/account_info.tt';
}

=head2 pass

Allows the user to change its webpassword.

=cut

sub pass : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::pass called');

    if($c->session->{user}{username} eq 'demonstration') {
        $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
        return;
    }

    $c->stash->{template} = 'tt/account_pass.tt';
}

=head2 savepass

Changes the password for the user.

=cut

sub savepass : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::savepass called');

    if($c->session->{user}{username} eq 'demonstration') {
        $c->response->redirect($c->uri_for($c->config->{site_config}{default_uri}));
        return;
    }

    unless($c->model('Provisioning')->get_usr_preferences($c)) {
        $c->response->redirect('/account/pass');
        return;
    }

#    $c->stash->{refill}{oldpass} = $oldpass;
#    $c->stash->{refill}{passwd1} = $passwd1;
#    $c->stash->{refill}{passwd2} = $passwd2;

    my ($passwd1,$passwd2,$oldpass) = @{$c->request->params}{qw/newpass1 newpass2 oldpass/};
    my %messages = %{ csc::Utils::validate_password($c, {}, $passwd1, $passwd2, $oldpass) };
    use Data::Dumper;
    $c->log->debug(Dumper \%messages);
    unless(keys %messages) {
        unless($c->model('Provisioning')->call_prov($c, 'voip', 'authenticate_webuser',
                                                    { webusername => $c->session->{user}{webusername},
                                                      domain      => $c->session->{user}{domain},
                                                      webpassword => $oldpass,
                                                    },
                                                   ))
        {
            $c->session->{prov_error} = 'Client.Voip.IncorrectPass';
            $c->response->redirect('/account/pass');
            return;
        }

        my $account;
        unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_voip_account_by_id',
                                                    { id => $c->session->{user}{data}{account_id} },
                                                    \$account,
                                                   ))
        {
            $c->response->redirect('/account/pass');
            return;
        }

        if($c->model('Provisioning')->call_prov($c, 'voip', 'update_webuser_password',
                                                { webusername => $c->session->{user}{webusername},
                                                  domain      => $c->session->{user}{domain},
                                                  webpassword => $passwd1
                                                }
                                               ))
        {
            $messages{topmsg} = 'Server.Voip.SavedPass';
            $c->session->{user}{password} = $passwd1;
        }
    }

    $c->session->{messages} = \%messages;
    $c->response->redirect('/account/pass');
}

=head2 balance

Displays the current account balance and asks the user to top up.

=cut

sub balance : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::balance called');

    unless($c->session->{user}{admin} and $c->config->{payment_features}) {
        $c->response->redirect('/account');
        return;
    }

    unless($c->model('Provisioning')->get_account_balance($c)) {
        $c->stash->{template} = 'tt/account_balance.tt';
        return 1;
    }

    $c->stash->{refill} = $c->session->{refill};
    delete $c->session->{refill};

    $c->stash->{subscriber}{account}{cash_balance} = sprintf "%.2f", $c->session->{user}{account}{cash_balance} / 100;
    $c->stash->{template} = 'tt/account_balance.tt';
}

=head2 setpay

Prepares the payment process and redirects the user to /account/dopay.

=cut

sub setpay : Local {
    my ( $self, $c ) = @_;

    my %messages;

    $c->log->debug('***account::setpay called');

    unless($c->session->{user}{admin} and $c->config->{payment_features}) {
        $c->response->redirect('/account');
        return;
    }

    delete $c->session->{payment}{credit_id} if exists $c->session->{payment}{credit_id};
    delete $c->session->{mpay24} if exists $c->session->{mpay24};
    delete $c->session->{paypal} if exists $c->session->{paypal};

    my $amount = $c->request->params->{amount};
    if($amount !~ /^\d+$/) {
        $messages{msgamount} = 'Client.Billing.MalformedAmount';
        $c->session->{refill}{amount} = $amount;
    }

    my $auto_reload = $c->request->params->{auto_reload};
    my $auto_amount = $c->request->params->{auto_amount};
    if($auto_reload) {
        if($auto_amount !~ /^\d+$/) {
            $messages{msgautoamount} = 'Client.Billing.MalformedAmount';
            $c->session->{refill}{auto_amount} = $auto_amount;
        }
    }

    if(keys %messages) {
        $c->session->{messages} = \%messages;
        $c->response->redirect($c->uri_for('/account/balance'));
        return;
    }

    $c->session->{payment}{auto_reload} = $auto_reload;
    $c->session->{payment}{auto_amount} = $auto_amount;

    unless($c->model('Provisioning')->get_usr_preferences($c)) {
        $c->response->redirect($c->uri_for('/account/balance'));
        return;
    }

    $c->session->{payment}{amount} = $amount * 100;
    $c->response->redirect('/account/dopay');
}

=head2 dopay

Displays the payment forms and errors, if any.

=cut

sub dopay : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay called');

    unless($c->session->{user}{admin} and $c->config->{payment_features}) {
        $c->response->redirect('/account');
        return;
    }

    unless($c->session->{payment}{amount}) {
        $c->response->redirect($c->uri_for('/account/balance'));
        return;
    }

    if(exists $c->session->{mpay24_errors}) {
        $c->stash->{mpay24_errors} = $c->session->{mpay24_errors};
        delete $c->session->{mpay24_errors};
    }

    if(exists $c->session->{refill}) {
        $c->stash->{refill} = $c->session->{refill};
        delete $c->session->{refill};
    }

    $c->stash->{backend} = 'account';
    $c->stash->{template} = 'tt/account_payment.tt';

    $c->stash->{payment} = $c->session->{payment};
    $c->stash->{mpay24_errors}{elv} = $c->session->{elv_error} if $c->session->{elv_error};
    delete $c->session->{elv_error};
}

=head2 dopay_elv

Executes payment via electronic wire transfer. Not yet implemented.

=cut

sub dopay_elv : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay_elv called');

    my $amount = $c->session->{payment}{amount};

    my $accountnumber = $c->request->params->{accountnumber};
    my $bankid = $c->request->params->{bankid};

#    my $tid = $self->_start_transaction($c, 'elv', $amount);
#    unless($tid) {
#        $c->response->redirect('/account/dopay');
#        return;
#    }

    $c->session->{elv_error} = "Bezahlen via Bankeinzug ist noch nicht implementiert!";
    $c->response->redirect('/account/dopay');

    return;
}

=head2 dopay_cc

Implements payment via credit card.

=cut

sub dopay_cc : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay_cc called');

    my $amount = $c->session->{payment}{amount};

    my $cctype = $c->request->params->{cctype};
    my $cardnum = $c->request->params->{cardnum};
    my $cvc = $c->request->params->{cvc};
    my $cc_month = $c->request->params->{cc_month};
    my $cc_year = $c->request->params->{cc_year};
    $cc_year =~ s/^\d\d//;
    my $expiry = sprintf("%02d%02d", $cc_year, $cc_month);

    my $tid = $self->_start_transaction($c, 'cc', $amount);
    unless($tid) {
        $c->response->redirect('/account/dopay');
        return;
    }

    my $rc = $c->model('Mpay24')->accept_cc_payment($c, $tid, $amount, $cctype, $cardnum, $expiry, $cvc);
    if($rc == 1) {
        unless($c->model('Provisioning')->update_account_balance($c, $amount)) {
            # that's not good. money has already been transfered!
            $self->_fail_transaction($c, $tid);
            $c->response->redirect('/account/balance');
            return;
        }
        unless($self->_finish_transaction($c, $tid)) {
            # hmm, what? some logging, at least.
        }
        $c->session->{messages}{topmsg} = 'Server.Billing.Success';
        $c->response->redirect('/account/balance');
    } elsif($rc == 2) {
        unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                    { id   => $tid,
                                                      data => { state => 'transact' },
                                                    },
                                                    undef
                                                   ))
        {
            return;
        }
        $c->response->redirect($c->session->{mpay24}{LOCATION});
        $c->log->info("redirected customer to ". $c->session->{mpay24}{LOCATION});
    } elsif(defined $c->session->{mpay24}) {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{cc} = $c->session->{mpay24}{EXTERNALSTATUS}
                                           || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{cc}{cctype} = $cctype;
        $c->session->{refill}{cc}{cardnum} = $cardnum;
        $c->session->{refill}{cc}{cvc} = $cvc;
        $c->session->{refill}{cc}{cc_month} = $cc_month;
        $c->session->{refill}{cc}{cc_year} = $cc_year;
        $c->response->redirect('/account/dopay#cc');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{cc} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->session->{refill}{cc}{cctype} = $cctype;
        $c->session->{refill}{cc}{cardnum} = $cardnum;
        $c->session->{refill}{cc}{cvc} = $cvc;
        $c->session->{refill}{cc}{cc_month} = $cc_month;
        $c->session->{refill}{cc}{cc_year} = $cc_year;
        $c->response->redirect('/account/dopay#cc');
    }

    return 1;
}

=head2 dopay_eps

Implements payment via the electronic payment system, offered by most
banks via their online banking interfaces.

=cut

sub dopay_eps : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay_eps called');

    my $amount = $c->session->{payment}{amount};

    my $bankname = $c->request->params->{bankname};
    my ($bank, $bankid);
    $bank = $bankname;

    if($bankname =~ /^ARZ_/) {
        ($bank, $bankid) = split /_/, $bankname;
    }

    my $tid = $self->_start_transaction($c, 'eps', $amount);
    unless($tid) {
        $c->response->redirect('/account/dopay');
        return;
    }

    if($c->model('Mpay24')->accept_eps_payment($c, $tid, $amount, $bank, $bankid)) {
        unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                    { id   => $tid,
                                                      data => { state => 'transact' },
                                                    },
                                                    undef
                                                   ))
        {
            return;
        }
        $c->response->redirect($c->session->{mpay24}{LOCATION});
        $c->log->info("redirected customer to ". $c->session->{mpay24}{LOCATION});
    } elsif(defined $c->session->{mpay24}) { # application error
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{eps} = $c->session->{mpay24}{EXTERNALSTATUS}
                                            || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/account/dopay#eps');
    } else { # transport error
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{eps} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/account/dopay#eps');
    }

    return 1;
}

=head2 dopay_maestro

Implements payment via maestro secure code.

=cut

sub dopay_maestro : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay_maestro called');

    my $amount = $c->session->{payment}{amount};

    my $cardnum = $c->request->params->{cardnum};
    my $maestro_month = $c->request->params->{maestro_month};
    my $maestro_year = $c->request->params->{maestro_year};
    $maestro_year =~ s/^\d\d//;
    my $expiry = sprintf("%02d%02d", $maestro_year, $maestro_month);

    my $tid = $self->_start_transaction($c, 'maestro', $amount);
    unless($tid) {
        $c->response->redirect('/account/dopay');
        return;
    }

    if($c->model('Mpay24')->accept_maestro_payment($c, $tid, $amount, $cardnum, $expiry)) {
        unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                    { id   => $tid,
                                                      data => { state => 'transact' },
                                                    },
                                                    undef
                                                   ))
        {
            return;
        }
        $c->response->redirect($c->session->{mpay24}{LOCATION});
        $c->log->info("redirected customer to ". $c->session->{mpay24}{LOCATION});
    } elsif(defined $c->session->{mpay24}) {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{maestro} = $c->session->{mpay24}{EXTERNALSTATUS}
                                                || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{maestro}{cardnum} = $cardnum;
        $c->session->{refill}{maestro}{maestro_month} = $maestro_month;
        $c->session->{refill}{maestro}{maestro_year} = $maestro_year;
        $c->response->redirect('/account/dopay#maestro');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{maestro} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->session->{refill}{maestro}{cardnum} = $cardnum;
        $c->session->{refill}{maestro}{maestro_month} = $maestro_month;
        $c->session->{refill}{maestro}{maestro_year} = $maestro_year;
        $c->response->redirect('/account/dopay#maestro');
    }

    return 1;
}

=head2 dopay_paypal

Implements payment via PayPal.

=cut

sub dopay_paypal : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::dopay_paypal called');

    my $amount = $c->session->{payment}{amount};

    my $tid = $self->_start_transaction($c, 'paypal', $amount);
    unless($tid) {
        $c->response->redirect('/account/dopay');
        return;
    }
    $c->session->{paypal}{tid} = $tid;

    # TODO: specify PayPal return and error url
    unless($c->model('Paypal')->set_express_checkout($c, $amount, 'csc')) {
        $c->response->redirect('/account/dopay');
        return;
    }
    $c->response->redirect($c->config->{paypal_redirecturl} . $c->session->{paypal}{Token});
}

=head2 paidack

Finalizes successful payments via PayPal.

=cut

sub paidack : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::paidack called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    my $token = $c->request->params->{token};
    my $payerid = $c->request->params->{PayerID};
    if($c->session->{paypal}{Token} eq $token and length $payerid) {
        $c->session->{paypal}{PayerID} = $payerid;
    } else {
        $c->session->{prov_error} = 'Server.Paypal.Invalid';
        $c->response->redirect('/account/dopay');
        return;
    }

    unless($c->model('Provisioning')->update_account_balance($c, $c->session->{paypal}{Amount})) {
        $self->_fail_transaction($c, $c->session->{paypal}{tid});
        $c->response->redirect('/account/dopay');
        return;
    }

    unless($c->model('Paypal')->do_express_checkout($c)) {
        $self->_fail_transaction($c, $c->session->{paypal}{tid});
        $c->model('Provisioning')->update_account_balance($c, (0 - $c->session->{paypal}{Amount}));
        $c->response->redirect('/account/dopay');
        return;
    }

    $self->_finish_transaction($c, $c->session->{paypal}{tid});
    $c->session->{messages}{topmsg} = 'Server.Billing.Success';

    $c->response->redirect('/account/balance');
}

=head2 paiderr

Finalizes failed payments via PayPal.

=cut

sub paiderr : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::paiderr called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    $self->_fail_transaction($c, $c->session->{paypal}{tid});
    $c->session->{prov_error} = 'Server.Paypal.Error';

    $c->response->redirect('/account/dopay');
}

=head2 success

Finalizes successful payments via mPAY24.

=cut

sub success : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***account::success called!");
    $c->log->info(Dumper $c->request->params);

    unless($c->request->params->{tid} == $c->session->{payment}{tid}) {
        $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->response->redirect('/account/dopay');
    }

    my $payment;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_payment',
                                                { id   => $c->request->params->{tid} },
                                                \$payment
                                               ))
    {
        $c->response->redirect('/account/dopay');
        return;
    }

    if($$payment{status} eq 'RESERVED' or $$payment{status} eq 'BILLED') {
        unless($c->model('Provisioning')->update_account_balance($c, $$payment{amount})) {
            $self->_fail_transaction($c, $c->request->params->{tid});
            $c->response->redirect('/account/dopay');
            return;
        }

        $self->_finish_transaction($c, $c->request->params->{tid});
        $c->session->{messages}{topmsg} = 'Server.Billing.Success';

    } else {
        $self->_fail_transaction($c, $$payment{id});
        $c->session->{messages}{toperr} = 'Server.Billing.Failed';
    }

    $c->response->redirect('/account/balance');
}

=head2 error

Finalizes failed payments via mPAY24.

=cut

sub error : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***account::error called!");
    $c->log->info(Dumper $c->request->params);

    $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize($c, 'Web.Payment.ExternalError');

    unless($c->request->params->{tid} == $c->session->{payment}{tid}) {
        $c->response->redirect('/account/dopay');
        return;
    }

    $self->_fail_transaction($c, $c->request->params->{tid});
    $c->response->redirect('/account/dopay');
}


sub _start_transaction : Private {
    my ($self, $c, $type, $amount) = @_;

    unless($c->session->{payment}{credit_id}
           or $c->model('Provisioning')->call_prov($c, 'billing', 'create_contract_credit',
                                                   { contract_id => $c->session->{user}{data}{account_id},
                                                     data        => { value  => $amount,
                                                                      reason => 'CSC reload',
                                                                    },
                                                   },
                                                   \$c->session->{payment}{credit_id}
                                                  ))
    {
        return;
    }

    my $payment_id;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'create_payment',
                                                { transaction_type => 'credit',
                                                  transaction_id   => $c->session->{payment}{credit_id},
                                                  type             => $type,
                                                  amount           => $amount,
                                                },
                                                \$payment_id
                                               ))
    {
        return;
    }

    $c->session->{payment}{tid} = $payment_id;
    return $payment_id;
}

sub _finish_transaction : Private {
    my ($self, $c, $tid) = @_;

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                { id   => $tid,
                                                  data => { state          => 'success',
                                                            mpaytid        => $c->session->{mpay24}{MPAYTID},
                                                            status         => $c->session->{mpay24}{STATUS},
                                                          },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_contract_credit',
                                                { id   => $c->session->{payment}{credit_id},
                                                  data => { state => 'success' },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    delete $c->session->{payment}{credit_id};

    return 1;
}

sub _fail_transaction : Private {
    my ($self, $c, $tid) = @_;

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                { id   => $tid,
                                                  data => { state          => 'failed',
                                                            mpaytid        => $c->session->{mpay24}{MPAYTID},
                                                            status         => $c->session->{mpay24}{STATUS},
                                                            errno          => $c->session->{mpay24}{ERRNO},
                                                            returncode     => $c->session->{mpay24}{RETURNCODE},
                                                            externalstatus => $c->session->{mpay24}{EXTERNALSTATUS},
                                                          },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    return 1;
}

=head2 subscriber

Displays the account's subscribers.

=cut

sub subscriber : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::subscriber called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    $c->stash->{template} = 'tt/account_subscriber.tt';

    return 1 unless $c->model('Provisioning')->get_voip_account_subscribers($c);

    my %subscribers;

    foreach my $subscriber (@{$c->session->{user}{subscribers}}) {
        if($$subscriber{preferences}{base_cli}) {
            push @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}}, $subscriber;
            #TODO: fixme, this is terrible inefficient
            @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}} =
                sort {$a->{preferences}{extension} cmp $b->{preferences}{extension}}
                     @{$subscribers{$$subscriber{preferences}{base_cli}}{extensions}};
        } elsif($$subscriber{sn}) {
            my $tmp_num = $$subscriber{cc}.$$subscriber{ac}.$$subscriber{sn};
            $$subscriber{extensions} = $subscribers{$tmp_num}{extensions}
                if exists $subscribers{$tmp_num};
            $subscribers{$tmp_num} = $subscriber;
        } else {
            #TODO: subscribers without number?
            $c->log->error('***account::subscriber: subscriber without E.164 number found: '.
                           $$subscriber{username} .'@'. $$subscriber{domain});
        }
    }

    $c->stash->{subscribers} = [sort {$a->{username} cmp $b->{username}} values %subscribers];
}

=head2 addsubscriber

Asks the user to add a new subscriber to the account.

=cut

sub addsubscriber : Local {
    my ( $self, $c, $settings ) = @_;

    $c->log->debug('***account::addsubscriber called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    $c->stash->{template} = 'tt/account_addsubscriber.tt';

    if(defined $settings and ref $settings eq 'HASH') {
        $c->stash->{refill} = $settings;
    }

    $c->stash->{available_numbers} = $c->model('Provisioning')->get_free_numbers($c);
    if(defined $c->stash->{available_numbers} and ref $c->stash->{available_numbers} eq 'ARRAY') {
        foreach my $free_number (@{$c->stash->{available_numbers}}) {
            # try to reselect selected number. (if it's still available...)
            if($$settings{cc} and $$free_number{cc} eq $$settings{cc} and
               $$settings{ac} and $$free_number{ac} eq $$settings{ac} and
               $$settings{sn} and $$free_number{sn} eq $$settings{sn})
            {
                $$free_number{active} = 'selected="selected"';
            }
        }
    }
}

=head2 doaddsubscriber

Adds a new subscriber to the account.

=cut

sub doaddsubscriber : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::doaddsubscriber called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    my (%settings, %messages);

    my $number = $c->request->params->{fnummer};
    if(defined $number) {
        @settings{'cc','ac','sn'} = split /-/, $number;
    } else {
        $messages{msgnumber} = 'Client.Voip.ChooseNumber';
    }

    my $sipuri = lc($c->request->params->{fsipuri});
    if(!defined $sipuri or length $sipuri == 0) {
        $messages{msgsipuri} = 'Client.Syntax.MissingUsername';
    } elsif($sipuri !~ /^[a-z0-9_.-]+$/) {
        $messages{msgsipuri} = 'Client.Syntax.MalformedUsername';
    }
    $settings{sipuri} = $sipuri;

    my ($passwd1,$passwd2) = @{$c->request->params}{qw/fpasswort1 fpasswort2/};
    my $messages_pass = csc::Utils::validate_password($c, { no_old => 1 }, $passwd1, $passwd2);
    %messages = (%messages,%$messages_pass);

    #if(!defined $passwd1 or length $passwd1 == 0) {
    #    $messages{msgpasswd} = 'Client.Voip.MissingPass';
    #} elsif(length $passwd1 < 6) {
    #    $messages{msgpasswd} = 'Client.Voip.PassLength';
    #} elsif(!defined $passwd2) {
    #    $messages{msgpasswd} = 'Client.Voip.MissingPass2';
    #} elsif($passwd1 ne $passwd2) {
    #    $messages{msgpasswd} = 'Client.Voip.PassNoMatch';
    #}

    unless(keys %messages) {
        my %create_settings = %settings;
        delete $create_settings{sipuri};

        $create_settings{webusername} = $settings{sipuri};
        $create_settings{username} = $settings{sipuri};
        $create_settings{domain} = $c->session->{user}{domain};
        $create_settings{webpassword} = $passwd1;
        # TODO: sip password should be auto-generated
        $create_settings{password} = $passwd1;

        $c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber',
                                             { id         => $c->session->{user}{account_id},
                                               subscriber => \%create_settings,
                                             },
                                            );
        if($c->session->{prov_error}) {
            if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') {
                $c->session->{messages}{msgsipuri} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            } elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') {
                $c->session->{messages}{msgnumber} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            }
            $self->addsubscriber($c, \%settings);
        } else {
            $messages{topmsg} = 'Server.Voip.SubscriberCreated';
            $c->session->{messages} = \%messages;
            $c->response->redirect($c->uri_for('/account/subscriber'));
        }
    } else {
        $messages{toperr} = "Client.Voip.InputErrorFound";
        $c->session->{messages} = \%messages;
        $self->addsubscriber($c, \%settings);
    }

}

=head2 addextension

Asks the user to create a new extension for its PBX.

=cut

sub addextension : Local {
    my ( $self, $c, $settings ) = @_;

    $c->log->debug('***account::addextension called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    $c->stash->{template} = 'tt/account_addextension.tt';

    if(defined $settings and ref $settings eq 'HASH') {
        $c->stash->{refill} = $settings;
        $c->stash->{refill}{extension} = $c->request->params->{fextension};
    }
    $c->stash->{base_cli} = $c->request->params->{base_cli};
}

=head2 doaddextension

Creates a new extension for a PBX.

=cut

sub doaddextension : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::doaddextension called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    my (%settings, %messages);

    my $base_cli = $c->request->params->{base_cli};
    my $extension = $c->request->params->{fextension};
    if(defined $extension) {
        $messages{msgnumber} = 'Web.Syntax.Numeric'
            unless $extension =~ /^\d+$/;
    } else {
        $messages{msgnumber} = 'Client.Voip.ChooseNumber';
    }

    my $sipuri = lc($c->request->params->{fsipuri});
    if(!defined $sipuri or length $sipuri == 0) {
        $messages{msgsipuri} = 'Client.Syntax.MissingUsername';
    } elsif($sipuri !~ /^[a-z0-9_.-]+$/) {
        $messages{msgsipuri} = 'Client.Syntax.MalformedUsername';
    }
    $settings{sipuri} = $sipuri;

    my ($passwd1,$passwd2) = @{$c->request->params}{qw/fpasswort1 fpasswort2/};
    my $messages_pass = csc::Utils::validate_password($c, { no_old => 1 }, $passwd1, $passwd2);
    %messages = (%messages,%$messages_pass);
    #my $passwd1 = $c->request->params->{fpasswort1};
    #my $passwd2 = $c->request->params->{fpasswort2};
    #if(!defined $passwd1 or length $passwd1 == 0) {
    #    $messages{msgpasswd} = 'Client.Voip.MissingPass';
    #} elsif(length $passwd1 < 6) {
    #    $messages{msgpasswd} = 'Client.Voip.PassLength';
    #} elsif(!defined $passwd2) {
    #    $messages{msgpasswd} = 'Client.Voip.MissingPass2';
    #} elsif($passwd1 ne $passwd2) {
    #    $messages{msgpasswd} = 'Client.Voip.PassNoMatch';
    #}

    unless(keys %messages) {
        my %create_settings = %settings;
        delete $create_settings{sipuri};

        $create_settings{webusername} = $settings{sipuri};
        $create_settings{username} = $settings{sipuri};
        $create_settings{domain} = $c->session->{user}{domain};
        $create_settings{webpassword} = $passwd1;
        # TODO: sip password should be auto-generated
        $create_settings{password} = $passwd1;

        if($c->model('Provisioning')->call_prov($c, 'billing', 'add_voip_account_subscriber',
                                                { id         => $c->session->{user}{account_id},
                                                  subscriber => \%create_settings,
                                                },
                                               ))
        {
            if($c->model('Provisioning')->call_prov($c, 'voip', 'set_subscriber_preferences',
                                                    { username    => $settings{sipuri},
                                                      domain      => $c->session->{user}{domain},
                                                      preferences => { base_cli  => $base_cli,
                                                                       extension => $extension
                                                                     },
                                                    },
                                                   ))
            {
                $messages{topmsg} = 'Server.Voip.SubscriberCreated';
                $c->session->{messages} = \%messages;
                $c->response->redirect($c->uri_for('/account/subscriber'));
            } else {
                if($c->session->{prov_error} eq 'Client.Voip.ExistingAlias') {
                    $messages{msgnumber} = 'Client.Voip.AssignedExtension';
                    $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
                }
                $c->model('Provisioning')->delete_subscriber($c, $settings{sipuri}, $c->session->{user}{domain});
            }
        } else {
            if($c->session->{prov_error} eq 'Client.Voip.ExistingSubscriber') {
                $messages{msgsipuri} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            } elsif($c->session->{prov_error} eq 'Client.Voip.AssignedNumber') {
                $messages{msgnumber} = $c->session->{prov_error};
                $c->session->{prov_error} = 'Client.Voip.InputErrorFound';
            }
        }
    } else {
        $messages{toperr} = "Client.Voip.InputErrorFound";
    }

    $c->session->{messages} = \%messages;
    $self->addextension($c, \%settings);

}

=head2 delsubscriber

Deletes a subscriber for an account.

=cut

sub delsubscriber : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***account::delsubscriber called');

    unless($c->session->{user}{admin}) {
        $c->response->redirect($c->uri_for('/account/info'));
        return;
    }

    my $username = lc($c->request->params->{username});

    if($c->model('Provisioning')->terminate_subscriber($c, $username, $c->session->{user}{domain})) {
        $c->session->{messages}{topmsg} = 'Server.Voip.SubscriberDeleted';
    }

    $c->response->redirect($c->uri_for('/account/subscriber'));
}


=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Paypal model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The account controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

# over and out
1;
