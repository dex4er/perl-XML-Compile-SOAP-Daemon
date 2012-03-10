use ExtUtils::MakeMaker;

use 5.008;

my $version = '3.03';

my %prereq =
  ( XML::Compile         => 1.24
  , XML::Compile::SOAP   => 2.26
  , XML::Compile::Tester => 0.05
  , XML::Compile::Cache  => 0.991

  , Log::Report     => 0.90
  , Time::HiRes     => 0
  , Test::More      => 0.54

# Only needed when ::Daemon::NetServer is being used
# , Net::Server     => 0.97
# , HTTP::Daemon    => 6.0
# , HTTP::Message   => 6.0

# Only needed when ::Daemon::AnyDaemon is being used
# , Any::Daemon     => 0.13
# , HTTP::Daemon    => 6.0
# , HTTP::Message   => 6.0

# Only needed when SSL is used
# , IO::Socket::SSL   => 0
# , HTTP::Daemon::SSL => 1.04
  );

# only update WSA if installed
eval "require XML::Compile::SOAP::WSA";
unless($@)
{   my $v = $XML::Compile::SOAP::WSA::VERSION || '';
    $prereq{'XML::Compile::SOAP::WSA'} = 0.12;
}

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP::Daemon'
 , VERSION	=> $version
 , PREREQ_PM    => \%prereq
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Daemon handling XML-SOAP'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile-soap-daemon/raw
DISTDIR         = ../public_html/xml-compile-soap-daemon/source
LICENSE         = artistic
SKIP_LINKS	= XML::LibXML

# for POD
EXTENDS		= ../XMLCompile:../XMLSOAP:../XMLTester:../XMLCache
FIRST_YEAR      = 2007
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/
PODTAIL		= ../XML-shared-podtail
__POSTAMBLE
