#!/usr/bin/perl

# a test server, runs repeatedly pua.pl, checks it's messages on 
# port 5059 and replies accordingly

use warnings;
use strict;
use IO::Socket::INET;   # to receive/sendmessages
use Test::More 'no_plan';

# Include POE and POE::Component::Server::TCP.

use POE qw(Component::Server::TCP);
use XML::Parser;
use Data::Dumper;

my $AT = '@';
my $expected;
my $input_buf;
my $subs_ok_answer;
    $subs_ok_answer = 'SIP/2.0 200 OK
Via: SIP/2.0/TCP garbo;branch=z9hG4bK32781107964501@garbo;received=127.0.0.1
To: Conny <sip:conny@192.168.123.2>;tag=a6f1fa7237095ed
From: Conny <sip:conny@192.168.123.2>;tag=1107964501
Call-ID: 0.246640064594434@garbo
CSeq: 2 SUBSCRIBE
Server: crude test server
Content-Length: 0

';

my $subs_fail_answer;
    $subs_fail_answer = 'SIP/2.0 408 Timeout
Via: SIP/2.0/TCP garbo;branch=z9hG4bK32781107964501@garbo;received=127.0.0.1
To: Conny <sip:conny@192.168.123.2>;tag=a6f1fa7237095ed7e0e9310f6f58d8bc-d7d5
From: Conny <sip:conny@192.168.123.2>;tag=1107964501
Call-ID: 0.246640064594434@garbo
CSeq: 2 SUBSCRIBE
Server: crude test server
Content-Length: 0

';


my $publ_ok_answer;
    $publ_ok_answer = 'SIP/2.0 200 OK
Via: SIP/2.0/TCP garbo;branch=z9hG4bK32781107964501@garbo;received=127.0.0.1
To: Conny <sip:conny@192.168.123.2>;tag=a6f1fa7237095ed
From: Conny <sip:conny@192.168.123.2>;tag=1107964501
Call-ID: 0.246640064594434@garbo
CSeq: 2 PUBLISH
SIP-ETag: kwj449x
Server: crude test server
Content-Length: 0

';

my $publ_fail_answer = 'SIP/2.0 412 Conditional Request Failed
Via: SIP/2.0/UDP 192.168.10.31:5060; branch=a7hG4bM391cjm267; rport=5060
From: <sip:abc@192.168.10.31:5062>; tag=1G85kljk
Call-ID: 35102264
Content-Length: 0
To: <sip:abc@192.168.10.31:5062>; tag=SCt-2-1103696779.19-192.168.10.31
CSeq: 1 PUBLISH

';

my $reg_ok_answer = 'SIP/2.0 200 OK
Via: SIP/2.0/TCP garbo;branch=z9hG4bK32781107964501@garbo;received=127.0.0.1
To: Conny <sip:conny@192.168.123.2>;tag=a6f1fa7237095ed
From: Conny <sip:conny@192.168.123.2>;tag=1107964501
Call-ID: 0.246640064594434@garbo
CSeq: 2 REGISTER
Server: crude test server
Content-Length: 0

';


my $reg_fail_answer = 'SIP/2.0 423 Uncool
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 REGISTER
WWW-Authenticate: Digest realm="iptel.org", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3"

';





#
# do some basic initializations
sub _start {
    $_[KERNEL]->alias_set('test-server');
    $_[HEAP]->{'beat_cnt'} = 0;
    $_[HEAP]->{'int_cnt'} = 0;
    start_tcp_server();
    $_[KERNEL]->delay('continue', 1); # give the server time to start
}


my $answer = $subs_fail_answer;

# not quite sophisticated method ... the test beats for the individual methods
my @offsets = (    # general_test
	       33, # init_publish_tests
	       44, # init_subscribe_tests
	       54, # subscribe_tests 
	       65, # publish_tests
	       76, # init_register_tests
	       80, # register_auth_tests 
	       89, # register_tests
	       91, # notify_tests
	       98
	      );

#
# main function, called for each test
sub continue {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    print "******************** Beat $heap->{'beat_cnt'} ********************\n";

    if ($heap->{'beat_cnt'} >= 0 && $heap->{'beat_cnt'} < $offsets[0]) {
        general_tests(@_);

    } elsif ($heap->{'beat_cnt'} < $offsets[1]) {
        if ($heap->{'beat_cnt'} == $offsets[0] 
 	        || $heap->{'beat_cnt'} == $offsets[0]+1) {

	    # desparately trying to reset all
 	    $heap->{'int_cnt'} = 0; 
	    sleep 1;
	}

	init_publish_tests(@_); # initial publish

    } elsif ($heap->{'beat_cnt'} < $offsets[2]) { 
        if ($heap->{'beat_cnt'} == $offsets[1]) {
            $heap->{'int_cnt'} = 0; 
	}
        init_subscribe_tests(@_); # initial subscribe
   
    } elsif ($heap->{'beat_cnt'} < $offsets[3]) { 
        if ($heap->{'beat_cnt'} == $offsets[2]) {
            $heap->{'int_cnt'} = 0; 
	}
        subscribe_tests(@_); # more about subscribe

    } elsif ($heap->{'beat_cnt'} < $offsets[4]) { 
        if ($heap->{'beat_cnt'} == $offsets[3]) {
            $heap->{'int_cnt'} = 0; 
	}
        publish_tests(@_); # refresh publish tests

    } elsif ($heap->{'beat_cnt'} < $offsets[5]) { 
        if ($heap->{'beat_cnt'} == $offsets[4]) {
            $heap->{'int_cnt'} = 0; 
	}
        init_register_tests(@_); # register specific tests

    } elsif ($heap->{'beat_cnt'} < $offsets[6]) { 
        if ($heap->{'beat_cnt'} == $offsets[5]) {
            $heap->{'int_cnt'} = 0; 
	}
        register_auth_tests(@_); # authentification specific tests
    } elsif ($heap->{'beat_cnt'} < $offsets[7]) { 
        if ($heap->{'beat_cnt'} == $offsets[6]) {
            $heap->{'int_cnt'} = 0; 
	}
        register_tests(@_); # authentification specific tests
    } elsif ($heap->{'beat_cnt'} < $offsets[8]) { 
        if ($heap->{'beat_cnt'} == $offsets[7]) {
            $heap->{'int_cnt'} = 0; 
	}
        notify_tests(@_); 
    }

    # one day i will learn how to program loops

    if ($heap->{'beat_cnt'} >= $offsets[$#offsets]) { exit 0; }

    $heap->{'beat_cnt'}++;

}


#
# tests that can be used equally for publish, register, subscribe

sub general_tests {
    my ( $kernel, $session, $heap, $input ) = @_[KERNEL, SESSION, HEAP, ARG0];

    # reuse the tests 1..10 for publish, register, subscribe
    if ($heap->{'beat_cnt'} <= 10) {
        $heap->{'method'} = 'PUBLISH';
	$heap->{'switch'} = '-p';
    } elsif ($heap->{'beat_cnt'} <= 21) {
        $heap->{'method'} = 'REGISTER';
	$heap->{'switch'} = '-r';
	$answer = $reg_fail_answer;
    } elsif ($heap->{'beat_cnt'} <= 32) { 
        $heap->{'method'} = 'SUBSCRIBE';
	$heap->{'switch'} = '-s';
    } else { die; }

    $heap->{'int_cnt'} = $heap->{'beat_cnt'}%11;

    if ($heap->{'int_cnt'} == 0) {
        system ('testpua.sh -rp 5059 '.$heap->{'switch'}.' -my-id=sips:me@nowhere.com');
	$_[KERNEL]->delay('continue', 2); # should not send anything
    }
    elsif ($heap->{'int_cnt'} == 1) {
	is($input, undef, $heap->{'method'}.' sips: scheme is not supported in my-id');
        # prepare the next test
        system ('testpua.sh -rp 5059 '.$heap->{'switch'}.' -w=sip:a@b.c --my-id=sip:py@nowhere.com');
    }
    elsif ($heap->{'int_cnt'} == 2) {
	my @lines = split ("\n", $input);
	my $c = 0;
	foreach (@lines) {
	  if (/^To: /) { $c++; next; }
	  if (/^From: /) { $c++; next; }
	  if (/^CSeq: /) { $c++; next; }
	  if (/^Call-ID: /) { $c++; next; }
	  if (/^Max-Forwards: /) { $c++; next; }
	  if (/^Via: /) { $c++; next; }
	}
	is($c, 6, $heap->{'method'}.' all mandatory headers are available');

        # go to the next test, using same data
	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 3) {
	my $l = get_header('To', $input);
        unlike($l, qr/;tag=/, $heap->{'method'}.' To: header has no tag');
	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 4) {
	my $l = get_header('From', $input);
        like($l, qr/;tag=(\w)+/, $heap->{'method'}.' From: header has a tag');
	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 5) {
	my $l = get_header('Max-Forwards', $input);
        like($l, qr/^Max-Forwards: 70$/, $heap->{'method'}.' Max-Forwards is 70');
	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 6) {
	my $l = get_header('Via', $input);
        like($l, qr/branch=(z9hG4bK.*)$/, 
	     $heap->{'method'}.' branch starts with magic number');

	# keep it, for the next test
	$heap->{'branch'} = $1;

        # prepare the next test
        system ('testpua.sh -rp 5059 '.$heap->{'switch'}.' -my-id=sip:moby@nowhere.com -w sip:x@y.z');
    }
    elsif ($heap->{'int_cnt'} == 7) {
	my $l = get_header('Via', $input);
        if ($l =~ /branch=(z9hG4bK.*)$/) {
	    isnt($1, $heap->{'branch'}, 
		 $heap->{'method'}.' branch param is possibly unique');
	} else {
	    is(1, 0, $heap->{'method'}.' no branch param found');
	}
	delete $heap->{'branch'};
        system ('testpua.sh -rp 5059 '.$heap->{'switch'}.' -my-id=sip:moby@thesea.com -my-name=Moby_Dick -w sip:p@q.r');
    }
    elsif ($heap->{'int_cnt'} == 8) {
	my $l = get_header('To', $input);
	if ($heap->{'switch'} ne '-s') {
            like($l, qr/^To: "Moby_Dick" <sip:moby${AT}thesea.com>$/, 
	      $heap->{'method'}.' display name is used in To: header');
        }
	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 9) {
	my $l = get_header('From', $input);
        like($l, qr/^From: "Moby_Dick" <sip:moby${AT}thesea.com>/, 
	     $heap->{'method'}.' display name is used in From: header');

	$kernel->post('test-server' => 'continue' => $input);
    }
    elsif ($heap->{'int_cnt'} == 10) {
	my $l = get_header('CSeq', $input);
	like($l, qr/CSeq: \d+ $heap->{'method'}/, 
	     $heap->{'method'}.' CSeq has correct method');

	$kernel->post('test-server' => 'continue' => $input);
    }
    else {
        die;
    }
    $heap->{'int_cnt'}++;
}

#
# publish specific tests: 

sub init_publish_tests {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        system ('testpua.sh -rp 5059 -p -i sip:conny@192.168.123.2:5059');
    }
    elsif ($heap->{'int_cnt'} == 1) {
        my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^PUBLISH sip:conny${AT}192.168.123.2(:5059)? SIP.2\.0$/, 
	     'PUBLISH -i sip-id');

        # prepare the next test
        system ('testpua.sh -rp 5059 -p -my-id=sip:nobody@nowhere.com');
    }
    elsif ($heap->{'int_cnt'} == 2) {
	my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^PUBLISH sip:nobody${AT}nowhere.com(:5059)? SIP\/2\.0$/, 
	     'PUBLSIH specific sip-id');

        # prepare the next test, same data
	$kernel->post('test-server' => 'continue' => $input => $content);

    }
    elsif ($heap->{'int_cnt'} == 3) {
	is(get_header('SIP-If-Match', $input), undef, 
	   'PUBLISH initial publish has no SIP-If-Match field');
	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 4) {
	my $l = get_header('Event', $input);
	is($l, 'Event: presence', 'PUBLISH event header is ok');
	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 5) {
	my $l = get_header('Content-Length', $input);
	like($l, qr/^Content-Length: \d+$/,
	   'PUBLISH Content-Length is probably ok');
	$l = get_header('Content-Type', $input);
	is($l, 'Content-Type: application/pidf+xml',
	   'PUBLISH Content-Type is ok');
	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 6) {
	my $p = new XML::Parser(Style => 'Tree'); # just let it check if valid xml
	my $d = Dumper($p->parse($content));      # make it flat
	ok(length($d) > 0, 'PUBLISH initial publish must contain a body');
	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 7) {
        ok ($content =~ /entity="sip:nobody${AT}nowhere.com"/s,
	    'PUBLISH entity matching my-id');
        ok ($content =~ /<basic>open<\/basic>/sx,
	    'PUBLISH default basic status is open');

	# set diffrent status
        system('testpua.sh -rp 5059 -p -my-id=sip:charles${AT}royal.uk --status=married');
	sleep(1);
    }
    elsif ($heap->{'int_cnt'} == 8) {
        like($content,qr/<basic>married<\/basic>/sx,
	    'PUBLISH can set basic-status value');

	# set a note
        system('testpua.sh -rp 5059 -p -my-id=sip:charly${AT}brown.net --note=Give_me_a_second_sign -c tel:+1234567890');
    }
    elsif ($heap->{'int_cnt'} == 9) {
        like($content,qr/<note>Give_me_a_second_sign<\/note>/sx,
	    'PUBLISH can set a note');
        like($content,qr/<contact>tel:\+1234567890<\/contact>/sx,
	    'PUBLISH can set a contact');

	$kernel->post('test-server' => 'continue' => $input => $content);
    }    

    else {
        die;
    }
    $heap->{'int_cnt'}++;
}


#
# more publish specific tests, testing the refreshing

sub publish_tests {

    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = $publ_ok_answer;
        system ('testpua.sh -rp 5059 -p -pe 10 -i sip:10@sec.onds'); 
    }
    elsif ($heap->{'int_cnt'} == 1) {
        is(get_header('Expires', $input), "Expires: 10", 
	   'PUBLISH exipires timeout is 10 sec');

	# just wait 10 seconds for refresh
    }
    elsif ($heap->{'int_cnt'} == 2) {
	is ($content, '', 'PUBLISH refresh has no content');

	my $l = get_header('Content-Type', $input);
	is($l, undef, 'PUBLISH refresh has no content type header');

	$l = get_header('Content-Length', $input);
	is($l, 'Content-Length: 0', 
	   'PUBLISH refresh has content length of 0');

	# go on with the next publish
    }
    elsif ($heap->{'int_cnt'} == 3) {
        is(get_header('SIP-If-Match', $input), "SIP-If-Match: kwj449x", 
	   'PUBLISH refresh sets correct SIP-If-Match');

        $answer = $publ_fail_answer;
    }
    elsif ($heap->{'int_cnt'} == 4) {
	# this should stop it after the next cycle
	$kernel->delay('continue', 12, 'timeout'); 
    }
    elsif ($heap->{'int_cnt'} == 5) {
        is($input, 'timeout', 'PUBLISH terminated after 412 response');
        $answer = $publ_ok_answer;
        system ('testpua.sh -rp 5059 -p -pe 10 -i sip:wait@pc.de'); 
    } 
    elsif ($heap->{'int_cnt'} == 6) {
        # wait for the refresh
    }
    elsif ($heap->{'int_cnt'} == 7) {
	# try to kill should trigger the next cycle
	`killall -HUP pua.pl`;
    }
    elsif ($heap->{'int_cnt'} == 8) {
        is(get_header('Expires', $input), "Expires: 0", 
	   'PUBLISH got the remove');

	is ($content, '', 'PUBLISH remove has no content');

	my $l = get_header('Content-Type', $input);
	is($l, undef, 'PUBLISH remove has no content type header');

	$l = get_header('Content-Length', $input);
	is($l, 'Content-Length: 0', 
	   'PUBLISH remove has content length of 0');

	# next one for proxy auth
        $answer = 'SIP/2.0 407 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 PUBLISH
Proxy-Authenticate: Digest realm="iptel.org", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3"

';
        system('testpua.sh -rp 5059 -p -pe 10 -u=abc -pw=abc --my-id=sip:nobody@nowhere.com:5059'); 
    } 
    elsif ($heap->{'int_cnt'} == 9) {
	# the challenge

    }
    elsif ($heap->{'int_cnt'} == 10) {
	my $l = get_header('Proxy-Authorization', $input);
	like($l, qr/^Proxy-Authorization: Digest username="abc", realm="iptel.org", uri="sip:nobody${AT}nowhere.com:5059", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3", response=/, 
	   'PUBLISH proxy digest authentification');

	$kernel->post('test-server' => 'continue');
    }

    else {
        die;
    }

    $heap->{'int_cnt'}++;
}


#
# subscribe specific tests: 

sub init_subscribe_tests {

    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        # prepare the next test, get pua.pl to leave
        system ('testpua.sh -rp 5059 -s -i sip:a@b.c -w=sip:user@192.168.123.2:5059');
    }
    elsif ($heap->{'int_cnt'} == 1) {
        my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^SUBSCRIBE sip:user${AT}192.168.123.2(:5059)? SIP.2\.0$/, 
	     'SUBSCRIBE some default sip-id');

        system ('testpua.sh -rp 5059 -s -i=sip:i@j.k -watch-id=sip:nobody@nowhere.com');
    }
    elsif ($heap->{'int_cnt'} == 2) {
	my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^SUBSCRIBE sip:nobody${AT}nowhere.com(:5059)? SIP\/2\.0$/, 
	     'SUBSCRIBE specific sip-id');

        # prepare the next test, same data
	$kernel->post('test-server' => 'continue' => $input => $content);

    }
    elsif ($heap->{'int_cnt'} == 3) {
	is(get_header('Expires', $input), "Expires: 3600", 
	   'SUBSCRIBE default exipires timeout');

        system ('testpua.sh -rp 5059 -s -subscribe-exp=60 -i=sip:i@j.k -w=sip:l@m.n');
    }
    elsif ($heap->{'int_cnt'} == 4) {
	is(get_header('Expires', $input), "Expires: 60", 
	   'SUBSCRIBE specify exipires timeout');

        system ('testpua.sh -rp 5059 -s -watch-id=sip:nobody@nowhere.com -i=sip:i@j.k');
    }
    elsif ($heap->{'int_cnt'} == 5) {
	my $l = get_header('Event', $input);
	is($l, 'Event: presence', 'SUBSCRIBE event header is ok');

	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 6) {
	my $l = get_header('To', $input);
	is($l, 'To: <sip:nobody@nowhere.com>', 'SUBSCRIBE to header is ok');

        system ('testpua.sh -rp 5059 -s -my-id=sip:nosy@somesi.te -my-name=Nosy -w=im:star@home.com');
    }
    elsif ($heap->{'int_cnt'} == 7) {
	my $l = get_header('From', $input);
	like($l, qr/From: "Nosy" <sip:nosy${AT}somesi\.te>;tag=/,
	     'SUBSCRIBE from header is ok');

	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    elsif ($heap->{'int_cnt'} == 8) {
	my $l = get_header('Accept', $input);
	is($l, 'Accept: application/pidf+xml',
	     'SUBSCRIBE accept header is ok');

        system ('testpua.sh -rp 5059 -s -my-host=cray.crack -i=sip:i@j.k -w=sip:a@b.c');
    }
    elsif ($heap->{'int_cnt'} == 9) {
	my $l = get_header('Call-ID', $input);
	like($l, qr/${AT}cray.crack$/,
	     'SUBSCRIBE Call-ID header is ok');

	$kernel->post('test-server' => 'continue' => $input => $content);
    }
    $heap->{'int_cnt'}++;
      
}
      

#
# more subscribe specific tests: 

sub subscribe_tests {

    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = $subs_ok_answer;
        system ('testpua.sh -rp 5059 -s -se 10 -i=sip:ich@ag.de -w sip:you@job.com');
    }
    elsif ($heap->{'int_cnt'} == 1) {
        # keep values
        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
        $heap->{'cseq'} = $1;

	$l = get_header('From', $input);
	$l =~ /tag=(.*)/;

        # wait for 10 seconds, there has to be a second call to this
        # within that duration - just don't send any continue

    }  elsif ($heap->{'int_cnt'} == 2) {

	# compare cseq
        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	my $cseq = $1;
        is($cseq, $heap->{'cseq'}+1, 'SUBSCRIBE CSeq number incremented');

	$l = get_header('To', $input);
	$l =~ /tag=(.*)/;
	my $tag = $1;
	
	is($tag, 'a6f1fa7237095ed', # taken from $subs_ok_answer
	   'SUBSCRIBE has correct tag in To header');

	$l = get_header('From', $input);
	$l =~ /tag=(.*)/;
	$tag = $1;
	
	is($tag, '1107964501', # taken from $subs_ok_answer
	   'SUBSCRIBE has same tag in From header');

	# again wait for 10 seconds

    }  elsif ($heap->{'int_cnt'} == 3) {

	# compare cseq
        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	my $cseq = $1;
        is($cseq, $heap->{'cseq'}+2, 'SUBSCRIBE CSeq number again incremented');	
	delete $heap->{'cseq'};
	$answer = $subs_fail_answer; # this should it stop after the next cycle

    }  elsif ($heap->{'int_cnt'} == 4) {
	$kernel->delay('continue', 12, 'timeout'); 

    }  elsif ($heap->{'int_cnt'} == 5) {
        is($input, 'timeout', 'Subscribe terminated after 408 response');

	$answer = $subs_ok_answer; 
        system ('testpua.sh -rp 5059 -s -se 10 -i im:a@b.c -w sip:sap@soup.se');

    }  elsif ($heap->{'int_cnt'} == 6) {
	$kernel->delay('continue', 1); 

    } elsif ($heap->{'int_cnt'} == 7) {
	# try to kill should trigger the next cycle
	`killall -HUP pua.pl`;
    } elsif ($heap->{'int_cnt'} == 8) {
	is(get_header('Expires', $input), "Expires: 0", 
	   'SUBSCRIBE leaving with exipires 0');

	$kernel->delay('continue', 1, 'timeout'); 

    } elsif ($heap->{'int_cnt'} == 9) {

	# next one for auth
        $answer = 'SIP/2.0 401 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 SUBSCRIBE
WWW-Authenticate: Digest realm="iptel.org", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3"

';
        system('testpua.sh -rp 5059 -s -pe 10 -u=abc -pw=abc --my-id=sip:nobody@nowhere.com:5059 -w=sip:boss@desk.top'); 
    } 
    elsif ($heap->{'int_cnt'} == 10) {
	# the challenge

    }
    elsif ($heap->{'int_cnt'} == 11) {
	my $l = get_header('Authorization', $input);
	like($l, qr/^Authorization: Digest username="abc", realm="iptel.org", uri="sip:nobody${AT}nowhere.com:5059", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3", response=/, 
	   'PUBLISH digest authentification');

	$kernel->post('test-server' => 'continue');
	$answer = $subs_ok_answer; 
    }

    $heap->{'int_cnt'}++;
}

sub init_register_tests {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = $reg_fail_answer;
	$kernel->post('test-server' => 'continue');
    }
    elsif ($heap->{'int_cnt'} == 1) {

        system ('testpua.sh -rp 5059 -r -my-id=sip:so@de.le');
    }
    elsif ($heap->{'int_cnt'} == 2) {
        my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^REGISTER sip:de.le(:5059)? SIP.2\.0$/, 
	     'REGISTER registrar derived from sip-id');

        # prepare the next test
        system ('testpua.sh -rp 5059 -r --my-id=sip:hugo@pc32.nowhere.com');
    }
    elsif ($heap->{'int_cnt'} == 3) {
        my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^REGISTER sip:pc32.nowhere.com(:5059)? SIP.2\.0$/, 
	     'REGISTER dedicated registrar-id');
        is(get_header('Contact', $input), 'Contact: <sip:conny@garbo>', 
	   'REGISTER construct Contact name');

        # prepare the next test
        system ('testpua.sh -rp 5059 -r --login honig -my-id=sip:nobody@wherever.com');
    }
    elsif ($heap->{'int_cnt'} == 4) {
        is(get_header('Contact', $input), 'Contact: <sip:honig@garbo>', 
	   'REGISTER take correct contact name from --login');

        system ('testpua.sh -rp 5059 -r --registrar sip:someprovider.net:5060 -my-id=sip:nobody@nowhere.com');
    }
    elsif ($heap->{'int_cnt'} == 5) {
        my @lines = split ("\n", $input);
	like($lines[0], 
	     qr/^REGISTER sip:someprovider.net:5060 SIP.2\.0$/, 
	     'REGISTER at correct registrar server');

	$kernel->post('test-server' => 'continue' => $input);

    }
    $heap->{'int_cnt'}++;

}

#
# register authentification tests

sub register_auth_tests {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = 'SIP/2.0 401 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 REGISTER
WWW-Authenticate: Digest realm="iptel.org", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3"

';
        system ('testpua.sh -rp 5059 -r -my-id=sip:so@de.le -u admin -pw heslo --registrar sip:10.0.0.113:6060');
    }
    elsif ($heap->{'int_cnt'} == 1) {
        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	$heap->{'cseq'} = $1;
    }
    elsif ($heap->{'int_cnt'} == 2) {
	my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	my $cseq = $1;
	is ($cseq, $heap->{'cseq'}+1, 
	    'REGISTER digest authentification incrs CSeq');
	delete $heap->{'cseq'};

	$l = get_header('Authorization', $input);
	is($l, 'Authorization: Digest username="admin", realm="iptel.org", uri="sip:10.0.0.113:6060", nonce="41a27b3b6184801b57dba727f73804c29f91f1b3", response="55a3888ff8ff7e8a9b31e38091effe21"', 
	   'REGISTER digest authentification without qop #1');

        # prepare the next test, new realm, new nonce, and different formatting

	$answer = 'SIP/2.0 401 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 REGISTER
WWW-Authenticate: Digest algorithm=MD5,
  domain="/",
  nonce="OuaECxW4AwA=052615b8b67d137234d9087a0acc857f04caa958",
  realm="sipinfo.iprimus.net"

';
        system ('testpua.sh -rp 5059 -r -u user54 -pw password --registrar sip:iprimus.net -i=sip:don@yum.my');
    } 
    elsif ($heap->{'int_cnt'} == 3) {
        # do nothing - for the reply 401
    }
    elsif ($heap->{'int_cnt'} == 4) {
	my $l = get_header('Authorization', $input);
	is($l, 'Authorization: Digest username="user54", realm="sipinfo.iprimus.net", algorithm="MD5", uri="sip:iprimus.net", nonce="OuaECxW4AwA=052615b8b67d137234d9087a0acc857f04caa958", response="a3e82b6874e0a39d0b9d70aad8781d37"', 
	   'REGISTER digest authentification without qop #2');

        # prepare the next test, new realm, new nonce

	$answer = 'SIP/2.0 401 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 REGISTER
WWW-Authenticate: Digest realm="SFTF", nonce="5369704365727431353232", qop="auth"

';
        system ('testpua.sh -rp 5059 -r -u abc -pw abc --registrar sip:sip.test.local -i=sip:user@garbo.local');
    } 
    elsif ($heap->{'int_cnt'} == 5) {
        # do nothing - for the reply 401
    }
    elsif ($heap->{'int_cnt'} == 6) {
	my $l = get_header('Authorization', $input);
	#is($l, 'Authorization: Digest username="abc", realm="SFTF", uri="sip:192.168.123.2", nonce="5369704365727431353232", cnonce="72ec36b48e5b206953fb0c94e966fad8", response="e3d043ddc003b09795b5828bbc5ea7a0", qop=auth, nc=00000001', 
	#   'REGISTER digest authentification with qop=auth');
	# keeps changing due to cnonce

     	# check if there is not yet another reply to 401
	$kernel->delay('continue', 3, 'timeout'); 
    }
    elsif ($heap->{'int_cnt'} == 7) {
        is($input, 'timeout', 'REGISTER terminated after 2nd 401 response');

	`killall -HUP pua.pl`;
	$answer = 'SIP/2.0 401 Unauthorized
Via: SIP/2.0/UDP garbo;branch=z9hG4bK199331109232002@garbo;received=192.168.123.2
From: <sip:conny@192.168.123.2>;tag=1109232002
Call-ID: 0.989628284328745@garbo
Content-Length: 0
To: <sip:conny@192.168.123.2>;tag=SCt-0-1109232002.13-192.168.123.2~case303reg
Contact: <sip:sc@192.168.123.2:5062;transport=UDP>
CSeq: 1 REGISTER

';
        system ('testpua.sh -rp 5059 -r -u admin -pw heslo --registrar sip:10.0.0.113:6060 -i sip:me@at.home');
	$kernel->delay('continue', 3, 'timeout'); 
    }
    elsif ($heap->{'int_cnt'} == 8) {
        # do nothing - for the reply 401
    }
    elsif ($heap->{'int_cnt'} == 9) {
        is($input, 'timeout', 
	   'REGISTER terminated after 401 response w/o WWW-Authenticate');
	$kernel->post('test-server' => 'continue' => $input);
    }
    $heap->{'int_cnt'}++;
}


sub register_tests {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = $reg_ok_answer;
        system ('testpua.sh -rp 5059 -r -re 10 --registrar sip:garbo.local -i sip:quick@ten.sec');
    }
    elsif ($heap->{'int_cnt'} == 1) {
	is(get_header('Expires', $input), "Expires: 10", 
	   'REGISTER specify exipires timeout');

        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	$heap->{'cseq'} = $1;

	# wait for register refresh
    }
    elsif ($heap->{'int_cnt'} == 2) {
        my $l = get_header('CSeq', $input);
	$l =~ /CSeq: (\d+)/;
	my $cseq = $1;
        is($cseq, $heap->{'cseq'}+1, 'REGISTER CSeq number incremented');	

	# expires in answer
	$answer = 'SIP/2.0 200 OK
Via: SIP/2.0/TCP garbo;branch=z9hG4bK32781107964501@garbo;received=127.0.0.1
To: Conny <sip:conny@192.168.123.2>;tag=a6f1fa7237095ed
From: Conny <sip:conny@192.168.123.2>;tag=1107964501
Call-ID: 0.246640064594434@garbo
CSeq: 2 REGISTER
Expires: 5
Content-Length: 0

';
        system ('testpua.sh -rp 5059 --my-sip-id sip:long@switch.org -r --registrar sip:garbo.local');
    }
    elsif ($heap->{'int_cnt'} == 3) {
	# wait for register refresh
    }

    $heap->{'int_cnt'}++;
}

#
# notify tests

my $CRLF = "\015\012";

sub notify_tests {
    my ( $kernel, $session, $heap, $input, $content) 
      = @_[KERNEL, SESSION, HEAP, ARG0, ARG1];

    if ($heap->{'int_cnt'} == 0) {
        $answer = $subs_ok_answer;
	`rm /tmp/t3`;
	`rm /tmp/t4`;
	`rm /tmp/t2`;
	`rm /tmp/t1`;
        system ('testpua.sh -rp 5059 -watch sip:freak@show.de -s -se 30 -en \'cat>/tmp/t2\' -ec t/testexec3.sh -eo t/testexec4.sh --exec t/testexec1.sh -i=sip:me@exec.test');

    }
    elsif ($heap->{'int_cnt'} == 1) {
	$kernel->delay('send_udp_message', 2,
		       get_notify('closed'));
	$kernel->delay('continue', 3);
    }
    elsif ($heap->{'int_cnt'} == 3) {

	my $pres = `cat /tmp/t2`;
	like($pres, qr/Presence information for sip:user${AT}192.168.123.2:\s*not available or not online/s,
	  'NOTIFY: exec-notify worked');

	my $c = `cat /tmp/t3`;
	chomp $c;
        # the -- comes from echo
	is($c, '-- -e sip:user@192.168.123.2 -s closed -c tel:+12345 -p 1.0 -t 2001-10-27T16:49:29Z',
	   'NOTIFY: exec-closed worked');

        if (-e '/tmp/t4') {
	    ok(0, 'NOTIFY: exec-open should not be called');
	} else {
	    ok(1, 'NOTIFY: exec-open should not be called');
	}

	ok(-e '/tmp/t1', 'NOTIFY: exec called');

	`rm /tmp/t1`;
	`rm /tmp/t2`;
	`rm /tmp/t3`;

	$kernel->delay('send_udp_message', 2,
		       get_notify('open'));
    }
    elsif ($heap->{'int_cnt'} == 4) {

        my $l = get_header('Via', $input);
	like($l, qr/received=127.0.0/, 'NOTIFY: received param in 200 reply found');

	my $pres = `cat /tmp/t2`;
	like($pres, qr/Presence information for sip:user${AT}192.168.123.2:\s*available and online/s,
	  'NOTIFY: exec-notify worked');

	my $c = `cat /tmp/t4`;
	chomp $c;
        # the -- comes from echo
	is($c, '-- -e sip:user@192.168.123.2 -s open -c tel:+12345 -p 1.0 -t 2001-10-27T16:49:29Z',
	   'NOTIFY: exec-open worked');

        if (-e '/tmp/t3') {
	    ok(0, 'NOTIFY: exec-closed should not be called');
	} else {
	    ok(1, 'NOTIFY: exec-closed should not be called');
	}

	ok(-e '/tmp/t1', 'NOTIFY: exec called again');

	`rm /tmp/t1 /tmp/t2 /tmp/t3 /tmp/t4`;
	$kernel->delay('send_udp_message', 2,
		       get_notify('open'));
    }
    elsif ($heap->{'int_cnt'} == 5) {
	ok(!(-e '/tmp/t1'), 'NOTIFY: exec not called when no status change');
	ok(!(-e '/tmp/t3'), 'NOTIFY: exec-closed not called when no status change');
	ok(!(-e '/tmp/t4'), 'NOTIFY: exec-open not called when no status change');
	ok(-e '/tmp/t2', 'NOTIFY: exec-notify called when no status change');

	`rm /tmp/t1 /tmp/t2 /tmp/t3 /tmp/t4`;
	$kernel->delay('send_udp_message', 2,
		       get_notify('open', 'nota bene'));
    }
    elsif ($heap->{'int_cnt'} == 6) {
	ok(-e '/tmp/t1', 'NOTIFY: exec called when note change');
	ok(!(-e '/tmp/t3'), 'NOTIFY: exec-closed not called when note change');
	ok(!(-e '/tmp/t4'), 'NOTIFY: exec-open not called when note change');
    }    
    $heap->{'int_cnt'}++;
}



#############################################################################

#
# return a notify message
sub get_notify {
    my ($c, $n) = @_;
    my $content = '<?xml version="1.0"?>
<!DOCTYPE presence PUBLIC "//IETF//DTD RFCxxxx PIDF 1.0//EN" "pidf.dtd">
<presence entity="sip:user@192.168.123.2">
<tuple id="9r28r49">
  <status>
    '."<basic>$c</basic>";
    if (defined $n) {
	$content .= "<note>$n</note>\n";
    }
    $content .= "<contact priority=\"1.0\">tel:+12345
</contact><timestamp>
2001-10-27T16:49:29Z</timestamp></status>
</tuple>
</presence>".$CRLF;

    return 'NOTIFY sip:conny@192.168.123.2 SIP/2.0'.$CRLF.
           'Content-Length: '.length($content).$CRLF.$CRLF.$content;
}

#
# return a single header line
sub get_header {
    my $name = shift;
    my $in = shift;

    my @lines = split ("\n", $in);
    my $l;
    foreach (@lines) {
        if (/^$name: /) { $l = $_; last; }
    }
    return $l;
}


#
# Start a TCP server.
sub start_tcp_server {
  
    POE::Component::Server::TCP->new
	( Alias => "tcp-server",
	  Port => 5059,

	  ClientConnected => sub {
 	      my ( $kernel, $session, $heap) = @_[ KERNEL, SESSION, HEAP];
	      $heap->{'in_content'} = 0; # flag needed in ClientInput
	      $heap->{'content'} = '';
	      $heap->{'input_buf'} = '';
	  },

	  ClientInput => sub {
	      my ( $kernel, $session, $heap, $input ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];
	      #print "test-server: Session ", $session->ID(), " got input: $input\n";
	      $heap->{'input_buf'} .= $input ."\n";
	      if ($input eq '' && $heap->{'in_content'} == 0) {
 	          #print $heap->{'input_buf'};
	          $heap->{'in_content'} = 1; # found it
		  $heap->{'content'} = '';
	      }
	      elsif ($heap->{'in_content'}) {
		  $heap->{'content'} .= $input."\n";
	      }
	    
	      if ($heap->{'in_content'} 
		  && $heap->{'input_buf'} =~ /Content-Length:\s*(\d+)/s) {
		  my $clen = $1;
		  if (length($heap->{'content'}) >= $clen) {
		      #print "content: $heap->{'content'}\n";
		      $kernel->post('test-server' 
				    => 'continue' 
				    => $heap->{'input_buf'} 
				    => $heap->{'content'});

		      my $an= $answer;# subs_fail_answer;
		      if (defined $an) {
			  $heap->{'client'}->put($an);
		      }

		      $heap->{'in_content'} = 0;
		      $heap->{'content'} = '';
		      $heap->{'input_buf'} = '';
		  }
	      }
	  },

	  ClientDisconnected => sub {
	      # print "test-server: client disconnected\n";
	  },

	  InlineStates => { a_start => sub 
			    {
			        $_[KERNEL]->alias_set('tcp-server');
				print "************* tcp-server started\n";
			    },
			    snd => sub
			    {
			        # keep it for the next run
			        my($heap, $answer) = @_[HEAP, ARG0];
				print '************* tcp-server next time:' . $answer;
			        #$heap->{'answer'} = $answer;
			    }
			  }
			  
    );

} # end start_tcp_server


sub udp_send {
#    my($kernel, $heap, $message) = @_;
    my($kernel, $heap, $session, $message) 
      = @_[KERNEL, HEAP, SESSION, ARG0];

    my $remote_address = pack_sockaddr_in(5060, 
					  inet_aton("127.0.0.1") );

    unless (exists $heap->{'udp_socket'}) {
        $heap->{udp_socket} = IO::Socket::INET->new(Proto     => 'udp',
					   LocalPort => 5059
					  );

	die "Couldn't create udp socket: $!" unless $heap->{udp_socket};
	$kernel->select_read($heap->{udp_socket}, "get_datagram");
    }
    send($heap->{udp_socket}, $message, 0, $remote_address) 
      == length($message) or
	die "Trouble sending udp message: $!";
}


# start a session
POE::Session->create(
    package_states => [ main => [ "_start", 'continue' ] ],

    inline_states => {
	send_udp_message => \&udp_send, # sending data via udp
    }
);


$poe_kernel->run();
exit 0;


