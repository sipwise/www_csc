package csc::Model::Paypal;

use strict;
use warnings;
use base 'Catalyst::Model';

use SOAP::Lite;
use Data::Dumper;

=head1 NAME

csc::Model::Paypal - Paypal billing model

=head1 DESCRIPTION

Catalyst model that uses the PayPal SOAP interface to retrieve and
transfer money from and to PayPal accounts.

=cut

sub new {
    my $class = shift;

    my $self = {};

    return bless $self, $class;
}

sub set_express_checkout {
    my ($self, $c, $amount, $backend) = @_;

    $c->log->debug("***Paypal::set_express_checkout: called");

    my ($returnurl, $cancelurl);
    if($backend eq 'csc') {
        $returnurl = $c->config->{paypal_csc_returnurl};
        $cancelurl = $c->config->{paypal_csc_cancelurl};
    } elsif($backend eq 'shop') {
        $returnurl = $c->config->{paypal_shop_returnurl};
        $cancelurl = $c->config->{paypal_shop_cancelurl};
    } else {
        $c->session->{prov_error} = 'Server.Internal';
        return;
    }

    my $return = eval {
        SOAP::Lite->uri($c->config->{paypal_soapuri})
                  ->proxy($c->config->{paypal_soapurl})
                  ->autotype(0)  # prevent SOAP::Lite from adding type declarations
                  ->call(SOAP::Data->name('SetExpressCheckoutReq')->attr({xmlns => 'urn:ebay:api:PayPalAPI'})
                           => (SOAP::Header->name(RequesterCredentials =>
                                 \SOAP::Data->value(SOAP::Data->name(Credentials =>
                                    \SOAP::Data->value(SOAP::Data->name(Username  => $c->config->{paypal_username}),
                                                       SOAP::Data->name(Password  => $c->config->{paypal_password}),
                                                       SOAP::Data->name(Signature => $c->config->{paypal_signature}),
                                                       SOAP::Data->name(Subject   => undef),
                                                      )             )->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'})
                                                   )
                                                 )->attr({xmlns=>'urn:ebay:api:PayPalAPI'}),
                               SOAP::Data->name(SetExpressCheckoutRequest =>
                                 \SOAP::Data->value(
                                    SOAP::Data->name(Version => '3.2')->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'}),
                                    SOAP::Data->name(SetExpressCheckoutRequestDetails =>
                                      \SOAP::Data->value(
                                         SOAP::Data->name(OrderTotal => sprintf("%.2f", $amount / 100))
                                                   ->attr({currencyID=>'EUR', xmlns=>'urn:ebay:apis:eBLBaseComponents'}),
                                         SOAP::Data->name(ReturnURL  => $returnurl),
                                         SOAP::Data->name(CancelURL  => $cancelurl),
                                         SOAP::Data->name(NoShipping => 1),
## TODO: should be set to local lang-code
                                         SOAP::Data->name(LocaleCode => 'DE'),
                                                    )   )->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'})
                        )     )                )   );
  };

  if($@) {
    $c->log->error("***Paypal::set_express_checkout SOAP request failed: $@");
    $c->session->{prov_error} = 'Server.Paypal.Fault';
    return;
  }

  if(ref $return eq 'SOAP::SOM' and $return->fault) {
    $c->log->error("***Paypal::set_express_checkout SOAP Fault from Paypal server: ".
                   $return->faultstring . " - " . $return->faultdetail);
    $c->session->{prov_error} = 'Server.Paypal.Fault';
    return;
  } elsif(ref $return eq 'SOAP::SOM') {
    my $result = $return->method;
    if($$result{Ack} eq 'Failure') {
      $c->log->error("***Paypal::set_express_checkout SOAP Error response from Paypal server: ".
                     $$result{Errors}{ErrorCode} . " - " . $$result{Errors}{LongMessage});
      $c->session->{prov_error} = 'Server.Paypal.Fault';
      return;
    } elsif($$result{Ack} eq 'Success') {
      $c->session->{paypal}{Token} = $$result{Token};
      $c->session->{paypal}{CorrelationID} = $$result{CorrelationID};
      $c->session->{paypal}{Timestamp} = $$result{Timestamp};
      $c->session->{paypal}{Amount} = $amount;
    } else {
      $c->log->error("***Paypal::set_express_checkout invalid response from Paypal server: ". Dumper $result);
      $c->session->{prov_error} = 'Server.Paypal.Invalid';
      return;
    }
  } else {
    $c->log->error("***Paypal::set_express_checkout invalid/no response from Paypal server: ". Dumper $return);
    $c->session->{prov_error} = 'Server.Paypal.Invalid';
    return;
  }

  return 1;
}

sub do_express_checkout {
    my ($self, $c) = @_;

    $c->log->debug("***Paypal::do_express_checkout: called");

    my $return = eval {
        SOAP::Lite->uri($c->config->{paypal_soapuri})
                  ->proxy($c->config->{paypal_soapurl})
                  ->autotype(0)  # prevent SOAP::Lite from adding type declarations
                  ->call(SOAP::Data->name('DoExpressCheckoutPaymentReq')->attr({xmlns => 'urn:ebay:api:PayPalAPI'})
                           => (SOAP::Header->name(RequesterCredentials =>
                                 \SOAP::Data->value(SOAP::Data->name(Credentials =>
                                    \SOAP::Data->value(SOAP::Data->name(Username  => $c->config->{paypal_username}),
                                                       SOAP::Data->name(Password  => $c->config->{paypal_password}),
                                                       SOAP::Data->name(Signature => $c->config->{paypal_signature}),
                                                       SOAP::Data->name(Subject   => undef),
                                                      )             )->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'})
                                                   )
                                                 )->attr({xmlns=>'urn:ebay:api:PayPalAPI'}),
                               SOAP::Data->name(DoExpressCheckoutPaymentRequest =>
                                 \SOAP::Data->value(
                                    SOAP::Data->name(Version => '3.2')->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'}),
                                    SOAP::Data->name(DoExpressCheckoutPaymentRequestDetails =>
                                      \SOAP::Data->value(
                                         SOAP::Data->name(Token         => $c->session->{paypal}{Token}),
                                         SOAP::Data->name(PaymentAction => 'Sale'),
                                         SOAP::Data->name(PayerID       => $c->session->{paypal}{PayerID}),
                                         SOAP::Data->name(PaymentDetails =>
                                           \SOAP::Data->value(
                                              SOAP::Data->name(OrderTotal => sprintf("%.2f", $c->session->{paypal}{Amount} / 100))
                                                        ->attr({currencyID=>'EUR', xmlns=>'urn:ebay:apis:eBLBaseComponents'}),
                                                         )   ),
                                                    )   )->attr({xmlns=>'urn:ebay:apis:eBLBaseComponents'})
                        )     )                )   );
  };

  if($@) {
    $c->log->error("***Paypal::do_express_checkout SOAP request failed: $@");
    $c->session->{prov_error} = 'Server.Paypal.Fault';
    return;
  }

  if(ref $return eq 'SOAP::SOM' and $return->fault) {
    $c->log->error("***Paypal::do_express_checkout SOAP Fault from Paypal server: ".
                   $return->faultstring . " - " . $return->faultdetail);
    $c->session->{prov_error} = 'Server.Paypal.Fault';
    return;
  } elsif(ref $return eq 'SOAP::SOM') {
    my $result = $return->method;
    if($$result{Ack} eq 'Failure') {
      $c->log->error("***Paypal::do_express_checkout SOAP Error response from Paypal server: ".
                     $$result{Errors}{ErrorCode} . " - " . $$result{Errors}{LongMessage});
      $c->session->{prov_error} = 'Server.Paypal.Fault';
      return;
    } elsif($$result{Ack} eq 'Success') {
      
    } else {
      $c->log->error("***Paypal::do_express_checkout invalid response from Paypal server: ". Dumper $result);
      $c->session->{prov_error} = 'Server.Paypal.Invalid';
      return;
    }
  } else {
    $c->log->error("***Paypal::do_express_checkout invalid/no response from Paypal server: ". Dumper $return);
    $c->session->{prov_error} = 'Server.Paypal.Invalid';
    return;
  }

  return 1;
}

# eBay Language has some non-standard data types that SOAP::Lite doesn't
# support, so we need to add a method for it here.
# Aaaarrgh. Stupid, stupid, stupid, ugly, stupid hack. Stupid!
*SOAP::Deserializer::as_ExpressCheckoutTokenType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_PaymentTransactionCodeType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_PaymentCodeType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_PaymentStatusCodeType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_PendingStatusCodeType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_ReversalReasonCodeType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::Deserializer::as_BasicAmountType = \&SOAP::XMLSchema1999::Deserializer::as_string;
*SOAP::XMLSchema2001::Deserializer::as_token = \&SOAP::XMLSchema1999::Deserializer::as_string;

=head1 BUGS AND LIMITATIONS

=over

=item functions should be documented

=back

=head1 SEE ALSO

Sipwise::Provisioning::Voip

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Sipwise::Paypal module is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. You should have received a copy of the licences terms together
with the software.

=cut

# over and out
1;
