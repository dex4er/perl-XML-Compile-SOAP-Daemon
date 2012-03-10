#!/usr/bin/perl
# Attempt to produce all errors

use warnings;
use strict;

use lib 'lib', '../lib';

use Test::More;

use constant
 { SERVERHOST => 'localhost'
 , SERVERPORT => 8876
 };

use XML::Compile::SOAP::HTTPDaemon;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::SOAP::Util ':soap11';

use LWP::UserAgent;
use HTTP::Request;

plan skip_all => "Please contribute by porting tests to Windows"
   if $^O eq 'MSWin32';

my $daemon = XML::Compile::SOAP::HTTPDaemon->new;

my $pidfile = "/tmp/soapdaemon-test-$$.pid";
my $soapenv = SOAP11ENV;

unless(fork())
{   # Child

# test-script debugging
# use Log::Report mode => 3;

    $daemon->run
     ( name    => 'Test server'
     , host    => SERVERHOST
     , port    => SERVERPORT

     , pid_file          => $pidfile
     , min_servers       => 1
     , max_servers       => 1
     , min_spare_servers => 0
     , max_spare_servers => 0
     );
}

my $daemon_pid;
ATTEMPT:
foreach my $attempt (1..10)
{   if(open PID, '<', $pidfile)
    {   $daemon_pid = <PID>;
        close PID;
        last ATTEMPT;
    }
    sleep 1;
}

unless($daemon_pid)
{   plan skip_all => "Unable to start daemon";
}

sub stop_daemon()
{  defined $daemon_pid or return;
   ok(1, "Stopping daemon $daemon_pid");
   kill TERM => $daemon_pid;
   sleep(1);
}

END { stop_daemon }

sub compare_answer($$$)
{   my ($answer, $expected, $text) = @_;
    isa_ok($answer, 'HTTP::Response');
    UNIVERSAL::isa($answer, 'HTTP::Response') or return;

    my $h = $answer->headers;
    my $a = join "\n"
     , $answer->code
     , $answer->message
     , $answer->content_type, ''
     , $answer->decoded_content;
    $a =~ s/\s*\z/\n/;

    is($a, $expected, $text);
}

plan tests => 16;

###
### BEGIN
###

ok(1, "Started daemon $daemon_pid");
isa_ok($daemon, 'XML::Compile::SOAP::HTTPDaemon');

my $ua = LWP::UserAgent->new;
isa_ok($ua, 'LWP::UserAgent');

my $uri = "http://".SERVERHOST.":".SERVERPORT;

### GET request

my $req1 = HTTP::Request->new(GET => $uri);
my $ans1 = $ua->request($req1);

compare_answer($ans1, <<__EXPECTED, 'not POST');
405
only POST or M-POST
text/plain

[405] attempt to connect via GET
__EXPECTED

### Non XML POST request

my $req2 = HTTP::Request->new(POST => $uri);
my $ans2 = $ua->request($req2);

compare_answer($ans2, <<__EXPECTED, 'not XML');
406
required is XML
text/plain

[406] content-type seems to be text/plain, must be some XML
__EXPECTED

### XML parsing fails

my $req4 = HTTP::Request->new(POST => $uri);
$req4->header(Content_Type => 'text/xml');
$req4->header(soapAction => '');
$req4->content("<bad-xml>");
my $ans4 = $ua->request($req4);

compare_answer($ans4, <<__EXPECTED, 'parsing error');
422
XML syntax error
text/plain

[422] The XML cannot be parsed: :1: parser error : Premature end of data in tag bad-xml line 1
__EXPECTED

### Not SOAP Envelope

my $req5 = HTTP::Request->new(POST => $uri);
$req5->header(Content_Type => 'text/xml');
$req5->header(soapAction => '');
$req5->content("<not-soap></not-soap>");
my $ans5 = $ua->request($req5);

compare_answer($ans5, <<__EXPECTED, 'no soap envelope');
403
message not SOAP
text/plain

[403] The message was XML, but not SOAP; not an Envelope but `not-soap'
__EXPECTED

### Unknown SOAP Envelope

my $req6 = HTTP::Request->new(POST => $uri);
$req6->header(Content_Type => 'text/xml');
$req6->header(soapAction => '');
$req6->content('<me:Envelope xmlns:me="xx"></me:Envelope>');
my $ans6 = $ua->request($req6);

compare_answer($ans6, <<__EXPECTED, 'unknown soap envelope');
501
SOAP version not supported
text/plain

[501] The soap version `xx' is not supported
__EXPECTED


### Message not found

my $req7 = HTTP::Request->new(POST => $uri);
$req7->header(Content_Type => 'text/xml');
$req7->header(soapAction => '');
$req7->content( <<_NO_SUCH);
<me:Envelope xmlns:me="$soapenv">
  <me:Body>
    <me:something />
  </me:Body>
</me:Envelope>
_NO_SUCH
my $ans7 = $ua->request($req7);

compare_answer($ans7, <<__EXPECTED, 'message not found');
404
message not recognized
text/xml
charset="utf-8"

<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
  <SOAP-ENV:Body>
    <SOAP-ENV:Fault>
      <faultcode>SOAP-ENV:Server.notRecognized</faultcode>
      <faultstring>SOAP11 there are no handlers available, so also not {http://schemas.xmlsoap.org/soap/envelope/}something</faultstring>
      <faultactor>http://schemas.xmlsoap.org/soap/actor/next</faultactor>
    </SOAP-ENV:Fault>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>
__EXPECTED
