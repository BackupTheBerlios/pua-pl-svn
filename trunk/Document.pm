package Document;

#
# abstract class for dealing with the various xml document
# types, like pidf, responsible for parsing and beautyfing
# the found content
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

#
# Constructor

sub new {
    my $class         = shift;
    my $self          = {};

    $self->{log}       = shift;  # reference to the log object
    $self->{options}   = shift;  # reference to the options object

    $self->set_template_file(shift);  # file name of the template file
    $self->set_output_file(shift);    # file name of the output file, if any

    $self->{content_type} = undef; # needs to be overwritten

    bless($self);
    return $self;
}



#
# returns XML document format as it is to be specified
# in the SUBSCRIBE Accept: header, e.g 'application/reginfo+xml'

sub get_content_type {
    my $self = shift;

    return $self->{content_type};
}


#
# to change the name of the template file

sub set_template_file {
    my $self = shift;
    $self->{tmpl_file} = shift;
}

#
# to change the name of the output file

sub set_output_file {
    my $self = shift;
    $self->{out_file} = shift;
}


#
# this function gets the xml document as received with a NOTIFY
# expected return value: sort of string that describes what
# is found in the xml doc, depending whatever it is 

sub parse {
   my $self = shift;
}


1;
