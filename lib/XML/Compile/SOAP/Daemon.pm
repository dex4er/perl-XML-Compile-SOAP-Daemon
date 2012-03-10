# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use warnings;
use strict;

package XML::Compile::SOAP::Daemon;
use vars '$VERSION';
$VERSION = '0.10';
our @ISA;   # filled-in at new().

use Log::Report 'xml-compile-soap-daemon', syntax => 'SHORT';

use XML::LibXML                  ();
use XML::Compile::Util           qw/type_of_node/;
use XML::Compile::SOAP::Util     qw/SOAP11ENV SOAP12ENV/;
use XML::Compile::SOAP11::Server ();
use XML::Compile::SOAP12::Server ();

use List::Util    qw/first/;
use Time::HiRes   qw/time/;

# we use HTTP status definitions for each protocol
use HTTP::Status  qw/RC_BAD_GATEWAY RC_NOT_IMPLEMENTED RC_SEE_OTHER/;

my $parser        = XML::LibXML->new;
my %faultWriter;
my @levelToReason = qw/ERROR WARNING NOTICE INFO TRACE/;


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
    my $support = delete $args->{support_soap} || 'ANY';
    $self->{supported} = ref $support ? $support->version : $support;

    foreach my $version ($self->soapVersions)
    {   $self->isSupportedVersion($version) or next;
        $faultWriter{$version}
          = "XML::Compile::${version}::Server"->faultWriter;
    }

    $self->{output_charset} = delete $args->{output_charset} || 'UTF-8';
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


sub isSupportedVersion($)
{   my $support = shift->{supported};
    $support eq 'ANY' || $support eq shift();
}


sub run(@)
{   my $self = shift;
    $self->SUPER::run
     ( no_client_stdout => 1    # it's a daemon, you know
     , @_
     , log_file         => undef # Net::Server should not mess with my preps
     );
}


# defined by Net::Server
sub process_request(@) { panic "must be extended" }

sub process($$$)
{   my ($self, $request, $xmlin) = @_;
    $xmlin    = $xmlin->documentElement
        if $xmlin->isa('XML::LibXML::Document');

    my $local = $xmlin->localName;
    return $self->faultNotSoapMessage(type_of_node $xmlin)
        if $local ne 'Envelope';

    my $envns = $xmlin->namespaceURI || '';
    my $version
      = $envns eq SOAP11ENV ? 'SOAP11'
      : $envns eq SOAP12ENV ? 'SOAP12'
      : return $self->faultUnsupportedSoapVersion($envns);

    my $info  = XML::Compile::SOAP->messageStructure($xmlin);
    $info->{soap_version} = $version;

    my $handlers = $self->{$version} || {};

    keys %$handlers;  # reset each!
    while(my ($name, $handler) = each %$handlers)
    {
        my $xmlout = $handler->($name, $xmlin, $info);
        defined $xmlout or next;

        trace "call $version $name";
        return $self->acceptResponse($request, $xmlout);
    }

    my $bodyel = $info->{body}[0] || '(none)';
    my @other  = sort grep {$_ ne $version && keys %{$self->{$_}}}
        $self->soapVersions;

    return $self->faultTryOtherProtocol($version, $bodyel, \@other)
        if @other;

    my @available = sort keys %$handlers;
    $self->faultMessageNotRecognized($version, $bodyel, \@available);
}


sub operationsFromWSDL($@)
{   my ($self, $wsdl, %args) = @_;
    my $callbacks = $args{callbacks} || {};
    my %names;

    my $default = $args{default_callback}
               || sub {$self->faultNotImplemented(@_)};

    foreach my $version ($self->soapVersions)
    {   $self->isSupportedVersion($version) or next;

        my $soap = "XML::Compile::${version}::Server"
           ->new(schemas => $wsdl->schemas);

        my @ops  = $wsdl->operations(produce => 'OBJECTS', soap => $soap);
        unless(@ops)
        {   info __x"no operations for {soap}; skipped", soap => $version;
            next;
        }

        foreach my $op (@ops)
        {   my $name = $op->name;
            $names{$name}++;
            my $callback = $callbacks->{$name} || $default;
            my $has_callback = defined $callbacks->{$name};

            ref $callback eq 'CODE'
                or error __x"callback {name} must provide a CODE ref"
                     , name => $name;

            my $code = $op->compileHandler
              ( soap     => $soap
              , callback => $callback
              );

            if($has_callback)
            {   trace __x"add handler for {soap} named {name}"
                  , soap => $version, name => $name;
            }
            else
            {   trace __x"add stub handler for {soap} named {name}"
                  , soap => $version, name => $name;
            }

            $self->addHandler($name, $version, $code);
        }

        info __x"added {nr} operations for {soap} from WSDL"
          , nr => scalar @ops, soap => $version;
    }

    # the same handler can be used for different soap versions, so we
    # should not complain too early.
    delete $callbacks->{$_} for keys %names;
    error __x"no port with name {names}", names => keys %$callbacks
        if keys %$callbacks;
}


sub addHandler($$$)
{   my ($self, $name, $soap, $code) = @_;

    my $version = ref $soap ? $soap->version : $soap;
    $self->{$version}{$name} = $code;
}


sub handlers($)
{   my ($self, $soap) = @_;
    my $version = ref $soap ? $soap->version : $soap;
    my $table   = $self->{$version} || {};
    keys %$table;
}


sub soapVersions() { qw/SOAP11 SOAP12/ }


sub inputToXML($$$)
{   my ($self, $client, $action, $strref) = @_;

    my $input = try { $parser->parse_string($$strref) };
    if($@ || !$input)
    {   info __x"request from {client}, {action} parse error: {msg}"
           , client => $client, action => $action, msg => $@;
        return undef;
    }

    $input;
}



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


sub faultNotSoapMessage($)
{   my ($self, $type) = @_;

    my $text =
        __x"The message was XML, but not SOAP; not an Envelope but `{type}'"
      , type => $type;

    $self->soapFault
      ( 'SOAP11'
      , XML::Compile::SOAP11::Server->faultMessageNotRecognized($text)
      , RC_BAD_GATEWAY
      , 'message not SOAP'
      );
}


sub faultUnsupportedSoapVersion($)
{   my ($self, $envns) = @_;

    my $text =
        __x"The soap version `{envns}' is not supported"
      , envns => $envns;

    $self->soapFault
      ( 'SOAP11'
      , XML::Compile::SOAP11::Server->faultUnsupportedSoapVersion($text)
      , RC_BAD_GATEWAY
      , 'SOAP version not supported'
      );
}


sub acceptResponse($) { $_[2] }


sub soapFault($$$$)
{   my ($self, $version, $data, $rc, $abstract) = @_;
    my $writer = $faultWriter{$version}
        or panic "soapFault no writer for $version";
    $writer->($data);
}


sub faultMessageNotRecognized($$$)
{   my ($self, $version, $name, $handlers) = @_;

    my $text =
       __x "{version} body element {name} not recognized, available are {def}"
        , version => $version, name => $name, def => $handlers;

    $self->soapFault
      ( $version,
      , "XML::Compile::${version}::Server"->faultMessageNotRecognized($text)
      , RC_NOT_IMPLEMENTED
      , 'message not recognized'
      );
}


sub faultTryOtherProtocol($$$)
{   my ($self, $version, $name, $other) = @_;

    my $text =
      __x"body element {name} not available in {version}, try {other}"
        , name => $name, version => $version, other => $other;

    $self->soapFault
      ( $version,
      , "XML::Compile::${version}::Server"->faultTryOtherProtocol($text)
      , RC_SEE_OTHER
      , 'SOAP protocol not in use'
      );
}


sub faultNotImplemented($$$)
{   my ($self, $name, $xml, $info) = @_;
    my $version = $info->{soap_version};

    my $text =
      __x"procedure {name} for {version} is not yet implemented"
        , name => $name, version => $version;

    $self->soapFault
      ( $version,
      , "XML::Compile::${version}::Server"->faultNotImplemented($text)
      , RC_NOT_IMPLEMENTED
      , 'procedure stub called'
      );
}


1;
