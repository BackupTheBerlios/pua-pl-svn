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

require pidf;           # my own submodule, for parsing pidf documents



###### methods ##############################################################

#
# Constructor, expects reference to the log object, and to the options

sub new {
    my $class        = shift;
    my $self         = {};
    bless($self);

    $self->{log}     = shift;               # reference to the log object
    $self->{options} = shift;               # reference to the options object
    $self->{state}   = 'subs_initializing'; # sub state for subscribe
    $self->{tuples}  = ();                  # empty hash

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

    $headers = 'Event: presence'.$CRLF.
               'Accept: application/pidf+xml'.$CRLF.
	       'Expires: '.$expires.$CRLF.
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

    unless ($options->{subscribe}) { return 'x'; } # exit from me out

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
	} else {
	    # exit
	    $ret = 'x'; 
	}

    } elsif ($state eq 'subs_running') {

	if ($event eq 'subexpired') {

	    # it's time to refresh subscription
 	    $self->create_subscribe($kernel);
	    $transaction = $self->{transaction};
	    $ret = 'running';

	} elsif ($event eq 'subscribed') {

	    # received status okfor a SUBSCRIBE message 
	    $self->handle_message(@_);
	    $ret = 'running';

	} elsif ($event eq 'notified') {

	    # this was an incoming notification about the presence of
	    # somebody we are watching. The ok reply to the server is
	    # already out. Parse the info and process it

	    my $status = $self->notify_check($header);

            if ($status eq 'ok') {

	        # all headers are ok, parse the body, the message content
	        pidf_parse($content, 
			   $log, 
			   sub {           # callback #1
			       my $self = $_[1];
			       my $options = $self->{options};
			       if ($options->{exec_notify} ne '') {
				   open(EXEC, '| '.$options->{exec_notify}) or
				     die("$SIP_USER_AGENT: Can't run ".
					$options->{exec_notify}. ", $!");
				   print EXEC $_[0];
				   close EXEC;
			       };
			       $self->{log}->write(WARN, $SIP_USER_AGENT.': '.$_[0]);
			   },
			   $self,          # arg 1
			   \&handle_tuple, # callback #2
			   $self);         # arg 2

		$self->clean_tuples(); # remove the remaining old ones

		if ($options->{notify_once}) {
		    # ready
		    $ret = 'x';
		    $self->change_state('subs_ignoring');
		} else {
		    $ret = 'running';
		    # stay in this state
		}	

	    } elsif ($status =~ /^\d+$/) {

  	        # it was a notification that the subscription temporary failed
                # including a "retry-after" hint, so start a timer, then retry

 	        $self->change_state('subs_waiting');
 	        $log->write(DEBUG, "subscribe: delay subscribe for $status sec");
	        $kernel->delay('subdelayed', $status);
		$ret = 'running';

	    } elsif ($status eq 're-subscribe') {

	        # immediately try again to subscribe
    	        $self->create_subscribe($kernel);
		$transaction = $self->{transaction};
		$ret = 'running';

	    } else {

	        # subscription failed, leave state 
                $log->write(WARN, "pa terminated subscription with reason ".
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
# handle a single tuple as parsed by pidf_parser, this is a callback
# keep the tuple to remember it later, and to react on changes

sub handle_tuple {
    my($entity, $status, $contact, $prio, $note, $timestamp, $self) = @_;
    my %tuples;
    my $options = $self->{options};

    if (defined $self->{tuples}) {
	%tuples = %{$self->{tuples}};
    } else {
	%tuples = ();
    }
	    
    my $t = Subscribe::Tuple->new($entity, $status, $contact, $prio, $note, $timestamp);

    # check if we have a contact field, if not, then we use the entity
    # field as identifier, and expect to have only one tuple

    my $id;
    if (defined $contact) { 
	$id = $contact; 
    } else {
        $id = $entity; 
    }

    if (exists $tuples{$id}) {
	if ($t->equals($tuples{$id})) {
	    # it's an update of the same
	} else {
	    # exec programs given on the command line
	    $self->run_exec($options->{exec_changed}, 
			    $entity, $status, $contact, 
			    $prio, $note, $timestamp);
	    

	    if ($t->{status} eq 'open' && (
 	        (exists $tuples{$id}->{status} 
		 && $tuples{$id}->{status} eq 'closed')
		      || !exists $tuples{$id}->{status})) {
		# change from closed (or unknown) to open
		$self->run_exec($options->{exec_open}, 
				$entity, $status, $contact, 
				$prio, $note, $timestamp);	
	    }

	    if ($t->{status} eq 'closed' 
 	        && exists($tuples{$id}->{status})
		&& $tuples{$id}->{status} eq 'open') {
		# change from open to closed
		$self->run_exec($options->{exec_closed}, 
				$entity, $status, $contact, 
				$prio, $note, $timestamp);
	    }
	}
    } # end if exists 
    else {
	# its the first time
	$self->run_exec($options->{exec_changed}, 
			$entity, $status, $contact, 
			$prio, $note, $timestamp);

	if ($t->{status} eq 'open') {
	    $self->run_exec($options->{exec_open}, 
			    $entity, $status, $contact, 
			    $prio, $note, $timestamp);
	}

	if ($t->{status} eq 'closed') {
	    $self->run_exec($options->{exec_closed}, 
			    $entity, $status, $contact, 
			    $prio, $note, $timestamp);
	}
    }
    $self->{new_tuples}{$id} = $t; # keep the new one
}


# 
# all tuples found in $self~>tuples but not in passed list are
# obsolete and to be removed

sub clean_tuples {
    my $self = shift;
    my $key;
    my %old;

    if (defined $self->{tuples}) {
	%old = %{$self->{tuples}};
    } else {
	%old = ();
    }

    my %new = %{$self->{new_tuples}};
    my $options = $self->{options};

    foreach $key (keys %old) {
	unless (exists $new{$key}) {
	    my $t = $old{$key}; # the tuple
	    # say goodby
	    $self->run_exec($options->{exec_closed}, 
			    $t->{entity}, 
			    'closed', 
			    $t->{contact}, 
			    $t->{prio}, 
			    $t->{note}, 
			    $t->{timestamp});

	    $self->run_exec($options->{exec_changed}, 
			    $t->{entity}, 
			    'closed', 
			    $t->{contact}, 
			    $t->{prio}, 
			    $t->{note}, 
			    $t->{timestamp}); 
	}

	delete $old{$key};
    }

    $self->{tuples} = $self->{new_tuples}; # new gets old
}


#
# parse the header of the received NOTIFY message and return one of
# the following, depending on the header 'Subscription-State'.
# 'ok'           - in case it is a plain presence notification with 
#                  a  pidf body
# 're-subscribe' - in case the server wants us to sbuscribe again
# <nnnn>         - in case it notifies about the pa wants us to retry 
#                  subscription after nnnn seconds
# <any other>    - all other return values are a subscription failure 
#                  reason
sub notify_check {
    my $self = shift;
    my ($headers) = $_[0];
    my ($h);

    foreach $h (split("\n", $headers)) {
  	if ($h =~ /Subscription-State:\s*terminated\s*;.*retry-after\s*=\s*(\d+)/i) {
            # subscription terminated, retry-after param found
 	    $log->write(DEBUG, "notify: subscription retry-after $1");
	    return $1;
	} 
	if ($h =~ /Subscription-State:\s*terminated\s*;.*reason\s*=\s*(\w+)/i) {
	    # terminated, and a reason was specified, so parse this
	    my $r = $1;
	    $log->write(DEBUG, "notify: subscription terminated, reason '$r'");

	    if ($r =~ /^deactivated/i || $r =~ /^timeout/i) {
	        # immediately try again
		return 're-subscribe'; 
	    } elsif ($r =~ /^probation/i || $r =~ /^giveup/i) {
		# we checked already for the retry-after param, and it was 
		# not there, so we retry after, say 60 sec
		return 60;
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

    # remove newlines of the args for passing on command line
    foreach (1..4,6) {
	if (defined $_[$_]) {
	    $_[$_] =~ s/$CRLF//gs;
	    $_[$_] =~ s/\n//gs;
	}
    }

    my ($cmd, $entity, $status, $contact, $prio, $note, $timestamp) = @_;

    if ($cmd eq '') {
	return;
    }

    my $args = " -e $entity";
    if (defined $status) {
	$args .= " -s $status";
    }
    if (defined $contact) {
	$args .= " -c $contact";
    }
    if (defined $prio) {
	$args .= " -p $prio";
    }
    if (defined $timestamp) {
	$args .= " -t $timestamp";
    }

    if ($cmd ne '') {
	$log->write(TRACE, 'notify: exec '.$cmd.$args);
	open(EXEC, '| '.$cmd.$args) or die("$SIP_USER_AGENT: Can't run ".
					   $cmd. ", $!");
	if (defined $note) {
	    print EXEC $note;
	}
	close EXEC;
    }
}


#
# subclass for hiding the presence tuple

package Subscribe::Tuple;

    my @args = ('entity', 'status', 'contact', 'prio', 'note', 'timestamp');

    # expects the arguments in this order:
    # $entity, $status, $contact, $prio, $note, $timestamp
    sub Subscribe::Tuple::new {
	my $class = shift;
	my $self  = {};
	bless($self);
	
	foreach (@args) {
	    $self->{$_} = shift; 
	}

	return $self;
    }

    # return true if this tuple is identical to the passed one
    sub equals {
	my $self = shift;
	my $other = shift;

	foreach (@args) {
	    if (defined $self->{$_} && defined $other->{$_}) {
	        return 0 if ($self->{$_} ne $other->{$_});
	    } elsif (defined $self->{$_} || defined $other->{$_}) {
		return 0;
	    }
	}
	return 1;
    }
# end package tuple

1;
