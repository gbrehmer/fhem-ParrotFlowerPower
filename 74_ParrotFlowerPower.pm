###############################################################################
#
#  (c) 2016-2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  Modifications by: Achim Winkler
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
sub ParrotFlowerPower_forDone_encodeJSON($$$$$$$$$);
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
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
            
            Log3 $name, 3, "ParrotFlowerPower ($name) - disabledForIntervals";
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
                                                                   ReadingsVal($name, "state", 0) eq "disabled" or 
                                                                   ReadingsVal($name, "state", 0) eq "Unknown") );

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
                                                                   ReadingsVal($name, "state", 0) eq "disabled" or 
                                                                   ReadingsVal($name, "state", 0) eq "Unknown") );

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

    Log3 $name, 4, "Sub ParrotFlowerPower_Run ($name) - start blocking call";
    
    $hash->{helper}{RUNNING_PID} = BlockingCall( "ParrotFlowerPower_BlockingRun", $name."|".ParrotFlowerPower_forRun_encodeJSON( $mac ), 
                                                 "ParrotFlowerPower_BlockingDone", 120, 
                                                 "ParrotFlowerPower_BlockingAborted", $hash ) unless( exists($hash->{helper}{RUNNING_PID}) );
    
    readingsSingleUpdate ( $hash, "state", "read data", 1 ) if ( ReadingsVal( $name, "state", 0 ) eq "active" );
}

sub ParrotFlowerPower_BlockingRun($) {
    my ($string)        = @_;
    my ($name,$data)    = split("\\|", $string);
    my $data_json       = decode_json($data);
    my $mac             = $data_json->{mac};


    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - Running nonBlocking";

    ##### read sensor data
    my $result = ParrotFlowerPower_callGatttool( $name, $mac );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - encoded json: $result";

    return "$name|$result";
}

sub ParrotFlowerPower_callGatttool($$) {
    my ($name, $mac)        = @_;
    my $loop                = 0;
    my $deviceName;
    my $deviceColor;
    my $batteryLevel;
    my $calibSoilMoisture;
    my $calibAirTemperature;
    my $calibSunlight;
    my $calibEA;
    my $calibECB;
    my $calibECPorous;


    while ( (qx(ps ax | grep -v grep | grep -iE "gatttool|hcitool") and $loop < 10) ) {
        Log3 $name, 4, "Sub ParrotFlowerPower ($name) - check if gattool or hcitool is running. loop: $loop";
        sleep 1;
        $loop++;
    }

    #### Read Sensor Data
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - run gatttool";

    $deviceName = convertHexToString( readSensorValue( $name, $mac, "00002a00-0000-1000-8000-00805f9b34fb" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. deviceName: $deviceName";

    $deviceColor = convertStringToU16( readSensorValue( $name, $mac, "39e1fe04-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. deviceColor: $deviceColor";
    
    $batteryLevel = convertStringToU8( readSensorValue( $name, $mac, "00002a19-0000-1000-8000-00805f9b34fb" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. batteryLevel: $batteryLevel";
    
    $calibSoilMoisture = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa09-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibSoilMoisture: $calibSoilMoisture";
    
    $calibAirTemperature = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa0a-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibAirTemperature: $calibAirTemperature";
    
    $calibSunlight = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa0b-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibSunlight: $calibSunlight";
    
    $calibEA = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa0c-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibEA: $calibEA";
    
    $calibECB = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa0d-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibECB: $calibECB";
    
    $calibECPorous = convertStringToFloat( readSensorValue( $name, $mac, "39e1fa0e-84a8-11e2-afba-0002a5d5c51b" ) );
    Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibECPorous: $calibECPorous";
    
    return ParrotFlowerPower_forDone_encodeJSON( $deviceName, $deviceColor, $batteryLevel, $calibSoilMoisture, $calibAirTemperature, $calibSunlight, $calibEA, $calibECB, $calibECPorous );
}

sub ParrotFlowerPower_readSensorValue($$$) {
    my ($name, $mac, $uuid ) = @_;
    my $hci = ReadingsVal( $name, "hciDevice", "hci0" );
    my @result;
    my $repeatCounter = 0;

    
    do {
        # try to read the value from sensor
        @result = split( ": ", qx(gatttool -i $hci -b $mac --char-read --uuid=$uuid 2>&1) );
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - call gatttool char read loop $loop";
        $repeatCounter++;
    }
    while ( ($repeatCounter < 10) && ((not defined($result[0])) || (not $result[0] =~ /Characteristic value/)) );

    if ( defined($result[0]) && $repeatCounter < 10) {
        # remove spaces
        $result[2] =~ s/\s//g;
        
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - processing gatttool response: $result[2]";

        return $result[2];
    }
    else {
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - invalid gatttool response";
        
        # return 0 in case of an error
        return 0;
    }
}

sub ParrotFlowerPower_convertStringToFloat($) {
    $_ = shift;

    # switch endianess of string
    $_ = unpack( "H*", reverse(pack("H*", $_)) );

    # convert string to float
    return unpack( "f", pack("L", hex($_)) );
}

sub ParrotFlowerPower_convertStringToU8($) {
    $_ = shift;

    # convert string to U8
    return hex($_);
}

sub ParrotFlowerPower_convertStringToU16($) {
    $_ = shift;

    # switch endianess of string
    $_ = unpack( "H*", reverse(pack("H*", $_)) );

    # convert string to U16
    return hex($_);
}

sub ParrotFlowerPower_convertHexToString($) {
    $_ = shift;

    # convert hex string into string
    return pack( "H*", $_ );
}

sub ParrotFlowerPower_forRun_encodeJSON($) {
    my $mac  = shift;

    my %data = (
        'mac' => $mac
    );

    return encode_json \%data;
}

sub ParrotFlowerPower_forDone_encodeJSON($$$$$$$$$) {

    my ( $deviceName, $deviceColor, $batteryLevel, $calibSoilMoisture, $calibAirTemperature, $calibSunlight, $calibEA, $calibECB, $calibECPorous ) = @_;
    my %response = (
        'name'        => $deviceName,
        'color'       => $deviceColor,
        'battery'     => $batteryLevel,
        'moisture'    => $calibSoilMoisture,
        'temperature' => $calibAirTemperature,
        'sunlight'    => $calibSunlight,
        'EA'          => $calibEA,
        'ECB'         => $calibECB,
        'ECPorous'    => $calibECPorous
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

    my $response_json = decode_json( $response );

    readingsBulkUpdate( $hash, "deviceName", $response_json->{name} );
    readingsBulkUpdate( $hash, "deviceColor", $response_json->{color} );
    readingsBulkUpdate( $hash, "battery", ($response_json->{battery} > 20 ? "ok" : "low") );
    readingsBulkUpdate( $hash, "batteryLevel", $response_json->{battery} );
    readingsBulkUpdate( $hash, "soilMoisture", $response_json->{moisture} );
    readingsBulkUpdate( $hash, "airTemperature", $response_json->{temperature} );
    readingsBulkUpdate( $hash, "sunlight", $response_json->{sunlight} );
    readingsBulkUpdate( $hash, "EEA", $response_json->{EA} );
    readingsBulkUpdate( $hash, "ECB", $response_json->{ECB} );
    readingsBulkUpdate( $hash, "ECPorous", $response_json->{ECPorous} );
    readingsBulkUpdate( $hash, "state", "active" ) if ( ReadingsVal($name, "state", 0) eq "read data" or ReadingsVal($name, "state", 0) eq "unreachable" );
    
    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingDone ($name) - Done!";
}

sub ParrotFlowerPower_BlockingAborted($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1);
    
    Log3 $name, 3, "($name) Sub ParrotFlowerPower_BlockingAborted - The BlockingCall process terminated unexpectedly: Timeout";
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
