package EventPackage;

#
# abstract class for dealing with the various event packages
# like presence, presence.winfo, reg, ... responsible for
# parsing of the corresponding XML documents and triggering
# actions, depending on the content
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $Date$, Conny Holzhey



use warnings;
use strict;

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging
use Options;            # to handle default options and the command line

require Exporter;

our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw($CRLF);


#
# Constructor

sub new {
    my $class        = shift;
    my $self         = {};

    $self->{log}     = shift;  # reference to the log object
    $self->{options} = shift;  # reference to the options object

    $self->{content_type} = undef; # needs to be overwritten
    $self->{name}         = undef; # package name, needs to be overwritten

    bless($self);
    return $self;
}


#
# returns event package name, e.g. 'presence.winfo'

sub get_name {
    my $self = shift;
    return $self->{name};
}


#
# returns XML document format as it is to be specified
# in the SUBSCRIBE Accept: header, e.g 'application/reginfo+xml'

sub get_content_type {
    my $self = shift;

    return $self->{content_type};
}

#
# this function gets the xml document as received with a NOTIFY
# expected return value: sort of string that describes what
# is found in the xml doc, depending whatever it is 

sub parse {
   my $self = shift;
}


1;
