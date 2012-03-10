#!/usr/bin/perl
# Framework for a Daemon based on Any::Daemon

use warnings;
use strict;

my $VERSION = "0.01";

use Log::Report   'otm'; #, mode => 3;

use XML::Compile::SOAP::Daemon::AnyDaemon;
use XML::Compile::WSDL11;
use XML::Compile::SOAP11;
use XML::Compile::Util    qw/pack_type/;

use Getopt::Long   qw/:config no_ignore_case bundling/;
use List::Util     qw/first/;
use File::Basename qw/basename/;
use HTTP::Status   qw/:constants/;

use Data::Dumper;          # Data::Dumper is your friend.
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

my $wsdl_fn = ('my.wsdl');
my @schemas = ('my1.xsd', 'my2.xsd');

my $my_err_ns = 'https://example.com/err';
use constant MY_ROLE => 'NEXT';

# Forward declarations
sub getInfo($$$);
sub failed_authorization();
sub error_unauthorized($);

##
#### MAIN
##

my $mode = 2;
#my $port = '4444/SSLEAY';
my $port = '4444';
my $host = '127.0.0.1';
my ($live, $test) = (0, 0);

GetOptions
   'v+'        => \$mode  # -v -vv -vvv
 , 'verbose=i' => \$mode  # --verbose=2  (0..3)
 , 'port|p=i'  => \$port  # --port=444
 , 'host|h=s'  => \$host  # --host=localhost
 , 'mode=s'    => \$mode  # --mode=DEBUG (DEBUG,ASSERT,VERBOSE,NORMAL)
 , 'live!'     => \$live
 , 'test!'     => \$test
   or error "Deamon is not started";

error __x"No filenames expected on the command-line"
    if @ARGV;

$live || $test
   or error "you must either specify --test or --live";

my $debug     = $mode==3;

# in the header of the reply
my $my_serv   =
 { server =>
    { software => [ "DEMO v$VERSION".($live ? '' : ' TEST!') ]
    , created  => time
    }
 };

# in preparation, use standard Perl output in $mode
dispatcher PERL => 'default', mode => $mode;

my $daemon = XML::Compile::SOAP::Daemon::AnyDaemon->new;

my $wsdl   = XML::Compile::WSDL11->new($wsdl_fn);
$wsdl->importDefinitions(\@schemas);
$wsdl->addKeyRewrite('UNDERSCORES');   # '-' in schema becoms '_' in Perl
$wsdl->prefixes(err => $my_err_ns);
$wsdl->prefixFor($my_err_ns);  # count it

my %callbacks =
 (  getInfo   => \&getInfo
 , ...
 );

$daemon->operationsFromWSDL
  ( $wsdl
  , callbacks => \%callbacks

# When you have multiple services in the WSDL
# , service   => ($live ? 'SERVICE' : 'SERVICE-test')
  );

$daemon->setWsdlResponse($wsdl_fn);

dispatcher SYSLOG => 'syslog', mode => $mode;
dispatcher close  => 'default';   # close errors to stdout

# start the database connection, when the DB-type does survive forks.
# otherwise, you need to 


# now start the daemon to handle requests
info __x"starting daemon in {envir} environment"
  , envir => ($live ? 'live' : 'test');

$daemon->run
 ( name => basename($0)
 , host => $host
 , port => $port
 , max_childs => 1
 );

info "Daemon stopped";
exit 0;

### implement your callbacks here

sub getInfo($$$)
{   my ($server, $in, $request) = @_;

    if($debug && open OUT, '>', '/tmp/getinfo')
    {   print OUT Dumper $in;
        close OUT;
    }

    return error_unauthorized 'someone'
        if failed_authorization;

    # change "response" into the name of the message part in the WSDL,
    # often "parameters"
    +{ response => $data };
}

sub failed_authorization() {0};

#
### return errors
#

sub error_unauthorized($)
{   my $name = shift;
    +{ Fault =>
        { faultcode   => pack_type($my_err_ns, 'Client.Unauthorized')
        , faultstring => "failed secure code for $name"
        , faultactor  => MY_ROLE
        }
     , _RETURN_CODE => HTTP_UNAUTHORIZED        # 401
     , _RETURN_TEXT => 'Unauthorized'
     };
}
