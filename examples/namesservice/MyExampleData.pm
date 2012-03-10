# Copyrights 2007-2008 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.05.
use warnings;
use strict;

package MyExampleData;
use vars '$VERSION';
$VERSION = '0.12';

use base 'Exporter';

our @EXPORT = qw/$namedb/;

our $namedb =
 { Netherlands =>
    {   male  => [ qw/Mark Tycho Thomas/ ]
    , female  => [ qw/Cleo Marjolein Suzanne/ ]
    }
 , Austria     =>
    {   male => [ qw/Thomas Samuel Josh/ ]
    , female => [ qw/Barbara Susi/ ]
    }
 ,German       =>
    {   male => [ qw/Leon Maximilian Lukas Felix Jonas/ ]
    , female => [ qw/Leonie Lea Laura Alina Emily/ ]
    }
 };

1;