#!/usr/bin/perl -w


# some tests for pidf.pl, a simple pidf parser

use Test::More 'no_plan';

use lib '..';
use Log::Easy;

use Pidf;

my $log = new Log::Easy;
$log->log_level(INFO);#TRACE);
$log->prefix('');

my $options = new Options($log, 'testing');


# test object
my $pidf = new Pidf($log, $options);

is ($pidf->get_content_type(), 'application/pidf+xml',
    'pidf: using correct content type');



################# taken the examples from RFC 3863 ##########################


my $doc = '<?xml version="1.0" encoding="UTF-8"?>
   <impp:presence xmlns:impp="urn:ietf:params:xml:ns:pidf"
       entity="pres:someone@example.com">
     <impp:tuple id="sg89ae">
       <impp:status>
         <impp:basic>open</impp:basic>
       </impp:status>
       <impp:contact priority="0.8">tel:+09012345678</impp:contact>
     </impp:tuple>
   </impp:presence>';

my $expected = 'Presence information for pres:someone@example.com:
  available and online
    prioity of this way of communication: 0.8
    using address: tel:+09012345678
';


my $res = $pidf->parse($doc);
is($res, $expected, 'pidf: using a namespace');

#############################################################################

$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <presence xmlns="urn:ietf:params:xml:ns:pidf"
       entity="pres:someone@example.com">
     <tuple id="sg89ae">
       <status>
         <basic>open</basic>
       </status>
       <contact priority="0.8">tel:+09012345678</contact>
     </tuple></presence>';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: using a default XML namespace');

#############################################################################

$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <presence xmlns="urn:ietf:params:xml:ns:pidf"
       xmlns:local="urn:example-com:pidf-status-type"
       entity="pres:someone@example.com">
     <tuple id="ub93s3">
       <status>
         <basic>open</basic>
         <local:location>home</local:location>
       </status>
       <contact>im:someone@example.com</contact>
     </tuple>
   </presence>';

$expected = 'Presence information for pres:someone@example.com:
  available and online
    using address: im:someone@example.com
';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: including a location status');

#############################################################################

$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <presence xmlns="urn:ietf:params:xml:ns:pidf"
        xmlns:im="urn:ietf:params:xml:ns:pidf:im"
        xmlns:myex="http://id.example.com/presence/"
        entity="pres:someone@example.com">
     <tuple id="bs35r9">
       <status>
         <basic>open</basic>
         <im:im>busy</im:im>
         <myex:location>home</myex:location>
       </status>
       <contact priority="0.8">im:someone@mobilecarrier.net</contact>
       <note xml:lang="en">Don\'t Disturb Please!</note>
       <note xml:lang="fr">Ne derangez pas, s\'il vous plait</note>
       <timestamp>2001-10-27T16:49:29Z</timestamp>
     </tuple>
     <tuple id="eg92n8">
       <status>
         <basic>open</basic>
       </status>
       <contact priority="1.0">mailto:someone@example.com</contact>
     </tuple>
     <note>I\'ll be in Tokyo next week</note>
   </presence>';

$expected = 'Presence information for pres:someone@example.com:
  available and online
    prioity of this way of communication: 0.8
    using address: im:someone@mobilecarrier.net
    note: Don\'t Disturb Please!
    Ne derangez pas, s\'il vous plait
    timestamp: 2001-10-27T16:49:29Z
  available and online
    prioity of this way of communication: 1.0 (prefered)
    using address: mailto:someone@example.com
  note: I\'ll be in Tokyo next week
';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: default namespace with status extension');

#############################################################################

$doc = '<?xml version="1.0" encoding="UTF-8"?>
   <impp:presence xmlns:impp="urn:ietf:params:xml:ns:pidf"
        xmlns:myex="http://id.example.com/presence/"
        entity="pres:someone@example.com">
     <impp:tuple id="ck38g9">
       <impp:status>
         <impp:basic>open</impp:basic>
       </impp:status>
       <myex:mytupletag>Extended value in tuple</myex:mytupletag>
       <impp:contact priority="0.65">tel:+09012345678</impp:contact>
     </impp:tuple>
     <impp:tuple id="md66je">
       <impp:status>
         <impp:basic>open</impp:basic>
       </impp:status>
       <impp:contact priority="1.0">
          im:someone@mobilecarrier.net</impp:contact>
     </impp:tuple>
     <myex:mytag>My extended presentity information</myex:mytag>
   </impp:presence>';

$expected = 'Presence information for pres:someone@example.com:
  available and online
    prioity of this way of communication: 0.65
    using address: tel:+09012345678
  available and online
    prioity of this way of communication: 1.0 (prefered)
    using address: im:someone@mobilecarrier.net
';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: own namespace with other extensions');

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

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: mandatory to understand elements');


#############################################################################

$doc = '<?xml version="1.0"?>
<!DOCTYPE presence PUBLIC "//IETF//DTD RFCxxxx XPIDF 1.0//EN" "xpidf.dtd">
<presence>
<presentity uri="sip:user@192.168.123.2;method=SUBSCRIBE"/>
<atom id="9r28r49">
<address uri="sip:user@192.168.123.2">
<status status="closed"/>
</address>
</atom>
</presence>';

$expected = '';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: lpidf document');

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
# todo: test template filling with the found elements
# pidf::pidf_parse($doc, $log, undef, undef, \&callback, 'Hammelswade');

#############################################################################

# as sent by pals.internet2.edu
$doc = '<?xml version="1.0"?>
<!DOCTYPE presence PUBLIC "//IETF//DTD RFCxxxx PIDF 1.0//EN" "pidf.dtd">
<presence entity="sip:yivi@pals.internet2.edu">
<tuple id="tid25847dd8">
  <contact  priority="0.500000">sip:conny@garbo</contact>
  <status>
    <basic>open</basic>
    <geopriv><location-info><civilAddress>    </civilAddress></location-info></geopriv>
  </status>
</tuple>
</presence>';

$expected = 'Presence information for sip:yivi@pals.internet2.edu:
  available and online
    prioity of this way of communication: 0.500000
    using address: sip:conny@garbo
';

$res = $pidf->parse($doc);
is($res, $expected, 'pidf: including geopriv');

