package Munin::Node::ProxySpooler;

# $Id$

use strict;
use warnings;

use Net::Server::Daemonize qw( daemonize );
use IO::Socket;
use Carp;

use Munin::Common::Defaults;
use Munin::Node::Logger;
use Munin::Node::SpoolWriter;


sub new
{
    my ($class, %args) = @_;

    $args{spooldir} ||= $Munin::Common::Defaults::MUNIN_SPOOLDIR;

    $args{spool} = Munin::Node::SpoolWriter->new(spooldir => $args{spooldir});

    # don't want to run as root unless absolutely necessary.  but only root
    # can change user
    #
    # FIXME: these will need changing to root/root as and when it starts
    # running plugins
    $args{user}  = $< || $Munin::Common::Defaults::MUNIN_PLUGINUSER;
    $args{group} = $( || $Munin::Common::Defaults::MUNIN_GROUP;

    # FIXME: should get the host and port from munin-node.conf
    $args{host} ||= 'localhost';
    $args{port} ||= '4949';

    return bless \%args, $class;
}


sub run
{
    my ($class, %args) = @_;

    my $self = __PACKAGE__->new(%args);

    # Daemonzises, and runs for cover.
    daemonize($self->{user}, $self->{group}, $self->{pidfile});

    open STDERR, '>>', "$Munin::Common::Defaults::MUNIN_LOGDIR/munin-sched.log";
    STDERR->autoflush(1);
    # FIXME: reopen logfile on SIGHUP

    # ready to actually do stuff!
#    my $intervals = $self->_get_intervals();
#    $self->_launch_pollers($intervals);

    logger('Spooler going to sleep');
    # FIXME: may need to respawn pollers if they fall over
    sleep;

    logger('Spooler shutting down');
    exit 0;
}


### SETUP ######################################################################

# takes the config response for the service, and returns the correct interval
sub _service_interval { /^update_rate (\d+)/ && return $1 foreach @_; return 300; }


### NODE INTERACTION ###########################################################

# returns an open IO::Socket to the node, ready for reading.
sub _open_node_connection
{
    my ($self) = @_;

    logger("Opening connection to $self->{host}:$self->{port}");

    my $socket = IO::Socket::INET->new(
        PeerAddress => $self->{host},
        PeerPort    => $self->{port},
        Proto       => 'tcp',
    ) or die "Failed to connect to node: $!\n";

    # FIXME: this REALLY shouldn't be required, but for some reason the socket
    # isn't being connect()ed
    $socket->connect($self->{port}, inet_aton($self->{host}))
        or die "Failed to connect to node: $!\n";

    $self->{socket} = $socket;

    my $line = $self->_read_line or die "Failed to read banner\n";

    die "Service is not a Munin node (responded with '$line')\n"
        unless ($line =~ /^# munin node at /);

    # report capabilities to unlock all the special services
    $line = $self->_talk_to_node('cap multigraph dirtyconfig')
        or die "Failed to read node capabilities\n";

    return;
}


# print $command to the node on $socket, and return the response.  if
# $multiline is true, handle multiline responses
#
# FIXME:  work out whether it should be multiline based based on the value of
# $command
sub _talk_to_node
{
    my ($self, $command, $multiline) = @_;

    croak "multiline means scalar context" if $multiline and not wantarray;

    my $socket = $self->{socket};

    $self->_write_line($command);
    my @response = ($multiline) ? $self->_read_multiline() : $self->_read_line();

    return wantarray ? @response : shift @response;
}


# write a single line to the node
sub _write_line
{
    my ($self, $command) = @_;

    logger("DEBUG: > $command");
    $self->{socket}->print($command, "\n") or die "Write error to socket: $!\n";

    return;
}


# read a single line from the node
sub _read_line
{
    my ($self) = @_;

    my $line = $self->{socket}->getline;
    defined($line) or die "Read error from socket: $!\n";
    chomp $line;
    logger("DEBUG: < $line");

    return $line;
}


# read a multiline response from the node  (ie. up to but not including the
# '.' line at the end.
sub _read_multiline
{
    my ($self) = @_;
    my ($line, @response);

    push @response, $line until ($line = $self->_read_line) eq '.';

    return @response;
}


1;

__END__

=head1 NAME

Munin::Node::ProxySpooler - Daemon to gather spool information by querying a
munin-node instance.

=head1 SYNOPSIS

  Munin::Node::ProxySpooler->run(%args);

=head1 METHODS

=over 4

=head2 B<run(%args)>

Forks off a spooler daemon, and returns control to the caller.  'spooldir' key
should be the directory to write to.

=back

=cut

# vim: sw=4 : ts=4 : et