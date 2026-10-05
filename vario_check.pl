#!/usr/bin/perl
use strict;
use JSON;
use Data::Dumper;
use MIME::Base64;
use Cwd 'abs_path';
use POSIX;
 
# List of required dependencies on APT (at a minimum):
# sudo apt install fonts-freefont-otf ghostscript gnuplot octave

# Uses the official V2 API (the www.groupe-e.ch/fr/api/vario URL is now behind a Cloudflare CAPTCHA).
# Next day data is published around 14h50.
# https://groupeeapimanagement.developer.azure-api.net/api-details#api=tariffapiapp-func-prod&operation=tariffs

$ENV{TZ} = 'Europe/Zurich';
tzset();

my $ScriptDir = abs_path($0);
$ScriptDir =~ s{/\w+\.pl$}{};
chdir $ScriptDir or die $!;

my $date = $ARGV[0];
if($date eq "")
{
	$date = strftime("%Y-%m-%d", localtime (time + 86400));
}
open IN, "lastdate.txt";
my $lastDate = <IN>;
exit 1 if $lastDate eq $date;

# Local midnight of $date and of the next day, as ISO 8601 with UTC offset (+02:00 or +01:00)
sub iso_midnight
{
	my ($y, $m, $d) = @_;
	my $t = mktime(0, 0, 0, $d, $m - 1, $y - 1900, 0, 0, -1);
	my $s = strftime("%Y-%m-%dT%H:%M:%S%z", localtime $t);
	$s =~ s/(\d\d)$/:$1/;
	$s =~ s/\+/%2B/;
	return $s;
}
my ($y, $m, $d) = $date =~ /^(\d{4})-(\d\d)-(\d\d)$/ or die "Bad date $date";
my $start = iso_midnight($y, $m, $d);
my $end = iso_midnight($y, $m, $d + 1);
my $url = "https://api.tariffs.groupe-e.ch/v2/tariffs?start_timestamp=$start&end_timestamp=$end";
my $data = `curl -s -f '$url'`;
die "curl failed: $?" if $?;
my $json = decode_json($data);
my @data = @{$json->{prices}};
#print Dumper(\@data);
my $cnt = @data;
die "Expected 96 prices, got $cnt (not yet published, or DST change day)\n" unless $cnt == 96;

# DT Plus (double tariff) is not in the API: fixed price, low from 23h to 7h and from 12h to 17h
sub dt_plus
{
	my $h = shift;
	return ($h >= 7 && $h < 12) || ($h >= 17 && $h < 23) ? 29.32 : 19.27;
}

open OUT, ">$date.dat";
for my $i(@data)
{
	if($i->{start_timestamp} =~ /${date}T(\d\d):(\d\d)+/)
	{
		my $h = $1 + $2 / 60;
		printf OUT "%g\t%g\t%g\t%g\n", $h, 100 * $i->{integrated}[0]{value}, 100 * $i->{grid}[0]{value}, dt_plus($h);
	}
	else
		{ die; }
}
close OUT;
system "octave --eval \"vario('$date')\" 2>/dev/null";

open IN, "$date.txt" or die;
$_ = <IN>;
my @a = split;
open OUT, ">$date.mail";
print OUT << "_END_";
--boundary-separator
Content-Type: text/html; charset="utf-8"

<html>
<head><title>Rapport Vario du $date</title></head>
<body>
<h1>Rapport Vario du $date</h1>

<table>
<tr><td>Prix minimal</td><td><b>$a[0]</b> ct / kWh</td><td>à <b>$a[1]</b></td></tr>
<tr><td>Prix maximal</td><td><b>$a[2]</b> ct / kWh</td><td>à <b>$a[3]</b></td></tr>
<tr><td>Prix moyen</td><td><b>$a[4]</b> ct / kWh</td></tr>
</table>

<br>
<table>
_END_

while(<IN>)
{
	@a = split;
	print OUT "<tr><td>De <b>$a[0]</b></td><td>à <b>$a[1]</b>:</td><td>moyenne <b>$a[2]</b> ct / kWh</td></tr>\n";
}
print OUT << "_END_";
</table> <br>
<IMG SRC="cid:airnavigation.aero" ALT="graphique">
</body>
</html>

--boundary-separator
Content-Location: CID:somethingatelse ; this header is disregarded
Content-ID: <airnavigation.aero>
Content-Type: IMAGE/PNG
Content-Transfer-Encoding: BASE64

_END_
undef $/;
open IN, "$date.png";
$_ = <IN>;
print OUT encode_base64($_);

print OUT "\n--boundary-separator--\n";

my $email = 'patrick@airnavigation.aero';
#my $email = 'rapin.patrick@gmail.com';

# ssmtp adds no Message-ID, and Gmail rejects messages without one
my $msgid = "<vario-$date-" . time . ".$$\@airnavigation.aero>";
system "cat $date.mail  | mail -a 'Message-ID: $msgid' -a 'From: Vario <patrick\@airnavigation.aero>' -s 'Rapport Vario du $date' $email --content-type='multipart/related;boundary=\"boundary-separator\";type=\"text/html\"'";
system "rm $date.*";
open OUT, ">lastdate.txt";
print OUT $date;
