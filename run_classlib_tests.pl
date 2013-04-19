use Cwd;
use Cwd 'abs_path';
use Getopt::Long;

system("source","~/.profile");
print "My Path: $ENV{PATH}\n";

my $root = getcwd();
my $monoroot = abs_path($root."/../Mono");
$monoroot = abs_path($root."/../mono") unless (-d $monoroot);
die ("Cannot find mono checkout in ../Mono or ../mono") unless (-d $monoroot);
print "Mono checkout found in $monoroot\n\n";

my $teamcity = 0;

if ($ENV{UNITY_THISISABUILDMACHINE}) {
	$teamcity = 1;
}

#do build

@testdirs = ('corlib','System', 'System.Xml', 'System.Core');

foreach (@testdirs)
{
	chdir("$monoroot/mcs/class/" . $_) eq 1 or die("failed to chdir " . $_);

	my $result = 0;
	if($^O eq 'MSWin32') {
		$result = system("msbuild build.proj /t:Test");
	} else {
		$result = system("make run-test-local");
	}

	if ($teamcity) {
		print("##teamcity[importData type='nunit' path='mcs/class/". $_ . "/TestResult-net_2_0.xml']\n");
	}
}
#$result eq 0 or die ("Failed running mono classlib tests");
