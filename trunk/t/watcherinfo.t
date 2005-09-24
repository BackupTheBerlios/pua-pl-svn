#!/usr/bin/perl -w


# some tests for watcherinfo.pl, a simple XML parser for watcherinfo docs 

use Test::More 'no_plan';

use lib '..';
use Log::Easy;

require "../watcherinfo.pm";

my $log = new Log::Easy;
$log->log_level(SPEW);#INFO);#TRACE);
$log->prefix('');




################# taken the example from RFC 3857 ##########################


my $doc = '<?xml version="1.0"?>
   <watcherinfo xmlns="urn:ietf:params:xml:ns:watcherinfo"
                version="0" state="full">
      <watcher-list resource="sip:B@example.com" package="presence">
        <watcher id="7768a77s" event="subscribe"
                 status="pending">sip:A@example.com</watcher>
      </watcher-list>
   </watcherinfo>';


my $expected = 'Watcher information for sip:B@example.com:
  pending subscription of sip:B@example.com\'s presence by
    sip:A@example.com
';

my $res;

watcherinfo::watcherinfo_parse($doc, $log, sub{ $res = $_[0]; });
is($res, $expected, '1 watcher using default namespace');






################# taken the example from RFC 3858 ##########################


$doc = '<?xml version="1.0"?>
<watcherinfo xmlns="urn:ietf:params:xml:ns:watcherinfo"
             version="0" state="full">
  <watcher-list resource="sip:professor@example.net" package="presence">
    <watcher status="active"
             id="8ajksjda7s"
             duration-subscribed="509"
             expiration="5"
             event="approved" >sip:userA@example.net</watcher>
    <watcher status="pending"
             id="hh8juja87s997-ass7"
             display-name="Mr. Subscriber" xml:lang="De_de"
             event="subscribe">sip:userB@example.org</watcher>
  </watcher-list>
</watcherinfo>';

$expected = 'Watcher information for sip:professor@example.net:
  active subscription of sip:professor@example.net\'s presence by
    sip:userA@example.net
    last time renewed 509 seconds ago
    subscription ends in 5 seconds
  pending subscription of sip:professor@example.net by
    Mr. Subscriber <sip:userB@example.org>
';



watcherinfo::watcherinfo_parse($doc, $log, sub{ $res = $_[0]; });
is($res, $expected, '2 watcher using default namespace');

#############################################################################


$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <winfo:watcherinfo 
       xmlns:winfo="urn:ietf:params:xml:ns:watcherinfo"
       version="0" state="full">
      <winfo:watcher-list resource="sip:B@example.com" package="presence">
          <winfo:watcher id="7768a77s" 
                 event="subscribe"
                 status="pending">sip:A@example.com</winfo:watcher>
      </winfo:watcher-list>
   </winfo:watcherinfo>';


$expected = 'Watcher information for sip:B@example.com:
  pending subscription of sip:B@example.com\'s presence by
    sip:A@example.com
';

watcherinfo::watcherinfo_parse($doc, $log, sub{ $res = $_[0]; });
is($res, $expected, '1 watcher using dedicated namespace');


#############################################################################

$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <impp:presence xmlns:impp="urn:ietf:params:xml:ns:pidf"
        xmlns:myex="http://id.mycompany.com/presence/"
        entity="pres:someone@example.com">
     <impp:tuple id="tj25ds">
       <impp:status>
         <impp:basic>open</impp:basic>
       </impp:status>
       <myex:complexExtension>
         <myex:ex1 impp:mustUnderstand="1">val1</myex:ex1>
         <myex:ex2>val2</myex:ex2>
       </myex:complexExtension>
       <impp:contact priority="0.725">tel:+09012345678</impp:contact>
     </impp:tuple>
     <myex:mytag>My extended presentity information</myex:mytag>
   </impp:presence>';

$expected = 'Presence information for pres:someone@example.com:
  available and online
    prioity of this way of communication: 0.725
    using address: tel:+09012345678
';

#pidf_parse($doc, $log, sub{ $res = $_[0]; });
#is($res, $expected, 'mandatory to understand elements');


#############################################################################


$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <presence xmlns="urn:ietf:params:xml:ns:pidf"
        xmlns:im="urn:ietf:params:xml:ns:pidf:im"
        xmlns:myex="http://id.example.com/presence/"
        entity="pres:rumpelstilzchen@waldecke.de">
     <tuple id="bs35r9">
       <status>
         <basic>open</basic>
       </status>   
       <note>Heute back ich, morgen koch ich</note>
       <contact priority="0.8">sip:rumpelstilzchen@waldecke.de</contact>
       <timestamp>1795-10-27T16:49:29Z</timestamp>
     </tuple>
   </presence>';

sub callback {
    my ($entity, $status, $contact, $prio, $note, $timestamp, $cb_arg) = @_;
    is ($entity, 'pres:rumpelstilzchen@waldecke.de', 'Callback2 arg entity');
    is ($status, 'open', 'Callback2 arg status');
    is ($prio, 0.8, 'Callback2 arg prio');
    is ($contact, 'sip:rumpelstilzchen@waldecke.de', 'Callback2 arg contact');
    is ($note, 'Heute back ich, morgen koch ich', 'Callback2 arg note');
    is ($timestamp, '1795-10-27T16:49:29Z', 'Callback2 arg timestamp');
    is ($cb_arg, 'Hammelswade', 'Callback2 arg arg');
}

#pidf_parse($doc, $log, undef, undef, \&callback, 'Hammelswade');



