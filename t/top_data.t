use warnings;
use strict;
use Test::More;

BEGIN {
    my $tests = 5;
    plan tests => $tests;
}

###########################################################
# test modules
unshift @INC, 'plugins/plugins-available/omd/lib';

SKIP: {
    skip 'external tests', 1 if defined $ENV{'PLACK_TEST_EXTERNALSERVER_URI'};

    use_ok('Thruk::OMD::Top::Parser::LinuxTop');
};

my $data_folder = $0;
$data_folder =~ s/\/[^\/]*$//mx;
$data_folder = $data_folder.'/data';
if($ARGV[0] && -d $ARGV[0]) {
    $data_folder = $ARGV[0].'/t/data';
}

ok(-d $data_folder) || BAIL_OUT("cannot test, datafolder error: $data_folder - $!");

###########################################################
test_file($data_folder.'/1421945063.debian6.txt', {
            'num'       => '149',
            'load1'     => '3.68',
            'load5'     => '3.34',
            'load15'    => '2.87',
            'cpu_us'    => '3.6',
            'cpu_sy'    => '3.1',
            'cpu_ni'    => '0.0',
            'cpu_id'    => '90.1',
            'cpu_wa'    => '2.9',
            'cpu_hi'    => '0.1',
            'cpu_si'    => '0.2',
            'cpu_st'    => '0.0',
            'mem'       => 1002,
            'mem_used'  => 987,
            'buffers'   => 2,
            'cached'    => 486,
            'swap'      => 2294,
            'swap_used' => 85,
            'procs'     => { 'other' => { 'cpu' => '103', 'num' => 3, 'mem' => '0.5', 'res' => 0, 'virt' => 0 } },
});

test_file($data_folder.'/1421945063.ubuntu14-04.txt', {
            'num'       => '404',
            'load1'     => '0.26',
            'load5'     => '0.35',
            'load15'    => '0.40',
            'cpu_us'    => '3.3',
            'cpu_sy'    => '1.3',
            'cpu_ni'    => '0.0',
            'cpu_id'    => '94.7',
            'cpu_wa'    => '0.6',
            'cpu_hi'    => '0.0',
            'cpu_si'    => '0.0',
            'cpu_st'    => '0.0',
            'mem_used'  => 7420,
            'mem'       => 7975,
            'buffers'   => 21,
            'cached'    => 555,
            'swap'      => 19338,
            'swap_used' => 784,
            'procs'     => { 'other' => { 'cpu' => '48.8', 'num' => 3, 'mem' => '6.6', 'res' => 0, 'virt' => 2 } },
});

test_file($data_folder.'/1421945063.rhel7.txt', {
            'num'       => '216',
            'load1'     => '0.55',
            'load5'     => '1.10',
            'load15'    => '0.91',
            'cpu_us'    => '4.1',
            'cpu_sy'    => '1.2',
            'cpu_ni'    => '0.0',
            'cpu_id'    => '94.3',
            'cpu_wa'    => '0.1',
            'cpu_hi'    => '0.0',
            'cpu_si'    => '0.3',
            'cpu_st'    => '0.0',
            'mem_used'  => 2541,
            'mem'       => 7806,
            'buffers'   => 1984,
            'swap'      => 2047,
            'swap_used' => 596,
            'procs'     => { 'other' => { 'cpu' => '156', 'num' => 9, 'mem' => '17.1', 'res' => 1016, 'virt' => 1 } },
});

###########################################################
sub test_file {
    my($file, $expected) = @_;
    `cat $file | gzip > $file.gz`;
    my $d = Thruk::OMD::Top::Parser::LinuxTop::_extract_top_data([$file.'.gz']);
    unlink($file.'.gz');
    my $data = $d->{(keys %{$d})[0]};
    delete $data->{'time'};
    is_deeply($data, $expected, $file);
}

###########################################################
# fake menu package
package Thruk::Utils::Menu;
use warnings;
use strict;

sub insert_item {};
