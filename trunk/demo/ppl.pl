#!/usr/bin/perl -w

#
# ppl.pl - Demonstrator and WEB UI for pua.pl a online presence 
# user agent. This provides a simple user interface of pua.pl, with
# the special crux that it is web based

use CGI qw/:standard/;
use strict;

my $query = new CGI;
my $PATH_TO_PROG ='/home/conny/projects/sippoc/trunk/';


print header;
print $query->start_html(-title => 'pua.pl Web UI',
                         -style=>{'src'=>'/pua-pl/doc/wp.css'});

print '<div id="center"><h2>pua.pl Web UI</h2>';

my $proxy = $query->param('proxy');
unless ($proxy) {
    print_form($query);
} else {
    my $err = check_param();
    if ($err ne '') {
        print "<blink><b>Error: $err</b></blink><p>\n";
	print_form($query);
    } else {
	# FIXME fixme! all is tainted
        my $cmd = $PATH_TO_PROG.'pua.pl -r -ro -re 60 -d 5'.
          ' --proxy='    .$query->param('proxy').
	  ' --my-sip-id='.$query->param('sip_id'). 
	    ($query->param('username') ? ' --username=' .$query->param('username') : '').
	    ($query->param('password') ? ' --password=' .$query->param('password') : '');

	print $cmd, "<p>\n";

	my $out = `perl -I ${PATH_TO_PROG}lib -I${PATH_TO_PROG}. -- $cmd`;
	print "<pre>$out</pre>\n";
    }
}
print $query->end_html();


# 
# check if all neccessary fields are filled in, and there must not be 
# any characters that would be allowed to misuse perl
 
sub check_param {

    my $p = $query->param('proxy');
    if ($p eq '') { 
	return "SIP Proxy server name not defined.";
    }
    unless ($p =~ /^([a-z.0-9])+$/i) {
	return 'Invalid character in proxy server name.';
    }

    my $s = $query->param('sip_id');
    if (!defined $s || $s eq '') { 
	return "SIP id not specified.";
    }
    unless ($s =~ /^([a-z.0-9:@])+$/i) {
	return 'Invalid character in sip-id.';
    }

    my $u = $query->param('username');
    if (defined $u and $u ne '') {
	unless ($u =~ /^([a-z.0-9:@])+$/i) {
	    return 'Invalid character in user name.';
	}
    }

    my $w = $query->param('password');
    if (defined $w and $w ne '') {
        unless ($w =~ /^([a-z.0-9:])+$/i) {
	    return 'Invalid character in password. Due to security of the web server the '.
	      'character set is limited to [a-z.0-9:], even when other chars would be possible.';
	}
    }
    return '';
} 


#
# the main input form 

sub print_form {
    my $query = shift;
    print "\nThis is a demo page for pua.pl. pua.pl itself is a simple SIP-based\n";
    print "presence user agent, and here you have a user interface to run it.\n";
    print "pua.pl is a actually a command-line and it uses SIP/SIMPLE to communicate ";
    print "to a server, and it supports partly the following standards: rfc-3261 (SIP), ";
    print "rfc-3903 (PUBLISH), rfc-3265 & rfc-3856 (NOTIFY, SUBSCRIBE), rfc-3863 (pidf).<p>\n";

    print "Running pua.pl throu this script limites the useage of pua.pl to a subset of ";
    print "options - see <a href=\"index.html\">here</a> for the complete list of options.";
    print "With this frontend, it is possible to do 3 things: register at a sip server, ";
    print "publish presence information and check some other user's presence information. ";;
    print "To do so, quite a number of parameter need to be known:\n";

    print $query->start_form(); 
    print "<table><tr><td>Proxy server name ";
    print $query->textfield(-name     => "proxy",
                            -default  => 'proxy.myprovider.org',
                            -override => 1
                            );
    print "</td><td>\n";
    print "Fill in the name of the SIP proxy server. A proxy server is like the single ";
    print "entry to all the SIP servers, it is responsible to forward your request ";
    print "to the correct SIP instance. To use a proxy server, typically a username and";
    print "password is required, but there are also server that work without. A well-known ";
    print "proxy server can be found at <a href=\"http://www.iptel.org\">iptel.org</a>";

    print "\n</td></tr><tr><td>User name at the proxy server\n";
    print $query->textfield(-name     => "username",
                            -default  => '',
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here the user name, ";
    print "as given to you by the operator of the proxy. In case you have not explicitly ";
    print 'given a user name, but only a SIP id (like sip:name@domain.org) and a password, ';
    print "take the <i>name</i> part of the SIP id.\n";

    print "\n</td></tr><tr><td>Password for the proxy server\n";
    print $query->textfield(-name     => "password",
                            -default  => '',
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here the corresponding, ";
    print "password. Note that the transmission to the web server where pua.pl runs is not ";
    print "using a secured connection, so in case this password is valuable, please don't ";
    print "continue.";

    print "\n</td></tr><tr><td>Your SIP id\n";
    print $query->textfield(-name     => "sip_id",
                            -default  => '',
                            -override => 1
                            );
    print "</td><td>\n";
    print "The SIP id, needed to set your SIP identity, usualy a URI of the form ";
    print '"sip:username@domain.org".';

    print "\n</td></tr></table>";
    print "<p><center>\n";
    print $query->submit();
    print "<p></center>\n";
    print $query->end_form();
}
