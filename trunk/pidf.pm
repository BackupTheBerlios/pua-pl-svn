
# a simple parser for pidf documents, see RFC-3863
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $Date$, Conny Holzhey



use warnings;
use strict;

use XML::Parser;        # to parse pidf documents

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging, got it from cpan



# global variables, internal states of the pidf parser

my $pidf_tag;      # the last tag name identified
my %pidf_info;     # the collected info
my $log;           # of type Log::Easy
my $out;           # a text decribing the pidf
my $callback1;     # specified by the caller, called with the descriptive 
                   # result of parsing, usually to be printed
my $callback2;     # specified by the caller, called with the result of parsing,
                   # this time in form of a list
my $cb_arg1;       # to give the app a chance to pass state info to the callback1
my $cb_arg2;       # to give the app a chance to pass state info to the callback2

my $entity;        # entity name found inf the pidf document

#
# parse the pidf document, as it came with the NOTIFY message.
# Run a good-old xml pull parser, which dumps the found elements
# into the StartTag, EndTag and Text methods. Parameters:
#
#   $doc  - the entire document to parse
#   $l    - reference to the log, see Log::Easy
#   $cb1  - Callback, gets a descriptive string with a message describing 
#           what has been found in the pidf document, and $arg1
#   $arg1 - unchanged passed to $cb1
#   $cb2  - Callback, gets called for each tuple found in the document
#           with the following arguments: entity, status, contact, prio,
#           note, timestamp, arg2. Most of of the arguments can be undef.
#   $arg2 - unchanged passed to $cb2

sub pidf_parse {
    my ($doc, $l, $cb1, $arg1, $cb2, $arg2) = @_;

    $log       = $l;
    $out       = '';
    $callback1 = $cb1;
    $callback2 = $cb2;
    $cb_arg1   = $arg1;
    $cb_arg2   = $arg2;

    my $parser = new XML::Parser(Style => 'Stream');
    $parser->setHandlers(Final=>\&handle_final);
    # the actual interpretatoin is done in the handlers below
    $parser->parse($doc);
}

#
# handler for the pidf parser, called on each opening XML tag

sub StartTag {
    shift;
    my $tag = shift;
    # $log->write(SPEW, "parser: StartTag $tag");

    if ($tag =~ /^(\w+:)?presence$/i) {
        my %e = %_;
	foreach (keys %e) {
	    next unless (/entity/);
  	    $out .= 'Presence information for '. $e{$_} . ":\n";
	    $entity = $e{$_};
	}
    } 

    # keep the priority atribute of contact
    if ($tag =~ /^(\w+:)?contact$/i) { 
        my %p = %_;
	foreach (keys %p) {
  	    next unless (/priority/);

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

	# $log->write(SPEW, "parser: Tag: $pidf_tag, text $_");

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

    # $log->write(SPEW, "parser: EndTag $tag");

    if (defined($pidf_tag)) {
        undef$pidf_tag;
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
		        $out .= ' (prefered!)';
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

	if (defined $callback2) {
	    &$callback2($entity, 
			$status, 
			$contact, 
			$prio, 
			$note,
			$timestamp,
			$cb_arg2);	
	}

	undef %pidf_info; # for the next tuple
    } 
}

#
# handler called when is parsing finished. Call parent CB
sub handle_final {
    if (defined $callback1) {
	&$callback1($out, $cb_arg1);	
    } else {
	$log->write(INFO, 'parse: ' . $out);
    }
}

1;
