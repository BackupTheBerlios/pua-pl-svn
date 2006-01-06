
# a parser for watcherinfo documents, see RFC-3858
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $Date$, Conny Holzhey


package watcherinfo;

use warnings;
use strict;

use XML::Parser;        # to parse xml documents

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging

require Exporter;

our(@ISA, @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(watcherinfo_parse);




# global variables, internal states of the xml parser

my $winfo_tag;     # the last tag name identified
my %winfo;         # the collected info for a single watcher entry
my $winfo_package; # global for the package watched
my $resource;      # watched resource name found inf the watcher-list statement
my $log;           # of type Log::Easy
my $out;           # a text decribing the pidf
my $found;         # set to true if at least 1 watcher exists
my $callback1;     # specified by the caller, called with the descriptive 
                   # result of parsing, usually to be printed
my $callback2;     # specified by the caller, called with the result of parsing,
                   # this time in form of a list
my $cb_arg1;       # to give the app a chance to pass state info to the callback1
my $cb_arg2;       # to give the app a chance to pass state info to the callback2



#
# parse the watcherinfo document, as it came with the NOTIFY message.
# Run a good-old xml pull parser, which dumps the found elements
# into the StartTag, EndTag and Text methods. Parameters:
#
#   $doc  - the entire document to parse
#   $l    - reference to the log, see Log::Easy
#   $cb1  - Callback, gets a descriptive string with a message describing 
#           what has been found in the watcherinfo document, and $arg1
#   $arg1 - unchanged passed to $cb1
#   $cb2  - Callback, gets called for each watcher found in the document
#           with the following arguments: tbd.
#           Most of of the arguments can be undef.
#   $arg2 - unchanged passed to $cb2

sub watcherinfo_parse {
    my ($doc, $l, $cb1, $arg1, $cb2, $arg2) = @_;

    $log       = $l;
    $out       = '';
    $callback1 = $cb1;
    $callback2 = $cb2;
    $cb_arg1   = $arg1;
    $cb_arg2   = $arg2;
    $found     = 0;

    my $parser = new XML::Parser(Style => 'Stream');
    $parser->setHandlers(Final    => \&watcherinfo_handleFinal);

    # the actual interpretatoin is done in the handlers below
    $parser->parse($doc);
}

#
# handler for the pidf parser, called on each opening XML tag

sub StartTag {
    shift;
    my $tag = shift;
    $log->write(SPEW, "parser: StartTag $tag");

    if ($tag =~ /^(\w+:)?watcher-list$/i) {
        my %r = %_; # get the params
	foreach (keys %r) {
	    if (/resource/i) {
                $out .= 'Watcher information for '. $r{$_} . ":\n";
                $resource = $r{$_};
            } elsif (/package/i) {
                $winfo_package = $r{$_};
            } elsif (/state/i) {
                # could add partial update handling here
            }
	}
        $winfo_tag = 'watcher-list';
    } 

    # keep the attributes of the watcher tag
    if ($tag =~ /^(\w+:)?watcher$/i) { 
        my %p = %_;
	foreach (keys %p) {
  	    if (/^status$/i) {
 	        # keep it 
	        $winfo{'status'} = $p{$_};
            } elsif (/^duration-subscribed$/i) {
                $winfo{'duration-subscribed'} = $p{$_}; 
            } elsif (/^display-name$/i) {
                $winfo{'display-name'} = $p{$_}; 
            } elsif (/^event$/i) {
                $winfo{'event'} = $p{$_}; 
            } elsif (/^expiration$/i) {
                $winfo{'expiration'} = $p{$_}; 
            } 
	}
        $winfo_tag = 'watcher';
    }
}


#
# handler for the xml parser, called on everything which is not a tag

sub Text {
    my $text = $_;

    $log->write(SPEW, "parser: Tag: ", (defined $winfo_tag? $winfo_tag: 'none'), " text $_");

    if (defined $winfo_tag && $winfo_tag =~ /^watcher$/i) {

        # keep only texts that have non-whitespace content
        unless (/^\s+$/s) {
	    s/^\s+//s; # erase leading whitespace
	    s/\s+$//s; # erase trailing whitespace

            $out .= '  ';
	    if (exists $winfo{'status'}) {
                $out .= $winfo{'status'} . ' ';
            }

            $out .= 'subscription of '.$resource;
            if (defined $winfo_package) {
                $out .= '\'s '.$winfo_package;
            }
            $out .= " by\n    ";

            if (exists $winfo{'display-name'}) {
                $out .= $winfo{'display-name'}.' <'.$text.">\n";
            } else {
                # no display name
                $out .= $text."\n";
            }

            if (exists $winfo{'duration-subscribed'}) {
                $out .= '    last time renewed '.$winfo{'duration-subscribed'}.
                        " seconds ago\n";
            } 
            if (exists $winfo{'expiration'}) {
                $out .= '    subscription ends in '.$winfo{'expiration'}." seconds\n";
            } 
            $found = 1;
	}
    }
}

#
# handler for the xml parser, called on each closing tag

sub EndTag {
    my $tag = $_;

    # $log->write(SPEW, "parser: EndTag $tag");

    if (defined($winfo_tag)) {
        undef $winfo_tag;
    }

    if (defined($winfo_package)) {
        undef $winfo_package;
    }

    undef %winfo; # for the next watcher
}

#
# handler called when is parsing finished. Call parent CB
sub watcherinfo_handleFinal {
    if (!$found) {
        $out .= "Not watched by anybody\n";
    } else {
        $found = 0;
    }

    if (defined $callback1) {
	&$callback1($out, $cb_arg1);	
    } else {
	$log->write(INFO, 'parse: ' . $out);
    }
}

1;
