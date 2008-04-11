package csc::Controller::shop;

use strict;
use warnings;
use base 'Catalyst::Controller';
use UUID;
use Net::SMTP;
use PDF::Reuse;

=head1 NAME

csc::Controller::shop - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/');
}

=head2 hardware

=cut

sub hardware : Local {
    my ( $self, $c ) = @_;

    $c->session->{shop}{session_key} = $self->_generate_session_key()
        unless $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/hardware.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};

    $self->_load_products($c) or return;

    foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
        my $name = $$product{name};
        $name =~ s/ /_/g;
        $c->stash->{product_hash}{$name}{price} = sprintf "%.2f", $$product{price} / 100;
    }

    if(ref $c->session->{shop}{cart} eq 'HASH' and keys %{$c->session->{shop}{cart}}) {
        my (@cart, $price_sum);
        foreach my $ci (sort keys %{$c->session->{shop}{cart}}) {
            push @cart, { count => $c->session->{shop}{cart}{$ci},
                          product => $ci,
                          price => sprintf "%.2f", $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price} / 100 };
            $price_sum += $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price};
        }
        $c->stash->{price_sum} = sprintf "%.2f", $price_sum / 100;
        $c->stash->{cart} = \@cart;
    } else {
        $c->stash->{price_sum} = '0.00';
    }

    return 1;
}

=head2 add_to_cart

=cut

sub add_to_cart : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    # dump session from "solutions" area, is this really what we want?
    if(exists $c->session->{shop}{extensions}) {
        delete $c->session->{shop};
        delete $c->session->{refill};
        $c->session->{shop}{session_key} = $self->_generate_session_key();
    }

    unless(defined $c->request->params->{product} and length $c->request->params->{product}) {
        $c->log->error('***shop::add_to_cart no product specified');
        $c->session->{messages}{toperr} = 'Server.Internal';
        return;
    }
    my $product = $c->request->params->{product};

    my $count = $c->request->params->{count};
    $count = 1 unless $count;  # hmm, or shouldn't we?

    $self->_load_products($c) or return;
    unless(exists $c->session->{shop}{dbprodhash}{$product}) {
        $c->log->error("***shop::add_to_cart product '$product' not found in product hash");
        $c->session->{messages}{toperr} = 'Server.Internal';
        return;
    }

    $c->log->info("***shop::add_to_cart adding $count '$product' to cart");
    $c->session->{shop}{cart}{$product} += $count;

    $c->response->redirect('/shop/hardware?sk='. $c->session->{shop}{session_key});
    return;
}

=head2 clear_cart

=cut

sub clear_cart : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    delete $c->session->{shop};
    delete $c->session->{refill};

    $c->session->{shop}{session_key} = $self->_generate_session_key();

    $c->response->redirect('/shop/hardware?sk='. $c->session->{shop}{session_key});
    return;
}

=head2 show_cart

=cut

sub show_cart : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
            $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/cart.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};

    $self->_load_products($c) or return;

    if(ref $c->session->{shop}{cart} eq 'HASH' and keys %{$c->session->{shop}{cart}}) {
        my (@cart, $price_sum);
        foreach my $ci (sort keys %{$c->session->{shop}{cart}}) {
            push @cart, { count     => $c->session->{shop}{cart}{$ci},
                          product   => $ci,
                          price     => sprintf("%.2f", $c->session->{shop}{dbprodhash}{$ci}{price} / 100),
                          price_sum => sprintf("%.2f", $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price} / 100),
                        };
            $price_sum += $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price};
        }
        $c->stash->{price_sum} = sprintf "%.2f", $price_sum / 100;
        $c->stash->{tax_sum} = sprintf "%.2f", $price_sum * 0.002;
        $c->stash->{price_with_tax} = sprintf "%.2f", $c->stash->{price_sum} + $c->stash->{tax_sum};
        $c->stash->{cart} = \@cart;
    } else {
        $c->stash->{price_sum} = '0.00';
    }

}

=head2 update_cart

=cut

sub update_cart : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
            $c->request->params->{sk} eq $c->session->{shop}{session_key};

    unless(defined $c->request->params->{product} and length $c->request->params->{product}) {
        $c->log->error('***shop::update_cart no product specified');
        $c->session->{messages}{toperr} = 'Server.Internal';
        return;
    }
    my $product = $c->request->params->{product};

    my $count = $c->request->params->{count};
    $count = 0 unless $count;  # hmm, or shouldn't we?

    $self->_load_products($c) or return;
    unless(exists $c->session->{shop}{dbprodhash}{$product}) {
        $c->log->error("***shop::update_cart product '$product' not found in product hash");
        $c->session->{messages}{toperr} = 'Server.Internal';
        return;
    }

    if($count) {
        $c->log->info("***shop::update_cart setting '$product' count to '$count'");
        $c->session->{shop}{cart}{$product} = $count;
    } else {
        $c->log->info("***shop::update_cart removing '$product' from cart");
        delete $c->session->{shop}{cart}{$product};
    }

    $c->response->redirect('/shop/show_cart?sk='. $c->session->{shop}{session_key});
    return;
}

=head2 set_extensions

=cut

sub set_extensions : Local {
    my ( $self, $c ) = @_;

    # avoid direct access
    $c->response->redirect('http://www.libratel.at/')
        unless $c->request->params->{extensions};

    # create new shop session
    delete $c->session->{shop} if exists $c->session->{shop};
    delete $c->session->{refill} if exists $c->session->{refill};
    $c->session->{shop}{session_key} = $self->_generate_session_key();

    $c->session->{shop}{extensions} = $c->request->params->{extensions};

    $c->response->redirect('/shop/system?sk='. $c->session->{shop}{session_key});
}

=head2 system 

=cut

sub system : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/system.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};
    $c->stash->{tarif} = $c->session->{shop}{tarif};
    $c->stash->{extensions} = $c->session->{shop}{extensions};

    $self->_load_products($c) or return;

    foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
        next unless $$product{class} eq 'hardware';
        my $name = $$product{name};
        $name =~ s/ /_/g;
        $c->stash->{price}{$name} = sprintf "%.2f", $$product{price} / 100;
    }

    if(exists $c->session->{refill}{hardware}) {
        $c->stash->{refill} = $c->session->{refill}{hardware};
        if(($c->session->{shop}{extensions} == 1
            and $c->session->{refill}{hardware}{system} ne 'none'
                && $c->session->{refill}{hardware}{system} ne 'pap2t')
           or ($c->session->{shop}{extensions} == 4
               and $c->session->{refill}{hardware}{system} ne 'spa9000_4')
           or ($c->session->{shop}{extensions} == 16
               and $c->session->{refill}{hardware}{system} ne 'spa9000_16'))
        {
            $c->stash->{refill}{showmore}{system} = 1;
        }
        if($c->session->{refill}{hardware}{spa922}
           or $c->session->{refill}{hardware}{spa941}
           or $c->session->{refill}{hardware}{spa942})
        {
            $c->stash->{refill}{showmore}{phones} = 1;
        }
    } else {
        if($c->session->{shop}{extensions} == 1) {
            $c->stash->{refill} = { system => 'pap2t' };
        } elsif($c->session->{shop}{extensions} == 4) {
            $c->stash->{refill} = { system => 'spa9000_4' };
        } elsif($c->session->{shop}{extensions} == 16) {
            $c->stash->{refill} = { system => 'spa9000_16' };
        } else {
            $c->stash->{refill} = { system => 'none' };
        }
    }

    return 1;
}

=head2 set_system

=cut

sub set_system : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my %messages;

    if(!defined $c->request->params->{system}) {
        $messages{system} = 'Web.MissingSystem';
    } elsif($c->request->params->{system} eq 'pap2t') {
        foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
            next unless $$product{name} eq 'PAP2T';
            $c->session->{shop}{system}{name} = $$product{name};
            $c->session->{shop}{system}{price} = sprintf "%.2f", $$product{price} / 100;
        }
    } elsif($c->request->params->{system} eq 'spa9000_4') {
        foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
            next unless $$product{name} eq 'SPA9000 4 Port';
            $c->session->{shop}{system}{name} = $$product{name};
            $c->session->{shop}{system}{price} = sprintf "%.2f", $$product{price} / 100;
        }
    } elsif($c->request->params->{system} eq 'spa9000_16') {
        foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
            next unless $$product{name} eq 'SPA9000 16 Port';
            $c->session->{shop}{system}{name} = $$product{name};
            $c->session->{shop}{system}{price} = sprintf "%.2f", $$product{price} / 100;
        }
    } elsif($c->request->params->{system} eq 'none') {
        delete $c->session->{shop}{system} if exists $c->session->{shop}{system};
    } else {
        $messages{system} = 'Web.MissingSystem';
    }

    delete $c->session->{shop}{phones} if exists $c->session->{shop}{phones};

    my $spa921 = $c->request->params->{spa921};
    if($spa921) {
        if($spa921 =~ /^\d+$/) {
            my $price;
            foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
                next unless $$product{name} eq 'SPA921';
                $price = $$product{price};
            }
            push @{$c->session->{shop}{phones}}, { name => 'SPA921', count => $spa921,
                                                   price => $price / 100, price_sum => sprintf "%.2f", $spa921 * $price / 100 };
        } else {
            $messages{count} = 'Web.Syntax.Numeric';
        }
    }

    my $spa922 = $c->request->params->{spa922};
    if($spa922) {
        if($spa922 =~ /^\d+$/) {
            my $price;
            foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
                next unless $$product{name} eq 'SPA922';
                $price = $$product{price};
            }
            push @{$c->session->{shop}{phones}}, { name => 'SPA922', count => $spa922,
                                                   price => $price / 100, price_sum => sprintf "%.2f", $spa922 * $price / 100 };
        } else {
            $messages{count} = 'Web.Syntax.Numeric';
        }
    }

    my $spa941 = $c->request->params->{spa941};
    if($spa941) {
        if($spa941 =~ /^\d+$/) {
            my $price;
            foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
                next unless $$product{name} eq 'SPA941';
                $price = $$product{price};
            }
            push @{$c->session->{shop}{phones}}, { name => 'SPA941', count => $spa941,
                                                   price => $price / 100, price_sum => sprintf "%.2f", $spa941 * $price / 100 };
        } else {
            $messages{count} = 'Web.Syntax.Numeric';
        }
    }

    my $spa942 = $c->request->params->{spa942};
    if($spa942) {
        if($spa942 =~ /^\d+$/) {
            my $price;
            foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
                next unless $$product{name} eq 'SPA942';
                $price = $$product{price};
            }
            push @{$c->session->{shop}{phones}}, { name => 'SPA942', count => $spa942,
                                                   price => $price / 100, price_sum => sprintf "%.2f", $spa942 * $price / 100 };
        } else {
            $messages{count} = 'Web.Syntax.Numeric';
        }
    }

    $c->session->{refill}{hardware} = { system => $c->request->params->{system}, spa921 => $spa921,
                                        spa922 => $spa922, spa941 => $spa941, spa942 => $spa942 };

    if(keys %messages) {
        $c->session->{messages} = \%messages;
        $c->response->redirect('/shop/system?sk='. $c->session->{shop}{session_key});
    } else {
        $c->response->redirect('/shop/tarif?sk='. $c->session->{shop}{session_key});
    }

    return 0;
}

=head2 tarif

=cut

sub tarif : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/tarif.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};

    my $products;
    return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_products',
                                                        undef,
                                                        \$products,
                                                      );
    $c->session->{shop}{dbproducts} = $$products{result};
#    foreach my $product (@{$c->session->{shop}{dbproducts}}) {
#        next unless $$product{class} eq 'voip';
#        $c->stash->{products}{$$product{name}} = $product;
#    }

    return 1;
}

=head2 set_tarif

=cut

sub set_tarif : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    foreach my $product (@{$c->session->{shop}{dbprodarray}}) {
        next unless $$product{name} eq $c->request->params->{tarif};
        delete $c->session->{shop}{tarif} if exists $c->session->{shop}{tarif};
        $c->session->{shop}{tarif}{name} = $c->request->params->{tarif};
        $c->session->{shop}{tarif}{price} = sprintf "%.2f", $$product{price} / 100;
        if(defined $$product{billing_profile}) {
            my $bilprof;
            return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_billing_profile',
                                                                { billing_profile => $$product{billing_profile} },
                                                                \$bilprof,
                                                              );
            $c->session->{shop}{tarif}{monthly} = sprintf "%.2f", $$bilprof{interval_charge} / 100;
        } else {
            $c->session->{shop}{tarif}{monthly} = 0;
        }
        $c->session->{shop}{tarif}{initial_charge} = sprintf "%.2f", 10;
    }

    $c->response->redirect('/shop/personal?sk='. $c->session->{shop}{session_key});
}

=head2 personal 

=cut

sub personal : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/personal.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};
    $c->stash->{tarif} = $c->session->{shop}{tarif};
    $c->stash->{system} = $c->session->{shop}{system};
    $c->stash->{phones} = $c->session->{shop}{phones};
    $c->stash->{price_sum} = $self->_calculate_price_sum($c);

    if(exists $c->session->{refill}{personal}) {
        $c->stash->{refill} = $c->session->{refill}{personal};
    } else {
        $c->stash->{refill}{private_checked} = 'checked="checked"';
        $c->stash->{refill}{data_business_class} = 'data_business_hidden';
        $c->stash->{refill}{contact_business_class} = 'contact_business_hidden';
        $c->stash->{refill}{sign_like_contact} = 1;
        $c->stash->{refill}{tech_like_contact} = 1;
        $c->stash->{refill}{deliver_to_contact} = 1;
    }

    return 1;
}

=head2 set_personal

=cut

sub set_personal : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my (%settings, %messages);

    $settings{customer_type} = $c->request->params->{customer_type};

    if($settings{customer_type} eq 'business') {
        $settings{comregnum} = $c->request->params->{comregnum};
        unless(defined $settings{comregnum} and length $settings{comregnum}) {
            $messages{msgpersonal} = 'Web.MissingInput';
        }
        $settings{company} = $c->request->params->{company};
        unless(defined $settings{company} and length $settings{company}) {
            $messages{msgpersonal} = 'Web.MissingInput';
        }

        $settings{sign_like_contact} = defined $c->request->params->{sign_like_contact} ? 1 : 0;
        unless($settings{sign_like_contact}) {
            $settings{sign_contact}{gender} = $c->request->params->{sign_gender};
            unless(defined $settings{sign_contact}{gender} and length $settings{sign_contact}{gender}) {
                $messages{msgsign} = 'Web.MissingContactInfo';
            }

            $settings{sign_contact}{firstname} = $c->request->params->{sign_firstname};
            unless(defined $settings{sign_contact}{firstname} and length $settings{sign_contact}{firstname}) {
                $messages{msgsign} = 'Web.MissingContactInfo';
            }

            $settings{sign_contact}{lastname} = $c->request->params->{sign_lastname};
            unless(defined $settings{sign_contact}{lastname} and length $settings{sign_contact}{lastname}) {
                $messages{msgsign} = 'Web.MissingContactInfo';
            }

            $settings{sign_contact}{phonenumber} = $c->request->params->{sign_phonenumber};
            unless(defined $settings{sign_contact}{phonenumber} and length $settings{sign_contact}{phonenumber}) {
                $messages{msgsign} = 'Web.MissingContactInfo';
            }

            $settings{sign_contact}{email} = $c->request->params->{sign_email};
            unless(defined $settings{sign_contact}{email} and length $settings{sign_contact}{email}) {
                $messages{msgsign} = 'Web.MissingContactInfo';
            }
        }

        $settings{tech_like_contact} = defined $c->request->params->{tech_like_contact} ? 1 : 0;
        unless($settings{tech_like_contact}) {
            $settings{tech_contact}{gender} = $c->request->params->{tech_gender};
            unless(defined $settings{tech_contact}{gender} and length $settings{tech_contact}{gender}) {
                $messages{msgtech} = 'Web.MissingContactInfo';
            }

            $settings{tech_contact}{firstname} = $c->request->params->{tech_firstname};
            unless(defined $settings{tech_contact}{firstname} and length $settings{tech_contact}{firstname}) {
                $messages{msgtech} = 'Web.MissingContactInfo';
            }

            $settings{tech_contact}{lastname} = $c->request->params->{tech_lastname};
            unless(defined $settings{tech_contact}{lastname} and length $settings{tech_contact}{lastname}) {
                $messages{msgtech} = 'Web.MissingContactInfo';
            }

            $settings{tech_contact}{phonenumber} = $c->request->params->{tech_phonenumber};
            unless(defined $settings{tech_contact}{phonenumber} and length $settings{tech_contact}{phonenumber}) {
                $messages{msgtech} = 'Web.MissingContactInfo';
            }

            $settings{tech_contact}{email} = $c->request->params->{tech_email};
            unless(defined $settings{tech_contact}{email} and length $settings{tech_contact}{email}) {
                $messages{msgtech} = 'Web.MissingContactInfo';
            }
        }
    }

    $settings{gender} = $c->request->params->{gender};
    unless(defined $settings{gender} and length $settings{gender}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{firstname} = $c->request->params->{firstname};
    unless(defined $settings{firstname} and length $settings{firstname}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{lastname} = $c->request->params->{lastname};
    unless(defined $settings{lastname} and length $settings{lastname}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{street} = $c->request->params->{street};
    unless(defined $settings{street} and length $settings{street}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{postcode} = $c->request->params->{postcode};
    unless(defined $settings{postcode} and length $settings{postcode}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{city} = $c->request->params->{city};
    unless(defined $settings{city} and length $settings{city}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{phonenumber} = $c->request->params->{phonenumber};
    unless(defined $settings{phonenumber} and length $settings{phonenumber}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{email} = $c->request->params->{email};
    unless(defined $settings{email} and length $settings{email}) {
        $messages{msgpersonal} = 'Web.MissingInput';
    }
    $settings{newsletter} = $c->request->params->{newsletter};

    ## delivery address spec ##
    $settings{deliver_to_contact} = defined $c->request->params->{deliver_to_contact} ? 1 : 0;
    unless($settings{deliver_to_contact}) {
        $settings{delivery}{gender} = $c->request->params->{deli_gender};
        unless(defined $settings{delivery}{gender} and length $settings{delivery}{gender}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
        $settings{delivery}{firstname} = $c->request->params->{deli_firstname};
        unless(defined $settings{delivery}{firstname} and length $settings{delivery}{firstname}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
        $settings{delivery}{lastname} = $c->request->params->{deli_lastname};
        unless(defined $settings{delivery}{lastname} and length $settings{delivery}{lastname}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
        $settings{delivery}{company} = $c->request->params->{deli_company};
        unless(defined $settings{delivery}{company} and length $settings{delivery}{company}) {
            delete $settings{delivery}{company};
        }
        $settings{delivery}{street} = $c->request->params->{deli_street};
        unless(defined $settings{delivery}{street} and length $settings{delivery}{street}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
        $settings{delivery}{postcode} = $c->request->params->{deli_postcode};
        unless(defined $settings{delivery}{postcode} and length $settings{delivery}{postcode}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
        $settings{delivery}{city} = $c->request->params->{deli_city};
        unless(defined $settings{delivery}{city} and length $settings{delivery}{city}) {
            $messages{msgdelivery} = 'Web.MissingContactInfo';
        }
    }

    $settings{username} = lc($c->request->params->{username});
    if(!defined $settings{username} or length $settings{username} == 0) {
        $messages{msgusername} = 'Client.Syntax.MissingUsername';
    }
    unless($messages{msgusername}) {
        my $checkresult;
        return unless $c->model('Provisioning')->call_prov($c, 'voip', 'check_username',
                                                           $settings{username}, \$checkresult);
        $messages{msgusername} = 'Client.Syntax.MalformedUsername'
            unless $checkresult;
        if($c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber',
                                                { username => $settings{username},
                                                  domain   => $c->config->{site_domain},
                                                }))
        {
            $messages{msgusername} = 'Client.Voip.ExistingSubscriber';
        } elsif($c->session->{prov_error} eq 'Client.Voip.NoSuchSubscriber') {
            delete $c->session->{prov_error};
        } else {
            return;
        }
    }

    my $passwd1 = $c->request->params->{fpasswort1};
    my $passwd2 = $c->request->params->{fpasswort2};
    if(!defined $passwd1 or length $passwd1 == 0) {
        $messages{msgpasswd} = 'Client.Voip.MissingPass';
    } elsif(length $passwd1 < 6) {
        $messages{msgpasswd} = 'Client.Voip.PassLength';
    } elsif(!defined $passwd2 or length $passwd2 == 0) {
        $messages{msgpasswd} = 'Client.Voip.MissingPass2';
    } elsif($passwd1 ne $passwd2) {
        $messages{msgpasswd} = 'Client.Voip.PassNoMatch';
    }

    $c->session->{refill}{personal} = \%settings;
    if($settings{customer_type} eq 'business') {
        $c->session->{refill}{personal}{business_checked} = 'checked="checked"';
        $c->session->{refill}{personal}{data_business_class} = 'data_business_show';
        $c->session->{refill}{personal}{contact_business_class} = 'contact_business_show';
    } else {
        $c->session->{refill}{personal}{private_checked} = 'checked="checked"';
        $c->session->{refill}{personal}{data_business_class} = 'data_business_hidden';
        $c->session->{refill}{personal}{contact_business_class} = 'contact_business_hidden';
    }

    if(keys %messages) {
        $c->session->{messages} = \%messages;
        $c->response->redirect('/shop/personal?sk='. $c->session->{shop}{session_key});
    } else {
        $settings{password} = $passwd1;
        $c->session->{shop}{personal} = \%settings;
        $c->response->redirect('/shop/number?sk='. $c->session->{shop}{session_key});
    }

    return 0;
}

=head2 number 

=cut

sub number : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = 'tt/shop/number.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};
    $c->stash->{tarif} = $c->session->{shop}{tarif};
    $c->stash->{system} = $c->session->{shop}{system};
    $c->stash->{phones} = $c->session->{shop}{phones};
    $c->stash->{price_sum} = $self->_calculate_price_sum($c);

    unless($c->session->{shop}{available_numbers}) {
        my $free_numbers;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_free_numbers',
                                                            { limit  => 50 },
                                                            \$free_numbers
                                                          );
        $c->session->{shop}{available_numbers} = [ sort { $$a{cc} <=> $$b{cc} or
                                                          $$a{ac} <=> $$b{ac} or
                                                          $$a{sn} <=> $$b{sn} }
                                                        @{$$free_numbers{result}}
                                                 ];
    }
    $c->stash->{available_numbers} = $c->session->{shop}{available_numbers};

    if(exists $c->session->{refill}{number}) {
        $c->stash->{refill} = $c->session->{refill}{number};
        if($c->session->{refill}{number}{number}) {
            foreach my $num (@{$c->stash->{available_numbers}}) {
                next unless $c->session->{refill}{number}{number} eq "$$num{cc}-$$num{ac}-$$num{sn}";
                $$num{selected} = 1;
            }
        }
    }

    return 1;
}

=head2 set_number

=cut

sub set_number : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my %messages;

    my $number = $c->request->params->{number};
    if(defined $number and $number) {
        @{$c->session->{shop}{number}}{'cc','ac','sn'} = split /-/, $number;
    } else {
        $messages{msgnumber} = 'Client.Voip.ChooseNumber';
    }
    $c->session->{refill}{number}{number} = $number;

    $c->session->{refill}{number}{phonebook} =
        $c->session->{shop}{phonebook} =
            defined $c->request->params->{phonebook} ? 1 : 0;


    if(keys %messages) {
        $c->session->{messages} = \%messages;
        $c->response->redirect('/shop/number?sk='. $c->session->{shop}{session_key});
    } else {
        $c->response->redirect('/shop/overview?sk='. $c->session->{shop}{session_key});
    }

    return 0;
}

=head2 overview 

=cut

sub overview : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->stash->{template} = $c->session->{shop}{paid_ok} ? 'tt/shop/finish.tt' : 'tt/shop/overview.tt';
    $c->stash->{sk} = $c->session->{shop}{session_key};
    $c->stash->{tarif} = $c->session->{shop}{tarif};

    if(ref $c->session->{shop}{cart} eq 'HASH' and keys %{$c->session->{shop}{cart}}) {
        my @cart;
        foreach my $ci (sort keys %{$c->session->{shop}{cart}}) {
            push @cart, { count     => $c->session->{shop}{cart}{$ci},
                          product   => $ci,
                          price     => sprintf("%.2f", $c->session->{shop}{dbprodhash}{$ci}{price} / 100),
                          price_sum => sprintf("%.2f", $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price} / 100),
                        };
        }
        $c->stash->{cart} = \@cart;
    } elsif(ref $c->session->{shop}{system} eq 'HASH') {
        $c->stash->{system} = $c->session->{shop}{system};
        $c->stash->{phones} = $c->session->{shop}{phones};
    }

    $c->session->{shop}{price_sum} = $self->_calculate_price_sum($c);
    $c->stash->{price_sum} = $c->session->{shop}{price_sum};
    $c->stash->{month_sum} = $c->stash->{tarif}{monthly};
    $c->stash->{shipping_fee} = $c->session->{shop}{shipping_fee} = '9.50';
    $c->stash->{price_sum2} = sprintf "%.2f", $c->session->{shop}{price_sum} + $c->stash->{shipping_fee};
    $c->stash->{price_tax} = sprintf "%.2f", $c->stash->{price_sum2} * .2;
    $c->stash->{month_tax} = sprintf "%.2f", $c->stash->{month_sum} * .2;
    $c->session->{shop}{price_sum} = $c->stash->{price_sum3} = sprintf "%.2f", $c->stash->{price_sum2} + $c->stash->{price_tax};
    $c->stash->{month_sum2} = sprintf "%.2f", $c->stash->{month_sum} + $c->stash->{month_tax};

    $c->stash->{personal} = $c->session->{shop}{personal};
    $c->stash->{number} = '0'. $c->session->{shop}{number}{ac} .' '. $c->session->{shop}{number}{sn};
    $c->stash->{phonebook} = $c->session->{shop}{phonebook};

    return 1;
}

=head2 topayment

=cut

sub topayment : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    my %messages;

    if(!defined $c->request->params->{agb}) {
        $messages{agb} = 'Web.MissingAGB';
    }

    if(keys %messages) {
        $c->session->{messages} = \%messages;
        $c->response->redirect('/shop/overview?sk='. $c->session->{shop}{session_key});
    } else {
        unless($self->_create_contracts($c)) {
            $c->session->{messages} = \%messages;
            $c->response->redirect('/shop/overview?sk='. $c->session->{shop}{session_key});
        } else {
            $c->response->redirect('/payment?sk='. $c->session->{shop}{session_key});
        }
    }

    return;
}

=head2 finish 

=cut

sub finish : Local {
    my ( $self, $c ) = @_;

    $c->response->redirect('http://www.libratel.at/')
        unless defined $c->request->params->{sk} and
               $c->request->params->{sk} eq $c->session->{shop}{session_key};

    $c->session->{shop}{paid_ok} = 1;
    $c->response->redirect('/shop/overview?sk='. $c->session->{shop}{session_key});
    return;
}

sub _generate_session_key : Private {
    my $self = shift;

    my ($uuid_bin, $uuid_string);
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_string);

    return $uuid_string;
}

sub _calculate_price_sum : Private {
    my ($self, $c) = @_;

    my $price = 0;

    if(ref $c->session->{shop}{cart} eq 'HASH' and keys %{$c->session->{shop}{cart}}) {
        foreach my $ci (sort keys %{$c->session->{shop}{cart}}) {
            $price += $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price} / 100;
        }
    } else {
        $price = $c->session->{shop}{system}{price} || 0;
        if(ref $c->session->{shop}{phones} eq 'ARRAY') {
            foreach my $phone (@{$c->session->{shop}{phones}}) {
                $price += $$phone{price_sum};
            }
        }
    }

    $price += $c->session->{shop}{tarif}{price} if $c->session->{shop}{tarif}{price};
    $price += $c->session->{shop}{tarif}{initial_charge} if $c->session->{shop}{tarif}{initial_charge};

    return sprintf "%.2f", $price;
}

sub _create_contracts : Private {
    my ($self, $c) = @_;

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

    unless($c->session->{shop}{dbinvoice}) {
        my @nowts = localtime time;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'create_invoice',
                                                            { month => $nowts[4] + 1, year => $nowts[5] - 100 },
                                                            \$c->session->{shop}{dbinvoice}
                                                          );
    }

    unless($c->session->{shop}{order_id}
           or $c->model('Provisioning')->call_prov($c, 'billing', 'create_order',
                                                   { customer_id => $c->session->{shop}{customer_id},
                                                     type        => 'web',
                                                     value       => $c->session->{shop}{price_sum} * 100,
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
                                                     invoice     => $c->session->{shop}{dbinvoice},
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

    if($c->session->{shop}{tarif}{initial_charge}) {
        $c->model('Provisioning')->call_prov( $c, 'billing', 'update_voip_account_balance',
                                              { id   => $c->session->{shop}{account_id},
                                                data => { cash => $c->session->{shop}{tarif}{initial_charge} * 100 }
                                              },
                                              undef
                                            ) or return;
    }

    unless( ! $c->session->{shop}{system}{name}
           or $c->session->{shop}{system}{contract_id})
    {
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

    unless($self->_send_ack_mail($c)) {
        $c->log->error('***shop::topayment failed to send e-mail for customer '. $c->session->{shop}{customer_id});
    }

    return 1;
}

sub _generate_sip_password : Private {
    my ($self,$c) = @_;

    return substr crypt($c->session->{shop}{session_key}, $c->session->{shop}{session_key}), 2;
}

sub _send_ack_mail : Private {
    my ($self, $c) = @_;

    my $smtp = Net::SMTP->new('localhost') or return;
    $smtp->mail('shop@libratel.at') or return;
    unless($c->config->{development}) {
        $smtp->recipient($c->session->{shop}{personal}{email}) or return;
        $smtp->recipient('office@libratel.at') or return;
    }
    $smtp->recipient('dtiefnig@sipwise.com') or return;
    $smtp->data() or return;
    $smtp->datasend("From: shop\@libratel.at\n");
    $smtp->datasend('To: '. $c->session->{shop}{personal}{email} ."\n");
    $smtp->datasend("Subject: Ihre Bestellung bei Libratel\n");
    $smtp->datasend("Content-Type: text/plain; charset=UTF-8; format=flowed\n");
    $smtp->datasend("Content-Transfer-Encoding: 8bit\n");
    $smtp->datasend("\n");

    $smtp->datasend("
--------------------------------------------------------------------
AUFTRAGSBESTÄTIGUNG                  LIBRATEL IP COMMUNICATIONS GMBH
--------------------------------------------------------------------

Sehr geehrte Damen und Herren,

vielen Dank für Ihren Einkauf bei Libratel. Wir freuen uns, Sie als
Kunden begrüßen zu dürfen und haben Ihre Bestellung wie folgt
aufgenommen:

");
    $smtp->datasend("AUFTRAGSNUMMER: ". $c->session->{shop}{dbinvoice} ."\n");
    $smtp->datasend("
                                        Einmalig           Monatlich
--------------------------------------------------------------------
");
    $smtp->datasend("1 x Tarif ". $c->session->{shop}{tarif}{name} .
                    " " x (30 - length $c->session->{shop}{tarif}{name}) .
                    "EUR ". $c->session->{shop}{tarif}{price} .
                    " " x (15 - length $c->session->{shop}{tarif}{price}) .
                    "EUR ". $c->session->{shop}{tarif}{monthly} ."\n");
    $smtp->datasend("1 x Startguthaben ". " " x 22 .
                    "EUR ". $c->session->{shop}{tarif}{initial_charge} .
                    " " x (15 - length $c->session->{shop}{tarif}{initial_charge}) .
                    "EUR 0.00\n");
    if(ref $c->session->{shop}{cart} eq 'HASH' and keys %{$c->session->{shop}{cart}}) {
        foreach my $ci (sort keys %{$c->session->{shop}{cart}}) {
            my $tprice = sprintf("%.2f", $c->session->{shop}{cart}{$ci} * $c->session->{shop}{dbprodhash}{$ci}{price} / 100);
            $smtp->datasend($c->session->{shop}{cart}{$ci} ."x ". $ci .
                            " " x ((38 - length $c->session->{shop}{cart}{$ci}) - length $ci) .
                            "EUR ". $tprice . " " x (15 - length $tprice) . "EUR 0.00\n");
        }
    } else {
        $smtp->datasend("1 x ". $c->session->{shop}{system}{name} .
                        " " x (36 - length $c->session->{shop}{system}{name}) .
                        "EUR ". $c->session->{shop}{system}{price} .
                        " " x (15 - length $c->session->{shop}{system}{price}) .
                        "EUR 0.00\n")
            if $c->session->{shop}{system}{name};
        if(ref $c->session->{shop}{phones} eq 'ARRAY') {
            foreach my $phone (@{$c->session->{shop}{phones}}) {
                $smtp->datasend($$phone{count} ." x ". $$phone{name} .
                                " " x (32 - length $$phone{count} - length $$phone{name}) .
                                "EUR ". $$phone{price_sum} .
                                " " x (15 - length $$phone{price_sum}) .
                                "EUR 0.00\n");
            }
        }
    }

    $smtp->datasend("--------------------------------------------------------------------\n");
    my $price_sum1 = $self->_calculate_price_sum($c);
    $smtp->datasend("Zwischensumme" . " " x 27 .
                    "EUR ". $price_sum1 .
                    " " x (15 - length $price_sum1) .
                    "EUR ". $c->session->{shop}{tarif}{monthly} ."\n");
    $smtp->datasend("+Versandkosten". " " x 26 .
                    "EUR ". $c->session->{shop}{shipping_fee} .
                    " " x (15 - length $c->session->{shop}{shipping_fee}) .
                    "EUR 0.00\n");
    my $price_tax = sprintf "%.2f", ($price_sum1 + $c->session->{shop}{shipping_fee}) * .2;
    my $month_tax = sprintf "%.2f", $c->session->{shop}{tarif}{monthly} * .2;
    $smtp->datasend("+20% USt". " " x 32 .
                    "EUR ". $price_tax .
                    " " x (15 - length $price_tax) .
                    "EUR ". $month_tax ."\n");
    $smtp->datasend("--------------------------------------------------------------------\n");
    $smtp->datasend("\n");
    my $month_sum = sprintf "%.2f", $c->session->{shop}{tarif}{monthly} + $month_tax;
    $smtp->datasend("Summe" . " " x 35 .
                    "EUR ". $c->session->{shop}{price_sum} .
                    " " x (15 - length $c->session->{shop}{price_sum}) .
                    "EUR ". $month_sum ."\n");
    $smtp->datasend("\n\n");

    $smtp->datasend("GESAMTBETRAG:". " " x 5 . "EUR ". $c->session->{shop}{price_sum} ." inkl. USt\n");
    $smtp->datasend("\n");

    $smtp->datasend("VERSANDART:". " " x 7 . "Hermes Paketversand\n");
    $smtp->datasend("\n");

    $smtp->datasend("RECHNUNGSADRESSE: " . $c->session->{shop}{personal}{firstname} ." ".
                                           $c->session->{shop}{personal}{lastname} ."\n");
    $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{company} ."\n") if $c->session->{shop}{personal}{company};
    $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{street} ."\n");
    $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{postcode} ." ". $c->session->{shop}{personal}{city} ."\n");
    $smtp->datasend("\n");

    if(ref $c->session->{shop}{personal}{delivery} eq 'HASH') {
        $smtp->datasend("VERSANDADRESSE:". " " x 3 .
                        $c->session->{shop}{personal}{delivery}{firstname} ." ".
                        $c->session->{shop}{personal}{delivery}{lastname} ."\n");
        $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{delivery}{company} ."\n")
            if $c->session->{shop}{personal}{delivery}{company};
        $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{delivery}{street} ."\n");
        $smtp->datasend(" " x 18 . $c->session->{shop}{personal}{delivery}{postcode} ." ".
                        $c->session->{shop}{personal}{delivery}{city} ."\n");
        $smtp->datasend("\n");
    } else {
        $smtp->datasend("VERSANDADRESSE:". " " x 3 . "Wie Rechnungsadresse.\n\n");
    }

    $smtp->datasend('
Ihre Rechnung wird Ihnen zusammen mit der Ware zugestellt.

--------------------------------------------------------------------
REGISTRIERUNGSDATEN                  LIBRATEL IP COMMUNICATIONS GMBH
--------------------------------------------------------------------
');
    $smtp->datasend('RUFNUMMER:'. ' ' x 4 .
                    '0'. $c->session->{shop}{number}{ac} .
                    ' '. $c->session->{shop}{number}{sn} ."\n");
    $smtp->datasend('BENUTZERNAME: '. $c->session->{shop}{personal}{username} ."\n");
    $smtp->datasend('PASSWORT:'. ' ' x 5 . $c->session->{shop}{personal}{password} ."\n"); 
    $smtp->datasend('
Wir empfehlen Ihnen, bei Ihrer ersten Anmeldung im Kundenbereich
Ihr Passwort unter dem Menüpunkt KONTO aus Sicherheitsgründen zu
ändern!

');
    $smtp->datasend('EMAIL:'. ' ' x 8 . $c->session->{shop}{personal}{email} . "\n");
    $smtp->datasend('
Ihre Rechnungen werden Ihnen an diese Email Adresse im .pdf
Format zugestellt!

');
    $smtp->datasend('TARIF:'. ' ' x 8 . $c->session->{shop}{tarif}{name} ."\n");
    $smtp->datasend('GUTHABEN:'. ' ' x 5 . $c->session->{shop}{tarif}{initial_charge} ."EUR\n");
    $smtp->datasend('
Sie können Ihr Guthaben jederzeit im Kundenbereich unter dem
Menüpunkt KONTO einsehen und aufladen.

Bei Fragen stehen wir Ihnen gerne per Email unter office@libratel.at
bzw. telefonisch unter 0720 456789 zur Verfügung.

Mit freundlichen Grüßen,

Ihr Libratel Team

--------------------------------------------------------------------
Libratel IP Communications GmbH       Geschäftsführer: Atilla Ceylan
Prof. Dr. Stephan Koren Straße 10                A-2700 Wr. Neustadt                

Email: office@libratel.at                Web: http://www.libratel.at
Tel: 0720 456789-0                               Fax: 0720 456789-10

Bankverbindung:   ERSTE Bank - BLZ: 20111 - Konto Nr: 288-112-575/00
                  BIC/SWIFT: GIBAATWW  -  IBAN: AT352011128811257500

Handelsgericht Wr. Neustadt          FN:293575d - UID Nr:ATU63410213
--------------------------------------------------------------------
');

    $smtp->dataend() or return;

    return 1;
}

sub _load_products : Private {
    my ( $self, $c, $force_reload ) = @_;

    if($force_reload or ! $c->session->{shop}{dbprodarray}) {

        delete $c->session->{shop}{dbprodarray};
        delete $c->session->{shop}{dbprodhash};

        my $products;
        return unless $c->model('Provisioning')->call_prov( $c, 'billing', 'get_products',
                                                            undef,
                                                            \$products,
                                                          );
        $c->session->{shop}{dbprodarray} = $$products{result};

        $products = {};
        for(@{$c->session->{shop}{dbprodarray}}) {
            $$products{$$_{name}} = $_;
        }
        $c->session->{shop}{dbprodhash} = $products;
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

The shop controller is Copyright (c) 2007 Sipwise GmbH, Austria. All
rights reserved.

=cut

1;
