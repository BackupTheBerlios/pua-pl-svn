package EventPackage;

#
# abstract class for dealing with the various event packages
# like presence, presence.winfo, reg. Has a list of objects
# derived from Document.pm
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

    $self->{name}    = undef; # package name, needs to be overwritten

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
# returns a list of XML document formats as it is to be specified
# in the SUBSCRIBE Accept: header, e.g 'application/reginfo+xml'

sub get_content_types {
    my $self = shift;
    my @ret = ();
    my $doc;

    foreach $doc (@{$self->{documents}}) {
	push @ret, $doc->get_content_type();
    }
    return @ret;
}


#
# this function gets the xml document as received with a NOTIFY
# expected return value: sort of string that describes what
# is found in the xml doc, depending whatever it is 

sub parse {
    my $self = shift;
    my $cont = shift;
    my $content_type = shift;
    my $doc;

    # look for the matching document parser
    foreach $doc (@{$self->{documents}}) {
	if (lc($content_type) eq $doc->get_content_type()) {
	    return $doc->parse($cont);
	}
    }
    $self->{log}->write(INFO, "EventPackage: no matching doc ".
			"found for $content_type");
    return undef;
}


1;
