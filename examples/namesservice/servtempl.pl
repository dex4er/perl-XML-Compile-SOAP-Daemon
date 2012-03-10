#!/usr/bin/perl
# See ./server.pl for a detailed example and explanation.

use warnings;
use strict;

use XML::Compile::SOAP::HTTPDaemon;
use XML::Compile::WSDL11;

use Log::Report   'example', syntax => 'SHORT';
use Getopt::Long  qw/:config no_ignore_case bundling/;
use List::Util    qw/first/;
use Data::Dumper;          # Data::Dumper is your friend.
$Data::Dumper::Indent = 1;

# Configuration
use constant SERVERNAME => 'my-first-server v0.1';
use constant SERVERHOST => 'localhost';
use constant SERVERPORT => '8877';

my @schemas = ('namesservice.wsdl', 'namesservice.xsd');

# Forward declarations

##
#### MAIN
##

my $mode = 0;

GetOptions
   'v+'        => \$mode  # -v -vv -vvv
 , 'verbose=i' => \$mode  # --verbose=2  (0..3)
 , 'mode=s'    => \$mode  # --mode=DEBUG (DEBUG,ASSERT,VERBOSE,NORMAL)
   or die "Deamon is not started";

dispatcher PERL => 'default', mode => $mode;

error __x"No filenames expected on the command-line"
   if @ARGV;

my $daemon = XML::Compile::SOAP::HTTPDaemon->new;

my $wsdl   = XML::Compile::WSDL11->new;
$wsdl->importDefinitions($_) for @schemas;

my %callbacks = ();

$daemon->operationsFromWSDL($wsdl, callbacks => \%callbacks);

dispatcher SYSLOG => 'default', mode => $mode;

$daemon->run
 ( name    => SERVERNAME
 , port    => SERVERPORT
 );

info "Daemon stopped\n";
exit 0;

### implement your callbacks here

1;
