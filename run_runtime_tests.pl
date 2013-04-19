use Cwd;
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
chdir("$monoroot/mono/tests") eq 1 or die("failed to chdir tests");
if ($teamcity) {
	print("##teamcity[testSuiteStarted name='mono runtime tests']\n");
}
my $result = 0;
if($^O eq 'MSWin32') {
	$result = system("msbuild build.proj /t:Test");
} else {
	$result = system("make test");
}
if ($teamcity) {
	print("##teamcity[testSuiteFinished name='mono runtime tests']\n");
}
$result eq 0 or die ("Failed running mono runtime tests");
