# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.04.
use warnings;
use strict;

# test environment at home: unpublished XML::Compile
use lib '../XMLCompile/lib', '../../XMLCompile/lib';
use lib '../XMLSOAP/lib', '../../XMLSOAP/lib';
use lib '../LogReport/lib', '../../LogReport/lib';

package TestTools;
use vars '$VERSION';
$VERSION = '0.10';
use base 'Exporter';

use XML::LibXML;
use Test::More;
use Test::Deep   qw/cmp_deeply/;

use POSIX        qw/_exit/;
use Log::Report  qw/try/;
use Data::Dumper qw/Dumper/;

our @EXPORT = qw/
 /;

our $TestNS   = 'http://test-types';
