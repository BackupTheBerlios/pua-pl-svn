package Register;

# handling of the Register SIP messages and responses
# tries to conform to RFC 3261
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



###### methods

#
# Constructor

sub new {
    my $class        = shift;
    my $self         = {};

    $self->{log}     = shift;  # reference to the log object
    $self->{options} = shift;  # reference to the options object

    # sub state for state machines
    
    $self->{state} = 'reg_initializing'; 

    bless($self);
    return $self;
}



#
# construct a register message 

sub get_msg {
    my $self = shift;
    my $expiry = shift;
    my $options = $self->{options};
    my $headers = '';

    unless (exists $self->{transaction}) {
	$self->{transaction} 
	  = new Transaction('log'      => $self->{log},
			    'options'  => $options,
			    'to_dn'    => $options->{my_name},
			    'to'       => $options->{my_id},
			    'from_dn'  => $options->{my_name},
			    'from'     => $options->{my_id});
    } else {
	# use the same data, but increment CSeq
	$self->{transaction}->next_cseq();
    }

    # set the head of the message
    $self->{transaction}
      ->set_param('head',
		  'REGISTER '. $options->{registrar}.' SIP/2.0');


    $self->{transaction}
      ->set_param('headers', 
#		  'Request-URI: '.$options->{domain} . $CRLF . FIXME
 		  'Contact: <sip:'.$options->{login} . 
		  '@'.$options->{my_host}.'>' . $CRLF . 
		  'Expires: '.$expiry);

    return $self->{transaction}->get_message();
}


#
# control function. This function is a simple matrix in form of nested 
# switch/case (or if-elsif chains, as this is perl) of states and of events. 
# All state transitions are done here. This table shows the possible 
# transitions, legend:- means, the event is ignored, o means it is handled
# but does not cause a state transition, x means it terminates the state
# machine, and with it the program. FIXME
#
# state \    event|started| registered|  ended   |regfailed|
#-----------------+-------+-----------+----------+---------+
# reg_initializing|   o   |reg_running|     x    | reg_ign.|
# reg_running     |   -   |     -     |reg_ending|  ign./o |
# reg_ending      |   -   |     x     |     x    | reg_ign.|
# reg_ignoring    |   x   |     x     |     x    |    x    |
#
# returns 2 values: (1) a suggested main state, return value 'x' means, 
# we're done so far and the main state machine may exit, and (2) a transaction
# in case a message shall be send.

sub control {
    my $self = shift;
    my ($kernel, $event, $header, $content) = @_;
    my $ret = 'x';
    my $transaction; # second return value, can be undef
    my $options = $self->{options};
    my $state = $self->{state};

    unless ($options->{register}) { return 'x'; } # exit, no register required

    $self->{log}->write(DEBUG, "register: in state $state got event $event");

    if ($event eq 'started') {
	my $msg = $self->get_msg($options->{register_exp});
	$self->{log}->write(DEBUG, "register: send initial message "
			    .(split("\n", $msg))[0]);
	$transaction = $self->{transaction};
	$ret = 'running';
	
    } elsif ($event eq 'registered') {
	
	$self->handle_message(@_);

	if ($options->{register_once} || $state eq 'reg_ending') {
	    $ret = 'x'; # no update, no expiry, no unregister
	    $self->change_state('reg_ignoring');
	} else {
	    $self->change_state('reg_running');
	    $ret = 'running';
	}

    } elsif ($event eq 'regfailed') {
	my $t = $self->handle_auth($header, $content);
	if (defined $t) {
	    $ret = 'running';
	    $transaction = $t;
	} else {
	    $self->change_state('reg_ignoring');
	    $ret = 'x';
	}
    } elsif ($event eq 'regexpired') {
	
	# refresh registration
	$self->{transaction}->next_cseq();
	$ret = 'running';
	$transaction = $self->{transaction};
	    
    } elsif ($event eq 'ended') {

	if ($self->{state} eq 'reg_running') {
	    # user wants to abort program, remove registration
	    my $msg = $self->get_msg(0);
	    $self->{log}->write(DEBUG, "register: send remove message "
				.(split("\n", $msg))[0]);

	    $self->change_state('reg_ending');    
	    $transaction = $self->{transaction};
	    $ret = 'terminating'; # ... but wait for the result 
	}

    } else {
	# exit
	$ret = 'x'; 
    }

    return ($ret, $transaction);
}

#
# handle_message, called when the ok status reply to the
# register request is received.

sub handle_message {
    my ($self, $kernel, $event, $header, $content) = @_;
    my ($c, $exp, $h);
    my $options = $self->{options};
    my $transaction = $self->{transaction};

    $self->{log}->write(WARN, $SIP_USER_AGENT. ": successfully registered");

    $exp = -1;

    foreach $h (split("\n", $header)) {

        # extract Contact header,
        if ($h =~ /^Contact\s*:\s*.*?;\s*expires\s*=\s*(\d+)/i) {
	    $exp = $1;
	}

        # look for the expire header
        if ($h =~ /^Expires\s*:\s*(\d+)$/i) {
	    if ($exp == -1) { 
		# avoid overwriting expiry duration if set by Contact header
		$exp = $1;
	    }
        }
    }

    # start timer, to refresh registration just 3 secs before expiry
    unless ($options->{register_once}) {
	unless ($exp == -1 || $exp < 4) {
	    $kernel->delay('regexpired', $exp - 3);
	} else {
	    # default timeout
	    $kernel->delay('regexpired', $options->{register_exp});
	}
    }
}


# 
# called when a SIP message is received. The function checks if it is
# register relevant, and if yes, it returns the name of the internal
# message to be posted, like 'regfailed', or undef in case of not relevant

sub check_message {
    my $self = shift;
    my ($header, $content) = @_;
    my $ret;
    my $h0;

    # get the cseq line, for the method name    
    foreach $h0 (split("\n", $header)) {
        if ($h0 =~ /^CSeq\s*:\s*\d+\s+REGISTER/i) {        
            my $code = $self->get_message_code($header);
            if ($code >= 200 && $code <= 299) {
                $ret = 'registered';
            } else {
                $ret = 'regfailed';
            }
            last;
        }
    } 
    return $ret;
}


1;
