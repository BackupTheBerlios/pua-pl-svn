package Options;

# this module contains standard settings, and the command line processing
#
# part of pua.pl
# a simple presence user agent, 
# see http://pua-pl.berlios.de for licence
#
# $Date: 2005-03-04 20:26:25 +0100 (Fri, 04 Mar 2005) $, Conny Holzhey



use warnings;
use strict;

use English;            # access to the perl variables with the readable names
use Getopt::Long;       # to parse the command line arguments
use File::Basename;     # to get the basename for the User-Agent
use Sys::Hostname;      # to get the host name of the machine running this 
use URI;                # helps parsing URI given on the command line

use lib qw(.);          # the libs below are local, so allow to load them
use Log::Easy qw(:all); # for logging, got it from cpan

require Exporter; # for exporting the SIP... variables

our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw($SIP_MY_ID 
	     $SIP_MY_NAME
	     $SIP_DOMAIN
	     $SIP_WATCH_ID
	     $SIP_MY_HOST
	     $SIP_BRANCH_PREFIX 
	     $SIP_USER_AGENT
	     $SIP_LOCAL_PORT
	     $SIP_REMOTE_PORT
	    );


my $VERSION = '1.'; # main version

# append subversions revision number
my $svn_version = '$LastChangedRevision$'; # will be replaced by svn
if ($svn_version =~ /LastChangedRevision: (\d+)/) {
    $VERSION .= $1;
}




## settings that have to be overwritten by command line options #############

#
# my sip id, should include the scheme, like 'sip:' or 'pres'
# sometimes called the presentity id

my $SIP_MY_ID = 'sip:conny@192.168.123.2';

#
# the display name which should be associated with the id $SIP_MY_ID
# Should be "Anonymous" in case the identity shall be hidden
my $SIP_MY_NAME = ''; # not shown on default

#
# the sip id for the registrar server name, this is the server that accepts 
# REGISTER requests and places the information it receives in those requests 
# into the location service for the domain it handles. This is the one who 
# remembers who is there under which name. The portnumber is not required 
# in case the server is at default port 5060

my $SIP_REGISTRAR = '';

#
# The request URI, as sent in the header field Request-URI in the REGISTER
# message. This names the domain of the location service for which the 
# registration is meant. The registrar server $SIP_REGISTRAR needs to feel 
# responsible for the domain you specify here. 

my $SIP_DOMAIN = '';

#
# in case you want to watch somebody else presence, the sip or pres id of that
# person must be specified here

my $SIP_WATCH_ID = 'sip:user@192.168.123.2'; #garbo.local'; 




### more setup ##############################################################

#
# the following params are probably ok, unless you want to test weird things

#
# The device ID from which you setup the registration/subscription.  Here we
# try to guess it. Just replace it with something fixed if you don't want to 
# reveal it. It is used for the Via header in the SIP messages, it is the 
# address of the machine where we expect the server to send the answers to 
# our requests.

our $SIP_MY_HOST = hostname;

#
# prefix of the branch parameter that is send with the Via header. To be RFC 
# 3261 compliant, it has to be "z9hG4bK", a truly magic cookie

our $SIP_BRANCH_PREFIX = 'z9hG4bK';

#
# how long (in seconds) the registration shall be valid, after that time it 
# will expire. Send with the Expires: header in the REGISTER message

our $SIP_REGISTER_EXPIRES = 3600; # 3600 on default

#
# how long (in seconds) the watcher subscription shall be valid, after that 
# time we will re-send it, or it will expire. Send with the Expires: header
# in the SUBSCRIBE message

our $SIP_SUBSCRIBE_EXPIRES = 3600; # 3600 on default

#
# how long (in seconds) the published presence shall be valid, after that 
# time we will re-send it, or it will expire.

our $SIP_PUBLISH_EXPIRES = 3600; # default ???

#
# Value of the User-Agent header

our $SIP_USER_AGENT = basename($PROGRAM_NAME). ' '.$VERSION;

#
# local port where to listen for incoming notifications, on default it is 5060

our $SIP_LOCAL_PORT = 5060;

#
# remote port where to sent messages to, on default it is 5060

our $SIP_REMOTE_PORT = 5060;



##### methods ###############################################################


# constructor
#

sub new {
    my $class = shift;
    $log      = shift;
    my $self  = {};

    bless($self);

    # a number of parameter matching the ones $SIP... defined above, just 
    # lowercase, and potentially overwritten by command line options

    $self->{my_id}         = $SIP_MY_ID;
    $self->{my_name}       = $SIP_MY_NAME;
    $self->{local_port}    = $SIP_LOCAL_PORT;

    $self->{watch_id}      = $SIP_WATCH_ID;
    $self->{subscribe_exp} = $SIP_SUBSCRIBE_EXPIRES;
    $self->{publish_exp}   = $SIP_PUBLISH_EXPIRES;
    $self->{register_exp}  = $SIP_REGISTER_EXPIRES;
    $self->{my_host}       = $SIP_MY_HOST;
    $self->{registrar}     = $SIP_REGISTRAR;
    $self->{domain}        = $SIP_DOMAIN;
    $self->{remote_port}   = $SIP_REMOTE_PORT;
    $self->{proxy}         = '';

    $self->{basic_status} = 'open'; # which own status is to be published
    $self->{note}         = '';     # sent with PUBLISH
    $self->{contact}      = '';     # as sent with PUBLISH

    $self->{exec_notify}  = ''; # what program to run when a notify is received
    $self->{exec_open}    = ''; # what program to run when a status open is received
    $self->{exec_closed}  = ''; # what program to run when status closed
    $self->{exec_changed} = ''; # what program to run when status changed

    $self->{register}  = 0;  # set by the comand line options in case we should register
    $self->{publish}   = 0;  # set in case we should publish our presence
    $self->{subscribe} = 0;  # set when subscription should be made

    $self->{register_once}  = 0; # terminate after first REGISTER
    $self->{publish_once}   = 0; # terminate after first PUBLISH
    $self->{subscribe_once} = 0; # terminate after first SUBSCRIBE (?)
    $self->{notify_once}    = 0; # terminate after first NOTIFY

    $self->{username}  = ''; # for digest authentification 
    $self->{password}  = ''; # for digest authentification 

    $self->{login}     = ''; # local login name

    $self->{testing}   = 0;  # test mode

    $self->{version}   = 0;  # to get the option -v
    $self->{options}   = 0;  # to get the option --options
    $self->{help}      = 0;  # to get the option -h
    $self->{debug}     = 1;  # to control the amount of log messages 

    my $result = GetOptions('register|r'         => \$self->{register},
			    'subscribe|s'        => \$self->{subscribe},
			    'publish|p'          => \$self->{publish},
			    'my-sip-id|my-id|i=s'=> \$self->{my_id},
			    'my-name=s'          => \$self->{my_name},
			    'local-port|lp=i'    => \$self->{local_port},
			    'remote-port|rp=i'   => \$self->{remote_port},
			    'proxy|x=s'          => \$self->{proxy},
			    'debug|d=i'          => \$self->{debug},
			    'version'            => \$self->{version},
			    'help'               => \$self->{help},
			    'options'            => \$self->{options},
			    'status=s'           => \$self->{basic_status},
			    'contact|c=s'        => \$self->{contact},
			    'note=s'             => \$self->{note},
			    'watch-id|w=s'       => \$self->{watch_id},
			    'subscribe-exp|se=i' => \$self->{subscribe_exp},
			    'publish-exp|pe=i'   => \$self->{publish_exp},
			    'register-exp|re=i'  => \$self->{register_exp},
			    'publish-once|po'    => \$self->{publish_once},
			    'register-once|ro'   => \$self->{register_once},
                            'notify-once|no'     => \$self->{notify_once},
			    'my-host=s'          => \$self->{my_host},
			    'registrar|rs=s'     => \$self->{registrar},
			    'domain|do=s'        => \$self->{domain},
			    'exec-notify|en=s'   => \$self->{exec_notify},
			    'exec-open|eo=s'     => \$self->{exec_open},
			    'exec-closed|ec=s'   => \$self->{exec_closed},
			    'exec|e=s'           => \$self->{exec_changed},
			    'username|u=s'       => \$self->{username},
			    'password|pw=s'      => \$self->{password},
			    'login=s'            => \$self->{login},
			    'testing'            => \$self->{testing}
			   );

    # many sanity checks

    unless ($result)  { $self->usage_short(''); }
    if ($self->{version}) { $self->usage_short("Version $VERSION"); }
    if ($self->{help})    { $self->usage_long(); }
    if ($self->{options}) { $self->usage_options(); }

    unless ($self->{subscribe} || $self->{publish} || $self->{register}) {
        $self->usage_short('At least one of the options register, subscribe, '.
		     'publish is required.');
    }

    if ($self->{my_id} =~ /^sips:/) {
	unless ($self->{testing}) {
	    $self->usage_short("Secure transport (as needed for ids with sips scheme, ".
			       "like \n  $self->{my_id}) is not supported.");
	}
    }

    unless ($self->{remote_port} =~ /(\d+)/) {
        $self->usage_short("Remote port number not understood.");
    } else {
        # otherwise perl thinks it is tainted
        $self->{remote_port} = $1;
    }

    unless ($self->{local_port} =~ /(\d)+/) {
        $self->usage_short("Local port number not understood.");
    }

    unless ($self->{basic_status} eq 'open' || $self->{basic_status} eq 'open') {
        $log->write(WARN, "Warning: basic status field value '$self->{basic_status}' ".
		    "is not covered by RFC 3863, 'open' or 'closed' is expected.");
    }

    if ($self->{debug} == 0) {      $log->log_level(EMERG); # not used, so it is quiet
    } elsif ($self->{debug} == 1) { $log->log_level(WARN);
    } elsif ($self->{debug} == 2) { $log->log_level(INFO);
    } elsif ($self->{debug} == 3) { $log->log_level(DEBUG);
    } elsif ($self->{debug} == 4) { $log->log_level(TRACE);
    } elsif ($self->{debug} == 5) { $log->log_level(SPEW);
    } else {
        $self->usage_short("Values for debug option expected in 0..5");
    }

    # check if the uri is complete
    my $uri = new URI($self->{my_id});
    unless ($uri->scheme) {
        $self->usage_short("Expecting scheme for uri specified with switch my-sip-id, ".
			  "like 'sip:'");
    }

    # set the domain to something derived from the uri, in case of register
    if ($self->{domain} eq '' and $self->{register}) {
	if ($uri->scheme =~ /^sip/) {
	    $self->{domain} = 'sip:' . $uri->host;
	} else {
	    $self->usage_short("Unable to guess domain of $self->{my_id}, unknown scheme.\n"
			      ."  please explicitly specify the domain with --domain");
	}
    }

    # set the registrar to something derived from the uri, in case of register
    if ($self->{registrar} eq '' and $self->{register}) {
	if ($uri->scheme =~ /^sip/) {
	    $self->{registrar} = 'sip:' . $uri->host;
	} else {
	    $self->usage_short("Unable to guess registrar for $self->{my_id}, unknown scheme.\n"
			      ."  please explicitly specify the registrar server with --registrar");
	}
    }

    # check if a proxy given
    if ($self->{proxy} eq '') {
	$self->usage_short("Proxy server missing, this is the address of the sip server. \n".
			   "  Run again with switch -x host.someserv.org (or whatever server name)");
    }

    if ($self->{login} eq '') {
	$self->{login} = getlogin || getpwuid($<);
    }

    return $self;
}



#
# print hint and exit

sub usage_short {
    my $self = shift;
    my $hint = shift;

    print 'usage: ', basename($PROGRAM_NAME), " [options] \n";
    if (length($hint)) { print "\n  $hint\n"; }

    print "\nSee ", basename($PROGRAM_NAME), " --help for options\n";
    exit(0);
}

#
# print usage and exit

sub usage_long {
    my $self = shift;

  print <<'EOU';
A simple command-line presence user agent. Partly conforms to RFC 3261 (SIP), 
3903 (PUBLISH), 3265 & 3856 (NOTIFY, SUBSCRIBE), 3863 (pidf).

Able to subscribe to other's presence, receive notifications and print
them, publish your own presence and register.

Common options:

  -r, --register: Send a REGISTER message to the registrar 
    server (specified with --registrar), so the system knows
    which ID and which machine you are using. This causes the
    server to remember a binding between your SIP identity uri 
    (see --my-sip-id) and the local machine. On termination of
    this programm, it removes the binding.

  -p, --publish: Send a PUBLISH message to the server, in order
    to make your own presence status known to other users.

  -s, --subscribe: Send a SUBSCRIBE message, to watch the 
    presence of somebody else (specified with --watch-id), and 
    to get notified when it changes.

  -v, --version: print version number and exit.

  -h, --help: What you see.

  --my-sip-id=uri: sets your SIP identity, usualy a URI of the form
    'sip:myname@domain.org'. 

  --my-name=name: Sets your real name to what will be shown to  
    other users. Optional parameter.

  -u, --username=name: Username for authentification at the remote
    server

  -pw, --password=name: Password for authentification at the remote
    server, in combination with -u

  -x, --proxy=server: for the server name of the SIP proxy server,
    e.g. -x=iptel.org

  --options: List more exotic options


Publish options, use in combination with -p:

  -c, --contact=uri: The contact address to be published. Can be any 
    address, like email or telephone number. The addres should 
    include the scheme, e.g. --contact tel:+09012345678, or 
    --contact mailto:someone@example.com are valid.

  --status=stat: It is the basic status of your contact id (resp.
    sip id, in case --contact is not used), as it is transmitted 
    to the server, and published to other users. Expected values 
    for stat are: 'open' means you are open for communication 
    (this is the default), 'closed' means you don't want to be 
    contacted , or you are offline on this address. Other values
    are possibly not supported by the server.

  --note=text: It specifies some arbitrary text that will be 
    transmitted to the server, and published to other users. 
    E.g. "I'm in Tokio next week."


Subscribe options, use in combination with -s:

  -w, --watch-id=uri: It sets the uri of the person whose presence
    status is to be subscribed, i.e. the uri of the person you 
    would like to know when she is online, and how to contact.
    The uri is usually something like 'sip:moby@sea.com'.


Register options, in combination with -r:

  -rs, --registrar=uri: Name of the registrar server, an uri like
    'sip:someprovider.net:5060'. If no registrar is specified, 
    the register request will be sent to a server name constructed 
    from your address (as specified with --my-sip-id). E.g. for a 
    given address --my-sip-id=sip:myname@domain.org, the registrar 
    will be guessed as 'sip:domain.org'.

  

EOU

    # ' for emacs
    exit(0);
}

#
# print options and exit

sub usage_options {
    my $self = shift;

  print <<'EOU';

Continuation of options for pua.pl

  -se, --subscribe-exp=duration: To be used in combination with -s
    (subscribe). Specifies the duration in seconds after 
    subscription should be refreshed, the shorter it is, the more 
    traffic is generated. Default value is 3600.

  -pe, --publish-exp=duration: To be used in combination with -p
    (publish). Specifies the duration in seconds how long a 
    published presence is valid. It controls how often the presence 
    status will be refshed. The shorter it is, the more traffic is 
    generated. Default value is 3600.

  -re, --register-exp=duration: To be used in combination with -r
    (register). Specifies the duration in seconds how long a 
    registration presence is valid, also it controls how often it 
    will be refshed. The shorter it is, the more traffic is 
    generated. Default value is 3600.

  --my-host=name: Hostname of this machine, as used in e.g. Via: 
    headers, usually this is automatically detected. 

  -lp, --local-port=number: Port number where to wait for SIP 
    messages on this local machine, default is 5060

  -rp, --remote-port=number: Port number of the SIP proxy, i.e. where 
    to send SIP messages on the remote machine. Default is 5060

  -en, --exec-notify=cmd: Run cmd each time a notification of
    somebody's else presence status is received. Works only in 
    combination with -s (subscribe). The command gets a descriptive
    description of the status on stdin. Example: -en 'cat > /tmp/pres'
    will re-write the file /tmp/pres each time the server sends a
    notification about the watched presentity. The file /tmp/pres
    then contains a text like 'xyz open for communication'. See the
    other --exec optiions for less descriptive methods. Please note:
    depending on the server settings and on -re, cmd might be 
    executed quite often.

  -eo, --exec-open=cmd: Run cmd each time a basic presence status 
    changes to open. The command cmd is invoked with a number of 
    switches on its own: -e entity name (usually a address in form
    sip:me@somwhere.net), -s status, here 'open', -c contact address, 
    -p priority, -t timestamp. A switch may be omitted, in case the 
    information is not available. Additionally, cmd may get on its 
    stdin an multi-line note. Cmd is invoked for each tuple, i.e. 
    it might be called more than once for one entity.

  -ec, --exec-closed=cmd: As -eo, but here the status has to change
    from open to closed (or from open to not available).

  -ro, --register-once: Register only once and then exit (assuming
    no -s/-p given). This is expected in combination with -r. If
    not set, the program will continue to run, and refresh the
    registration each time before it expires - this is the default.

  -po, --publish-once: Publish the presence only once and then 
    exit (assuming no -r/-s given), i.e. not refresh after expiry. 

  -no, --notify-once: Leave the program after the first notification
    is received (assuming no -p/-r given). This is expected in 
    combination with -s. If not set, the program will continue to run, 
    and refresh the subscription each time before it expires.
    
  --login=name: local login name, as used in the Contact: header 
    field. On default the software will try to guess.

  -d, --debug=n: Set the debug level, values of n: 0 (quiet) up to
    5 (very noisy)

Note: sips protocol scheme is not supported.

Still missing an option? Let me know: yivi@holzhey.de.


EOU

    # ' for emacs
    exit(0);
}

1;
