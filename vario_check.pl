#!/usr/bin/perl
use strict;
use JSON;
use Data::Dumper;
use MIME::Base64;
use Cwd 'abs_path';
use POSIX;
 
# List of required dependencies on APT (at a minimum):
# sudo apt install fonts-freefont-otf ghostscript gnuplot octave

# This is URL of official V2 API. But apparently it is impossible to have data for the next day.
# https://groupeeapimanagement.developer.azure-api.net/api-details#api=tariffapiapp-func-prod&operation=tariffs
 
my $ScriptDir = abs_path($0);
$ScriptDir =~ s{/\w+\.pl$}{};
chdir $ScriptDir or dir $!;

my $date = $ARGV[0];
if($date eq "")
{
	$date = strftime("%Y-%m-%d", localtime (time + 86400));
}
open IN, "lastdate.txt";
my $lastDate = <IN>;
exit 1 if $lastDate eq $date;
my $url = "https://www.groupe-e.ch/fr/api/vario/${date}A";
my $data = `curl -s $url or die`;
my $json = decode_json($data);
my @data = @{$json->{data}};
#print Dumper(\@data);
my $cnt = @data;
die $cnt unless $cnt == 97;
shift @data; # The first item is 23h45-0h00, annoying to handle
open OUT, ">$date.dat";
for my $i(@data)
{
	if($i->{start_timestamp} =~ /${date}T(\d\d):(\d\d)+/)
	{ 
		printf OUT "%g\t%g\t%g\t%g\n", $1 + $2 / 60, $i->{vario_plus}, $i->{vario_grid}, $i->{dt_plus};
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

system "cat $date.mail  | mail -s 'Rapport Vario du $date' $email --content-type='multipart/related;boundary=\"boundary-separator\";type=\"text/html\"'";
system "rm $date.*";
open OUT, ">lastdate.txt";
print OUT $date;
