# Copyrights 2007-2012 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP::Daemon::AnyDaemon;
use vars '$VERSION';
$VERSION = '3.01';


# The selected type of netserver gets added to the @ISA during new(),
# so there are two base-classes!  Any::Daemon at least version 0.13
use base 'XML::Compile::SOAP::Daemon', 'Any::Daemon';

use Log::Report 'xml-compile-soap-daemon';

use Time::HiRes       qw/time alarm/;
use Socket            qw/SOMAXCONN/;
use IO::Socket::INET  ();
use HTTP::Daemon      ();   # Contains HTTP::Daemon::ClientConn

use XML::Compile::SOAP::Util  qw/:daemon/;
use XML::Compile::SOAP::Daemon::LWPutil;


sub new($%)
{   my ($class, %args) = @_;
    my $self = Any::Daemon->new(%args);
    (bless $self, $class)->init(\%args);  # $ISA[0] branch only
}

sub setWsdlResponse($)
{   my ($self, $fn) = @_;
    trace "setting wsdl response to $fn";
    lwp_wsdl_response $fn;
}

#-----------------------

sub _run($)
{   my ($self, $args) = @_;
    my $name = $args->{server_name} || 'soap server';
    lwp_add_header
       'X-Any-Daemon-Version' => $Any::Daemon::VERSION
      , Server => $name;

    my $socket = $args->{socket};
    unless($socket)
    {   my $host = $args->{host} or error "run() requires host";
        my $port = $args->{port} or error "run() requires port";

        $socket  = IO::Socket::INET->new
          ( LocalHost => $host
          , LocalPort => $port
          , Listen    => ($args->{listen} || SOMAXCONN)
          , Reuse     => 1
          ) or fault __x"cannot create socket at {interface}"
            , interface => "$host:$port";

        info __x"created socket at {interface}", interface => "$host:$port";
    }
    $self->{XCSDA_socket}    = $socket;

    $self->{XCSDA_conn_opts} =
      { client_timeout  => ($args->{client_timeout}  ||  30)
      , client_maxreq   => ($args->{client_maxreq}   || 100)
      , client_reqbonus => ($args->{client_reqbonus} ||   0)
      , postprocess     => $args->{postprocess}
      };

    $self->Any::Daemon::run
      ( child_task => sub {$self->accept_connections}
      , max_childs => ($args->{max_childs} || 10)
      , background => (exists $args->{background} ? $args->{background} : 1)
      );
}

sub accept_connections()
{   my $self   = shift;
    my $socket = $self->{XCSDA_socket};

    while(my $client = $socket->accept)
    {   info __x"new client {remote}", remote => $client->peerhost;

        # not sure whether this trick also works with IO::Socket::SSL's
        my $old_client_class = ref $client;
        my $connection = bless $client, 'HTTP::Daemon::ClientConn';
        ${*$connection}{httpd_daemon} = $self;

        $self->handle_connection($connection);

        bless $client, $old_client_class;
        $client->close;
    }
}

sub handle_connection($)
{   my ($self, $connection) = @_;
    my $conn_opts = $self->{XCSDA_conn_opts};
    eval {
        lwp_handle_connection $connection
          , %$conn_opts
          , expires  => time() + $conn_opts->{client_timeout}
          , handler  => sub {$self->process(@_)}
    };
    info __x"connection ended with force; {error}", error => $@
        if $@;
    1;
}

sub url() { "url replacement not yet implemented" }
sub product_tokens() { shift->{prop}{name} }

#-----------------------------


1;
