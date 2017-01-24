###############################################################################
#
#  Original Code by: Marko Oldenburg
#  Modifications by: Achim Winkler
#
#  (c) 2016-2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################


package main;

use strict;
use warnings;
use POSIX;

use JSON;
use Blocking;

my $version = "0.0.1";




# Declare functions
sub ParrotFlowerPower_Initialize($);
sub ParrotFlowerPower_Define($$);
sub ParrotFlowerPower_Undef($$);
sub ParrotFlowerPower_Attr(@);
sub ParrotFlowerPower_stateRequest($);
sub ParrotFlowerPower_stateRequestTimer($);
sub ParrotFlowerPower_Set($$@);
sub ParrotFlowerPower_Run($);
sub ParrotFlowerPower_BlockingRun($);
sub ParrotFlowerPower_callGatttool($$);
sub ParrotFlowerPower_forRun_encodeJSON($);
sub ParrotFlowerPower_forDone_encodeJSON($$$$$$);
sub ParrotFlowerPower_BlockingDone($);
sub ParrotFlowerPower_BlockingAborted($);




sub ParrotFlowerPower_Initialize($) {
    my ($hash) = @_;

    
    $hash->{SetFn}      = "ParrotFlowerPower_Set";
    $hash->{DefFn}      = "ParrotFlowerPower_Define";
    $hash->{UndefFn}    = "ParrotFlowerPower_Undef";
    $hash->{AttrFn}     = "ParrotFlowerPower_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          "hciDevice:hci0,hci1,hci2 ".
                          "disabledForIntervals ".
                          $readingFnAttributes;

    foreach my $d(sort keys %{$modules{ParrotFlowerPower}{defptr}}) {
        my $hash = $modules{ParrotFlowerPower}{defptr}{$d};
        $hash->{VERSION} = $version;
    }
}

sub ParrotFlowerPower_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> ParrotFlowerPower <BTMAC>" if ( @a != 3 );

    my $name            = $a[0];
    my $mac             = $a[2];

    $hash->{BTMAC}      = $mac;
    $hash->{VERSION}    = $version;
    $hash->{INTERVAL}   = 3600;

    $modules{ParrotFlowerPower}{defptr}{$hash->{BTMAC}} = $hash;
    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    $attr{$name}{room} = "ParrotFlowerPower" if( !defined($attr{$name}{room}) );

    RemoveInternalTimer( $hash );

    if ( $init_done ) {
        ParrotFlowerPower_stateRequestTimer( $hash );
    } else {
        InternalTimer( gettimeofday() + int(rand(30)) + 15, "ParrotFlowerPower_stateRequestTimer", $hash, 0 );
    }

    Log3 $name, 3, "ParrotFlowerPower ($name) - defined with BTMAC $hash->{BTMAC}";

    $modules{ParrotFlowerPower}{defptr}{$hash->{BTMAC}} = $hash;
    return undef;
}

sub ParrotFlowerPower_Undef($$) {
    my ( $hash, $arg ) = @_;
    my $mac = $hash->{BTMAC};
    my $name = $hash->{NAME};


    RemoveInternalTimer($hash);

    delete( $modules{ParrotFlowerPower}{defptr}{$mac} );
    Log3 $name, 3, "Sub ParrotFlowerPower_Undef ($name) - delete device $name";
    return undef;
}

sub ParrotFlowerPower_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};
    my $orig                                = $attrVal;


    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "ParrotFlowerPower ($name) - disabled";
        }
        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "ParrotFlowerPower ($name) - enabled";
        }
    }

    if ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            Log3 $name, 3, "ParrotFlowerPower ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }
        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "ParrotFlowerPower ($name) - enabled";
        }
    }

    if ( $attrName eq "interval" ) {
        if ( $cmd eq "set" ) {
            if ( $attrVal < 300 ) {
                Log3 $name, 3, "ParrotFlowerPower ($name) - interval too small, please use something >= 300 (sec), default is 3600 (sec)";
                return "interval too small, please use something >= 300 (sec), default is 3600 (sec)";
            } else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "ParrotFlowerPower ($name) - set interval to $attrVal";
            }
        }
        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL} = 3600;
            Log3 $name, 3, "ParrotFlowerPower ($name) - set interval to default";
        }
    }

    return undef;
}

sub ParrotFlowerPower_stateRequest($) {
    my ($hash)      = @_;
    my $name        = $hash->{NAME};


    if ( !IsDisabled($name) ) {
        readingsSingleUpdate ( $hash, "state", "active", 1 ) if ( (ReadingsVal($name, "state", 0) eq "initialized" or 
                                                                   ReadingsVal($name, "state", 0) eq "unreachable" or 
                                                                   ReadingsVal($name, "state", 0) eq "corrupted data" or 
                                                                   ReadingsVal($name, "state", 0) eq "disabled" or 
                                                                   ReadingsVal($name, "state", 0) eq "Unknown" or 
                                                                   ReadingsVal($name, "state", 0) eq "charWrite faild") );

        ParrotFlowerPower_Run( $hash );
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }
    
    Log3 $name, 5, "Sub ParrotFlowerPower_stateRequestTimer ($name) - state request called";
}

sub ParrotFlowerPower_stateRequestTimer($) {
    my ($hash)      = @_;
    my $name        = $hash->{NAME};


    RemoveInternalTimer($hash);

    if ( !IsDisabled($name) ) {
        readingsSingleUpdate ( $hash, "state", "active", 1 ) if ( (ReadingsVal($name, "state", 0) eq "initialized" or 
                                                                   ReadingsVal($name, "state", 0) eq "unreachable" or 
                                                                   ReadingsVal($name, "state", 0) eq "corrupted data" or 
                                                                   ReadingsVal($name, "state", 0) eq "disabled" or 
                                                                   ReadingsVal($name, "state", 0) eq "Unknown" or 
                                                                   ReadingsVal($name, "state", 0) eq "charWrite faild") );

        ParrotFlowerPower_Run( $hash );
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }

    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int(rand(300)), "ParrotFlowerPower_stateRequestTimer", $hash, 1 );

    Log3 $name, 5, "Sub ParrotFlowerPower_stateRequestTimer ($name) - state request timer called";
}

sub ParrotFlowerPower_Set($$@) {
    my ($hash, $name, @aa)  = @_;
    my ($cmd, $arg)         = @aa;
    my $action;

    if ( $cmd eq 'statusRequest' ) {
        ParrotFlowerPower_stateRequest( $hash );
    } else {
        my $list = "statusRequest:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub ParrotFlowerPower_Run($) {
    my ( $hash, $cmd ) = @_;
    my $name    = $hash->{NAME};
    my $mac     = $hash->{BTMAC};

    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined($hash->{helper}{RUNNING_PID}) );

    my $response_encode = ParrotFlowerPower_forRun_encodeJSON( $mac );

    Log3 $name, 4, "Sub ParrotFlowerPower_Run ($name) - start blocking call";
    
    $hash->{helper}{RUNNING_PID} = BlockingCall( "ParrotFlowerPower_BlockingRun", $name."|".$response_encode, 
                                                 "ParrotFlowerPower_BlockingDone", 30, 
                                                 "ParrotFlowerPower_BlockingAborted", $hash ) unless( exists($hash->{helper}{RUNNING_PID}) );
    
    readingsSingleUpdate ( $hash, "state", "read data", 1 ) if ( ReadingsVal( $name, "state", 0 ) eq "active" );
}

sub ParrotFlowerPower_BlockingRun($) {
    my ($string)        = @_;
    my ($name,$data)    = split("\\|", $string);
    my $data_json       = decode_json($data);
    my $mac             = $data_json->{mac};


    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - Running nonBlocking";

    ##### call sensor data
    my ($sensData, $batFwData) = ParrotFlowerPower_callGatttool( $name, $mac );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - Processing response data: $sensData";

    return "$name|chomp($sensData)" unless( defined($batFwData) );

    #### processing sensor respons
    my @dataSensor  = split( " ", $sensData );

    return "$name|charWrite faild" unless( $dataSensor[0] ne "aa" and 
                                           $dataSensor[1] ne "bb" and 
                                           $dataSensor[2] ne "cc" and 
                                           $dataSensor[3] ne "dd" and 
                                           $dataSensor[4] ne "ee" and 
                                           $dataSensor[5] ne "ff");

    my $temp;
    if ( $dataSensor[1] eq "ff" ) {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]) - hex("0xffff");
    } else {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]);
    }
    my $lux         = hex("0x".$dataSensor[4].$dataSensor[3]);
    my $moisture    = hex("0x".$dataSensor[7]);
    my $fertility   = hex("0x".$dataSensor[9].$dataSensor[8]);

    #### processing firmware and battery response
    my @dataBatFw   = split( " ", $batFwData );

    my $blevel      = hex("0x".$dataBatFw[0]);
    my $fw          = ($dataBatFw[2] - 30).".".($dataBatFw[4] - 30).".".($dataBatFw[6] - 30);

    ###### return processing data
    return "$name|corrupted data" if ( $temp == 0 and $lux == 0 and $moisture == 0 and $fertility == 0 );

    my $response_encode = ParrotFlowerPower_forDone_encodeJSON( $temp, $lux, $moisture, $fertility, $blevel, $fw );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - no dataerror, create encode json: $response_encode";

    return "$name|$response_encode";
}

sub ParrotFlowerPower_callGatttool($$) {

    my ($name, $mac)        = @_;
    my $hci                 = ReadingsVal($name, "hciDevice", "hci0");
    my $loop                = 0;
    my $wresp;
    my @readSensData;
    my @readBatFwData;


    while ( (qx(ps ax | grep -v grep | grep -iE "gatttool|hcitool") and $loop < 10) ) {
        Log3 $name, 4, "Sub ParrotFlowerPower ($name) - check if gattool or hcitool is running. loop: $loop";
        sleep 1;
        $loop++;
    }

    #### Read Sensor Data
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - run gatttool";

    $loop = 0;
    do {
        @readSensData   = split( ": ", qx(gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 /dev/null) );
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - call gatttool charRead loop $loop";
        $loop++;

    } while ( $loop < 10 and $readSensData[0] =~ /connect error/ );

    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. sensData: $readSensData[1]";

    return ( $readSensData[1], undef ) unless( $readSensData[0] =~ /Characteristic value/ );


    ### Read Firmware and Battery Data
    $loop = 0;
    do {

        @readBatFwData  = split( ": ", qx(gatttool -i $hci -b $mac --char-read -a 0x38 2>&1 /dev/null) );
        Log3 $name, 4, "Sub ParrotFlowerPower ($name) - call gatttool readBatFw loop $loop";
        $loop++;

    } while ( $loop < 10 and $readBatFwData[0] =~ /connect error/ );

    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. batFwData: $readBatFwData[1]";

    return ( $readBatFwData[1], undef ) unless( $readBatFwData[0] =~ /Characteristic value/ );

    ### no Error in data string
    return ( $readSensData[1], $readBatFwData[1] );
}

sub ParrotFlowerPower_forRun_encodeJSON($) {
    my $mac  = shift;

    my %data = (
        'mac' => $mac
    );

    return encode_json \%data;
}

sub ParrotFlowerPower_forDone_encodeJSON($$$$$$) {

    my ( $temp, $lux, $moisture, $fertility, $blevel, $fw ) = @_;
    my %response = (
        'temp'      => $temp,
        'lux'       => $lux,
        'moisture'  => $moisture,
        'fertility' => $fertility,
        'blevel'    => $blevel,
        'firmware'  => $fw
    );

    return encode_json \%response;
}

sub ParrotFlowerPower_BlockingDone($) {

    my ($string)            = @_;
    my ( $name, $response ) = split( "\\|", $string );
    my $hash                = $defs{$name};


    delete($hash->{helper}{RUNNING_PID});

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingDone ($name) - helper disabled. Abort" if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );


    readingsBeginUpdate( $hash );

    if ( $response eq "corrupted data" ) {
        readingsBulkUpdate( $hash, "state", "corrupted data" );
        readingsEndUpdate( $hash, 1 );
        return undef;
    } 
    elsif ( $response eq "charWrite faild" ) {
        readingsBulkUpdate( $hash, "state", "charWrite faild" );
        readingsEndUpdate( $hash, 1 );
        return undef;
    } 
    elsif ( ref($response) eq "HASH" ) {
        readingsBulkUpdate( $hash, "lastGattError", "$response" );
        readingsBulkUpdate( $hash, "state", "unreachable" );
        readingsEndUpdate( $hash, 1 );
        return undef;
    }

    my $response_json = decode_json( $response );

    readingsBulkUpdate( $hash, "batteryLevel", $response_json->{blevel} );
    readingsBulkUpdate( $hash, "battery", ($response_json->{blevel} > 20 ? "ok" : "low") );
    readingsBulkUpdate( $hash, "temperature", $response_json->{temp} / 10 );
    readingsBulkUpdate( $hash, "lux", $response_json->{lux} );
    readingsBulkUpdate( $hash, "moisture", $response_json->{moisture} );
    readingsBulkUpdate( $hash, "fertility", $response_json->{fertility} );
    readingsBulkUpdate( $hash, "firmware", $response_json->{firmware} );
    readingsBulkUpdate( $hash, "state", "active" ) if ( ReadingsVal($name, "state", 0) eq "read data" or 
                                                        ReadingsVal($name, "state", 0) eq "unreachable" or 
                                                        ReadingsVal($name, "state", 0) eq "corrupted data" );

    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingDone ($name) - Done!";
}

sub ParrotFlowerPower_BlockingAborted($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1);
    
    Log3 $name, 3, "($name) Sub ParrotFlowerPower_BlockingAborted - The BlockingCall Process terminated unexpectedly. Timedout";
}


1;








=pod
=item device
=item summary       Modul to retrieves data from a Parrot Flower Power Sensors
=item summary_DE    Modul um Daten vom Parrot Flower Power Sensor zu auszulesen

=begin html

<a name="ParrotFlowerPower"></a>
<h3>Parrot Flower Power</h3>
<ul>
  <u><b>ParrotFlowerPower - Retrieves data from a Parrot Flower Power Sensor</b></u>
  <br>
  With this module it is possible to read the data from a sensor and to set it as reading.</br>
  Gatttool and hcitool is required to use this module. (apt-get install bluez)
  <br><br>
  <a name="ParrotFlowerPowerdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; ParrotFlowerPower &lt;BT-MAC&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Weihnachtskaktus ParrotFlowerPower C4:7C:8D:62:42:6F</code><br>
    </ul>
    <br>
    This statement creates a ParrotFlowerPower with the name Weihnachtskaktus and the Bluetooth Mac C4:7C:8D:62:42:6F.<br>
    After the device has been created, the current data of the Xiaomi Flower Monitor is automatically read from the device.
  </ul>
  <br><br>
  <a name="ParrotFlowerPowerreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status of the flower power sensor or error message if any errors.</li>
    <li>battery - current battery state dependent on batteryLevel.</li>
    <li>batteryLevel - current battery level in percent.</li>
    <li>fertility - Values for the fertilizer content</li>
    <li>firmware - current device firmware</li>
    <li>lux - current light intensity</li>
    <li>moisture - current moisture content</li>
    <li>temperature - current temperature</li>
  </ul>
  <br><br>
  <a name="ParrotFlowerPowerset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - retrieves the current state of the Parrot Flower Power Sensor.</li>
    <br>
  </ul>
  <br><br>
  <a name="ParrotFlowerPowerattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Parrot Flower Power device</li>
    <li>interval - interval in seconds for statusRequest</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

=end html_DE
=cut
