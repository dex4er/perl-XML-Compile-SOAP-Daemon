# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

# test environment at home: unpublished XML::Compile
use lib '../XMLCompile/lib';
use lib '../XMLSOAP/lib';
use lib '../XMLTester/lib';
use lib '../LogReport/lib';

package TestTools;
use vars '$VERSION';
$VERSION = '0.12';

use base 'Exporter';

our @EXPORT = qw/
 /;

our $TestNS   = 'http://test-types';