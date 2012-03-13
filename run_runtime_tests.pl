use File::Spec;
use File::Basename;
use File::Copy;
use File::Path;

my $root = File::Spec->rel2abs( dirname($0) );
my $monoroot = File::Spec->rel2abs( dirname($0) . "/../mono" );

my $teamcity = 0;

if ($ENV{UNITY_THISISABUILDMACHINE}) {
	$teamcity = 1;
}

system("cp $root/test-driver $monoroot/mono/tests") eq 0 or die("failed copy test-driver");

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
