# Copyrights 2007-2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
use warnings;
use strict;

package XML::Compile::SOAP::Daemon::CGI;
use vars '$VERSION';
$VERSION = '3.00';

use base 'XML::Compile::SOAP::Daemon';

our @ISA;

use Log::Report 'xml-compile-soap-daemon';
use CGI 3.50, ':cgi';


sub runCgiRequest(@) {shift->run(@_)}

# called by SUPER::run()
sub _run($)
{   my ($self, $args) = @_;

    my $q = CGI->new;

    my ($rc, $msg, $xmlout)
      = $self->process(\$query->param('POSTDATA'), $q, $ENV{soapAction});

    print $q->( -type  => 'text/xml'
              , -nph    => 1
              , -status => "$rc $msg"
              , -Content_length => length($xmlout)
              );

    print $xmlout;
}

#-----------------------------


1;
