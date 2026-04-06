#!/usr/bin/perl
use strict;
use JSON;
use Data::Dumper;

my $date = $ARGV[0];
my $data = `curl -s "https://www.groupe-e.ch/fr/api/vario/${date}T"` or die;
my $json = decode_json($data);
my @data = @{$json->{data}};
die unless @data == 97;
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

system "octave --eval \"vario('$date')\" 2>/dev/null";
system "mail -s 'Vario $date' -A $date.txt -A $date.png patrick\@airnavigation.aero  < $date.txt"
#print Dumper(\@data);