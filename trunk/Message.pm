package Message;

# handling of the MESSAGE SIP messages and responses
# tries to conform to RFC 33428
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



#
# Constructor

sub new {
    my $class        = shift;
    my $self         = {};

    $self->{log}     = shift;  # reference to the log object
    $self->{options} = shift;  # reference to the options object

    $self->{state} = 'mess_initializing'; 

    bless($self);
    return $self;
}



#
# construct the MESSAGE meessage, expects the expiry duration and the 
# content (body) document given as argument

sub get_msg {
    my $self = shift;
    my $doc = shift;
    my $expires = shift; # optional, can be empty

    my $headers = '';
    my $options = $self->{options};

    unless (exists $self->{transaction}) {
	$self->{transaction} 
	  = new Transaction('log'      => $self->{log},
			    'options'  => $options,
			    'to'       => $options->{msg_to},
			    'from_dn'  => $options->{my_name},
			    'from'     => $options->{my_id});
    } else {
	$self->{transaction}->next_cseq();
    }

    # set the head of the message
    $self->{transaction}
      ->set_param('head',
		  'MESSAGE '.$options->{msg_to}.' SIP/2.0');

    # set some extra header lines, MESSAGE specific
    if ($expires ne '') {
        # it may expire, add an extra header line for the date
        my $date = 'date'; # FIXME
        chomp $date;
        $headers .= 'Date: '. $date . $CRLF;
        $headers .= 'Expires: '.$expires.$CRLF;
    }

    $self->{transaction}->set_param('headers', $headers);

    if (length($doc) > 0) {
	$self->{transaction}->set_param('con_type', 'text/plain');
	$self->{transaction}->set_param('body', $doc);
    } else {
	# reset
	$self->{transaction}->set_param('con_type');
	$self->{transaction}->set_param('body');
    }

    return $self->{transaction}->get_message();
}


#
# control function. This function is a simple matrix in form of nested 
# switch/case (or if-elsif chains, as this is perl) of states and of events. 
# All state transitions are done here. This table shows the possible 
# transitions, legend:- means, the event is ignored, o means it is handled
# but does not cause a state transition, x means it terminates the state
# machine, and with it the program. For MESSAGE it is specific that we 
# can go into state mess_receiving without any message sent previously.
# This depends on if there is a outgoing MESSAGE given by the user or not. 
#
# state \     event|  started  |    msgsent   |   ended   |msgfailed |
#------------------+-----------+--------------+-----------+----------+
# mess_initializing|o/mess_rec.|mess_rec./ign.|     x     | mess_ign.|
# mess_receiving   |     -     |       -      |     x     | ign./ o  |
# mess_ignoring    |     x     |       x      |     x     |     x    |
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

    unless ($options->{msg_send} || $options->{msg_receive}) 
    { 
        return 'x'; # exit from me out
    }

    $self->{log}->write(DEBUG, "message: in state $state got event $event");

    if ($state eq 'mess_initializing') {
        if ($event eq 'started') {

	    my $msg = $self->get_msg($options->{msg_doc}, 
                                     $options->{msg_exp});

	    $self->{log}->write(DEBUG, "message: send initial message "
			.(split("\n", $msg))[0]);

	    $transaction = $self->{transaction};
	    $ret = 'running';

        } elsif ($event eq 'msgsent') {

	    $self->handle_message(@_);

	    if ($options->{msg_send_once}) {
		$ret = 'x'; # no update, no expiry, no unpublish
		$self->change_state('mess_ignoring');
	    } else {
		$self->change_state('mess_receiving');
		$ret = 'running';
	    }

	} elsif ($event eq 'msgfailed') {

	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		$self->change_state('mess_ignoring');
		$ret = 'x';
	    }
	} elsif ($event eq 'ended') {
            $ret = 'x';
	} else {
	    # any other event, not for me
	    $ret = 'running';
	}
    } elsif ($state eq 'mess_receiving') {
        if ($event eq 'msgsent') {
            if ($options->{msg_receive}) {
                $self->handle_message(@_);
                $ret = 'running'; 
            } else {
                # finished,as there is nothing more to wait for
		$ret = 'x'; 
		$self->change_state('mess_ignoring');
            }
        } elsif ($event eq 'ended') {

	    # user wants to abort program, remove published presence
	    $self->change_state('mess_ignoring'); # don't care about the result
	    $ret = 'x'; 

	} elsif ($event eq 'msgfailed') {
	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		# MESSAGE didn't work
		$self->{log}->write(WARN, "$SIP_USER_AGENT: MESSAGE failed, server sent error '"
				    .(split("\n", $header))[0] ."'\n");
		$self->change_state('mess_ignoring');
		$ret = 'x';
	    }

	}
    }
    return ($ret, $transaction);
}


#
# handle_message, called when the ok status reply to the
# MESSAGE request is received.

sub handle_message {
    my ($self, $kernel, $event, $header, $content) = @_;
    my ($h, $exp);
    my $options = $self->{options};

    $self->{log}->write(WARN, $SIP_USER_AGENT. ": MESSAGE successfully sent.");
}


# 
# called when a SIP message is received. The function checks if it is
# publish relevant, and if yes, it returns the name of the internal
# message to be posted, like 'pubfailed', or undef in case of not relevant

sub check_message {
    my $self = shift;
    my ($header, $content) = @_;
    my $ret;
    my $h0;

    # get the cseq line, for the method name    
    foreach $h0 (split("\n", $header)) {
        if ($h0 =~ /^CSeq\s*:\s*\d+\s+MESSAGE/i) {        
            my $code = $self->get_message_code($header);
            if ($code >= 200 && $code <= 299) {
                $ret = 'msgsent';
            } else {
                $ret = 'msgfailed';
            }
            last;
        }
    } 
    return $ret;
}


1;
