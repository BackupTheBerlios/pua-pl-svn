package Watcherinfo;

#
# An module for parsing and interpretation of watcherinfo 
# documents, see RFC-3858
#
# part of pua.pl, a simple presence user agent,
# see http://pua-pl.berlios.de for licence
#
# $Date$ Conny Holzhey


use warnings;
use strict;

use XML::Parser;        # to parse XML documents

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

    $self->{log}     = shift;     # reference to the log object
    $self->{options} = shift;     # reference to the options object
    $self->{basepackage} = shift; # kind of package that is to be watched

    $self->{content_type} = 'application/watcherinfo+xml'; 
    $self->{log}->write(DEBUG, "Document $self->{basepackage}.winfo: new");
    return $self;
}





# global variables, mainly internal states of the xml parser.
# Would be nicer to move them into the object, but easier that
# way, as the parser callbacks use them. So they need to be reset,
# to avoid problems with several instances

my $winfo_tag;     # the last tag name identified
my %winfo;         # the collected info for a single watcher entry
my $winfo_package; # global for the package watched
my $resource;      # watched resource name found in the watcher-list statement
my $log;           # of type Log::Easy
my $out;           # a text decribing the watchers
my $found;         # set to true if at least 1 watcher exists


#
# parse the watcherinfo document, as it came with the NOTIFY message.
# Run a good-old xml pull parser, which dumps the found elements
# into the StartTag, EndTag and Text methods. Parameters:
# $self     - object reference
# $doc      - the entire document to parse
# $template - where to fill in the findings, TODO
# Returns a string that describes the received document, or an empty
# string case nothing was found, or invalid document was passed.
sub parse {
    my ($self, $doc) = @_;

    $log           = $self->{log};
    $out           = '';
    $found         = 0;
    %winfo         = (); # empty list
    $winfo_package = undef;
    $winfo_tag     = undef;
    $resource      = undef;

    my $parser = new XML::Parser(Style => 'Stream');
    $parser->setHandlers(Final => \&watcherinfo_handleFinal);

    # the actual interpretatoin is done in the handlers below
    $parser->parse($doc);

    if ($self->{basepackage} eq $winfo_package) {
        return $out;
    } else {
        return ''; # it was not for me
    }
}


#
# handler for the winfo parser, called on each opening XML tag
# not exported, and it is not a method, therefor using global vars

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

    $log->write(SPEW, "parser: Tag: ", 
                (defined $winfo_tag? $winfo_tag: 'none'), " text $_");

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

    undef %winfo; # for the next watcher
}


#
# handler called when is parsing finished. Call parent CB

sub watcherinfo_handleFinal {

    unless ($found) {
        $out .= "  $winfo_package is not watched by anybody\n";
    } else {
        $found = 0;
    }

    $log->write(INFO, $winfo_package.".winfo: $out");
}

1;
