package csc::Controller::calllist;

use strict;
use warnings;
use base 'Catalyst::Controller';
use csc::Utils;

=head1 NAME

csc::Controller::calllist - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

Displays incoming and outgoing calls for a subscriber.

=cut

sub index : Private {
    my ( $self, $c ) = @_;

    $c->log->debug('***calllist::index called');
    $c->stash->{template} = 'tt/calllist.tt';
    my @localized_months = ( "foo" );

    return 1 unless $c->model('Provisioning')->get_usr_preferences($c);

    $c->stash->{subscriber}{active_number} = csc::Utils::get_active_number_string($c);
    if($c->session->{user}{extension}) {
        my $ext = $c->session->{user}{preferences}{extension};
        $c->stash->{subscriber}{active_number} =~ s/$ext$/ - $ext/;
    }

    return 1 unless $c->model('Provisioning')->call_prov($c, 'billing', 'get_voip_account_by_id',
                                                         { id => $c->session->{user}{data}{account_id} },
                                                         \$c->stash->{subscriber}{account}
                                                        );

    my $cts = $c->session->{user}{data}{create_timestamp};
    if($cts =~ s/^(\d{4}-\d\d)-\d\d \d\d:\d\d:\d\d/$1/) {
        my ($cyear, $cmonth) = split /-/, $cts;
        my ($nyear, $nmonth) = (localtime)[5,4];
        $nyear += 1900;
        $nmonth++;

        for(1 .. 12) {
            my $amon = sprintf("%02d", $_);
            push @localized_months, $c->model('Provisioning')->localize($c, "Web.Months.".$amon) || $amon;
        }

        my @selectmonths;

        while($cyear < $nyear) {
            my @yearmon;
            for($cmonth .. 12) {
                my $amon = sprintf("%02d", $_);
                unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
            }
            unshift @selectmonths, { year => $cyear, months => \@yearmon };
            $cmonth = 1;
            $cyear++;
        }

        my @yearmon;
        for($cmonth .. $nmonth) {
            my $amon = sprintf("%02d", $_);
            unshift @yearmon, { display => $localized_months[$amon] ." $cyear", link => $cyear.$amon };
        }
        unshift @selectmonths, { year => $cyear, months => \@yearmon };

        $c->stash->{subscriber}{selectmonths} = \@selectmonths;
    }

    my $listfilter = $c->request->params->{list_filter};
    if(defined $listfilter) {
        if(length $listfilter) {
            $listfilter =~ s/^\*//;
            $listfilter =~ s/\*$//;
            $c->session->{user}{calls}{filter} = $listfilter;
        } else {
            delete $c->session->{user}{calls}{filter};
            undef $listfilter;
        }
    }

    my @localtime = localtime;

    my ($callmonth, $callyear);
    my $monthselect = $c->request->params->{listmonth};
    if(defined $monthselect and $monthselect =~ /^(\d{4})(\d{2})$/) {
        $callyear = $1;
        $callmonth = $2;
        $listfilter = $c->session->{user}{calls}{filter};
    } else {
        $callyear = $localtime[5] + 1900;
        $callmonth = $localtime[4] + 1;
        delete $c->session->{user}{calls}{filter};
        delete $c->session->{user}{calls}{start};
        delete $c->session->{user}{calls}{end};
    }

    my $liststart = $c->request->params->{list_start};
    if(defined $liststart) {
        if(length $liststart) {
            $c->stash->{subscriber}{list_start} = $liststart;
            if($liststart =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{user}{calls}{start} = $liststart;
            } else {
                $liststart = $c->session->{user}{calls}{start};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{user}{calls}{start};
            undef $liststart;
        }
    } else {
        $c->stash->{subscriber}{list_start} = $c->session->{user}{calls}{start};
    }

    my $listend = $c->request->params->{list_end};
    if(defined $listend) {
        if(length $listend) {
            $c->stash->{subscriber}{list_end} = $listend;
            if($listend =~ /^\d\d\.\d\d\.\d\d\d\d$/) {
                $c->session->{user}{calls}{end} = $listend;
            } else {
                $listend = $c->session->{user}{calls}{end};
                $c->session->{messages}{msgdate} = 'Client.Syntax.Date';
            }
        } else {
            delete $c->session->{user}{calls}{end};
            undef $listend;
        }
    } else {
        $c->stash->{subscriber}{list_end} = $c->session->{user}{calls}{end};
    }

    my ($sdate, $edate);
    if(!defined $liststart and !defined $listend) {
        $sdate = { year => $callyear, month => $callmonth };
        $edate = { year => $callyear, month => $callmonth };
        $c->stash->{subscriber}{call_range} = $localized_months[$callmonth] .' '. $callyear;
    } else {
        if(defined $liststart) {
            my ($day, $month, $year) = split /\./, $liststart;
            $sdate = { year => $year, month => $month, day => $day };
            if(defined $listend) {
                $c->stash->{subscriber}{call_range} = "$liststart";
            } else {
                $c->stash->{subscriber}{call_range}
                    = "$liststart - ". sprintf("%02d.%02d.%04d", $localtime[3],
                                                                 $localtime[4] + 1,
                                                                 $localtime[5] + 1900);
            }
        }
        if (defined $listend) {
            my ($day, $month, $year) = split /\./, $listend;
            $edate = { year => $year, month => $month, day => $day };
            if(defined $liststart) {
                $c->stash->{subscriber}{call_range} .= " - $listend";
            } else {
                my $cts = $c->session->{user}{data}{create_timestamp};
                $cts =~ /^(\d{4})-(\d\d)-(\d\d).+/;
                $c->stash->{subscriber}{call_range} = "$3.$2.$1 - $listend";
            }
        }
    }

    unless($c->model('Provisioning')->call_prov($c, 'voip', 'get_subscriber_calls',
                                                { username => $c->session->{user}{username},
                                                  domain   => $c->session->{user}{domain},
                                                  filter   => { start_date => $sdate,
                                                                end_date   => $edate,
                                                              }
                                                },
                                                \$c->session->{user}{call_list}
                                               ))
    {
        delete $c->session->{user}{call_list} if exists $c->session->{user}{call_list};
        return 1;
    }
    unless($c->model('Provisioning')->get_contacts_for_numbers($c)) {
        delete $c->session->{user}{call_list} if exists $c->session->{user}{call_list};
        return 1;
    }

    if($callyear == (localtime)[5] + 1900
       and $callmonth == (localtime)[4] + 1)
    {
        $c->stash->{subscriber}{call_list} = csc::Utils::prepare_call_list($c, $c->session->{user}{call_list}, 1, $listfilter)
            if @{$c->session->{user}{call_list}};
    } else {
        $c->stash->{subscriber}{call_list}{previous} = csc::Utils::prepare_call_list($c, $c->session->{user}{call_list}, 0, $listfilter)
            if @{$c->session->{user}{call_list}};
        $c->stash->{subscriber}{call_list} = undef
            unless defined $c->stash->{subscriber}{call_list}{previous};
    }

    delete $c->session->{user}{call_list} if exists $c->session->{user}{call_list};

    if(defined $listfilter and length $listfilter) {
        $c->stash->{subscriber}{call_filter} = "*$listfilter*";
        $c->stash->{subscriber}{list_filter} = "$listfilter";
    }
    $c->stash->{subscriber}{list_month} = sprintf("%04d%02d", $callyear, $callmonth);

}

=head1 BUGS AND LIMITATIONS

=over

=item none

=back

=head1 SEE ALSO

Provisioning model, Catalyst

=head1 AUTHORS

Daniel Tiefnig <dtiefnig@sipwise.com>

=head1 COPYRIGHT

The calllist controller is Copyright (c) 2007-2010 Sipwise GmbH,
Austria. All rights reserved.

=cut

1;
