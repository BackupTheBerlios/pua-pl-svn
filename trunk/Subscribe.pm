package Subscribe;

# handling of the SUBSCRIBE SIP messages and responses
# tries to conform to RFC 3265 and 3856 
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
use Transaction;        # to handle message sequences

use Handler;            # super class
use vars qw(@ISA);
@ISA = qw(Handler);

use Presence;    # my own submodule, event package for presence and pidf doc
use Watcherinfo; # my own submodule, event package for watcherinfo 


###### methods ##############################################################

#
# Constructor, expects reference to the log object, and to the options
# additionally expects name of the package, like 'presence' or
# 'presence.winfo' or ...

sub new {
    my $class        = shift;
    my $self         = {};
    bless($self);

    $self->{log}     = shift;               # reference to the log object
    $self->{options} = shift;               # reference to the options object
    $self->{package} = shift;               # reference to the package name
    $self->{state}   = 'subs_initializing'; # sub state for subscribe

    # create the event package object, sort of if-elsif-factory would do
    if ($self->{package} =~ /^(.*)\.winfo$/) {
        $self->{event_package} = new Watcherinfo($self->{log}, 
						 $self->{options}, $1);
    } elsif ($self->{package} eq 'presence') {
        $self->{event_package} = new Presence($self->{log}, 
					      $self->{options});
    } else {
	$self->{log}->write(WARN, "$SIP_USER_AGENT Warning: Unknown event package ".
			    "$self->{package}");
    }
    return $self;
}


#
# construct and return a subscribe sip message, informing
# the server whom we watch for

sub get_msg {
    my $self = shift;
    my $expires = $_[0];
    my $options = $self->{options};
    my $headers = '';

    # if ($expires == 0) { $expires = 1; } 

    unless (exists $self->{transaction}) {
	$self->{transaction} 
	  = new Transaction('log'      => $self->{log},
			    'options'  => $options,
			    'to'       => $options->{watch_id},
			    'from_dn'  => $options->{my_name},
			    'from'     => $options->{my_id});
    } else {
	$self->{transaction}->next_cseq();
    }

    # set the head of the message
    $self->{transaction}
      ->set_param('head',
		  'SUBSCRIBE '.$options->{watch_id}.' SIP/2.0');

    # set some extra header lines, subscribe specific

    $headers = 'Event: '.$self->{package}.$CRLF;
    if (exists ($self->{event_package})) {
	my $ct;
        my $ep = $self->{event_package};
	my @cts = $ep->get_content_types();
	foreach $ct (@cts) {
	    $headers .= 'Accept: '.$ct.$CRLF;
	}
    }
    $headers .= 'Expires: '.$expires.$CRLF.
	        'Contact: <sip:'.$options->{login} . 
		   '@'.$options->{my_host};
		    
    # check if port number included
    unless ($options->{my_host} =~ /:\d+$/) {
        $headers .= ':'.$options->{local_port};
    }
    $headers .= '>'.$CRLF;

    $self->{transaction}->set_param('headers', $headers);

    return $self->{transaction}->get_message();
}



#
# The state processing for the SUBSCRIBE relevant states, returns a suggested 
# main state. Legend:- means, the event is ignored, o means it is handled
# but does not cause a state transition, x means it terminates the state
# machine, and with it the program.
#
# state \     event|started| subscribed |   ended   |    notified    |subfailed
#------------------+-------+------------+-----------+----------------+---------
# subs_initializing|   o   |subs_running|     x     |        -       |subs_ign.
# subs_running     |   -   |     -      |subs_ending|o/x/subs_waiting|subs_ign.
# subs_waiting     |   -   |     -      |     x     |        -       |subs_ign.
# subs_ending      |   -   |     x      |     x     |        -       |subs_ign.
# subs_ignoring    |   x   |     x      |     x     |        x       |   x
#
# returns 2 values: (1) a suggested main state, return value 'x' means, 
# we're done so far and the main state machine may exit, and (2) a transaction
# in case a message shall be send.

sub control {
    my $self = shift;
    my ($kernel, $event, $header, $content) = @_;
    my $ret = 'x';
    my $options = $self->{options};
    my $state = $self->{state};
    my $transaction;
    my $ok = 0;

    unless ($options->{subscribe}) { return 'x'; } 

    $log->write(DEBUG, "subscribe: in state $state got event $event");

    if ($state eq 'subs_initializing') {

        if ($event eq 'started') {

	    $self->create_subscribe($kernel); # create the message
	    $ret = 'running';
	    $transaction = $self->{transaction};

        } elsif ($event eq 'subscribed') {

	    # all ok, refresh subscription after expiry-3 seconds
            # so we start a timer. TODO: restart timer after we got a
            # timeout notification from the server ?

	    $self->handle_message(@_);

 	    if ($options->{subscribe_exp} > 3) {
 	        $kernel->delay('subexpired', $options->{subscribe_exp} - 3);
	    }
	    $self->change_state('subs_running');
	    $ret = 'running';

        } elsif ($event eq 'subfailed') {

	    # check if it is the server challenging authorization
	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		$self->change_state('subs_ignoring');
		$ret = 'x';
	    }
	} elsif ($event eq 'ended') {
            $ret = 'x';
	} else {
	    # any other event, not for me
	    $ret = 'running';
	}

    } elsif ($state eq 'subs_running') {

	if ($event eq 'subexpired') {

	    if ($options->{notify_once}) {
		# give up, don't expect any more notifies
                $log->write(WARN, "$SIP_USER_AGENT: no notification received".
			    ", giving up.");
		$self->change_state('subs_ignoring');
		$ret = 'x';

	    } else {

		# it's time to refresh subscription
		$self->create_subscribe($kernel);
		$transaction = $self->{transaction};
		$ret = 'running';
	    }

	} elsif ($event eq 'subscribed') {

	    # received status ok for a SUBSCRIBE message 
	    $self->handle_message(@_);
	    $ret = 'running';

	} elsif ($event eq 'notified') {

	    # this was an incoming notification about the presence of
	    # somebody we are watching. The ok reply to the server is
	    # already out. Parse the info and process it

            if (length($content)) {

	        # parse the body, the message content
                if (exists $self->{event_package}) {
		    my ($ct, $cont);
		    my $ep = $self->{event_package};
		    $ct = $self->get_content_type($header);

		    # if no content type was given, we don't know how to parse
		    if (defined $ct) {
			$cont = $ep->parse($content, $ct);
		    } 
			
                    if (defined $cont and $cont ne '') {
			$self->{log}->write(WARN, $SIP_USER_AGENT.': '.$cont);
			$self->run_exec($options->{'exec_'.$self->{package}}, 
					$cont);
		    }
                }
                # pass the entire xml document to the executable
		$self->run_exec($options->{'exec_xml_'.$self->{package}}, 
				$content);
                # pass the entire xml document to the generic executable
		$self->run_exec($options->{'exec_xml'}, $content);
            }

            my ($status, $delay) = $self->notify_check($header);
  
            if ($status eq 'ok') {

		if ($options->{notify_once}) {
		    # ready
		    $ret = 'x';
		    $self->change_state('subs_ignoring');
                    $log->write(DEBUG, "Subscribe: Notification received, leaving.");
		} else {
		    # stay in this state, wait for next
                    $ret = 'running';
                    # check if server has set expiry of subscription
                    if (defined $delay) {
                        # overwrite previously set time out
                        $kernel->delay('subexpired', $delay - 3);
                    }
		}	

	    } elsif ($status eq 're-subscribe') {

		if ($options->{notify_once}) {
		    # ready
		    $ret = 'x';
                    $log->write(DEBUG, "Subscribe: Notification received, leaving.");
		    $self->change_state('subs_ignoring');
		} else {
                    if (defined $delay and $delay > 0) {
                        # it was a notification that the subscription temporary failed
                        # including a "retry-after" hint, so start a timer, then retry

                        $self->change_state('subs_waiting');
                        $log->write(DEBUG, "subscribe: delay subscribe for $delay sec");
                        $kernel->delay('subdelayed', $delay);
                        $ret = 'running';
                    } else {
 	 	        # immediately try again to subscribe
		        $self->create_subscribe($kernel);
		        $transaction = $self->{transaction};
		        $ret = 'running';
                    }
		}
	    } else {

	        # subscription failed, leave state 
                $log->write(WARN, "$SIP_USER_AGENT: pa terminated subscription with reason ".
			    $status. ", leaving...");
		$self->change_state('subs_ignoring');
		$ret = 'x';
	    }

	} elsif ($event eq 'ended') {

	    # this event is generated when a signal is caught that
	    # shows that the program shall be ended, for instance by
	    # the user pressing Ctrl-C. Send a subscribe message to 
	    # the server that indicates that we unsubscribe, i.e. by
	    # setting the Expires header to 0. We will terminate the 
	    # programm after receiving the ok, or after 3 seconds

	    $self->change_state('subs_ending');
	    my $msg = $self->get_msg(0);
  	    $log->write(DEBUG, "subscribe: send unsubscribe message "
			.(split("\n", $msg))[0]);
	    $kernel->sig_handled();

	    $ret = 'terminating';
	    $transaction = $self->{transaction};

	} elsif ($event eq 'subfailed') {

	    # check if it is the server challenging authorization
	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		$self->change_state('subs_ignoring');
		$ret = 'x';   
		$log->write(WARN, "$SIP_USER_AGENT: Subscription to $options->{watch_id}"
			    ." failed, error '"
			    .(split("\n", $header))[0] ."'\n");
	    }
	} else {

	    # all other events are not for me, so don't want to do something
	    # with them ...
	    $ret = 'running';
	}

    } # end if state subs_running
    elsif ($state eq 'subs_waiting') {

        # this stat is for temporarily unsubscription. We wait for a timeout
        # and then try to suscribe again

	if ($event eq 'subdelayed') {

            # this event indicates that we  can re-subscribe again -
            # previously the server sent a notify with a retry-after
            # timer, which just expired. So try again to subscribe now

  	    $self->create_subscribe($kernel);
	    $self->change_state('subs_running');
	    $transaction = $self->{transaction};
	    $ret = 'running';

	} elsif ($event eq 'notified') {

	    # TODO: we have no outstanding subscription when being in state 
            # 'waiting' -> send a 489, bad request
 	    $ret = 'running';

	} elsif ($event eq 'ended') {

	    # user wants to abort program
	    $ret = 'x';

        } else {

	    $ret = 'running'; # no change

	}
    } # end if state waiting

    return ($ret, $transaction);
}


#
# send a subscribe message to the presence agent, with default expire

sub create_subscribe {
    my $self = shift;
    my $options = $self->{options};
    my $msg;
    
    if ($options->{notify_once}) {
	$msg = $self->get_msg(0);
    } else {
	$msg = $self->get_msg($options->{subscribe_exp});
    }
    $log->write(DEBUG, "subscribe: send default subscribe message "
		.(split("\n", $msg))[0]);
}

#
# change the state and log it


#
# handle_subscribed, called when the ok status reply to the
# subscribe request is received.

sub handle_message {
    my $self = shift;
    my ($kernel, $event, $header, $content) = @_;
    my $options = $self->{options};

    # all ok, refresh subscription after expiry-3 seconds
    # so we start a timer. TODO: restart timer after we got a
    # timeout notification from the server ? Get the expire
    # header field for the timer, instead the option ?

    if ($options->{subscribe_exp} > 3) {
        $kernel->delay('subexpired', $options->{subscribe_exp} - 3);
    }

    # extract tag from To: header
    my $h;
    foreach $h (split("\n", $header)) {
        if ($h =~ /^To:/i) {
	    if ($h =~ /tag=(.*)$/i) {
		$self->{transaction}->set_param('to_tag', $1);
	    } else {
	        $log->write(WARN, "$SIP_USER_AGENT: Couldn't find tag in To: ".
			    "header of message $header\n");
	    }
	}
        elsif ($h =~ /^From:/i) {
	    if ($h =~ /tag=(.*)$/i) {
		# tell our transaction
		$self->{transaction}->set_param('from_tag', $1);
	    } else {
	        $log->write(WARN, "$SIP_USER_AGENT: Couldn't find tag in From: ".
			    "header of message $header\n");
	    }
	}
    }
}



#
# parse the header of the received NOTIFY message and return one of
# the following, depending on the header 'Subscription-State'.
# 'ok'           - in case it is a plain notification with a body,
#                  extra parameter timeout is set in case a expiry 
#                  parameter is found
# 're-subscribe' - in case the server wants us to subscribe again.
#                  Extra parameter nnnn is set in case the pa wants
#                  us to retry subscription after nnnn second
# <any other>    - all other return values are a subscription failure 
#                  reason
sub notify_check {
    my $self = shift;
    my ($headers) = $_[0];
    my ($h);
    my ($ret, $delay);

    foreach $h (split("\n", $headers)) {
        if ($h =~ /Subscription-State:\s*active\s*;.*expires\s*=\s*(\d+)/i) {
            return ('ok', $1);
  	} 
        if ($h =~ /Subscription-State:\s*terminated\s*;.*retry-after\s*=\s*(\d+)/i) {
            # subscription terminated, retry-after param found
 	    $log->write(DEBUG, "notify: subscription retry-after $1");
	    return ('re-subscribe', $1);
	} 
	if ($h =~ /Subscription-State:\s*terminated\s*;.*reason\s*=\s*(\w+)/i) {
	    # terminated, and a reason was specified, so parse this
	    my $r = $1;
	    $log->write(DEBUG, "notify: subscription terminated, reason '$r'");

	    if ($r =~ /^deactivated/i || $r =~ /^timeout/i) {
	        # immediately try again
		return ('re-subscribe', 0); 
	    } elsif ($r =~ /^probation/i || $r =~ /^giveup/i) {
		# we checked already for the retry-after param, and it was 
		# not there, so we retry after, say 60 sec
		return ('re-subscribe', 60);
	    } else {
		# all else is fatal
		return $r;
	    }
	} 
	if ($h =~ /Subscription-State:\s*terminated/i) {
	  $log->write(DEBUG, "notify: subscription terminated, unknown reason");
	    return 'unknown error';
	}
    }
    return 'ok';
}


#
# run the external command, with a number of parameters

sub run_exec {
    my $self = shift;
    my ($cmd, $input) = @_;

    if (!defined $cmd or $cmd eq '') {
	return;
    }

    $log->write(TRACE, 'notify: exec '.$cmd);
    open(EXEC, '| '.$cmd) or die("$SIP_USER_AGENT: Can't run ".
				 $cmd. ", $!");
    print EXEC $input;
    close EXEC;
}


# 
# called when a SIP message is received. The function checks if it is
# subscribe relevant, and if yes, it returns the name of the internal
# message to be posted, like 'subscribed', or undef in case of not relevant.
# If the message is a notify, it also sends the response

sub check_message {
    my $self = shift;
    my ($header, $content, $human_addr) = @_;
    my ($l0, $l, $ok, $ret);
    my $return_headers = '';

    my $subscribeline = '';
    my $callid = '';
    my $transaction;

    # the message cannot be for subscribe if there is no previously
    # created transaction object
    unless (exists $self->{transaction}) {
        return undef; # not for me
    }  else {
        $transaction = $self->{transaction};
    }
    
    # get the cseq line, for the method name    
    foreach $l (split("\n", $header)) {
        unless (defined $l0) { $l0 = $l; } # keep the first one
        if ($l =~ /^CSeq\s*:\s*\d+\s+SUBSCRIBE/i) {        
            $subscribeline = $l;
        }
        if ($l =~ /^Call-ID\s*:\s*(.*?)\s*$/i) {        
            if ($1 eq $transaction->get_call_id()) {
                $callid = $1;
            }
        }

        # if the message is a response to SUBSCRIBE and the call-id
        # matches the one of the transaction, we have to handle it

        if ($callid ne '' && $subscribeline ne '') {
            my $code = $self->get_message_code($header);
            if ($code >= 200 && $code <= 299) {
                $ret = 'subscribed';
            } else {
                $ret = 'subfailed';
            }
            last;
        }

        # for notify, get the header lines that will be required for the
        # sip 200 OK message responds

	if ($l =~ /^Via:\s*SIP\/2\.0/i) {
            if (defined $human_addr) {
                $return_headers .= $l.';received='.$human_addr . $CRLF;
            } else {
                $return_headers .= $l . $CRLF;
            }
	} elsif ($l =~ /^CSeq\s*:\s*(\d)+\s+NOTIFY/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^From\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^To\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	} elsif ($l =~ /^Call-ID\s*:/i) {
  	    $return_headers .= $l . $CRLF;
	}

    } 

    # send a ok reply to the server, if it was a notify
 
    if ($l0 =~ /^NOTIFY/) {
        $ok = $self->get_ok_reply_msg($return_headers);
	$log->write(SPEW, "server: reply with $ok");
        $ret = 'notified';
    }

    return ($ret, $ok);
}




1;
