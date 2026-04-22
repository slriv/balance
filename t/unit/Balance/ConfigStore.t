use v5.38;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use lib 'lib';
use Balance::ConfigStore;

# Test ConfigStore module

subtest 'ConfigStore initialization' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    ok($store, 'ConfigStore created');
    ok(-f $db_path, 'Database file created');
};

subtest 'ConfigStore set and get' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    $store->set('test_key', 'test_value');
    my $value = $store->get('test_key');
    is($value, 'test_value', 'Value retrieved correctly');
};

subtest 'ConfigStore get nonexistent key' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    my $value = $store->get('nonexistent');
    ok(!defined $value, 'Nonexistent key returns undef');
};

subtest 'ConfigStore set_bulk' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    my $values = {
        key1 => 'value1',
        key2 => 'value2',
        key3 => 'value3',
    };
    
    $store->set_bulk($values);
    
    is($store->get('key1'), 'value1', 'key1 set correctly');
    is($store->get('key2'), 'value2', 'key2 set correctly');
    is($store->get('key3'), 'value3', 'key3 set correctly');
};

subtest 'ConfigStore get_all' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    $store->set_bulk({
        alpha => 'a',
        beta => 'b',
        gamma => 'c',
    });
    
    my $all = $store->get_all;
    is($all->{alpha}, 'a', 'alpha retrieved from get_all');
    is($all->{beta}, 'b', 'beta retrieved from get_all');
    is($all->{gamma}, 'c', 'gamma retrieved from get_all');
};

subtest 'ConfigStore delete' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    $store->set('to_delete', 'value');
    is($store->get('to_delete'), 'value', 'Key exists');
    
    $store->delete('to_delete');
    ok(!defined $store->get('to_delete'), 'Key deleted');
};

subtest 'ConfigStore update existing key' => sub {
    my $tempdir = tempdir(CLEANUP => 1);
    my $db_path = File::Spec->catfile($tempdir, 'config.db');
    
    my $store = Balance::ConfigStore->new(db_path => $db_path);
    
    $store->set('key', 'value1');
    is($store->get('key'), 'value1', 'Initial value set');
    
    $store->set('key', 'value2');
    is($store->get('key'), 'value2', 'Value updated');
};

done_testing();
