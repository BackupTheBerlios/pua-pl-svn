package Transaction;

# handles a sequence of SIP message and its responds, for both dialogs
# and non-dialog transactions. It keeps the initial values for resending
# the message, eg. like a SIP PUBLISH refresh, you only have to update the 
# etag for the refresh message, using the same transaction object. Also
# its task is calculations common for all SIP messages, like authentication
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $LastChangedDate$, Conny Holzhey



use warnings;
use strict;

use English;            # access to the perl variables with readable names

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging
use Options;            # to handle default options and the command line



#
# header lines have to be terminated with CRLF

use constant CRLF => "\015\012";

#
# constructor, expects name/value arguments, with the following
# names/values supported. Mandatory fields have to be set either in
# the constructor or later, e.g. get_message, set_param
#
#   log      - the log object (mandatory)
#   options  - reference to a Options.pm object (mand.)
#   from     - the sip address to be used in the From: header (m.)
#   from_dn  - the display name to be used in the From: header
#   from_tag - the tag to be used in From: header
#   to       - the sip address to be used in the To: header (m)
#   to_dn    - the display name to be used in the To: header
#   to_tag   - the tag to be used in To: header
#   head     - the head of the message, like PUBLISH sip:bla SIP/2.0 (m)
#   call_id  - the call-id header value
#   headers  - additional lines to be sent as headers
#   con_type - the Content Type header
#   body     - some optional payload to be sent with the message
#
sub new {
    my $class        = shift;
    my %params = @_;

    my $self         = {};
    bless($self);

    # move one by one the params to the object
    foreach (keys %params) {
        $self->{$_} = $params{$_};
    }

    return $self;
}

#
# return the SIP message taking the given options into account.
# By passing name/value pairs (same as the constructor accepts), 
# the data can be overwritten

sub get_message {
    my $self = shift;
    my %params = @_;
    my $message = '';
    my $options = $self->{options};

    # overwrite existing params
    foreach (keys %params) {
	if ($params{$_} == undef) {
	    delete $self->{$_}; # or remove in case of undef value
	} else {
	    $self->{$_} = $params{$_};
	}
    }

    # the head of the message
    if (exists $self->{head}) {
        $message = $self->{head};
	my $CRLF = CRLF;
	unless ($message =~ /$CRLF$/) {
	    $message .= CRLF;
	}
    } else {
	die("$SIP_USER_AGENT: Internal problem with head of message");
    }

    # the Via: headers
    $message .= 'Via: SIP/2.0/UDP '.$options->{my_host}.':'.$options->{local_port}.
      ';branch=' . $self->get_branch_param() . CRLF;

    # the To: header
    $message .= 'To: ';
    if (exists $self->{to_dn} and $self->{to_dn} ne '') {
        $message .= '"' . $self->{to_dn} . '" ';
    }
    
    unless (exists $self->{to}) {
	die("$SIP_USER_AGENT: Internal problem with To: header");
    }
    $message .= '<' . $self->{to} . '>';
    # check if we are in a dialog
    if (exists $self->{to_tag}) {
        # indeed 
        $message .= ';tag=' . $self->{to_tag};
    }
    $message .= CRLF;

    # the From header
    $message .= 'From: ';
    if (exists $self->{from_dn} && $self->{from_dn} ne '') {
        $message .= '"' . $self->{from_dn} . '" ';
    }

    unless (exists $self->{from}) {
	die("$SIP_USER_AGENT: Internal problem with From: header");
    }
    $message .= '<' . $self->{from} . '>';
    $message .= $self->get_from_tag();
    $message .= CRLF;

    # the Call-ID header
    $message .= 'Call-ID: ' . $self->get_call_id() . CRLF;

    # the CSeq header
    $message .= 'CSeq: ' . $self->get_cseq_number();
    $self->{head} =~ /^(\S*)/;
    $message .= ' ' . $1 . CRLF; # the method name

    # the Max-Forwards
    $message .= 'Max-Forwards: 70'.CRLF;

    # what we can accept
    # $message .= 'Allow: NOTIFY' . CRLF;

    # the that's me
    $message .= 'User-Agent: ' . $SIP_USER_AGENT . CRLF;


    # now the headers which are specific for the applications
    if (exists $self->{headers}) {
        $message .= $self->{headers};
	my $CRLF = CRLF;
	unless ($message =~ /$CRLF$/) {
	    $message .= CRLF;
	}
    }

    # the content type, if any
    if (exists $self->{body} and length($self->{body})) {
	unless (exists $self->{con_type}) {
	    die("$SIP_USER_AGENT: Internal problem with Content-Type: header");
	}
	$message .= 'Content-Type: ' . $self->{con_type} . CRLF;
    }

    # the content length
    my $l;
    unless (exists $self->{body}) { 
	$l = 0; 
    } else {
	$l = length($self->{body});
    }

    $message .= 'Content-Length: ' . $l . CRLF;

    # end of header
    $message .= CRLF;

    # finally the body
    if (exists $self->{body}) {
        $message .= $self->{body};
    }

    return $message;
}

#
# set a specific transaction parameter, or remove it, in case its value 
# is not specified

sub set_param {
    my $self = shift;
    my ($name, $value) = @_;

    if (defined $value) {
	$self->{$name} = $value;
    } else {
	delete $self->{$name};
    }
}


# returns a single header line, undef in case it doesn't exists

sub get_header {
    my $self = shift;
    my $name = shift;

    my @lines = split (CRLF, $self->get_message());
    my $l = '';
    foreach (@lines) {
        if (/^$name: /) { 
	    $l = $_; 
	    last; 
	}
    }

    return $l;
}

#
# return param previously set

sub get_param {
    my $self = shift;
    my $name = shift;
    
    return $self->{$name};
}


#
# replace a line of the headers parameter that starts with the same
# identifier than the passed one, append it if it is new

sub replace_header {
    my $self = shift;
    my $line = shift;
    my $CRLF = CRLF;

    if (exists $self->{headers} 
	&& length($self->{headers}) && $line =~ /^(\S+)/) {
	my $id = $1;
	
	my @lines = split ($CRLF, $self->{headers});
	my ($i);
	for ($i = 0; $i <= $#lines; $i++) {
	    if ($lines[$i] =~ /^$id\s+/) { 
		$lines[$i]  = $line;
		last;
	    }
	}

	if ($i > $#lines) {
	    push @lines, $line;
	}

	$self->{headers} = join(CRLF, @lines);
    } else {
	# append

	unless ($self->{headers} =~ /$CRLF$/s) {
	    $self->{headers} .= CRLF;
	} 
	
	$self->{headers} .= $line;
     }
}

#
# Return a unique string that can be used as branch parameter for the Via 
# header. The unique string starts with the $SIP_BRANCH_PREFIX. The
# function generates it the first time it is called, then it will return 
# always the same string.

sub get_branch_param {
    my $self = shift;
    my $options = $self->{options};

    unless (exists $self->{branch_param}) {
        $self->{branch_param} = $SIP_BRANCH_PREFIX . $PID . time() . 
	  '@' . $options->{my_host};
    }
    return $self->{branch_param};
}

#
# Initial generation of the tag, appeded at the From: header. The tag is
# returned by the server, this way we can identify which message belong 
# to a dialog

sub get_from_tag {
    my $self = shift;

    unless (exists $self->{from_tag}) {
        $self->{from_tag} = time();
    } 
    return ';tag=' . $self->{from_tag};
}

#
# create the call ID, a globally unique identifier for this call. It is 
# generated by the combination of a random string and the host name.
# used in the header 'Call-ID'

sub get_call_id {
    my $self = shift;
    my $options = $self->{options};
    unless (exists $self->{call_id}) {
	return rand() . '@' . $options->{my_host};
    } else {
	return $self->{call_id};
    }
}

#
# return and keep the command sequence number. Incremented by
# each call to this function. To be used with the CSeq: header

sub get_cseq_number {
    my $self = shift;
    unless (exists $self->{cseq}) {
	$self->{cseq} = 1;
    }
    return $self->{cseq};
}

#
# increment cseq number

sub next_cseq {
    my $self = shift;
    if (exists $self->{cseq}) {
	$self->{cseq}++;
    } else {
	$self->{cseq} = 1;
    }
}


1;
