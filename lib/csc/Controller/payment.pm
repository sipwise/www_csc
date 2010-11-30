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

    $c->response->redirect('/')
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

    $c->stash->{tarif} = $c->session->{shop}{tarif};
    $c->stash->{number} = '0'. $c->session->{shop}{number}{ac} .' '. $c->session->{shop}{number}{sn}
        if defined $c->session->{shop}{number}{sn};

    $c->stash->{existing_customer} = $c->session->{shop}{existing_customer}
        if $c->session->{shop}{existing_customer};

    return 1;
}

sub dopay_eps : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_eps called');

    $c->response->redirect('/')
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
                                            || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#eps');
    } else { # transport error
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{eps} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->session->{refill}{eps}{bankname} = $bankname;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#eps');
    }

    return 1;
}

sub dopay_elv : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_elv called');

    $c->response->redirect('/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    # currently disabled until implemented
    $c->session->{mpay24_errors}{elv} = "ELV is currently not implemented.";
    $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
    return;

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
        $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
        return;
    } elsif(defined $c->session->{mpay24}) {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{elv} = $c->session->{mpay24}{EXTERNALSTATUS}
                                            || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{elv}{accountnumber} = $accountnumber;
        $c->session->{refill}{elv}{bankid} = $bankid;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#elv');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{elv} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
        $c->session->{refill}{elv}{accountnumber} = $accountnumber;
        $c->session->{refill}{elv}{bankid} = $bankid;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#elv');
    }

    return 1;
}

sub dopay_cc : Local {
    my ( $self, $c ) = @_;

    $c->log->debug('***payment::dopay_cc called');

    $c->response->redirect('/')
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
                                           || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{cc}{cctype} = $cctype;
        $c->session->{refill}{cc}{cardnum} = $cardnum;
        $c->session->{refill}{cc}{cvc} = $cvc;
        $c->session->{refill}{cc}{cc_month} = $cc_month;
        $c->session->{refill}{cc}{cc_year} = $cc_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#cc');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{cc} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
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

    $c->response->redirect('/')
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
                                                || $c->model('Provisioning')->localize($c, 'Web.Payment.UnknownError');
        $c->session->{refill}{maestro}{cardnum} = $cardnum;
        $c->session->{refill}{maestro}{maestro_month} = $maestro_month;
        $c->session->{refill}{maestro}{maestro_year} = $maestro_year;
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#maestro');
    } else {
        $self->_fail_transaction($c, $tid);
        $c->session->{mpay24_errors}{maestro} = $c->model('Provisioning')->localize($c, 'Web.Payment.HttpFailed');
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

    $c->response->redirect('/')
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

    # hmm. update payment status?

    $c->response->redirect($c->config->{paypal_redirecturl} . $c->session->{paypal}{Token});

    return 1;
}

# some paidack and paiderr notes:
# 1) used by paypal only
# 2) used only to acknowledge shop order payments
#    -> see account.pm for CSC credit payment ACK from paypal
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

# This function is used to confirm payments by mPAY24 servers for both
# shop order and credit payments. We don't care which one it is.
sub confirm : Local {
    my ( $self, $c ) = @_;

    use Data::Dumper;
    $c->log->info("***payment::confirm called!");
    $c->log->info(Dumper $c->request->params);

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                { id   => $c->request->params->{TID},
                                                  data => { mpaytid => $c->request->params->{MPAYTID},
                                                            status  => $c->request->params->{STATUS},
                                                          },
                                                },
                                                undef
                                               ))
    {
        return;
    }
    if($c->request->params->{STATUS} eq 'BILLED') {
        $self->_finish_transaction($c, $c->request->params->{TID});
    } elsif($c->request->params->{STATUS} eq 'ERROR') {
        $self->_fail_transaction($c, $c->request->params->{TID});
    }

    $c->response->body('OK');
}

# the following functions are used for mPAY24 payments, as the mPAY24
# servers redirect users to the URLs after successfull / failed payments
# -> these are used both for shop order and credit payments
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

    if($$payment{transaction_type} eq 'credit') {
        $c->response->redirect('/account/success?tid='. $$payment{id});
        return;
    }

    my $order;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id => $$payment{transaction_id} },
                                                \$order
                                               ))
    {
        $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        return;
    }

    $c->log->info("***payment::success payment $$payment{id} for order $$order{id} status is: $$payment{status} / $$payment{state}");

    if($$payment{status} eq 'RESERVED' or $$payment{status} eq 'BILLED' or $$payment{status} eq 'CREDITED') {
        $c->response->redirect('/shop/finish?sk='. $c->session->{shop}{session_key});
        return;
    } else {
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
        $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize($c, 'Web.Payment.ExternalError');
        if($c->session->{shop}{session_key}) {
            $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        } elsif($c->session->{payment}{amount}) {
            $c->response->redirect('/account/error?tid='. $c->request->params->{TID});
        } else {
            $c->response->redirect('http://'. $c->config->{site_config}{company}{webserver});
        }
        return;
    }

    if($$payment{transaction_type} eq 'credit') {
        $c->response->redirect('/account/error?tid='. $$payment{id});
        return;
    }

    my $order;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id   => $$payment{transaction_id} },
                                                \$order
                                               ))
    {
        $c->session->{mpay24_errors}{top} = $c->model('Provisioning')->localize($c, 'Web.Payment.ExternalError');
        if($c->session->{shop}{session_key}) {
            $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        } elsif($c->session->{payment}{amount}) {
            $c->response->redirect('/account/error?tid='. $c->request->params->{TID});
        } else {
            $c->response->redirect('http://'. $c->config->{site_config}{company}{webserver});
        }
        return;
    }

    $c->log->info("***payment::error payment $$payment{id} for order $$order{id} status is: $$payment{status} / $$payment{state}");

    $c->session->{mpay24_errors}{$$payment{type}} = $$payment{externalstatus}
                                                    || $c->model('Provisioning')->localize($c, 'Web.Payment.ExternalError');
    $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key} .'#'. $$payment{type});
    return;
}

sub _start_transaction : Private {
    my ($self, $c, $type, $amount) = @_;

    my $payment_id;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'create_payment',
                                                { transaction_type => 'order',
                                                  transaction_id   => $c->session->{shop}{order_id},
                                                  type             => $type,
                                                  amount           => $amount,
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
                                                  data => { state => 'success' },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    my $payment;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_payment',
                                                { id   => $tid },
                                                \$payment
                                               ))
    {
        return;
    }

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_order',
                                                { id   => $$payment{transaction_id},
                                                  data => { state => 'transact' },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    my $order;
    unless($c->model('Provisioning')->call_prov($c, 'billing', 'get_order',
                                                { id => $$payment{transaction_id} },
                                                \$order
                                               ))
    {
        return;
    }

    foreach my $contract (@{$$order{contracts}}) {
        next unless $$contract{class} eq 'voip';

        unless($c->model('Provisioning')->call_prov($c, 'billing', 'activate_voip_account',
                                                    { id => $$contract{id} },
                                                    undef
                                                   ))
        {
            return;
        }
    }

    return 1;
}

sub _fail_transaction : Private {
    my ($self, $c, $tid) = @_;

    my %mpay;
    $mpay{mpaytid} = $c->session->{mpay24}{MPAYTID} if defined $c->session->{mpay24}{MPAYTID};
    $mpay{status} = $c->session->{mpay24}{STATUS} if defined $c->session->{mpay24}{STATUS};
    $mpay{errno} = $c->session->{mpay24}{ERRNO} if defined $c->session->{mpay24}{ERRNO};
    $mpay{returncode} = $c->session->{mpay24}{RETURNCODE} if defined $c->session->{mpay24}{RETURNCODE};
    $mpay{externalstatus} = $c->session->{mpay24}{EXTERNALSTATUS} if defined $c->session->{mpay24}{EXTERNALSTATUS};

    unless($c->model('Provisioning')->call_prov($c, 'billing', 'update_payment',
                                                { id   => $tid,
                                                  data => { state => 'failed', %mpay },
                                                },
                                                undef
                                               ))
    {
        return;
    }

    return 1;
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
            $c->stash->{messages} = $c->model('Provisioning')->localize($c, $c->session->{messages});
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

The payment controller is Copyright (c) 2007-2010 Sipwise GmbH, Austria.
You should have received a copy of the licences terms together with the
software.

=cut

1;
