# Copyrights 2007-2009 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.06.
use warnings;
use strict;

package XML::Compile::SOAP::Daemon;
use vars '$VERSION';
$VERSION = '2.01';

our @ISA;   # filled-in at new().

use Log::Report 'xml-compile-soap-daemon', syntax => 'SHORT';
dispatcher SYSLOG => 'default';

use XML::LibXML        ();
use XML::Compile::Util qw/type_of_node/;

use List::Util         qw/first/;
use Time::HiRes        qw/time/;

# we use HTTP status definitions for each soap protocol
use HTTP::Status       qw/RC_FORBIDDEN RC_NOT_IMPLEMENTED
  RC_SEE_OTHER RC_NOT_ACCEPTABLE RC_UNPROCESSABLE_ENTITY
  RC_NOT_IMPLEMENTED RC_NOT_FOUND/;

# Net::Server error levels to Log::Report levels
my @levelToReason = qw/ERROR WARNING NOTICE INFO TRACE/;

my $parser        = XML::LibXML->new;


sub default_values()
{   my $self  = shift;
    my $def   = $self->SUPER::default_values;
    my %mydef =
     ( # changed defaults
       setsid => 1, background => 1, log_file => 'Log::Report'

       # make in-code defaults explicit, Net::Server 0.97
       # see http://rt.cpan.org//Ticket/Display.html?id=32226
     , log_level => 2, syslog_ident => 'net_server', syslog_logsock => 'unix'
     , syslog_facility => 'daemon', syslog_logopt => 'pid'
     );
   @$def{keys %mydef} = values %mydef;
   $def;
}

#-------------------------------------


sub new(@)  # not called by HTTPDaemon
{   my ($class, %args) = @_;

    # Use a Net::Server as base object

    my $daemon = delete $args{based_on} || 'Net::Server::PreFork';
    unless(ref $daemon)
    {   eval "require $daemon";
        $@ and error __x"failed to compile Net::Server class {class}, {error}"
           , class => $daemon, error => $@;

        my %options;
        $daemon = $daemon->new;
    }

    $daemon->isa('Net::Server')
        or error __x"The daemon is not a Net::Server, but {class}"
             , class => ref $daemon;

    # Upgrade daemon, wow Perl!
    @ISA = ref $daemon;
    (bless $daemon, $class)->init(\%args);
}

sub init($)
{   my ($self, $args) = @_;

    if(my $support = delete $args->{support_soap})
    {   # simply only load the protocol versions you want to accept.
        error __x"new(support_soap} removed in 2.00";
    }

    my @classes = XML::Compile::Operation->registered;
    @classes   # explicit load required since 2.00
        or warning "No protocol modules loaded.  Need XML::Compile::SOAP11?";

    $self->{output_charset} = delete $args->{output_charset} || 'UTF-8';
    $self->{handler}        = {};
    $self;
}

sub post_configure()
{   my $self = shift;
    my $prop = $self->{server};

    # Change the way messages are logged

    my $loglevel = $prop->{log_level};
    my $reasons  = ($levelToReason[$loglevel] || 'NOTICE') . '-';

    my $logger   = delete $prop->{log_file};
    if($logger eq 'Log::Report')
    {   # dispatching already initialized
    }
    elsif($logger eq 'Sys::Syslog')
    {   dispatcher SYSLOG => 'default'
          , accept    => $reasons
          , identity  => $prop->{syslog_ident}
          , logsocket => $prop->{syslog_logsock}
          , facility  => $prop->{syslog_facility}
          , flags     => $prop->{syslog_logopt}
    }
    else
    {   dispatcher FILE => 'default', to => $logger;
    }

    $self->SUPER::post_configure;
}

# Overrule Net::Server's log() to translate it into Log::Report calls
sub log($$@)
{   my ($self, $level, $msg) = (shift, shift, shift);
    $msg = sprintf $msg, @_ if @_;
    $msg =~ s/\n$//g;  # some log lines have a trailing newline

    my $reason = $levelToReason[$level] or return;
    report $reason => $msg;
}

# use Log::Report for hooks
sub write_to_log_hook { panic "write_to_log_hook cannot be used" }


sub outputCharset() {shift->{output_charset}}


sub run(@)
{   my ($self, %args) = @_;
    delete $args{log_file};      # Net::Server should not mess with my preps
    $args{no_client_stdout} = 1; # it's a daemon, you know
    $self->SUPER::run(%args);
}


# defined by Net::Server
sub process_request(@) { panic "must be extended" }

sub process($)
{   my ($self, $input) = @_;

    my $xmlin;
    if(ref $input eq 'SCALAR')
    {   $xmlin = try { $parser->parse_string($$input) };
        !$@ && $input
            or return $self->faultInvalidXML($@->died)
    }
    else
    {   $xmlin   = $input;
    }
    
    $xmlin       = $xmlin->documentElement
        if $xmlin->isa('XML::LibXML::Document');

    my $local    = $xmlin->localName;
    $local eq 'Envelope'
        or return $self->faultNotSoapMessage(type_of_node $xmlin);

    my $envns    = $xmlin->namespaceURI || '';
    my $proto    = XML::Compile::Operation->fromEnvelope($envns)
        or return $self->faultUnsupportedSoapVersion($envns);
    # proto is a XML::Compile::SOAP*::Operation
    my $server   = $proto->serverClass;

    my $info     = XML::Compile::SOAP->messageStructure($xmlin);
    my $version  = $info->{soap_version} = $proto->version;
    my $handlers = $self->{handler}{$version} || {};

    keys %$handlers;  # reset each()
    while(my ($name, $handler) = each %$handlers)
    {
        my ($rc, $msg, $xmlout) = $handler->($name, $xmlin, $info);
        defined $xmlout or next;

        trace "data ready for $version $name";
        return ($rc, $msg, $xmlout);
    }

    my $bodyel = $info->{body}[0] || '(none)';
    my @other  = sort grep {$_ ne $version && keys %{$self->{$_}}}
        $self->soapVersions;

    return (RC_SEE_OTHER, 'SOAP protocol not in use'
             , $server->faultTryOtherProtocol($bodyel, \@other))
        if @other;

    my @available = sort keys %$handlers;
    ( RC_NOT_FOUND, 'message not recognized'
    , $server->faultMessageNotRecognized($bodyel, \@available));
}


sub operationsFromWSDL($@)
{   my ($self, $wsdl, %args) = @_;
    my %callbacks = $args{callbacks} ? %{$args{callbacks}} : ();
    my %names;

    my $default = $args{default_callback};

    my @ops  = $wsdl->operations;
    unless(@ops)
    {   info __x"no operations in WSDL";
        return;
    }

    foreach my $op (@ops)
    {   my $name = $op->name;
        $names{$name}++;
        my $code;

        if(my $callback = delete $callbacks{$name})
        {   UNIVERSAL::isa($callback, 'CODE')
               or error __x"callback {name} must provide a CODE ref"
                    , name => $name;

            trace __x"add handler for operation `{name}'", name => $name;
            $code = $op->compileHandler(callback => $callback);
        }
        else
        {   trace __x"add stub handler for operation `{name}'", name => $name;
            my $server  = $op->serverClass;
            my $handler = $default
              || sub { $self->makeResponse(RC_NOT_IMPLEMENTED
                         , 'procedure stub used'
                         , $server->faultNotImplemented($name));
                     };

            $code = $op->compileHandler(callback => $handler);
        }

        $self->addHandler($name, $op, $code);
    }

    info __x"added {nr} operations from WSDL", nr => (scalar @ops);

    warning __x"no operation for callback handler `{name}'", name => $_
        for sort keys %callbacks;

    $self;
}


sub addHandler($$$)
{   my ($self, $name, $soap, $code) = @_;

    my $version = ref $soap ? $soap->version : $soap;
    $self->{handler}{$version}{$name} = $code;
}


sub handlers($)
{   my ($self, $soap) = @_;
    my $version = ref $soap ? $soap->version : $soap;
    my $table   = $self->{handler}{$version} || {};
    keys %$table;
}


sub soapVersions() { sort keys %{shift->{handler}} }


sub printIndex(;$)
{   my $self = shift;
    my $fh   = shift || \*STDOUT;

    foreach my $version ($self->soapVersions)
    {   my @handlers = $self->handlers;
        @handlers or next;

        local $" = "\n   ";
        $fh->print("$version:\n   @handlers\n");
    }
}


sub faultInvalidXML($)
{   my ($self, $error) = @_;
    my $text = __x"The XML cannot be parsed: {error}", error => $error;
    (RC_UNPROCESSABLE_ENTITY, 'XML syntax error', $text);
}


sub faultNotSoapMessage($)
{   my ($self, $type) = @_;

    my $text =
        __x"The message was XML, but not SOAP; not an Envelope but `{type}'"
      , type => $type;

    (RC_FORBIDDEN, 'message not SOAP', $text);
}


sub faultUnsupportedSoapVersion($)
{   my ($self, $envns) = @_;

    my $text = __x"The soap version `{envns}' is not supported"
                  , envns => $envns;

    (RC_NOT_IMPLEMENTED, 'SOAP version not supported', $text);
}


1;
