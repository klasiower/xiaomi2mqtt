#!/usr/bin/env perl

use warnings;
use strict;
use IPC::Run;
use JSON;

use FindBin;
use lib "$FindBin::Bin/../extlib";
my $root = "$FindBin::Bin/../";

my $config = {
    gatttool_bin        =>  '/usr/bin/gatttool',
    gatt_timeout        => 15,
    use_reset           => 0,
    # hciconfig hci0 reset
    sudo_bin            => '/usr/bin/sudo',
    hciconfig_bin       => '/bin/hciconfig',
    hci_device          => 'hci0',
    hci_timeout         => 10,
    verbose             => 1,
    # export        => 'sensor:xiaomi2 values: battery:100 | fertility:1127 | light:4396 | moisture:61 | name:Flower care | temperature:312 | time:1533376650 | version:2.7.0'
    export              => [qw(mac battery fertility light moisture temperature time)],
    # munin_dir        => '/var/lib/munin/xiaomi/',
    use_munin           => 1,
    munin_dir           => './data/',
    sensor_file         => './data/sensors.txt',
    use_mqtt            => 1,
    mqtt_broker         => '192.168.0.22',
    mqtt_topic_prefix   => '/custom',
    mqtt_retain         => 1,
};

eval {
    local *F;
	my $file = $config->{sensor_file};
	unless ($file =~ m{^/}) {
		$file = sprintf('%s/%s', $root, $config->{sensor_file});
	}
    open F, '<', $file or die("Can't read sensor_file:$file ($!)");
    while (my $line = <F>) {
        chomp $line;
        next if $line =~ m{^ *#};
        my ($mac, $name) = split / +/, $line;
        $config->{sensor}{$name} = {
            use     =>  1,
            mac     =>  $mac,
            values  => { mac => $mac }
        }
    }
}; if ($@) {
    my ($e) = $@;  chomp $e;
    die($e);
};

# use Data::Dumper qw(Dumper); print Dumper($config); exit 0;

my $json = JSON->new();
use Net::MQTT::Simple;
my $mqtt = Net::MQTT::Simple->new($config->{mqtt_broker});

if ($config->{use_reset}) {
    hci_reset();
}
foreach my $sensor (sort keys %{ $config->{sensor} }) {

    if(! $config->{sensor}{$sensor}{use}) {
        $config->{verbose} && print STDERR "[DBG] skipping disabled sensor $sensor $config->{sensor}{$sensor}{mac}\n";
        next;
    }
    my $result = gatt_read($sensor, "0x03");

    sleep 1;

    $result = gatt_read($sensor, "0x03");
    if ($result) {
        # printf 'name:%s'."\n", unpack('A*', $result);
        $config->{sensor}{$sensor}{values}{name} = $result;
    } else {
        $config->{verbose} && print STDERR "[DBG] skipping sensor $sensor $config->{sensor}{$sensor}{mac}\n";
        next;
    }

    $result = gatt_read($sensor, "0x38");
    if ($result) {
        my @fields = unpack "CxA5", $result;
        # print 'Battery/Version: '.(join ',', @fields)."\n";
        $config->{sensor}{$sensor}{values}{battery} = $fields[0];
        $config->{sensor}{$sensor}{values}{version} = $fields[1];
    } else {
        $config->{verbose} && print STDERR "[DBG] skipping sensor $sensor $config->{sensor}{$sensor}{mac}\n";
    next;
    }

    gatt_write($sensor, "0x33", "A01F");

    $result = gatt_read($sensor, "0x35");
    if ($result) {
        # $config->{verbose} && print STDERR "[DBG] result:".(unpack "H*", $result)."\n";
        # result:aabbccddeeff99887766000000000000
        if ((unpack "H*", $result) eq 'aabbccddeeff99887766000000000000') {
            $config->{verbose} && print STDERR "[DBG] skipping result:".(unpack "H*", $result)."\n";
        } else {
            $config->{sensor}{$sensor}{values}{time} = time();
            my @fields = unpack "SxLCSx6", $result;
            # print 'Values: '.(join ',', @fields)."\n";
            $config->{sensor}{$sensor}{values}{temperature} = $fields[0] / 10;
            $config->{sensor}{$sensor}{values}{light}       = $fields[1];
            $config->{sensor}{$sensor}{values}{moisture}    = $fields[2] / 10;
            $config->{sensor}{$sensor}{values}{fertility}   = $fields[3];
        }
    }


    $config->{verbose} && printf 'sensor:%s values: %s'."\n",
        $sensor,
        (join ' | ',
            map { "$_:".($config->{sensor}{$sensor}{values}{$_} // '') }
                sort keys %{ $config->{sensor}{$sensor}{values} }
        )
    ;

    if ($config->{use_munin}) {
        my $path = $config->{munin_dir}.'/'.$sensor;
		unless ($path =~ m{^/}) {
			$path = sprintf('%s/%s/%s', $root, $config->{munin_dir}, $sensor);
		}
        eval {
            $SIG{__WARN__} = sub { die };
            local *F;
            open  F, '>', $path;
            print F $json->encode($config->{sensor}{$sensor}{values})."\n";
            close F;
        }; if ($@) {
            print STDERR sprintf('[ERR] writing file:%s (%s)'."\n", $path, $@)
        } else {
            $config->{verbose} && print STDERR sprintf('[DBG] wrote file:%s'."\n", $path)
        }
    }
    if ($config->{use_mqtt}) {
        my $topic = sprintf('%s/%s', $config->{mqtt_topic_prefix}, $sensor);
        if ($config->{mqtt_retain}) {
            $mqtt->retain ($topic, $json->encode($config->{sensor}{$sensor}{values}));
            $config->{verbose} && print STDERR sprintf('[DBG] mqtt_retain sensor:%s topic:%s broker:%s'."\n", $sensor, $topic, $config->{mqtt_broker});
        } else {
            $mqtt->publish($topic, $json->encode($config->{sensor}{$sensor}{values}));
            $config->{verbose} && print STDERR sprintf('[DBG] mqtt_publish sensor:%s topic:%s broker:%s'."\n", $sensor, $topic, $config->{mqtt_broker});
        }
    }
}

exit;

sub gatt_read {
    my ($sensor, $handle) = @_;

    my $cmd = [$config->{gatttool_bin}, "--adapter=$config->{hci_device}", "--device=$config->{sensor}{$sensor}{mac}", "--char-read", "-a", "$handle"];
    my ($in, $out, $err);

    eval {
        $config->{verbose} && print STDERR sprintf('[DBG][gatt_read] sensor:%s handle:%s cmd:(%s)', $sensor, $handle, "@$cmd")."\n";
        IPC::Run::run($cmd, \$in, \$out, \$err, IPC::Run::timeout($config->{gatt_timeout}));
    }; if ($@) {
        my ($e) = $@;  chomp $e;
        $config->{verbose} && print STDERR sprintf('[DBG][gatt_read] sensor:%s handle:%s IPC err:(%s) out:(%s) err:(%s)', $sensor, $handle, $e, $out // '', $err // '')."\n";
        return undef;
    }

    $out && chomp $out;
    $err && chomp $err;
    $config->{verbose} && print STDERR sprintf('[DBG][gatt_read] sensor:%s handle:%s out:(%s) err:(%s)', $sensor, $handle, $out // '', $err // '')."\n";
    my ($hex) = $out =~ m{Characteristic value/descriptor: (.*)$};

    unless ($hex) {
        $config->{verbose} && print STDERR sprintf('[ERR][gatt_read] command:(%s) failed:(%s) out:(%s)', (join ' ', @$cmd), $err // '', $out // '')."\n";
        return undef;
    }

    return
        pack "C*",
            map hex,
                split / /, $hex
    ;
}

sub gatt_write{
    my ($sensor, $handle, $value) = @_;

    my $cmd = [$config->{gatttool_bin}, "--adapter=$config->{hci_device}", "--device=$config->{sensor}{$sensor}{mac}", "--char-write-req", "--handle", "$handle", "--value=$value"];
    my ($in, $out, $err);

    eval {
        $config->{verbose} && print STDERR sprintf('[DBG][gatt_write] sensor:%s handle:%s cmd:(%s)', $sensor, $handle, "@$cmd")."\n";
        IPC::Run::run($cmd, \$in, \$out, \$err, IPC::Run::timeout($config->{gatt_timeout}));
    }; if ($@) {
        my ($e) = $@;  chomp $e;
        $config->{verbose} && print STDERR sprintf('[DBG][gatt_write] sensor:%s handle:%s IPC err:(%s) out:(%s) err:(%s)', $sensor, $handle, $e, $out // '', $err // '')."\n";
        return undef;
    }
    $out && chomp $out;
    $err && chomp $err;
    $config->{verbose} && print STDERR sprintf('[DBG][gatt_write] sensor:%s handle:%s out:(%s) err:(%s)', $sensor, $handle, $out // '', $err // '')."\n";
}

sub hci_reset {
    # hciconfig hci0 reset

    my $cmd = [$config->{sudo_bin}, $config->{hciconfig_bin}, $config->{hci_device}, 'reset'];
    my ($in, $out, $err);

    eval {
        $config->{verbose} && print STDERR sprintf('[DBG][hci_reset] cmd:(%s)', "@$cmd" // '')."\n";
        IPC::Run::run($cmd, \$in, \$out, \$err, IPC::Run::timeout($config->{hci_timeout}));
    }; if ($@) {
        my ($e) = $@;  chomp $e;
        $config->{verbose} && print STDERR sprintf('[DBG][hci_reset] IPC err:(%s) out:(%s) err:(%s)', $e, $out // '', $err // '')."\n";
        return undef;
    }
    $out && chomp $out;
    $err && chomp $err;
    $config->{verbose} && print STDERR sprintf('[DBG][hci_reset] out:(%s) err:(%s)', $out // '', $err // '')."\n";
}

__DATA__
# sudo hcitool lescan
# sudo hcitool leinfo "${MAC}"
# exit

echo -n "name of device: "
gatttool --device=${MAC} --char-read -a 0x03

echo -n "battery/version of device: "
gatttool --device=${MAC} --char-read -a 0x38

echo -n "initializing device: "
gatttool -b ${MAC} --char-write-req --handle=0x33 --value=A01F

echo -n "values of device: "
gatttool --device=${MAC} --char-read -a 0x35

# stringA=$(sudo gatttool -b ${MAC} --char-read --handle=0x35)
# stringT=${stringA:36:2}${stringA:33:2}
# stringT=$(echo "$stringT" | tr a-f A-F)
# stringT=$(echo "ibase=16; $stringT" | bc)
# echo perl /opt/fhem/fhem.pl 7072 "setreading Plant1 Temp $stringT"
# stringL=${stringA:45:2}${stringA:42:2}
# stringL=$(echo "$stringL" | tr a-f A-F)
# stringL=$(echo "ibase=16; $stringL" | bc)
# echo perl /opt/fhem/fhem.pl 7072 "setreading Plant1 Lux $stringL"
# stringM=${stringA:54:2}
# stringM=$(echo "$stringM" | tr a-f A-F)
# stringM=$(echo "ibase=16; $stringM" | bc)
# echo perl /opt/fhem/fhem.pl 7072 "setreading Plant1 Moisture $stringM"
# stringF=${stringA:60:2}${stringA:57:2}
# stringF=$(echo "$stringF" | tr a-f A-F)
# stringF=$(echo "ibase=16; $stringF" | bc)
# echo perl /opt/fhem/fhem.pl 7072 "setreading Plant1 Fertility $stringF"
# exit
