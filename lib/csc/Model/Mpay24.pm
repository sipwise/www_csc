package csc::Model::Mpay24;

use strict;
use warnings;
use base 'Catalyst::Model';

=head1 NAME

csc::Model::Mpay24 - mPAY24 billing Model

=head1 DESCRIPTION

Catalyst model that uses the mPAY24 key/value interface to retrieve and
transfer money from customers.

=head1 METHODS

=head2 index

=over

Creates a new Mpay24 object. Takes no arguments, configuration is done
via settings in Catalyst->config hash. See csc.pm.

=back

=cut

sub new {
    my $class = shift;

    my $self = {};

    return bless $self, $class;
}

=head2 accept_cc_payment

=over

Issues a credit card request on mPAY24. Returns true on success, false
otherwise.
Parameters are:

=over

=item amount

The amount of money that should be charged in Euro cent.

=item brand

The credit card brand. Visa or Mastercard.

=item cardnumber

The credit card number. 11 to 16 digits.

=item expiry

The expiration date in the format YYMM.

=item cvc

The card validation code, only applicable for Visa cards.

=back

The transaction will be cleared immediately.

=back

=cut

sub accept_cc_payment {
    my ($self, $c, $tid, $amount, $brand, $cardnum, $expiry, $cvc) = @_;

    my $data = 'OPERATION=ACCEPTPAYMENT' .
               '&MERCHANTID='. $c->config->{mpay24_merchantid} .
               '&TID='. $tid .
               '&P_TYPE=CC' .
               '&BRAND='. $brand .
               '&CURRENCY=EUR' .
               '&PRICE='. $amount .
               '&IDENTIFIER='. $cardnum .
               '&EXPIRY='. $expiry .
               '&AUTH_3DS=Y' .
               '&CLEARING=0';
    $data .= '&CVC='. $cvc if $brand =~ /^visa$/i and defined $cvc;

    return $self->_call_api($c, $data, $tid);
}

=head2 accept_elv_payment

=over

Issues an ELV request on mPAY24. Returns true on success, false
otherwise.
Parameters are:

=over

=item amount

The amount of money that should be charged in Euro cent.

=item accountnumber

The bank account number. Depends on the bank institute.

=item bankid

The routing code of the bank institute.

=back

The transaction will be cleared immediately.

=back

=cut

sub accept_elv_payment {
    my ($self, $c, $tid, $amount, $accountnumber, $bankid) = @_;

    my $data = 'OPERATION=ACCEPTPAYMENT' .
               '&MERCHANTID='. $c->config->{mpay24_merchantid} .
               '&TID='. $tid .
               '&P_TYPE=ELV' .
               '&BRAND=HOBEX-AT' .
               '&CURRENCY=EUR' .
               '&PRICE='. $amount .
               '&IDENTIFIER='. $accountnumber .
               '&SORT_CODE='. $bankid .
               '&CLEARING=0';

    return $self->_call_api($c, $data, $tid);
}

=head2 accept_eps_payment

=over

Issues an EPS request on mPAY24. Returns true on success, false
otherwise.
Parameters are:

=over

=item amount

The amount of money that should be charged in Euro cent.

=item bankname

The name of the bank institute. One of the following:

=over

=item BA
Bank Austria Credit Anstalt

=item BAWAG

BAWAG P.S.K. Gruppe

=item ERSTE

Erste Bank & Sparkassen Gruppe

=item HYPO

Hypo Oberoesterreich

=item RZB

Raiffeisenbanken Gruppe

=item ARZ

used together with the parameter bankid

=back

=item bankid

Used together with bankname = ARZ, one of the following:

=over

=item 101

oesterreichische Volksbanken, Immo-Bank und Gaertnerbank

=item 093

Bank fuer Aerzte und Freie Berufe

=item 029

Niederoesterreichische Landesbank-Hypothekenbank AG

=item 019

Vorarlberger Landes- und Hypothekenbank AG

=item 011

Bankhaus Carl Spaengler & Co. AG

=item 002

Hypo Tirol Bank AG

=item 015

Hypo-Alpe-Adria-Bank AG and HYPO Alpe-Adria-Bank International AG

=item 109

Investkredit Bank AG

=back

=back

The request will return a redirect URL where the user should be sent.
This URL is store in the session as {mpay24}{LOCATION}.

=back

=cut

sub accept_eps_payment {
    my ($self, $c, $tid, $amount, $bankname, $bankid) = @_;

    my $data = 'OPERATION=ACCEPTPAYMENT' .
               '&MERCHANTID='. $c->config->{mpay24_merchantid} .
               '&TID='. $tid .
               '&P_TYPE=EPS' .
               '&CURRENCY=EUR' .
               '&PRICE='. $amount .
               '&BRAND='. $bankname;
    $data .= '&BANK_ID='. $bankid if $bankname =~ /^ARZ$/i;

    return $self->_call_api($c, $data, $tid);
}

=head2 accept_maestro_payment

=over

Issues a maestro secure code request on mPAY24. Returns true on success,
false otherwise.
Parameters are:

=over

=item amount

The amount of money that should be charged in Euro cent.

=item cardnumber

The secure code number that is printed on the maestro card.

=item expiry

The expiration date in the format YYMM. If the card does not have an
expiration month, use "12" as the month.

=back

The request will return a redirect URL where the user should be sent.
This URL is store in the session as {mpay24}{LOCATION}.

=back

=cut

sub accept_maestro_payment {
    my ($self, $c, $tid, $amount, $cardnum, $expiry) = @_;

    my $data = 'OPERATION=ACCEPTPAYMENT' .
               '&MERCHANTID='. $c->config->{mpay24_merchantid} .
               '&TID='. $tid .
               '&P_TYPE=MAESTRO' .
               '&CURRENCY=EUR' .
               '&PRICE='. $amount .
               '&IDENTIFIER='. $cardnum .
               '&EXPIRY='. $expiry;

    return $self->_call_api($c, $data, $tid);
}

sub _call_api {
    my ($self, $c, $data, $tid) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent('Sipwise CSC 1.0 ');

    my $req = HTTP::Request->new(POST => $c->config->{mpay24_baseurl});
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($data);

#    print STDERR "***Mpay24::_call_api calling API with $data\n";
    my $res = $ua->request($req);
#    print STDERR "***Mpay24::_call_api API call finished: ". $res->content;

    if ($res->is_success) {
        $c->session->{mpay24}{TID} = $tid;
        my $result = $self->_parse_url($res->content);
        $c->session->{mpay24}{STATUS} = $$result{STATUS};

        if($$result{STATUS} eq 'OK') {

            if($$result{RETURNCODE} eq 'OK') { # paid ok
                $c->session->{mpay24}{MPAYTID} = $$result{MPAYTID};
                return 1;
            } elsif($$result{RETURNCODE} eq 'REDIRECT') { # payment continues
                $c->session->{mpay24}{LOCATION} = $$result{LOCATION};
                return 2;
            } else {
                $c->log->error("***Mpay24::accept_cc_payment API call returned unknown ".
                               "RETURNCODE '$$result{RETURNCODE}': $data - ". $res->content);
                return;
            }

        } else {

            $c->log->error("***Mpay24::accept_cc_payment API call failed: $data - ". $res->content);
            $c->session->{mpay24}{TID} = $tid;
            $c->session->{mpay24}{MPAYTID} = $$result{MPAYTID};
            $c->session->{mpay24}{RETURNCODE} = $$result{RETURNCODE};
            $c->session->{mpay24}{ERRNO} = $$result{ERRNO};
            $c->session->{mpay24}{EXTERNALSTATUS} = $$result{EXTERNALSTATUS};

        }
    } else {
      $c->log->error("***Mpay24::accept_cc_payment API call failed: $data - ". $res->status_line);
    }

    return;
}

sub _parse_url {
    my ($self, $url) = @_;

    chomp $url;
    my @parts = split(/&/, $url);
    use Data::Dumper;

    my %return;

    foreach my $part (@parts) {
        my ($key, $value) = split(/=/, $part, 2);
        if(defined $value and length $value) {
            $value =~ s/\+/ /g;
            $value =~ s/\%([\da-f]{2})/chr hex $1/gei;
            # sigh. this is so stupid.
            utf8::encode($value);
            $return{$key} = $value;
        } else {
            $return{$key} = '';
        }
    }

    return \%return;
}

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The Sipwise::Mpay24 module is Copyright (c) 2007 Sipwise GmbH, Austria.
All rights reserved.

=cut

1;
