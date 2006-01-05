#!/usr/bin/perl -w

#
# ppl.pl - Demonstrator and WEB UI for pua.pl. An online 
# presence user agent and gateway http->sip. This provides 
# a simple user interface of pua.pl, with the special crux 
# that it is web based, i.e. running on some remote server.
# See http://pua-pl.berlios.de for licence

# $LastChangedDate$, Conny Holzhey

use CGI qw/:standard/;
use strict;

my $query = new CGI;
# my $PATH_TO_PROG ='/home/holzhey-de/htdocs/cgi-bin/pua-pl/';
# my $PATH_TO_PROG =`pwd`;
# chomp $PATH_TO_PROG;  
# $PATH_TO_PROG .= '/../';

my $PATH_TO_PROG ='/pua-pl/';
my $PATH_TO_LIBS = '.';

my $CRLF = "\015\012";

# main program

my $proxy = $query->param('proxy');
unless ($proxy) {
    printHeaders($query, 0);
    print_form($query, 1);
} else {
    my $err = check_param();
    if ($err ne '') {
        printHeaders($query, 0);
        print "<blink><b>Error: $err</b></blink><p>\n";
	print_form($query, 0);
    } else {
	printHeaders($query, 1);

	my $opts = '';
	my $register  = $query->param('register');
	my $publish   = $query->param('publish');
	my $subscribe = $query->param('subscribe');

        if (defined $register and $register eq 'ON') {
	    $opts = '-r --register-once ';
            if ($query->param('regexp') ne '') {
                $opts .= '--register-exp='.$query->param('regexp').' ';
            }
 	    if ($query->param('registrar') ne '') {
	        $opts .= '--registrar='.$query->param('registrar').' ';
	    }
        } 
	if (defined $publish and $publish eq 'ON') {
	    $opts .= '-p --publish-once ';

            if ($query->param('pubexp') ne '') {
                $opts .= '--publish-exp='.$query->param('pubexp').' ';
            }
 	    if ($query->param('status') ne '') {
	        $opts .= '--status='.$query->param('status').' ';
	    }
 	    if ($query->param('contact') ne '') {
	        $opts .= '--contact='.$query->param('contact').' ';
	    }
        } 
	if (defined $subscribe and $subscribe eq 'ON') {
	    $opts .= '-s -no -se 30 ';
 	    if ($query->param('watch') ne '') {
	        $opts .= '--watch-id='.$query->param('watch').' ';
	    }
	    $opts .= '--event-package='.$query->param('package').' ';
	}

        my $cmd = 'pua.pl '.$opts.' -d 1 --local-port=5060'.
          ' --proxy='    .$query->param('proxy').
	  ' --my-sip-id='.$query->param('sip_id'). 
	  ' --my-host=www.in-ulm-herum.de'.
	    ($query->param('username') ? ' --username=' .
	     $query->param('username') : '').
	    ($query->param('password') ? ' --password=' .
	     $query->param('password') : '').
            ' --trace';

	# for logging, erase the password, if any
	my $cmd1 = $cmd;
	$cmd1 =~ s/--password=[^ ]*/--password=xxxx/;

	print "<h3>Command line</h3>", $cmd1, "<p>\n";
	print "More to come, please wait ... (max 30 seconds)<p>\n";

	# backticks!
	my $out = `perl -I ${PATH_TO_LIBS} -I${PATH_TO_PROG}. -- ${PATH_TO_PROG}$cmd`;

        my ($res, @messages) = parseOutput($out, $query->param('proxy'));
        # print "<h3>Output of pua.pl</h3><pre>$res</pre><p>\n";
        print "<pre>$res</pre><p>\n";


        # write result to logfile
        if (open LOG, ">> ${PATH_TO_PROG}/logfile") {
            my $date = gmtime;
            my $rho = remote_host();
            print LOG "$date, $rho: $cmd1\n";
            print LOG "$res";
            close LOG;
        }

	if (@messages and $#messages > 0) {
  	    print "<h3>SIP messages</h3>\n";
	    print "<p><table width=95%>\n";
	    my $m;
	    foreach $m (@messages) {
		print "<tr><td>$m</td></tr>\n";
	    }
	}
	print "</table>\n";
    }
}
print <<'EOB';

<center><small>Commercial use is not permitted. This script
is open source, see <a href="http://pua-pl.berlios.de">here</a> for licence.
Thanks to <a href="http://breitnetz.de/">IT Technologie</a> for hosting support. For questions or suggestions,
please contact me: <script type="text/javascript">
<!--
	var first = 'ma';
	var second = 'il';
	var third = 'to:';
	var address = 'yivi';
	var domain = 'holzhey'+'&#46;&#100;&#101;';
	document.write('<a href="');
	document.write(first+second+third);
	document.write(address);
	document.write('&#64;');
	document.write(domain);
	document.write('" title="email Conny ');
	document.write('Holzhey">');
	document.write('Conny ');
	document.write('Holzhey<\/a>');
// -->
</script></small></center></div>

EOB

print $query->end_html();



#
# print http and html header

sub printHeaders {
    my $query = shift;
    my $setcookie = shift;

    my %params; # query params to be stored in the cookie

    if ($setcookie) {

	# fetch all parameters, to store them in the cookie
	%params = $query->Vars;

	# erase the password
	if (exists $params{'password'}) {
	    delete $params{'password'};
	}

        # erase all empty fields
	foreach (keys %params) {
	    if ($params{$_} eq '') { 
		delete $params{$_};
	    }
	}

	# create the cookie when at least the proxy was input
	my $cookie = $query->cookie(-name=>'pua.pl',
				    -value=>\%params,
				    -expires=>'+1M'); # one month
	                            #-domain=>'.holzhey.de');
        # print http header with the cookie
	print $query->header(-cookie=>$cookie);

    } else {

	# try to get the default value from previous session, if any
	my $cookie = $query->cookie();
	if (defined $cookie) {
	    %params = $query->cookie('pua.pl');
	    foreach (keys %params) {
		if ($params{$_} eq '') {
		    delete $params{$_};
		} 
		    
		# write the cookie values back to the query
                # parameter, but take care not to overwrite
		if (!defined $query->param($_)) {
		    $query->param(-name  => $_, 
				  -value => $params{$_});
		}
	    }
	}
        # print http header without the cookie
	print $query->header();
    }

    # HTML headers
    printHTMLHeader();
    printTabHeader();
    print '<BODY>',"\n";
    print '<div id="center"><h2>pua.pl Web UI</h2>';
}



# 
# check if all neccessary fields are filled in, and there must not be 
# any characters that would be allowed to misuse perl
 
sub check_param {

    my $p = $query->param('proxy');
    if ($p eq '') { 
	return "SIP Proxy server name not defined.";
    }
    unless ($p =~ /^([-a-z.0-9:])+$/i) {
	return 'Invalid character in proxy server name.';
    }

    my $s = $query->param('sip_id');
    if (!defined $s || $s eq '' || $s eq 'sip:') { 
	return "SIP id not specified.";
    }
    unless ($s =~ /^([-a-z._0-9:@])+$/i) {
	return 'Invalid character in sip-id.';
    }

    my $u = $query->param('username');
    if (defined $u and $u ne '') {
	unless ($u =~ /^([-a-z._0-9:@])+$/i) {
	    return 'Invalid character in user name.';
	}
    }

    my $w = $query->param('password');
    if (defined $w and $w ne '') {
        unless ($w =~ /^([-a-z._0-9:])+$/i) {
	    return 'Invalid character in password. Due to security of '.
	      'the web server the character set is limited to '.
	      '[a-z.0-9:], even if other chars would be valid.';
	}
    }

    my $re = $query->param('registrar');
    if ($re ne '' && !($re =~ /^([-a-z.0-9:])+$/i)) {
	return 'Invalid character in registrar server name.';
    }

    my $co = $query->param('contact');
    if ($co ne '' && !($co =~ /^([-+a-z@._0-9:])+$/i)) {
	return 'Invalid character in contact URI.';
    }

    my $wa = $query->param('watch');
    if ($wa ne '' && $wa ne 'sip:' && !($wa =~ /^([-a-z@._0-9:])+$/i)) {
	return 'Invalid character in watcher URI.';
    }

    my $st = $query->param('status');
    if ($st ne 'open' and $st ne 'closed') {
        return 'Invalid value for basic presence status, permitted are "open" or "closed"';
    }

    my $ep = $query->param('package');
    if ($ep ne 'presence' and $ep ne 'presence.winfo' and $ep ne 'presence.winfo.winfo') {
	return 'Invalid value for event package, permitted are: presence, '.
	  'presence.winfo and presence.winfo.winfo.';
    }

    my $re = $query->param('regexp');
    if ($re ne '' && !($re =~ /^\d+$/)) {
        return 'Expiry duration for Register is not a number';
    }

    my $pe = $query->param('pubexp');
    if ($pe ne '' && !($pe =~ /^\d+$/)) {
        return 'Expiry duration for Publish is not a number';
    }


    return '';
} 

#
# parse the output, all starting with <<< or >>> is interpretet
# as SIP message. 
# returns the output, followed by a list of SIP messages,
# ready to displayed in HTML format. Remembär: Always be 
# careful with perl and passing arrays around.

sub parseOutput {
    my $raw = shift;
    my $proxy = shift;
    my $ret = '';
    my @messages;
    my $msg;
    my $line;

    foreach $line (split("\n", $raw)) {

	if ($line eq '<<<<<<') {
	    # new incoming msg
	    $msg .= '</pre>';
	    push @messages, $msg;
	    $msg = "<pre><b>pua.pl &lt;- $proxy</b>\n";

	} elsif ($line =~ /^<<< (.*)$/) {
	    # incoming msg
	    $msg .= escapeHTML($1) . "\n";

	} elsif ($line =~ /^>>> (.*)$/) {
	    # outgoing msg
	    $msg .= escapeHTML($1) . "\n";
	} elsif ($line eq '>>>>>>') {
	    # new outgoing message
	    $msg .= '</pre>';
	    push @messages, $msg;
	    $msg = "<pre><b>pua.pl -&gt; $proxy</b>\n";
	} else {
	    # append all other lines to $ret
	    $ret .= escapeHTML($line) . "<br>\n";
	}
    }

    return ($ret, @messages, $msg);
}

#
# the main input form 

sub print_form {
    my $query = shift;
    my $long = shift;
    if ($long) {
	print "\nThis is the Web UI page for ";
	print "<a href=\"http://pua-pl.berlios.de\">pua.pl</a>. ";
	print "pua.pl itself is a simple SIP-based presence user agent, ";
	print "and this is a user interface to run it - and a HTTP ";
	print "to SIP gateway.<p>\n";

	print "pua.pl is a actually a command-line tool and it uses SIP/SIMPLE ";
	print "to communicate to a server, and it partly supports the ";
	print "following standards: rfc-3261 (SIP), rfc-3903 (PUBLISH), ";
	print "rfc-3265 & rfc-3856 (NOTIFY, SUBSCRIBE), rfc-3863 (pidf).<p>\n";
	
	print "Running pua.pl thru this script limites the useage to a ";
	print "subset of options - see <a href=\"http://pua-pl.berlios.de\">";
        print "here</a> for the complete list of options.";
	print "With this frontend, it is possible to do 3 things: register ";
	print "at a sip server, publish presence information and check ";
	print "some other user's presence information. ";;
	print "To do so, some parameter need to be filled in below.<p>\n";
    }
    print "Mandatory input fields are marked with <font color=red>*</font>,";
    print " additionally at least one of the operations ";
    print "Register/Subscribe/Publish should be selected.<p>\n";

    print $query->start_form(-name =>'tabform');
    print "<table><tr><td>Proxy server name <font color=red>*</font>";
    
    my $default;
    $default = $query->param('proxy');
    if (!defined $default) { $default = 'pals.internet2.edu'; }

    print $query->textfield(-name     => "proxy",
                            -default  => $default,
                            -override => 1
                            );
    print "<p></td><td>\n";
    print "Fill in the name of the SIP proxy server. A proxy server is ";
    print "the single entry to the SIP world, it is responsible ";
    print "to forward any request to the correct SIP servers. To use ";
    print "a proxy server, typically an account (username and password) ";
    print "is required, but there are also server that work without. See ";
    print "for instace <a href=\"http://www.iptel.org\">iptel.org</a> ";
    print "for a SIP proxy server.<p>";

    print "\n</td></tr><tr><td>User name at the proxy server\n";

    $default = $query->param('username');
    if (!defined $default) { $default = ''; }

    print $query->textfield(-name     => "username",
                            -default  => $default,
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here ";
    print "the user name, as given to you by the operator of the proxy. ";
    print "In case you have not explicitly given a user name, just a ";
    print 'SIP id (like sip:name@domain.org), take the <i>name</i> part ';
    print "of the SIP id.<p>\n";

    print "\n</td></tr><tr><td>Password for the proxy server\n";

    $default = $query->param('password');
    if (!defined $default) { $default = ''; }

    print $query->textfield(-name     => "password",
                            -default  => $default,
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here the ";
    print "corresponding password. Note: the transmission to the web server ";
    print "where pua.pl runs is <b>not</b> using a secured connection, ";
    print "and the password might be shown literally in the traces. ";
    print "So in case this password is valuable, please don't continue.<p>";

    print "\n</td></tr><tr><td>SIP id <font color=red>*</font>\n";

    $default = $query->param('sip_id');
    if (!defined $default) { 
	my $u = $query->param('username');
	if (defined $u) {
	    $default = 'sip:'.$u;
	}
	$default = 'sip:'; 
    }

    print $query->textfield(-name     => "sip_id",
                            -default  => $default,
                            -override => 1
                            );
    print "<p></td><td>\n";
    print "The SIP id, needed to set your SIP identity, usualy a URI of ";
    print 'the form "sip:username@domain.org".<p>';

    print "\n</td></tr></table>";
    print "<p><center>\n";

    # start tabbed panes
    print '<script type="text/javascript">'."\n";
    printRegisterForm($query);
    printSubscribeForm($query);
    printPublishForm($query);

    print "\n<p>\n";
    print $query->submit();
    print "<p></center>\n";
    print $query->end_form();
}


#
# register form tab
# script within script, avoid using quotes

sub printRegisterForm {
    my $query = shift;
    my $reg = $query->param('register');
    print 'var pane1 = "<table width=90% class=\'pane_tbl\'><tr><td>'.
          '<table border=0><tr><td colspan=2>';
    print "<input type='checkbox' name='register' value='ON' ";
    if (defined $reg and $reg eq 'ON') { print 'checked'; }
    print "/>&nbsp; Check if Register operation should be performed.<p></td></tr>";

    print '<tr><td>Registrar server name<br>';
    print "<input type='text' name='registrar' ";
    my $rar = $query->param('registrar');
    if (defined $rar) {
	print "value='$rar'";
    }
    print "/>";

    print '</td><td>Name of the registrar server, expects a URI like ';
    print 'sip:someprovider.net:5060. If no registrar is specified, ';
    print 'the register request will be sent to a server name ';
    print 'constructed from your address (as specified with SIP id '.
          'above). E.g. for a given SIP id sip:myname@domain.org, '.
          'the registrar will be guessed as sip:domain.org.<p></td></tr>';

    # expiry duration
    print '<tr><td>Expires after<br><input type=\'text\' name=\'regexp\' ';
    my $exp = $query->param('regexp');
    if (defined $exp) {
        print 'value=\''.$exp.'\'';
    } else {
        print 'value=\'60\'';
    }
    print ' /></td><td>Timeout in seconds how long the registration '.
          'is valid. After expiry, the Register '.
          'operation needs to be performed again.'.
          '</td></tr></table></td></tr></table>";';
}


#
# subscribe form tab
# script within script, avoid using quotes

sub printSubscribeForm {
    my $query = shift;
    my $sub = $query->param('subscribe');

    print 'var pane2 = "<table width=90% class=\'pane_tbl\'><tr><td>'.
          '<table border=0><tr><td colspan=2>';
    print "<input type='checkbox' name='subscribe' value='ON' ";

    if (defined $sub and $sub eq 'ON') { 
	print 'checked'; 
    }

    print "/>&nbsp; Check if Subscribe operation should be performed.".
          "<p></td></tr>";

    print '<tr><td>URI to subscribe<br>';
    print "<input type='text' name='watch' ";
    my $w = $query->param('watch');
    if (defined $w) {
	print "value='$w'";
    } else {
        print "value='sip:'";
    }
    print "/>";

    print '<p></td><td>URI to subscribe, i.e. the address of the person to '.
          ' watch. Expected is something like sip:moby@sea.com.'.
          '<p></td></tr><tr><td>';
    print 'Event package<br><select '.
          'name=\'package\' size=1><option';

    my $pack = $query->param('package');
    if (!defined $pack) { 
        print ' selected'; 
    } elsif ($pack eq 'presence') { 
        print ' selected'; 
    }
    print '>presence</option><option';
    if (defined $pack && $pack eq 'presence.winfo') {
        print ' selected'; 
    }
    print '>presence.winfo</option><option';
    if (defined $pack && $pack eq 'presence.winfo.winfo') {
        print ' selected'; 
    }
    print '>presence.winfo.winfo</option></select></td><td>';
    print 'Set this to <i>presence</i> in case you want to subscribe to '.
          'the information, whether the person is online or not. '.
	  'Set this to <i>presence.winfo</i> in case you want information '.
	  'about who subscribes to the person\'s presence... '.
	  '</td></tr></table></td></tr></table>";';
}


#
# publish form tab
# script within script, avoid using quotes

sub printPublishForm {
    my $query = shift;
    my $pub = $query->param('publish');

    print 'var pane3 = "<table width=90% class=\'pane_tbl\'><tr><td><table border=0>'.
          '<tr><td colspan=2><input type=\'checkbox\' name=\'publish\' value=\'ON\'';

    if (defined $pub and $pub eq 'ON') { print ' checked'; }
    
    print ' />Check if Publish operation should be performed.<p></td></tr><tr><td>'.
          'Contact URI<br><input type=\'text\' name=\'contact\' ';

    my $con = $query->param('contact');
    if (defined $con) {
        print 'value=\''.$con.'\'';
    }

    print ' /></td><td>The contact address to be published. Can be any address, '.
          'like an email or telephone number. The addres should include the '.
          'scheme, e.g. tel:+09012345678, or mailto:someone@example.com are '.
          'valid.<p></td></tr>';

    # basic presence status
    print '<tr><td>Basic presence status<br><select '.
          'name=\'status\' size=1><option';

    my $stat = $query->param('stat');
    if (!defined $stat) { 
        print ' selected'; 
    } elsif ($stat eq 'open') { 
        print ' selected'; 
    }
    print '>open</option><option';
    if (defined $stat && $stat eq 'closed') {
        print ' selected'; 
    }

    print '>closed</option></select></td><td>'.
          'This is to specify the status of the '.
          'contact URI, \'open\' means, the person'.
          ' behind the contact URI is able and'.
          ' willing to accept communication this way.<p></td></tr>';

    # expiry duration
    print '<tr><td>Expires after<br><input type=\'text\' name=\'pubexp\' ';
    my $exp = $query->param('pubexp');
    if (defined $exp) {
        print 'value=\''.$exp.'\'';
    } else {
        print 'value=\'60\'';
    }
    print ' /></td><td>Timeout in seconds how long the published '.
          'contact address is valid. After expiry, the Publish '.
          'operation needs to be performed again.';

print <<'EOF'
<p></td></tr></table></td></tr></table>";

var ts = new tabstrip();
var t1 = new tab("Register Options",pane1);
var t2 = new tab("Subscribe Options",pane2);
var t3 = new tab("Publish Options",pane3);

ts.add(t1);
ts.add(t2);
ts.add(t3);

ts.write();
</script>


EOF
}


#
# print HTML header

sub printHTMLHeader {
print <<'EOH'
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	 "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en-US">
<head><title>pua.pl, presence user agent web UI &amp; gateway</title>
<link rel="stylesheet" type="text/css" href="../doc/wp.css" />

EOH
}
# for breitnetz: <link rel="stylesheet" type="text/css" href="../doc/wp.css" />


#
# some javascript functions to allow tabs for the various 
# options. 
# This code largely copied from http://javascript.internet.com 

sub printTabHeader {

print <<'EOH'
<script type="text/javascript">
var currentPaneStyle = 0;
var currentTab = 0;

function tabstrip()
{
   this.tabs = new Array();
   this.add = addTab;
   this.write = writeTabstrip;
}

function tab(caption,content)
{
  this.setId = setId;
  this.caption = caption;
  this.content = content;
  this.write = writeTab;
  this.writeContent = writePane;
}

function addTab(tab)
{
  tab.setId("tab" + this.tabs.length);
  this.tabs[this.tabs.length] = tab;
}

function setId(id)
{
  this.id = id;
}

function initiate()
{
  var div = document.getElementById("tab0");
  showPane(div);
}

function showPane(div)
{
  if(currentTab != 0)
  {
    currentTab.style.backgroundColor = "#e0e0e0";
  }
  div.style.backgroundColor = "#FFFFFF";
  currentTab = div;

  if(currentPaneStyle != 0)
    currentPaneStyle.display = "none";
  var paneId = "pn_" + div.id;
  var objPaneStyle = document.getElementById(paneId).style;
  objPaneStyle.display = "block";
  currentPaneStyle = objPaneStyle;
}

function SubmitForm()
{
   window.alert("Form submitted. This would normally take you to another page");
   // normally, you would here check the form and submit it.
   // if the form has the name 'tabform', then it is submitted
   // with tabform.submit();
}

function writePane()
{
  document.write("<div class='tab_pane' id='pn_" + this.id + "'>" + this.content + "</div>");
}

function writeTab()
{
   document.write("<td class='tabs'><div class='tabs' id='" + this.id + "' onclick='showPane(this)'>&nbsp;<u>" + this.caption + "</u>&nbsp;</div></td>");
}

function writeTabstrip()
{
  document.write("<table class='tabs'><tr>");
  for(var i = 0; i < this.tabs.length; i++)
  {
    this.tabs[i].write();
  }
  document.write("</tr></table>");

  for(var k = 0; k < this.tabs.length; k++)
  {
    this.tabs[k].writeContent();
  }
  initiate();
}

// for the result page
function addRow(id, text1, text2){
    var tbody = document.getElementById(id).getElementsByTagName("TBODY")[0];
    var row = document.createElement("TR")
    var td1 = document.createElement("TD")
    td1.appendChild(document.createTextNode(text1))
    var td2 = document.createElement("TD")
    td2.appendChild (document.createTextNode(text2))
    row.appendChild(td1);
    row.appendChild(td2);
    tbody.appendChild(row);
  }
</script>
</head>
EOH
}
