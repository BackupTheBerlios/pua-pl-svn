package Winfo;

#
# An Event Package for handling xxx.winfo, see RFC-3858
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
use Watcherinfo;

use EventPackage;       # super class
use vars qw(@ISA);
@ISA = qw(EventPackage);



#
# Constructor only, rest is handled by base class

sub new {
    my $class        = shift;

    my $self         = {};
    bless($self);

    $self->{log}         = shift; # reference to the log object
    $self->{options}     = shift; # reference to the options object
    $self->{basepackage} = shift; # kind of package that is to be watched

    $self->{name}    = $self->{basepackage}.'.winfo'; # package name

    my $doc = new Watcherinfo($self->{log}, 
	                      $self->{options}, 
                              $self->{basepackage});
    push @{$self->{documents}}, $doc;

    $self->{log}->write(DEBUG, "Event Package $self->{name}: new");
    return $self;
}



1;
