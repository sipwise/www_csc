package csc::Controller::payment;

use strict;
use warnings;
use base 'Catalyst::Controller';

=head1 NAME

csc::Controller::payment - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index 

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    if(exists $c->session->{mpay24_errors}) {
        $c->stash->{mpay24_errors} = $c->session->{mpay24_errors};
        delete $c->session->{mpay24_errors};
    }

    if(exists $c->session->{refill}) {
        $c->stash->{refill} = $c->session->{refill};
        delete $c->session->{refill};
    }

    $c->stash->{template} = 'tt/shop/payment_select.tt';
    $c->stash->{backend} = 'payment';
    $c->stash->{sk} = $c->session->{shop}{session_key};
    $c->stash->{phones} = $c->session->{shop}{phones};
    $c->stash->{price_sum} = $c->session->{shop}{price_sum};

    return 1;
}

sub dopay_eps : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_eps called');

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my $amount = $c->session->{shop}{price_sum} * 100;

    my $bankname = $c->request->params->{bankname};
    my ($bank, $bankid);
    $bank = $bankname;

    if($bankname =~ /^ARZ_/) {
        ($bank, $bankid) = split /_/, $bankname;
    }

    my $tid = $self->_start_transaction($c, 'eps', $amount);
    unless($tid) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    delete $c->session->{shop}{payment_details} if exists $c->session->{shop}{payment_details};
    $c->session->{shop}{payment_details} = {
                                             type    => 'eps',
                                             bank    => $bank,
                                             bankid  => $bankid,
                                           };

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
                                            || $c->model('Provisioning')->localize('Web.Payment.UnknownError');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#eps');
    } else { # transport error
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{eps} = $c->model('Provisioning')->localize('Web.Payment.HttpFailed');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#eps');
    }

    return 1;
}

sub dopay_elv : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_elv called');

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my $amount = $c->session->{shop}{price_sum} * 100;

    my $agb_ack = $c->request->params->{agb_ack};
    my $accountnumber = $c->request->params->{accountnumber};
    my $bankid = $c->request->params->{bankid};

    my $tid = $self->_start_transaction($c, 'elv', $amount);
    unless($tid) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    delete $c->session->{shop}{payment_details} if exists $c->session->{shop}{payment_details};
    $c->session->{shop}{payment_details} = {
                                             type    => 'elv',
                                             bankid  => $bankid,
                                             account => $accountnumber,
                                           };

    if($c->model('Mpay24')->accept_elv_payment($c, $tid, $amount, $accountnumber, $bankid)) {
        unless($self->_finish_transaction($c, $tid)) {
            # hmm, what? some logging, at least.
        }
        $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
        return;
    } elsif(defined $c->session->{mpay24}) {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{elv} = $c->session->{mpay24}{EXTERNALSTATUS}
                                            || $c->model('Provisioning')->localize('Web.Payment.UnknownError');
        $c->session->{refill}{elv}{accountnumber} = $accountnumber;
        $c->session->{refill}{elv}{bankid} = $bankid;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#elv');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{elv} = $c->model('Provisioning')->localize('Web.Payment.HttpFailed');
        $c->session->{refill}{elv}{accountnumber} = $accountnumber;
        $c->session->{refill}{elv}{bankid} = $bankid;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#elv');
    }

    return 1;
}

sub dopay_cc : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_cc called');

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my $amount = $c->session->{shop}{price_sum} * 100;

    my $cctype = $c->request->params->{cctype};
    my $cardnum = $c->request->params->{cardnum};
    my $cvc = $c->request->params->{cvc};
    my $cc_month = $c->request->params->{cc_month};
    my $cc_year = $c->request->params->{cc_year};
    $cc_year =~ s/^\d\d//;
    my $expiry = sprintf("%02d%02d", $cc_year, $cc_month);

    my $tid = $self->_start_transaction($c, 'cc', $amount);
    unless($tid) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    delete $c->session->{shop}{payment_details} if exists $c->session->{shop}{payment_details};
    $c->session->{shop}{payment_details} = {
                                             type    => 'cc',
                                             cctype  => $cctype,
                                             cardnum => $cardnum,
                                           };
    $c->session->{shop}{payment_details}{cardnum} =~ s/^(\d{8})(\d+)/$1 . "x" x length $2/ex;

    my $rc = $c->model('Mpay24')->accept_cc_payment($c, $tid, $amount, $cctype, $cardnum, $expiry, $cvc);
    if($rc == 1) {
        unless($self->_finish_transaction($c, $tid)) {
            # hmm, what? some logging, at least.
        }
        $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
        return;
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
                                           || $c->model('Provisioning')->localize('Web.Payment.UnknownError');
        $c->session->{refill}{cc}{cctype} = $cctype;
        $c->session->{refill}{cc}{cardnum} = $cardnum;
        $c->session->{refill}{cc}{cvc} = $cvc;
        $c->session->{refill}{cc}{cc_month} = $cc_month;
        $c->session->{refill}{cc}{cc_year} = $cc_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#cc');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{cc} = $c->model('Provisioning')->localize('Web.Payment.HttpFailed');
        $c->session->{refill}{cc}{cctype} = $cctype;
        $c->session->{refill}{cc}{cardnum} = $cardnum;
        $c->session->{refill}{cc}{cvc} = $cvc;
        $c->session->{refill}{cc}{cc_month} = $cc_month;
        $c->session->{refill}{cc}{cc_year} = $cc_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#cc');
    }

    return 1;
}

sub dopay_maestro : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_maestro called');

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my $amount = $c->session->{shop}{price_sum} * 100;

    my $cardnum = $c->request->params->{cardnum};
    my $maestro_month = $c->request->params->{maestro_month};
    my $maestro_year = $c->request->params->{maestro_year};
    $maestro_year =~ s/^\d\d//;
    my $expiry = sprintf("%02d%02d", $maestro_year, $maestro_month);

    my $tid = $self->_start_transaction($c, 'maestro', $amount);
    unless($tid) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    delete $c->session->{shop}{payment_details} if exists $c->session->{shop}{payment_details};
    $c->session->{shop}{payment_details} = {
                                             type    => 'maestro',
                                             cardnum => $cardnum,
                                           };

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
                                                || $c->model('Provisioning')->localize('Web.Payment.UnknownError');
        $c->session->{refill}{maestro}{cardnum} = $cardnum;
        $c->session->{refill}{maestro}{maestro_month} = $maestro_month;
        $c->session->{refill}{maestro}{maestro_year} = $maestro_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#maestro');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{maestro} = $c->model('Provisioning')->localize('Web.Payment.HttpFailed');
        $c->session->{refill}{maestro}{cardnum} = $cardnum;
        $c->session->{refill}{maestro}{maestro_month} = $maestro_month;
        $c->session->{refill}{maestro}{maestro_year} = $maestro_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#maestro');
    }

    return 1;
}

sub dopay_paypal : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_paypal called');

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my $amount = $c->session->{shop}{price_sum} * 100;

    my $tid = $self->_start_transaction($c, 'paypal', $amount);
    unless($tid) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }
    $c->session->{paypal}{tid} = $tid;

    delete $c->session->{shop}{payment_details} if exists $c->session->{shop}{payment_details};
    $c->session->{shop}{payment_details} = { type => 'paypal' };

    unless($c->model('Paypal')->set_express_checkout($c, $amount, 'shop')) {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }
    $c->response->redirect($c->config->{paypal_redirecturl} . $c->session->{paypal}{Token});

    return 1;
}

sub paidack : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::paidack called');

    my $token = $c->request->params->{token};
    my $payerid = $c->request->params->{PayerID};
    if($c->session->{paypal}{Token} eq $token and length $payerid) {
        $c->session->{paypal}{PayerID} = $payerid;
    } else {
        $c->session->{prov_error} = 'Server.Paypal.Invalid';
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    unless($c->model('Paypal')->do_express_checkout($c)) {
        $self->_fail_transaction($c, $c->session->{paypal}{tid});
        $c->session->{prov_error} = 'Server.Paypal.Error' unless $c->session->{prov_error};
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    $self->_finish_transaction($c, $c->session->{paypal}{tid});

    $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
}

sub paiderr : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::paiderr called');

    $self->_fail_transaction($c, $c->session->{paypal}{tid});
    $c->session->{prov_error} = 'Server.Paypal.Error';

    $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
}

sub confirm : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***payment::confirm called!");
    $c->log->info(Dumper $c->request->params);

    if($c->request->params->{P_TYPE} eq 'MAESTRO'
       or $c->request->params->{P_TYPE} eq 'EPS'
       or $c->request->params->{P_TYPE} eq 'CC')
    {
        unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                    { id   => $c->request->params->{TID},
                                                      data => { mpaytid        => $c->request->params->{MPAYTID},
                                                                status         => $c->request->params->{STATUS},
                                                              },
                                                    },
                                                    undef
                                                   ))
        {
            return;
        }
    } else {
        $c->log->info("***payment::confirm IGNORING confirm call for paytype '". $c->request->params->{P_TYPE} ."'");
    }

    $c->response->body('OK');
}

sub success : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***payment::success called!");
    $c->log->info(Dumper $c->request->params);

    my $payment;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_payment',
                                                { id   => $c->request->params->{TID} },
                                                \$payment
                                               ))
    {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    my $order;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id   => $$payment{order_id} },
                                                \$order
                                               ))
    {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    $c->log->info("***payment::success payment $$payment{id} for order $$order{id} status is: $$payment{status} / $$payment{state}");

    if($$order{type} eq 'charge') {
        $c->response->redirect('https://csc.libratel.at/account/success?tid='. $$payment{id});
        return;
    }

    if($$payment{status} eq 'RESERVED' or $$payment{status} eq 'BILLED') {
        if($$order{type} eq 'charge') {
            unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_voip_account_balance',
                                                        { id     => $c->session->{user}{account_id},
                                                          data => { cash => $$payment{amount} },
                                                        }))
            {
                $self->_fail_transaction($c, $$payment{id});
            } else {
                $self->_finish_transaction($c, $$payment{id});
            }
            $c->response->redirect('/account/balance');
        } else {
            $self->_finish_transaction($c, $$payment{id});
            $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
        }
        return;
    } else {
        $self->_fail_transaction($c, $$payment{id});
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

}

sub error : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***payment::error called!");
    $c->log->info(Dumper $c->request->params);

    my $payment;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_payment',
                                                { id   => $c->request->params->{TID} },
                                                \$payment
                                               ))
    {
        $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize('Web.Payment.ExternalError');
        if($c->session->{shop}{session_key}) {
            $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        } elsif($c->session->{payment}{amount}) {
            $c->response->redirect('https://csc.libratel.at/account/error?tid='. $c->request->params->{TID});
        } else {
            $c->response->redirect('http://'. $c->config->{www_server});
        }
        return;
    }

    my $order;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id   => $$payment{order_id} },
                                                \$order
                                               ))
    {
        $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize('Web.Payment.ExternalError');
        if($c->session->{shop}{session_key}) {
            $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        } elsif($c->session->{payment}{amount}) {
            $c->response->redirect('https://csc.libratel.at/account/error?tid='. $c->request->params->{TID});
        } else {
            $c->response->redirect('http://'. $c->config->{www_server});
        }
        return;
    }

    $c->log->info("***payment::error payment $$payment{id} for order $$order{id} status is: $$payment{status} / $$payment{state}");

    if($$order{type} eq 'charge') {
        $c->response->redirect('https://csc.libratel.at/account/error?tid='. $$payment{id});
        return;
    }

    $self->_fail_transaction($c, $$payment{id});

    $c->session->{mpay24_errors}{$$payment{type}} = $$payment{externalstatus}
                                                    || $c->model('Provisioning')->localize('Web.Payment.ExternalError');
    $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#'. $$payment{type});
    return;
}

sub _start_transaction : Private {
    my ($self, $c, $type, $amount) = @_;

    my $pi = $c->session->{shop}{personal};

    unless($c->session->{shop}{customer_id}) {
        $c->model('Provisioning')->call_prov($c, 'billing', 'create_customer',
                                             { data => {
                                                         shopuser => $$pi{username},
                                                         shoppass => $$pi{password},
                                                         contact  => { comregnum   => $$pi{comregnum},
                                                                       company     => $$pi{company},
                                                                       gender      => $$pi{gender},
                                                                       firstname   => $$pi{firstname},
                                                                       lastname    => $$pi{lastname},
                                                                       street      => $$pi{street},
                                                                       postcode    => $$pi{postcode},
                                                                       city        => $$pi{city},
                                                                       phonenumber => $$pi{phonenumber},
                                                                       email       => $$pi{email},
                                                                       newsletter  => $$pi{newsletter},
                                                                     },
                                                         ($$pi{customer_type} eq 'business' ?
                                                           (($$pi{sign_like_contact} ? () :
                                                             (comm_contact => { gender      => $$pi{sign_contact}{gender},
                                                                                firstname   => $$pi{sign_contact}{firstname},
                                                                                lastname    => $$pi{sign_contact}{lastname},
                                                                                phonenumber => $$pi{sign_contact}{phonenumber},
                                                                                email       => $$pi{sign_contact}{email},
                                                                              })
                                                            ),
                                                            ($$pi{tech_like_contact} ? () :
                                                             (tech_contact => { gender      => $$pi{tech_contact}{gender},
                                                                                firstname   => $$pi{tech_contact}{firstname},
                                                                                lastname    => $$pi{tech_contact}{lastname},
                                                                                phonenumber => $$pi{tech_contact}{phonenumber},
                                                                                email       => $$pi{tech_contact}{email},
                                                                              })
                                                            ),
                                                           ) : ()
                                                         ),
                                                       },
                                             },
                                             \$c->session->{shop}{customer_id}
                                            ) or return;
    }

    unless($c->session->{shop}{order_id}
           or $c->model('Provisioning')->call_prov($c, 'billing', 'create_order',
                                                   { customer_id => $c->session->{shop}{customer_id},
                                                     type        => 'web',
                                                     value       => $amount,
                                                     ($$pi{deliver_to_contact} ? () :
                                                      (delivery_contact => { gender    => $$pi{delivery}{gender},
                                                                             firstname => $$pi{delivery}{firstname},
                                                                             lastname  => $$pi{delivery}{lastname},
                                                                             company   => $$pi{delivery}{company},
                                                                             street    => $$pi{delivery}{street},
                                                                             postcode  => $$pi{delivery}{postcode},
                                                                             city      => $$pi{delivery}{city},
                                                                           })
                                                     ),
                                                   },
                                                   \$c->session->{shop}{order_id}
                                                  ))
    {
        return;
    }

    unless($c->session->{shop}{account_id}) {
        $c->model('Provisioning')->call_prov($c, 'billing', 'create_voip_account',
                                             { product     => ($c->session->{shop}{tarif} eq 'free'
                                                               ? 'Libratel VoIP Free'
                                                               : 'Libratel VoIP Premium'),
                                               customer_id => $c->session->{shop}{customer_id},
                                               status      => 'pending',
                                               order_id    => $c->session->{shop}{order_id},
                                               subscribers => [{ username    => $c->session->{shop}{personal}{username},
                                                                 domain      => $c->config->{site_domain},
                                                                 password    => $self->_generate_sip_password($c),
                                                                 admin       => 1,
                                                                 cc          => $c->session->{shop}{number}{cc},
                                                                 ac          => $c->session->{shop}{number}{ac},
                                                                 sn          => $c->session->{shop}{number}{sn},
                                                                 webusername => $c->session->{shop}{personal}{username},
                                                                 webpassword => $c->session->{shop}{personal}{password},
                                                                 #TODO: phonebook attribute in BSS
                                                                 # phonebook   => $c->session->{shop}{phonebook},
                                                              }],
                                             },
                                             \$c->session->{shop}{account_id}
                                            ) or return;
    }

    unless($c->session->{shop}{system}{contract_id}) {
        $c->model('Provisioning')->call_prov($c, 'billing', 'create_hardware_contract',
                                             { product     => $c->session->{shop}{system}{name},
                                               customer_id => $c->session->{shop}{customer_id},
                                               status      => 'pending',
                                               order_id    => $c->session->{shop}{order_id},
                                             },
                                             \$c->session->{shop}{system}{contract_id}
                                            ) or return;
    }

    if(ref $c->session->{shop}{phones} eq 'ARRAY') {
        foreach my $phone (@{$c->session->{shop}{phones}}) {
            next if ref $$phone{contract_ids} eq 'ARRAY' and scalar @{ $$phone{contract_ids} } == $$phone{count};
            my $start = ref $$phone{contract_ids} eq 'ARRAY' ? scalar @{ $$phone{contract_ids} } : 1;
            for($start .. $$phone{count}) {
                my $contract_id;
                $c->model('Provisioning')->call_prov($c, 'billing', 'create_hardware_contract',
                                                     { product     => $$phone{name},
                                                       customer_id => $c->session->{shop}{customer_id},
                                                       status      => 'pending',
                                                       order_id    => $c->session->{shop}{order_id},
                                                     },
                                                     \$contract_id
                                                    ) or return;
                push @{ $$phone{contract_ids} }, $contract_id;
            }
        }
    }

    my $payment_id;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'create_payment',
                                                { order_id => $c->session->{shop}{order_id},
                                                  type     => $type,
                                                  amount   => $amount,
                                                },
                                                \$payment_id
                                               ))
    {
        return;
    }

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

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_order',
                                                { id   => $c->session->{shop}{order_id},
                                                  data => { state => 'transact' },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id   => $c->session->{shop}{order_id} },
                                                \$c->session->{shop}{order}
                                               ))
    {
        return;
    }

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'activate_voip_account',
                                                { id   => $c->session->{shop}{account_id} },
                                                undef
                                               ))
    {
        return;
    }

    unless(!$c->session->{shop}{tarif}{initial_charge}
           or $c->model('Provisioning')->call_prov( $c, 'billing', 'update_voip_account_balance',
                                                    { id   => $c->session->{shop}{account_id},
                                                      data => { cash => $c->session->{shop}{tarif}{initial_charge} * 100 }
                                                    },
                                                    undef
                                                  ))
    {
        return;
    }

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

sub _generate_sip_password : Private {
    my ($self,$c) = @_;

    return substr crypt($c->session->{shop}{session_key}, $c->session->{shop}{session_key}), 2;
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;

    $c->stash->{current_view} = 'Frontpage';

    unless($c->response->{status} =~ /^3/) { # only if not a redirect
        if(exists $c->session->{prov_error}) {
            $c->session->{messages}{prov_error} = $c->session->{prov_error};
            delete $c->session->{prov_error};
        }
        if(exists $c->session->{messages}) {
            $c->stash->{messages} = $c->model('Provisioning')->localize($c->session->{messages});
            delete $c->session->{messages};
        }
    }
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

The payment controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
