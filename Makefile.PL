use ExtUtils::MakeMaker;

use 5.008;

WriteMakefile
 ( NAME	 	=> 'XML::Compile::SOAP::Daemon'
 , VERSION	=> '0.10'
 , PREREQ_PM    =>
   { XML::Compile       => 0.55
   , XML::Compile::SOAP => 0.56
   , Log::Report     => 0.15
   , LWP             => 5.803
   , Time::HiRes     => 0
   , Net::Server     => 0.97

   , Test::More      => 0.54
   , Test::Deep      => 0.095
   , Test::Pod       => 1.00
   }
 , AUTHOR       => 'Mark Overmeer'
 , ABSTRACT     => 'Daemon handling XML-SOAP'
 , LICENSE      => 'perl'
 );

### used by oodist during production of distribution
sub MY::postamble { <<'__POSTAMBLE' }

# for DIST
RAWDIR          = ../public_html/xml-compile-soap/raw
DISTDIR         = ../public_html/xml-compile-soap/source
LICENSE         = artistic

# for POD
EXTENDS		= ../XMLCompile:../XMLSOAP
FIRST_YEAR      = 2007
EMAIL           = perl@overmeer.net
WEBSITE         = http://perl.overmeer.net/xml-compile/
__POSTAMBLE
