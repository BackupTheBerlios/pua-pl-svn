package Pidf;

#
# An module for parsing and interpretation of pidf documents, 
# see RFC-3863
#
# part of pua.pl, a simple presence user agent,
# see http://pua-pl.berlios.de for licence
#
# $Date:$ Conny Holzhey


use warnings;
use strict;

use XML::Parser;        # to parse pidf documents

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging
use Options;            # to handle default options and the command line

use Document;           # super class
use vars qw(@ISA);
@ISA = qw(Document);



#
# Constructor

sub new {
    my $class        = shift;

    my $self         = {};
    bless($self);

    $self->{log}     = shift;      # reference to the log object
    $self->{options} = shift;      # reference to the options object

    $self->{content_type} = 'application/pidf+xml'; 
    $self->{log}->write(DEBUG, "pidf: new");
    return $self;
}




# global variables, mainly internal states of the xml parser


# global variables, internal states of the pidf parser

my $pidf_tag;      # the last tag name identified
my %pidf_info;     # the collected info
my $log;           # of type Log::Easy
my $out;           # a text decribing the pidf
my $entity;        # entity name found inf the pidf document



#
# parse the presence pidf document, as it came with the NOTIFY message.
# Run a good-old xml pull parser, which dumps the found elements
# into the StartTag, EndTag and Text methods. Parameters:
# $self     - object reference
# $doc      - the entire document to parse
# Returns a string that describes the received content,
# or empty string if nothing usefull was found
sub parse {
    my ($self, $doc) = @_;

    $log       = $self->{log};
    $out       = '';

    my $parser = new XML::Parser(Style => 'Stream');
    $parser->setHandlers(Final => \&handle_final);

    # the actual interpretatoin is done in the handlers below
    $parser->parse($doc);

    return $out;
}


#
# handler for the pidf parser, called on each opening XML tag

sub StartTag {
    shift;
    my $tag = shift;
    # $log->write(SPEW, "pidf: StartTag $tag");

    if ($tag =~ /^(\w+:)?presence$/i) {
        my %e = %_;
	foreach (keys %e) {
	    next unless (/entity/i);
  	    $out .= 'Presence information for '. $e{$_} . ":\n";
	    $entity = $e{$_};
	}
    } 

    # keep the priority atribute of contact
    if ($tag =~ /^(\w+:)?contact$/i) { 
        my %p = %_;
	foreach (keys %p) {
  	    next unless (/priority/i);

	    # keep it 
	    $pidf_info{'_priority'} = $p{$_};
	}
    }

    # keep the fact that we are within a tuple
    if ($tag =~ /^(\w+:)?tuple$/i) { 
        $pidf_info{'_tuple'} = 1;
    }

    $pidf_tag = $tag;
}


#
# handler for the pidf parser, called on everything which is not a tag

sub Text {
    if (defined($pidf_tag)) {

	# $log->write(SPEW, "pidf: Tag: $pidf_tag, text $_");

        # keep only texts that have non-whitespace content
        unless (/^\s+$/s) {
	    s/^\s+//s; # erase leading whitespace
	    s/\s+$//s; # erase trailing whitespace

	    if (exists $pidf_info{'_tuple'}) {
	        if (exists $pidf_info{$pidf_tag}) {
		    $pidf_info{$pidf_tag} .= "\n    ".$_;
		} else {
		    $pidf_info{$pidf_tag} = $_; 
		}
            } else {
	        # notes can be outside of a tuple
	        if ($pidf_tag =~ /^(\w+:)?note$/) {
		    $out .= '  note: '.$_."\n";
	        }
            }
	}
    }
}

#
# handler for the pidf parser, called on each closing tag

sub EndTag {
    my $tag = $_;

    # $log->write(SPEW, "pidf: EndTag $tag");

    if (defined($pidf_tag)) {
        undef $pidf_tag;
    }
	
    # print all about the tuple when it is closed

    if ($tag =~ /<\/(\w+:)?tuple>/i) {

	my($status, $contact, $prio, $note, $timestamp);

        foreach (keys %pidf_info) {
	    # filter a bit
 	    if (/^(\w+:)?basic$/i) {

		$status = $pidf_info{$_};;

	        if ($pidf_info{$_} =~ /closed/i) {
		    $out .= " not available or not online\n";
  	        } elsif ($pidf_info{$_} =~ /open/i) {
		    $out .= "  available and online\n";
	        }

		# in case there was a priority attribute, print it
		if (exists $pidf_info{'_priority'}) {
		    $prio = $pidf_info{'_priority'};
 	 	    $out .= '    prioity of this way of communication: ' . $prio;
		    if ($prio == 1) {
		        $out .= ' (prefered)';
		    }
		    $out .= "\n";
		}

            } elsif (/^(\w+:)?note$/i) {

	        $note = $pidf_info{$_};
	        chomp $note;
 		$out .= '    note: ' . $note . "\n";

	    } elsif (/^(\w+:)?contact$/i) {

	        $contact = $pidf_info{$_};
	        chomp $contact;
 		$out .= '    using address: ' . $contact . "\n";

	    } elsif (/^(\w+:)?timestamp$/i) {

	        $timestamp = $pidf_info{$_};
	        chomp $timestamp;
 		$out .= '    timestamp: ' . $timestamp . "\n";
		
	    } else {
                # all other elements debug only
  	        $log->write(TRACE, "  $_: ".$pidf_info{$_});
            }
	}

        # TODO: fill in the found values for $entity, $status, $contact, 
	# $prio, $note,	$timestamp, into the template, if any

	undef %pidf_info; # for the next tuple
    } 
}

#
# handler called when is parsing finished. 
sub handle_final {
    if ($out ne '') {
	$log->write(INFO, 'pidf: parsed ' . $out);
    }
}


1;
