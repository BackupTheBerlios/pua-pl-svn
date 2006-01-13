#!/usr/bin/perl -w


# some tests for watcherinfo.pl, a simple XML parser for watcherinfo docs 

use Test::More 'no_plan';

use lib '..';
use Log::Easy;

use Watcherinfo;

my $log = new Log::Easy;
$log->log_level(INFO);#TRACE);
$log->prefix('');

my $options = new Options($log, 'testing');


# test object #1
my $pwinfo = new Watcherinfo($log, $options, 'presence');
# test object #2
my $pwinfo2 = new Watcherinfo($log, $options, 'presence.winfo');

is ($pwinfo->get_content_type(), 'application/watcherinfo+xml',
    'winfo: using correct content type');
is ($pwinfo2->get_content_type(), 'application/watcherinfo+xml',
    'winfo2: using correct content type');



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

$res = $pwinfo->parse($doc);
is($res, $expected, 'winfo:1 watcher using default namespace');
$res = $pwinfo2->parse($doc);
is($res, '', 'winfo2: ignoring other packages');

# same again with changed roles, using package presence.winfo

$doc = '<?xml version="1.0"?>
   <watcherinfo xmlns="urn:ietf:params:xml:ns:watcherinfo"
                version="0" state="full">
      <watcher-list resource="sip:B@example.com" package="presence.winfo">
        <watcher id="7768a77s" event="subscribe"
                 status="pending">sip:A@example.com</watcher>
      </watcher-list>
   </watcherinfo>';


$expected = 'Watcher information for sip:B@example.com:
  pending subscription of sip:B@example.com\'s presence.winfo by
    sip:A@example.com
';

$res = $pwinfo2->parse($doc);
is($res, $expected, 'winfo2: 1 watcher using default namespace');
$res = $pwinfo->parse($doc);
is($res, '', 'winfo: ignoring other packages');







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
  pending subscription of sip:professor@example.net\'s presence by
    Mr. Subscriber <sip:userB@example.org>
';


$res = $pwinfo->parse($doc);
is($res, $expected, 'winfo: 2 watcher using default namespace');

# again with presence.winfo

$doc = '<?xml version="1.0"?>
<watcherinfo xmlns="urn:ietf:params:xml:ns:watcherinfo"
             version="0" state="full">
  <watcher-list resource="sip:professor@example.net" package="presence.winfo">
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
  active subscription of sip:professor@example.net\'s presence.winfo by
    sip:userA@example.net
    last time renewed 509 seconds ago
    subscription ends in 5 seconds
  pending subscription of sip:professor@example.net\'s presence.winfo by
    Mr. Subscriber <sip:userB@example.org>
';


$res = $pwinfo->parse($doc);
is($res, '', 'winfo: ignoring foreign packages');
$res = $pwinfo2->parse($doc);
is($res, $expected, 'winfo2: 2 watcher using default namespace');


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

$res = $pwinfo->parse($doc);
is($res, $expected, 'winfo: 1 watcher using dedicated namespace');


#############################################################################

$doc = '<?xml version="1.0"?>
<watcherinfo xmlns="urn:ietf:params:xml:ns:watcherinfo" version="0" state="full">
  <watcher-list resource="sip:yivi@pals-dev.internet2.edu" package="presence">
  </watcher-list>
</watcherinfo>';

$expected = 'Watcher information for sip:yivi@pals-dev.internet2.edu:
  presence is not watched by anybody
';

$res = $pwinfo->parse($doc);
is($res, $expected, 'winfo: empty watcher list');


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

# TODO template stuff
#pidf_parse($doc, $log, undef, undef, \&callback, 'Hammelswade');



