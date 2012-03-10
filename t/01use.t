#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib', 't';
use Test::More tests => 2;
use TestTools;

# The versions of the following packages are reported to help understanding
# the environment in which the tests are run.  This is certainly not a
# full list of all installed modules.
my @show_versions =
 qw/Test::More
    XML::Compile
    XML::Compile::SOAP
    XML::LibXML
    Net::Server
    LWP
   /;

foreach my $package (@show_versions)
{   eval "require $package";

    no strict 'refs';
    my $report
      = !$@    ? "version ". (${"$package\::VERSION"} || 'unknown')
      : $@ =~ m/^Can't locate/ ? "not installed"
      : "reports error";

    warn "$package $report\n";
}

warn "libxml2 ".XML::LibXML::LIBXML_DOTTED_VERSION()."\n";

require_ok('XML::Compile::SOAP::Daemon');
require_ok('XML::Compile::SOAP::HTTPDaemon');
