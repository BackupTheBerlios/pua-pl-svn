package Presence;

#
# An Event Package for handling presence of resources
# see RFC-3863
#
# part of pua.pl, a simple presence user agent,
# see http://pua-pl.berlios.de for licence
#
# $Date$ Conny Holzhey


use warnings;
use strict;

use XML::Parser;        # to parse pidf documents

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging
use Options;            # to handle default options and the command line
use Pidf;

use EventPackage;       # super class
use vars qw(@ISA);
@ISA = qw(EventPackage);



#
# Constructor only, rest is handled by base class

sub new {
    my $class        = shift;

    my $self         = {};
    bless($self);

    $self->{log}     = shift;      # reference to the log object
    $self->{options} = shift;      # reference to the options object
    $self->{name}    = 'presence'; # package name

    my $doc = new Pidf($self->{log}, $self->{options});

    push @{$self->{documents}}, $doc;

    $self->{log}->write(DEBUG, "Event Package presence: new");
    return $self;
}



1;
