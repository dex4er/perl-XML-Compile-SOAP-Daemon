# Copyrights 2007-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::HTTPDaemon;
use vars '$VERSION';
$VERSION = '2.00';

use base 'XML::Compile::SOAP::Daemon';

use Log::Report 'xml-compile-soap-daemon', syntax => 'SHORT';

use XML::LibXML    ();
use List::Util     qw/first/;
use HTTP::Response ();
use HTTP::Status   qw/RC_BAD_REQUEST RC_OK RC_METHOD_NOT_ALLOWED
  RC_EXPECTATION_FAILED RC_NOT_ACCEPTABLE/;

use HTTP::Daemon   ();
use XML::Compile::SOAP::Util  qw/:daemon/;
use Time::HiRes    qw/time alarm/;


sub options()
{   my ($self, $ref) = @_;
    my $prop = $self->{server};
    $self->SUPER::options($ref);
    foreach ( qw/client_timeout client_maxreq client_reqbonus name/ )
    {   $prop->{$_} = undef unless exists $prop->{$_};
        $ref->{$_} = \$prop->{$_};
    }
}

sub default_values()
{   my $self  = shift;
    my $def   = $self->SUPER::default_values;
    my %mydef = ( client_timeout => 30, client_maxreq => 100
     , client_reqbonus => 0, name => 'soap daemon');
    @$def{keys %mydef} = values %mydef;
    $def;
}

sub headers($)
{   my ($self, $response) = @_;
    $response->header(Server => $self->{prop}{name});
    $self;
}

sub headersForXML($)
{  my ($self, $response) = @_;
   $self->headers($response);
   $response->header('Content-Type' => 'text/xml; charset="utf-8"');
   $self;
}


sub process_request()
{   my $self = shift;
    my $prop = $self->{server};

    # Merge Net::Server behavior with HTTP::Daemon
    # Now, our connection will become a HTTP::Daemon connection
    my $old_class  = ref $prop->{client};
    my $connection = bless $prop->{client}, 'HTTP::Daemon::ClientConn';
    ${*$connection}{httpd_daemon} = $self;

    local $SIG{ALRM} = sub { die "timeout\n" };
    my $expires = time() + $prop->{client_timeout};
    my $maxmsgs = $prop->{client_maxreq};

    eval {
        my $timeleft;
        while(($timeleft = $expires - time) > 0.01)
        {   alarm $timeleft;
            my $request  = $connection->get_request or last;
            alarm 0;

            my $response = $self->runRequest($request, $connection);
            $connection->force_last_request if $maxmsgs==1;
            $connection->send_response($response);

            --$maxmsgs or last;
            $expires += $prop->{client_reqbonus};
        }
    };

    info __x"connection ended with force; {error}", error => $@
        if $@;

    # Our connection becomes as Net::Server::Proto::TCP again
    bless $prop->{client}, $old_class;
    1;
}

sub url() { "url replacement not yet implemented" }
sub product_tokens() { shift->{prop}{name} }


sub runRequest($$)
{   my ($self, $request, $connection) = @_;

    my $client   = $connection->peerhost;
    if($request->method !~ m/^(?:M-)?POST/)
    {   return $self->protocolError(RC_METHOD_NOT_ALLOWED
          , "only POST or M-POST"
          , "attempt to connect via ".$request->method)
    }

    my $media    = $request->content_type || 'text/plain';
    $media =~ m{[/+]xml$}i
        or return $self->protocolError(RC_NOT_ACCEPTABLE
          , 'required is XML'
          , "content-type seems to be $media, must be some XML");

    my $action   = $self->actionFromHeader($request);
    defined $action
        or return $self->protocolError(RC_EXPECTATION_FAILED
          , 'not SOAP'
          , "soap requires an soapAction header field");

    my $ct       = $request->header('Content-Type');
    my $charset  = $ct =~ m/\;\s*type\=(["']?)([\w-]*)\1/ ? $2: 'utf-8';
    my $xmlin    = $request->decoded_content(charset => $charset, ref => 1);
    my $xmlout   = $self->process($xmlin);

      UNIVERSAL::isa($xmlout, 'HTTP::Response') ? $xmlout
    : $self->acceptResponse($request, RC_OK, $xmlout);
}


sub actionFromHeader($)
{   my ($self, $request) = @_;

    my $action;
    if($request->method eq 'POST')
    {   $action = $request->header('SOAPAction');
    }
    elsif($request->method eq 'M-POST')
    {   # Microsofts HTTP Extension Framework
        my $http_ext_id = '"' . MSEXT . '"';
        my $man = first { m/\Q$http_ext_id\E/ } $request->header('Man');
        defined $man or return undef;

        $man =~ m/\;\s*ns\=(\d+)/ or return undef;
        $action = $request->header("$1-SOAPAction");
    }
    else
    {   return undef;
    }

      !defined $action            ? undef
    : $action =~ m/^\s*\"(.*?)\"/ ? $1
    :                               '';
}

sub acceptResponse($$$)
{   my ($self, $request, $status, $xmlout) = @_;

    my $resp = HTTP::Response->new($status);
    $resp->protocol($request->protocol);  # match request
    my $s    = $xmlout->toString;
    $resp->content_ref(\$s);
    { use bytes; $resp->header('Content-Length' => length $s); }
    $self->headersForXML($resp);

    if(substr($request->method, 0, 2) eq 'M-')
    {   # HTTP extension framework.  More needed?
        $resp->header(Ext => '');
    }

    $resp;
}

sub soapFault($$$)
{   my ($self, $rc, $abstract, $xml) = @_;
    my $resp = HTTP::Response->new($rc, $abstract);
    my $s    = $resp->content($xml->toString(1));
    { use bytes; $resp->header('Content-Length' => length $s); }
    $self->headersForXML($resp);
    $resp;
}

sub protocolError($$$)
{   my ($self, $rc, $abstract, $text) = @_;
    $self->SUPER::protocolError($rc, $abstract, $text);
    my $resp = HTTP::Response->new($rc, $abstract, [], $text);
    $self->headers($resp);
    $resp->header(Content_Type => 'text/plain');
    $resp;
}
    

1;
