package Handler;

#
# abstract class for handling of the Publish/Subscribe/Register state 
# machines, has common functionality like authentification 
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $LastChangedDate$, Conny Holzhey



use warnings;
use strict;

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging
use Options;            # to handle default options and the command line
use Transaction;        # to handle message sequences
use Authen::DigestMD5;  # calculates responds

require Exporter; 

our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw($CRLF);

#
# header lines have to be terminated with CRLF

our $CRLF = "\015\012";


###### methods

#
# Constructor

sub new {
    my $class        = shift;
    my $self         = {};

    $self->{log}     = shift;  # reference to the log object
    $self->{options} = shift;  # reference to the options object

    bless($self);
    return $self;
}



#
# change the state and log it, common function

sub change_state {
    my $self = shift;
    my($newstate) = $_[0];

    my $os = $self->{state}; 
    $self->{state} = $newstate; 

    $self->{log}->write(DEBUG, ref($self).": change state from $os to $newstate");
}

#
# this function has to exists, main state handler

sub control {
    my $self = shift;
    my ($kernel, $event, $header, $content) = @_;
    die("$SIP_USER_AGENT: Internal problem, abstract control shouldn't be called");
}


#
# Calculate the Digest Authorization header and returns the header line.
# Expects the transaction of the message already set up.

sub authenticate {
    my $self = shift;
    my $options = $self->{options};
    my $transaction = $self->{transaction};
    my ($header, $content) = @_;
    my $auth_params = '';
    my %auth_param;
    my $log = $self->{log};

    foreach (split("\n", $header)) {
        chomp;
        if (/^(WWW|Proxy)-Authenticate\s*:\s*Digest\s+(.*)$/i) {
	    $auth_params = $2;
	    last;
	}
    }

    if ($auth_params eq '') {
        $log->write(DEBUG, 'auth: can\'t find WWW/Proxy-Authenticate header');
        return 0;
    }

    # get the name/value pairs, the first one goes for quoted strings
    # uses minimal matching

    $log->write(SPEW, "auth: params found:");
    while ($auth_params =~ s/(\w+?)\s*=\s*"(.*?)"\s*,?// 
	   || $auth_params =~ s/(\w+?)\s*=\s*?([^,]*)\s*,?//) {
        my $name = $1;
        my $value = $2;
	$name =~ s/[A-Z]/[a-z]/g; # lowercase prefered
        $log->write(SPEW, "  name: $name, value: $value");

	$auth_param{$name} = $value;
    }

    # can't do authentification w/o username and password
    unless ($options->{username} ) {
	die("$SIP_USER_AGENT: Server demands authentification. ".
	    "Please run again and specify a username (-u=name).\n");
    }

    unless ($options->{password}) {
	die("$SIP_USER_AGENT: Server demands authentification. ".
	    "Please run again and specify a password (-pw=xxx).\n");
    }

    # get the request uri out of the previously set up transaction
    my ($uri, $method);
    my $h = $transaction->get_param('head');
    unless ($h =~ /^(\S+) (\S+) SIP/) {
	die("$SIP_USER_AGENT: Internal error, invalid head of transaction.");
    }
    $method = $1;
    $uri = $2;

    my $res = new Authen::DigestMD5::Response;

    $res->set(%auth_param);
    $res->set(username      => $options->{username},
	      'digest-uri'  => $uri,
	      'method'      => $method,
	      'entity-body' => $content
	     );

    $res->add_digest(password => $options->{password});

    my %result;
    $result{'response'} = $res->{response};
    $result{'username'} = $options->{username};
    $result{'uri'}      = $uri;
    $result{'cnonce'}   = $res->{cnonce} if (exists $auth_param{'qop'});
    $result{'nc'}       = $res->{nc} if (exists $auth_param{'qop'});
    foreach (keys %auth_param) {
	$result{$_} = $auth_param{$_};
    }

    my(@order) = qw(username realm algorithm uri nonce cnonce response);
    push(@order, "opaque");

    my @pairs;
    for (@order) {
	next unless defined $result{$_};
	push(@pairs, "$_=" . qq("$result{$_}"));
    }

    # unquoted values
    @order = qw(qop nc);
    for (@order) {
	next unless defined $result{$_};
	push(@pairs, "$_=" . qq($result{$_}));
    }

    return "Digest " . join(", ", @pairs);
}


#
# handle_auth, to be called on a non-200 return message of the server.
# Parse a bit of the message to find out if the server requests 
# authentification, return the changed transaction in case of yes, 
# otherwise (no 401, so auth challenged...) return undef;

sub handle_auth {
    my $self = shift;
    my ($header, $content) = @_;
    
    # check if it is the server challengin authentification
    my @headers = split("\n", $header);
    if (($headers[0] =~ /^SIP\/2\.0\s+(\d+)\s+(.*)$/) 
	&& ($1 == 401 || $1 == 407)) {
	
	my $code = $1;

	# If there is already a Authorization header, then we
	# tried already, so give up, unless stale 

	my $stale = $self->is_stale(@headers);

	if ($stale || '' eq $self->{transaction}->get_header('Authorization')) {
		
	    # auth failed, try again with same transaction
	    my $auth = $self->authenticate($header, $content);
	    if ($auth) {

		$self->{log}->write(INFO, ref($self).": "
				    ."server challenged authentification with '"
				    .(split("\n", $header))[0] ."'\n");
	
		my $trans = $self->{transaction};
 		$trans->next_cseq();
		if ($code == 407) {
		    $trans->replace_header('Proxy-Authorization: ' . $auth);
		} else {
		    $trans->replace_header('Authorization: ' . $auth);
		}
		return $trans;
	    } else {
		# auth didn't work, or server sent other error
		$self->{log}->write(WARN, "$SIP_USER_AGENT: Authentification "
				    ."failed, server sent error '"
				    .(split("\n", $header))[0] ."'\n");
	    }
	}
    }
    return undef;
}

#
# look if the given message header has a stale flag set, 
# indicating that a previously successfull authorization 
# is not working anymore

sub is_stale {
    my ($self, @headers) = @_;
    my $line;

    foreach $line (@headers) {
	if ($line =~ /^WWW-Authenticate\s*:\s*Digest .*stale\s*=\s*true/i) {
	    return 1;
	}
	if ($line =~ /^Proxy-Authenticate\s*:\s*Digest .*stale\s*=\s*true/i) {
	    return 1;
	}
    }
    return 0;
}
1;
