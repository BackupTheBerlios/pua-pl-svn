#!/usr/bin/perl -w

# pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $LastChangedDate$, Conny Holzhey

use warnings;
use strict;

use Carp;               

use POE qw(Component::Client::TCP); # the TCP client is used to send requests
                                    # to the presence server

use IO::Socket::INET;   # to receive/sendmessages

use lib qw(.);          # the libs below are local, so allow to load them


################### global variables, internal ##############################


#
# For logging. Rough guidelines: log level DEBUG shows states and state 
# transitions. Level TRACE shows connection and parse info, SPEW 
# additionally shows received and sent sip messages

use Log::Easy qw(:all); 

my $log = new Log::Easy;
$log->log_level(INFO);
$log->prefix('');

#
# my dedicated submodule to handle the default options
# and the command line

use Options;
my $options = new Options($log);

#
# Handler.pm derived objects (actually library instances), for 
# each message handling one

use Publish;   # handler for PUBLISH messages
use Subscribe; # handler for SUBSCRIBE messages
use Register;  # handler for REGISTER messages
use Message;   # handler for MESSAGE messages

my @handlers ; # a list of Handler.pm derived objects, like Publish...


#
# header lines have to be terminated with CRLF

my $CRLF = "\015\012";


#
# the main internal states. The following names are correct: 'initializing'
# 'running', 'terminating'.See sub control() where the states are set 
# and used

my $state = 'initializing'; 






######################## state handling #####################################

#
# List of things the script does. This is basically the plain sequence, 
# without any errors. 
#
# 1) REGISTER at the registrar server, only if option -r set
# 2) wait for ok
#
# 3) PUBLISH the presence server about my presence, if any
# 4) wait for ok
#
# 5) SUBSCRIBE to somebody else presence, if any
# 6) wait for ok
#
# 7) wait for NOTIFY of somebody else presence
# 8) send ok
#
# 9) repeat 5)..9)
# 



#
# main control function, in case the processing order needs to be
# changed, this is the right place. These are the main states: initializing, 
# running, terminating. This function is a simple matrix in form of nested 
# switch/case (or if-elsif chains, as this is perl) of states and of events. 
# All state transitions are done here. This table shows the possible 
# transitions, legend:- means, the event is ignored, o means it is handled
# but does not cause a state transition, x means it terminates the state
# machine, and with it the program.
#
# state \ event|started|registered|subscribed|notified|   ended   |published|
# -------------+-------+----------+----------+--------+-----------+---------+
# initializing | run/x |    -     |    -     |   -    |     x     |    -    |
# running      |   -   |    o     |    o     |  o/x   |terminating|    o    |
# terminating  |   -   |    x     |    x     |   -    |     x     |    x    |
#
# cont.
# state \ event|subdelayed|*expired|regfailed|subfailed|pubfailed|
# -------------+----------+--------+---------+---------+---------+---------+
# initializing |     -    |    -   |    -    |    -    |    -    |
# running      |     o    |    o   |    x    |    x    |    x    |
# terminating  |     -    |    -   |    x    |    x    |    x    |
#

sub control {
    my ($event, $kernel, $heap, $session, $header, $content) = @_;
    my $h;

    $log->write(DEBUG, "control: in state $state got event $event");

    if ($state eq 'initializing') {

        # started is the initial event, right after the framework comes up
        if ($event eq 'started') {

	    # create a object each for message specific handling
	    my $publ = new Publish($log, $options);
	    my $subs = new Subscribe($log, $options, $options->{event_package});
	    my $reg  = new Register($log, $options);
            my $msg  = new Message($log, $options);

	    push @handlers, $reg;
	    push @handlers, $publ;
	    push @handlers, $subs;
            push @handlers, $msg;

	    sip_wait_message($kernel, $heap); # start listening

	    # next step is to register at the registrar, subscribe
	    # for somebody elses presence, or publish, depending
            # on what was given on the command line. Let the
            # individual handlers decide what to do

	    my $ns = ''; # new state

	    foreach $h (@handlers) {
		my ($s, $t) = $h->control($kernel, 'started',
					  $header, $content);

		# check if a message was returned, and send it
		if (defined $t) {
		    sip_send_message($heap, $kernel, $t->get_message());
		}
		
		# remember that at least one handler wants to 
		# go to state running
		if ($s eq 'running') { $ns = 'running'; }
	    }

	    if ($ns eq 'running') {
       	        change_state('running');
	    } else {
	        # exit
	        $log->write(DEBUG, "control: leaving");
	        $kernel->yield('shutdown');
	    }

        } elsif ($event eq 'ended') {

	    # user wants to abort program
	    $log->write(DEBUG, "control: leaving");
	    $kernel->yield('shutdown');

	}
        # end if initial state

    } elsif ($state eq 'running') {

	my $term = 0;
	my $ex = 1;

	foreach $h (@handlers) {
	    my ($s, $t) = $h->control($kernel, $event, $header, $content);

	    # check if a message was returned, and send it
	    if (defined $t) {
		sip_send_message($heap, $kernel, $t->get_message());
	    }
		
	    # remember that at least one handler wants to 
	    # go to state terminating
	    if ($s eq 'terminating') { $term = 1; }
	    $ex = $ex && ($s eq 'x');
	}

	if ($ex) {
	    # all handlers returned 'x', so nothing to do, leave
	    $log->write(DEBUG, "control: leaving");
  	    $kernel->stop();

	} elsif ($term) {
	    change_state('terminating');
	} 
	# else stay in this state
	# end if running state

    } elsif ($state eq 'terminating') {

	my $ex = 1;

	foreach $h (@handlers) {
	    my ($s, $t) = $h->control($kernel, $event, $header, $content);

	    # check if a message was returned, and send it
	    if (defined $t) {
		sip_send_message($heap, $kernel, $t->get_message());
	    }
	    $ex = $ex && ($s eq 'x');
	}

	if ($event eq 'ended' || $ex) {

	    # all sub state machines are ready to leave or
	    # user really wants to abort program
	    $log->write(DEBUG, "control: leaving");
  	    $kernel->stop();
	} 

    } else {
        # should not happen
        die("$SIP_USER_AGENT: Invalid internal main state");
    }
}

#
# change the main state and log it, only used from sub xx_control
sub change_state {
    my ($newstate) = @_;
    my $os;

    $os = $state; 
    $state = $newstate; 

    $log->write(DEBUG, "control: change main state from $os to $newstate");
}






####### session methods #####################################################


#
# session method, called when in initial state _start 

sub _start {

    # some basic initializations
    $_[KERNEL]->alias_set('pua');

    $_[KERNEL]->post('pua', 'started');

    $_[HEAP]->{content} = '';
    $_[HEAP]->{content_len} = 0;
    $_[HEAP]->{headers} = '';

    # install the signal handling
    $_[KERNEL]->sig('HUP', 'ended');
    $_[KERNEL]->sig('INT', 'ended');
    $_[KERNEL]->sig('KILL', 'ended');
    $_[KERNEL]->sig('QUIT', 'ended');
    $_[KERNEL]->sig('TERM', 'ended');

} # end _start




#
# session method, called when the client gets a return message, or a notify

sub sip_got_message {
    my ( $heap, $session, $header, $content) 
        = @_[ HEAP, SESSION, ARG0, ARG1];

    $log->write(SPEW, "sip_got_message: got header '$header'");
    if (defined $content) {
        $log->write(SPEW, "sip_got_message: got content '$content'");
    } else {
        $log->write(SPEW, "sip_got_message: got no content");
    }

    # let the handlers deal with the message, return value is a string which will
    # be interpreted as message to be posted, one of 'register', 'regfailed'
    # 'subscribed', 'subfailed', 'notified', etc.

    my ($m, $reply, $done, $h);
    $done = 0;
    foreach $h (@handlers) {
        ($m, $reply) = $h->check_message($header, $content, $heap->{'peer_address'});
        if (defined $m) {

            if (defined $reply) { # in case of NOTIFY
	        $_[KERNEL]->post(pua => send_udp_message => $reply => 0);
            }

            # inform control function
            $_[KERNEL]->post(pua => $m => $header => $content);

            $done++;
        }
    }

    unless ($done) {
        # nobody did something with this message, return a not implemented
        # to the sip server
        $reply = get_501($heap->{'peer_address'}, $header);
        $_[KERNEL]->post(pua => send_udp_message => $reply => 0);
    }
}




######################### helpers ###########################################


#
# Create the TCP client that sends a message and waits for 
# the responds. The client is terminated when the responds is 
# received. In case TCP doesn't work, post a primitive to myself
# to indicate that we should try it using an UDP client

sub sip_send_message {
    my ($heap, $kernel, $msg) = @_;

    if (exists $heap->{'tcp_failed'} && $heap->{'tcp_failed'} > 0) {

        # previous attempt via tcp failed, use udp instead
        $kernel->post( pua => send_udp_message => $msg => 1); 

    } else {

        # first try to send the message via tcp protocol 

        POE::Component::Client::TCP->new(
            RemoteAddress => $options->{proxy},
            RemotePort    => $options->{remote_port}, # server can be shifted for testing
            Args          => [ $msg ],

            Started => sub {
                $_[HEAP]->{session_id} = $_[SENDER]->ID; # the parent session
                $_[HEAP]->{headers} = '';
                $_[HEAP]->{content} = '';
                $_[HEAP]->{content_len} = 0;
                $_[HEAP]->{message} = $_[ARG0]; # that will be sent to pa
            },

            Connected => sub {
                my ( $heap, $session ) = @_[ HEAP, SESSION ];
		$log->write(TRACE, "client: connected.");

                my $msg = $heap->{'message'};
                $log->write(SPEW, "client: sending ".$msg);

		$heap->{server}->put($msg); # put the sip message

                # trace it
		if ($options->{'trace'}) {
		    $log->write(NOTICE, '>>>>>>');
		    foreach (split ($CRLF, $msg)) {
			$log->write(NOTICE, '>>> '. $_);
		    }
		}
            },

	    ConnectError => sub { 
	        # tcp connection failed, try again with udp
	        $log->write(INFO, "TCP Connection failed $_[ARG1] in '$_[ARG0]': $_[ARG2]".
			    " ... will try UDP.");
		$heap->{'tcp_failed'} = 1;
	        $_[KERNEL]->post( pua => send_udp_message => $_[HEAP]->{'message'} => 1);
		
	    },

            ServerInput => sub {
                my ( $kernel, $heap, $session, $input ) 
		  = @_[ KERNEL, HEAP, SESSION, ARG0 ];
                # $log->write(SPEW, "client: got input from server '$input'");
                append_input($kernel, $heap, $input);

	    }, # end sub ServerInput
 
	    ServerFlushed => sub {
                my ( $session ) = $_[ SESSION ];
		$log->write(TRACE, "client: server flushed");
            },
 
            Disconnected => sub {
                my ( $kernel, $heap, $session ) = @_[ KERNEL, HEAP, SESSION ];
		$log->write(TRACE, "client: server disconnected");
            },
 
	 ); # end POE::Component::Client::TCP->new()
    }
}

#
# send a message via udp protocol to the server. In case of a reply to the message
# is expected, a timeout is started and the listen on the port is initiated

sub udp_send {
    my($kernel, $heap, $session, $message, $reply_expected) 
      = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];

    if ($reply_expected) {

        # Reset flag indicating if we received something via udp, and start
        # a timer. After expiry we will check that flag again, and in case it
        # is unchanged, we know we didn't receive a reply

        $heap->{'udp_received'} = 0; 
        $kernel->delay('timeout_udp', 20); # 20 seconds

        sip_wait_message($kernel, $heap); # start listening
    }

    my $host = inet_aton($options->{proxy});
    unless (defined $host) {
	die "$SIP_USER_AGENT: proxy server $options->{proxy} cannot be resolved.\n";
    }

    my $remote_address = pack_sockaddr_in($options->{remote_port}, 
					  $host); 

    $log->write(SPEW, "client: sending via udp '$message'");
    send($heap->{udp_socket}, $message, 0, $remote_address) 
        == length($message) or
            die "$SIP_USER_AGENT: Trouble sending udp message: $!";

    if ($options->{'trace'}) {
	$log->write(NOTICE, '>>>>>>');
	foreach (split ($CRLF, $message)) {
	    $log->write(NOTICE, '>>> '. $_);
	}
    }
}


#
# this funciton is called while waiting for the blocking udp socket operations
# to finish. 

sub udp_timeout {
    my($heap) = $_[HEAP];

    $log->write(DEBUG, 'client: udp timeout');

    if (exists $heap->{'udp_received'} && $heap->{'udp_received'} > 0) {
        # all went ok
    } else {
        # still waiting for responds
        # actually this may not be an error ... FIXME
        die "$SIP_USER_AGENT: Timeout while waiting for response SIP message via udp\n";
    }
}


#
# Create the UDP server that waits for a sip message and sends 
# the responds. 

sub sip_wait_message() {
    my $kernel = shift;
    my $heap = shift;
    
    unless (exists $heap->{'udp_socket'}) {
        my $socket = IO::Socket::INET->new(Proto     => 'udp',
					   LocalPort => $options->{local_port},
					  );

	die "$SIP_USER_AGENT: Couldn't create udp socket on port "
	    ."$options->{local_port}: $!" 
	    unless $socket;
    
	$log->write(DEBUG, "server: listening on udp local port $options->{local_port}");
	$kernel->select_read( $socket, "get_datagram" );
	$heap->{'udp_socket'} = $socket;
    }
}


#
# sort of low level function, called when the udp connection 
# receives something, 

sub udp_read {
    my($kernel, $heap, $session, $socket) = @_[KERNEL, HEAP, SESSION, ARG0];
    my $message;
    my $remote_address;

    $heap->{'udp'} = 1; # been here
    $heap->{'udp_received'} = 1; 

    $remote_address = recv( $socket, $message = '', (64*1024) - 1 , 0);
    return unless defined $remote_address;

    my ( $peer_port, $peer_addr ) = unpack_sockaddr_in($remote_address);
    my $human_addr = inet_ntoa($peer_addr);
    $heap->{'peer_address'} = $human_addr;
    $log->write(SPEW, "server: $human_addr : $peer_port sent us $message\n");

    my @lines = split($CRLF, $message, -1); # preserve trailing fields

    # process line-wise all the lines we have so far. 

    $heap->{'content'} = '';
    $heap->{'content_len'} = 0;
    $heap->{'headers'} = '';

    my $l;
    foreach $l (@lines) {
        append_input($kernel, $heap, $l);
    }
}


#
# this function can be used for line-wise processing of 
# incoming messages, regardless if they are transported via 
# udp or tcp

sub append_input {
    my ($kernel, $heap, $input, $return_headers) = @_;

    my $headers = $heap->{headers};

    # trace the received message
    if ($options->{'trace'}) {
	if ($headers eq '') {
	    $log->write(NOTICE, '<<<<<<');
	}
	$log->write(NOTICE, '<<< '. $input);
    }

    if ($heap->{'content'} eq '') {

        # still in process to receive the headers
        chomp($input);
	$input =~ s/\015//;

	if ($headers ne '') {
  	    if ($input =~ /^\s+(\S.*)/) {
	        # leading whitespace indicates continuation of the 
	        # previous header line, so append it (below) without \n
	        $input = ' '.$1; # and with only 1 whitespace
	    } else {
	        $headers .= "\n"; 
	    }
	}

	# Check if it is the content length, this method
	# will break in case somebody puts the actual 
	# length on a second line

	if ($input =~ /^\s*Content-Length\s*:\s*(\d+)\s*$/i) {
	    $heap->{content_len} = $1;
	}

	if ($input eq '') {
	    # finished with headers
	    # inform main session, in case there is no content
	    if ($heap->{content_len} == 0) {
                if ($headers) {
    	            $kernel->post( pua => sip_got_message => $headers);
                    $heap->{headers} = ''; # don't send it again
                } 
	    } else {
	        # miss use $heap->{content} a bit
	        $heap->{'content'} = -1;
            }
	    
	} else {
	    # append to what we have so far
	    # still processing the headers
	    $heap->{headers} = $headers . $input;
        }

    } else {

        if ($heap->{'content'} eq -1) { 
	    $heap->{'content'} = '';
	}

        # headers already finished,
        # append it to the content 
        $heap->{content} .= $input."\n";
 
	# FIXME: what if delimiter is only \n ?
	$heap->{content_len} -= length($input) + length($CRLF);
	if ($heap->{content_len} <= 0) {
            if ($headers) {
  	        # finished, inform session and close this
	        $kernel->post('pua' => sip_got_message 
		  	            => $heap->{headers}
                                    => $heap->{content}); 
                $heap->{headers} = '';
            }
	}
    }
} # end append_input


#
# construct a 501 not implemented message message.
# the Via headers, the From, To Call-ID and CSeq headers are taken
# from the request, and should be passed with the headers param

sub get_501 {
    my ($human_addr, $header) = @_;
    my $return_headers = '';
    my $l;

    foreach $l (split("\n", $header)) {
	if ($l =~ /^Via:\s*SIP\/2\.0/i) {
            if (defined $human_addr) {
                $return_headers .= $l.';received='.$human_addr . $CRLF;
            } else {
                $return_headers .= $l . $CRLF;
            }
	} elsif ($l =~ /^CSeq\s*:\s*(\d)+\s+/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^From\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^To\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^Call-ID\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	}
    }

    my $msg =
      'SIP/2.0 501 Not Implemented'.$CRLF.
      $return_headers.
      'User-Agent: '.$SIP_USER_AGENT.$CRLF.
      'Content-Length: 0'.$CRLF.$CRLF;

    return $msg;
}




######### main ###########################################



# map the states of the session to the functions
POE::Session->create(
    package_states => [ main => [ "_start", "sip_got_message" ] ],

    # internal events are basically all mapped to sub control, to 
    # have all in one place

    inline_states => {
        started     => sub { control('started',     @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        registered  => sub { control('registered',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        subscribed  => sub { control('subscribed',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        published   => sub { control('published',   @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        ended       => sub { control('ended',       @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        notified    => sub { control('notified',    @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	subdelayed  => sub { control('subdelayed',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	subexpired  => sub { control('subexpired',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	pubexpired  => sub { control('pubexpired',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	regexpired  => sub { control('regexpired',  @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	regfailed   => sub { control('regfailed',   @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	subfailed   => sub { control('subfailed',   @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
	pubfailed   => sub { control('pubfailed',   @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        msgsent     => sub { control('msgsent',     @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        msgfailed   => sub { control('msgfailed',   @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },
        msgreceived => sub { control('msgreceived', @_[KERNEL, HEAP, SESSION, ARG0, ARG1]); },

        get_datagram     => \&udp_read, # receiving data via udp
	send_udp_message => \&udp_send, # sending data via udp
	timeout_udp      => \&udp_timeout 
    }
);



$poe_kernel->run();
exit 0;

