#!/usr/bin/perl
use strict;
use IO::Socket::INET;
use Cwd 'abs_path';
use POSIX;

# Minimal web server displaying the Vario tariffs graph with a date picker.
# Usage: ./vario_web.pl [port] [address]    (default: 8080 127.0.0.1)
# Serves vario.html on / and proxies /api?date=YYYY-MM-DD to the official V2 API,
# which sends no CORS header and thus cannot be called directly from the browser.

$ENV{TZ} = 'Europe/Zurich';
tzset();
$SIG{CHLD} = 'IGNORE';

my $ScriptDir = abs_path($0);
$ScriptDir =~ s{/\w+\.pl$}{};
chdir $ScriptDir or die $!;

my $port = $ARGV[0] || 8080;
my $addr = $ARGV[1] || '127.0.0.1';
my $server = IO::Socket::INET->new(LocalAddr => $addr, LocalPort => $port, Listen => 10, ReuseAddr => 1)
	or die "Cannot listen on $addr:$port: $!";
print "Vario graph on http://$addr:$port/\n";

# Local midnight of a date, as ISO 8601 with UTC offset (+02:00 or +01:00)
sub iso_midnight
{
	my ($y, $m, $d) = @_;
	my $t = mktime(0, 0, 0, $d, $m - 1, $y - 1900, 0, 0, -1);
	my $s = strftime("%Y-%m-%dT%H:%M:%S%z", localtime $t);
	$s =~ s/(\d\d)$/:$1/;
	$s =~ s/\+/%2B/;
	return $s;
}

sub reply
{
	my ($client, $status, $type, $body) = @_;
	print $client "HTTP/1.0 $status\r\nContent-Type: $type\r\nContent-Length: " . length($body) .
		"\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n$body";
}

sub handle
{
	my $client = shift;
	my $request = <$client>;
	while(my $line = <$client>)
		{ last if $line =~ /^\r?\n$/; }
	my ($method, $path) = $request =~ m{^(\w+) (\S+)};
	return reply($client, '405 Method Not Allowed', 'text/plain', "Method not allowed\n") unless $method eq 'GET';

	if($path =~ m{^/(index\.html)?(\?.*)?$})
	{
		open my $in, '<:raw', 'vario.html' or return reply($client, '500 Internal Server Error', 'text/plain', "vario.html missing\n");
		local $/;
		return reply($client, '200 OK', 'text/html; charset=utf-8', <$in>);
	}
	if(my ($y, $m, $d) = $path =~ m{^/api\?date=(\d{4})-(\d\d)-(\d\d)$})
	{
		my $start = iso_midnight($y, $m, $d);
		my $end = iso_midnight($y, $m, $d + 1);
		my $data = `curl -s -f 'https://api.tariffs.groupe-e.ch/v2/tariffs?start_timestamp=$start&end_timestamp=$end'`;
		return reply($client, '502 Bad Gateway', 'text/plain', "Tariffs API request failed\n") if $?;
		return reply($client, '200 OK', 'application/json', $data);
	}
	reply($client, '404 Not Found', 'text/plain', "Not found\n");
}

while(my $client = $server->accept)
{
	my $pid = fork;
	if(defined $pid && $pid == 0)
	{
		$server->close;
		handle($client);
		$client->close;
		exit 0;
	}
	$client->close;
}
