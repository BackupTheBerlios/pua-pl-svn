package Publish;

# handling of the PUBLISH SIP messages and responses
# tries to conform to RFC 3903
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

    # keep the e-tag for the publish refresh
    $self->{etag} = '';

    # sub state for publish state machines
    
    $self->{state} = 'publ_initializing'; 

    bless($self);
    return $self;
}



#
# construct a publish message, expects the expiry duration and the 
# content (body) pidf document given as argument

sub get_msg {
    my $self = shift;
    my $expires = shift;
    my $pidf = shift;
    my $headers = '';
    my $options = $self->{options};

    unless (exists $self->{transaction}) {
	$self->{transaction} 
	  = new Transaction('log'      => $self->{log},
			    'options'  => $options,
			    'to_dn'    => $options->{my_name},
			    'to'       => $options->{my_id},
			    'from_dn'  => $options->{my_name},
			    'from'     => $options->{my_id});
    } else {
	$self->{transaction}->next_cseq();
    }

    # set the head of the message
    $self->{transaction}
      ->set_param('head',
		  'PUBLISH '.$options->{my_id}.' SIP/2.0');

    # set some extra header lines, publish specific
    if ($self->{etag} ne '') {
        # its a refresh, add an extra header line for the etag
        $headers .= 'SIP-If-Match: '. $self->{etag} . $CRLF;
    }

    $headers .= 'Event: presence'.$CRLF;
    $headers .= 'Expires: '.$expires.$CRLF;
    $self->{transaction}->set_param('headers', $headers);

    if (length($pidf) > 0) {
	$self->{transaction}->set_param('con_type',
					'application/pidf+xml');
	$self->{transaction}->set_param('body', $pidf);
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
# machine, and with it the program.
#
# state \     event|started| published  |   ended   |pubfailed|pubexpired
#------------------+-------+------------+-----------+---------+----------
# publ_initializing|   o   |publ_running|     x     |publ_ign.|    -
# publ_running     |   -   |     -      |publ_ending| ign./o  |    o
# publ_ending      |   -   |     x      |     x     |publ_ign.|    -
# publ_ignoring    |   x   |     x      |     x     |    x    |    x
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

    unless ($options->{publish}) { return 'x'; } # exit from me out

    $self->{log}->write(DEBUG, "publish: in state $state got event $event");

    if ($state eq 'publ_initializing') {
        if ($event eq 'started') {

	    my $msg = $self->get_msg($options->{publish_exp}, 
				     $self->get_pidf_doc());
	    $self->{log}->write(DEBUG, "publish: send initial message "
			.(split("\n", $msg))[0]);
	    $transaction = $self->{transaction};
	    $ret = 'running';

        } elsif ($event eq 'published') {

	    $self->handle_message(@_);

	    if ($options->{publish_once}) {
		$ret = 'x'; # no update, no expiry, no unpublish
		$self->change_state('publ_ignoring');
	    } else {
		$self->change_state('publ_running');
		$ret = 'running';
	    }

	} elsif ($event eq 'pubfailed') {

	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		$self->change_state('pub_ignoring');
		$ret = 'x';
	    }
	} else {
	    # exit
	    $ret = 'x'; 
	}
    } elsif ($state eq 'publ_running') {
        if ($event eq 'published') {
  	    $self->handle_message(@_);
	    $ret = 'running'; 

	} elsif ($event eq 'pubexpired') {

	    # send same again, but without body, to indicate a refresh
 	    my $msg = $self->get_msg($options->{publish_exp}, '');
	    $self->{log}->write(DEBUG, "publish: send refresh message "
			.(split("\n", $msg))[0]);

	    $transaction = $self->{transaction};
	    $ret = 'running'; 

        } elsif ($event eq 'ended') {

	    # user wants to abort program, remove published presence
	    my $msg = $self->get_msg(0, '');
	    $self->{log}->write(DEBUG, "publish: send remove message "
				.(split("\n", $msg))[0]);
	    $self->change_state('publ_ignoring'); # don't care about the result

	    $transaction = $self->{transaction};
	    $ret = 'terminating'; # ... but wait for the result 

	} elsif ($event eq 'pubfailed') {
	    my $t = $self->handle_auth($header, $content);
	    if (defined $t) {
		# try again including Authorization
		$ret = 'running';
		$transaction = $t;	
	    } else {
		# publish didn't work
		$self->{log}->write(WARN, "$SIP_USER_AGENT: Publish failed, server sent error '"
				    .(split("\n", $header))[0] ."'\n");
		$self->change_state('publ_ignoring');
		$ret = 'x';
	    }

	}
    }
    return ($ret, $transaction);
}



#
# handle_published, called when the ok status reply to the
# publish request is received.

sub handle_message {
    my ($self, $kernel, $event, $header, $content) = @_;
    my ($h, $exp);
    my $options = $self->{options};

    $self->{log}->write(WARN, $SIP_USER_AGENT. ": successfully published.");

    $exp = -1;
    $self->{etag} = ''; # reset, the old one shouldn't be reused

    foreach $h (split("\n", $header)) {

        # extract tag for the SIP-If-Match header
        if ($h =~ /^SIP-ETag\s*:\s*(.*)$/i) {
  	    $self->{etag} = $1;
	}

        # look for the expire header
        if ($h =~ /^Expires\s*:\s*(\d+)$/i) {
	    $exp = $1;
        }
    }

    if ($self->{etag} eq '') {
        $self->{log}->write(WARN, "$SIP_USER_AGENT: Couldn't find SIP-ETag ".
		    "header of message ", 
		    (split("\n", $header))[0]);
    }

    # Refresh published status after expiry-3 seconds, assuming it takes
    # up to 3 seconds until the re-publish reaches the server, so we start 
    # a timer. 

    if ($exp == -1) { 
        $self->{log}->write(INFO, "publish: No Expires: header found in publish response");
        $exp = $options->{publish_exp}; 
    } elsif ($exp != $options->{publish_exp}) {
        $self->{log}->write(INFO, 'publish: PA changed publish exipiry duration to '
		    . $exp);
    }
    
    if (!$options->{publish_once} && $exp > 5) {
	$kernel->delay('pubexpired', $exp - 3);
    }

    
}


# 
# construct a pidf document with my presence attributes, bit simple

sub get_pidf_doc {
    my $self = shift;
    my $options = $self->{options};

    my $pidf = '<?xml version="1.0"?>
<presence entity="'.$options->{my_id}.'">
<tuple id="12345">
  <status>
    <basic>'.$options->{basic_status}.'</basic>';
    if ($options->{'contact'} ne '') {
	$pidf .= "\n".'    <contact';
        if ($options->{priority} ne '') {
            $pidf .= ' priority="'.$options->{priority}.'"';
        }
        $pidf .= '>'.$options->{'contact'}.'</contact>';
    }
    if ($options->{'note'} ne '') {
	$pidf .= "\n".'    <note>'.$options->{'note'}.'</note>';
    }
    $pidf .= '
  </status>
</tuple>
</presence>
';
    return $pidf;
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
        if ($h0 =~ /^CSeq\s*:\s*\d+\s+PUBLISH/i) {        
            my $code = $self->get_message_code($header);
            if ($code >= 200 && $code <= 299) {
                $ret = 'published';
            } else {
                $ret = 'pubfailed';
            }
            last;
        }
    } 
    return $ret;
}


1;
