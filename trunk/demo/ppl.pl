#!/usr/bin/perl -w

#
# ppl.pl - Demonstrator and WEB UI for pua.pl. An online presence 
# user agent. This provides a simple user interface of pua.pl, with
# the special crux that it is web based

use CGI qw/:standard/;
use strict;

my $query = new CGI;
my $PATH_TO_PROG ='/home/conny/projects/sippoc/trunk/';


# main program

# print http header
print header;

# HTML headers
printHeader();
printTabHeader();
print '<BODY onUnload="spawntopfivewindow();">',"\n";
print '<div id="center"><h2>pua.pl Web UI</h2>';

my $proxy = $query->param('proxy');
unless ($proxy) {
    print_form($query, 1);
} else {
    my $err = check_param();
    if ($err ne '') {
        print "<blink><b>Error: $err</b></blink><p>\n";
	print_form($query, 0);
    } else {
        my $cmd = $PATH_TO_PROG.'pua.pl -r -ro -re 60 -d 5'.
          ' --proxy='    .$query->param('proxy').
	  ' --my-sip-id='.$query->param('sip_id'). 
	    ($query->param('username') ? ' --username=' .
	     $query->param('username') : '').
	    ($query->param('password') ? ' --password=' .
	     $query->param('password') : '');

	print "<b>Command line:</b> <br>", $cmd, "<p>\n";

	my $out = `perl -I ${PATH_TO_PROG}lib -I${PATH_TO_PROG}. -- $cmd 2>&1`;
	print "<b>Output of pua.pl:</b><pre>$out</pre>\n";
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
    if (!defined $s || $s eq '' || $s eq 'sip:') { 
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
	    return 'Invalid character in password. Due to security of '.
	      'the web server the character set is limited to '.
	      '[a-z.0-9:], even if other chars would be valid.';
	}
    }
    return '';
} 


#
# the main input form 

sub print_form {
    my $query = shift;
    my $long = shift;
    if ($long) {
	print "\nThis is a demo page for pua.pl. pua.pl itself is a simple SIP-based\n";
	print "presence user agent, and here you have a user interface to run it.\n";
	print "pua.pl is a actually a command-line and it uses SIP/SIMPLE to communicate ";
	print "to a server, and it supports partly the following standards: rfc-3261 (SIP), ";
	print "rfc-3903 (PUBLISH), rfc-3265 & rfc-3856 (NOTIFY, SUBSCRIBE), rfc-3863 (pidf).<p>\n";
	
	print "Running pua.pl thru this script limites the useage of pua.pl to a subset of ";
	print "options - see <a href=\"index.html\">here</a> for the complete list of options.";
	print "With this frontend, it is possible to do 3 things: register at a sip server, ";
	print "publish presence information and check some other user's presence information. ";;
	print "To do so, quite a number of parameter need to be known:\n";
    }

    print $query->start_form(-name =>'tabform');
    print "<table><tr><td>Proxy server name ";
    
    my $default;
    $default = $query->param('proxy');
    if (!defined $default) { $default = 'proxy.someprovider.net'; }

    print $query->textfield(-name     => "proxy",
                            -default  => $default,
                            -override => 1
                            );
    print "</td><td>\n";
    print "Fill in the name of the SIP proxy server. A proxy server is like the single ";
    print "entry to all the SIP servers, it is responsible to forward your request ";
    print "to the correct SIP instance. To use a proxy server, typically a username and";
    print "password is required, but there are also server that work without. A well-known ";
    print "proxy server can be found at <a href=\"http://www.iptel.org\">iptel.org</a>";

    print "\n</td></tr><tr><td>User name at the proxy server\n";

    $default = $query->param('username');
    if (!defined $default) { $default = ''; }

    print $query->textfield(-name     => "username",
                            -default  => $default,
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here the user name, ";
    print "as given to you by the operator of the proxy. In case you have not explicitly ";
    print 'given a user name, but only a SIP id (like sip:name@domain.org) and a password, ';
    print "take the <i>name</i> part of the SIP id.\n";

    print "\n</td></tr><tr><td>Password for the proxy server\n";

    $default = $query->param('password');
    if (!defined $default) { $default = ''; }

    print $query->textfield(-name     => "password",
                            -default  => $default,
                            -override => 1
                            );
    print "</td><td>\n";
    print "In case the proxy server requires authentication, input here the corresponding, ";
    print "password. Note: the transmission to the web server where pua.pl runs is <b>not</b> ";
    print "using a secured connection, so in case this password is valuable, please don't ";
    print "continue.";

    print "\n</td></tr><tr><td>Your SIP id\n";

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
    print "</td><td>\n";
    print "The SIP id, needed to set your SIP identity, usualy a URI of the form ";
    print '"sip:username@domain.org".';

    print "\n</td></tr></table>";
    print "<p><center>\n";

    # start tabbed panes
    print '<script type="text/javascript">'."\n";
    printRegisterForm($query);

    print $query->submit();
    print "<p></center>\n";
    print $query->end_form();
}


#
# register form tab
# script within script

sub printRegisterForm {
    my $query = shift;
    
    print 'var pane1 = "<p><table width=80% border=1 frame=\'void\'><tr><td colspan=2>';
    print "<input type='checkbox' name='register' value='ON' checked='checked' />";
    print "Check if Register operation should be performed.<p></td></tr>";

    print '<tr><td>Registrar server name<br>';
    print "<input type='text' name='registrar'  />";

print <<'EOF'
</td><td>Name of the registrar server, an uri like sip:someprovider.net:5060 is expected.. If no registrar is specified, the register request will be sent to a server name constructed from your address (as specified with SIP id above). E.g. for a given SIP id sip:myname@domain.org, the registrar will be guessed as sip:domain.org</td></tr></table>";

var pane2 = "First name: <input type='text' class='txt' name='inpFirst' size=20></input><br>Last name: <input type='text' class='txt' name='inpLast' size=20></input><br>Address 1: <input type='text' class='txt' name='inpAdr1' size=20></input><br>Address 2: <input type='text' class='txt' name='inpAdr2' size=20></input><br>City : <input type='text' class='txt' name='inpCity' size=20></input><br>Postcode/ZIP: <input type='text' class='txt' name='inpPC' size=20></input><br>E-Mail: <input type='text' class='txt' name='inpEmail' size=20></input>";


var ts = new tabstrip();
var t1 = new tab("Register",pane1);
var t2 = new tab("Publish",pane2);

ts.add(t1);
ts.add(t2);

ts.write();
</script>
</form>

EOF
}


#
# print HTML header

sub printHeader {
print <<'EOH'
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html
	PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
	 "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en-US">
<head><title>pua.pl, presence user agent web UI &amp; gateway</title>
<link rel="stylesheet" type="text/css" href="/pua-pl/doc/wp.css" />

EOH
}

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
    currentTab.style.backgroundColor = "#00ffff";
  }
  div.style.backgroundColor = "#ccccff";
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
   document.write("<td class='tabs'><div class='tabs' id='" + this.id + "' onclick='showPane(this)'>" + this.caption + "</div></td>");
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
</script>
</head>
EOH
}
