use v5.38;
use Test::More;
use FindBin qw($Bin);

my $script = "$Bin/../../../bin/balance";
my $prefix = '/__balance_missing_mount_prefix__';

my $output = qx{$^X -I$Bin/../../../lib $script 2>&1};
my $exit_code = $? >> 8;

isnt($exit_code, 0, 'script exits non-zero when no mounts are provided');
like($output, qr/balance starting: perl /, 'startup banner still shown');
like($output, qr/FATAL: At least two mounts must be provided via --mount=\/path\n/, 'clean fatal message is shown');
like($output, qr/--mount=\/path/, 'fatal message includes explicit mount guidance');
unlike($output, qr/main::__ANON__/, 'fatal output does not include Perl stack trace frames');
unlike($output, qr/called at /, 'fatal output does not include confess stack trace');

done_testing();