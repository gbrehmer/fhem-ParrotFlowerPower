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
    Log3 $name, 3, "Sub ParrotFlowerPower_Undef ($name) - delete device";
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
        readingsSingleUpdate ( $hash, "state", "active", 1 );

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
        readingsSingleUpdate ( $hash, "state", "active", 1 );

        ParrotFlowerPower_Run( $hash );
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }

    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int(rand(30)), "ParrotFlowerPower_stateRequestTimer", $hash, 1 );

    Log3 $name, 5, "Sub ParrotFlowerPower_stateRequestTimer ($name) - state request timer called";
}

sub ParrotFlowerPower_Set($$@) {
    my ($hash, $name, @aa)  = @_;
    my ($cmd, $arg)         = @aa;

    
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

    
    if ( not exists($hash->{helper}{RUNNING_PID}) ) {
        Log3 $name, 4, "Sub ParrotFlowerPower_Run ($name) - start blocking call";
    
        readingsSingleUpdate ( $hash, "state", "read data", 1 );
    
        $hash->{helper}{RUNNING_PID} = BlockingCall( "ParrotFlowerPower_BlockingRun", $name."|".$mac, 
                                                     "ParrotFlowerPower_BlockingDone", 60 + 120, 
                                                     "ParrotFlowerPower_BlockingAborted", $hash );
    } else {
        Log3 $name, 4, "Sub ParrotFlowerPower_Run ($name) - blocking call already running";    
    }
}

sub ParrotFlowerPower_BlockingRun($) {
    my ($string)        = @_;
    my ($name, $mac)    = split("\\|", $string);
    

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - read data from sensor";

    ##### read sensor data
    my $result = ParrotFlowerPower_callGatttool( $name, $mac );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingRun ($name) - read data finished: $result";

    return "$name|$result";
}

sub ParrotFlowerPower_callGatttool($$) {
    my ($name, $mac)        = @_;
    my $loop                = 0;
    my $deviceName          = ReadingsVal( $name, "deviceName", "" );
    my $deviceColor         = ReadingsVal( $name, "deviceColor", "" );
    my $batteryLevel;
    my $calibSoilMoisture;
    my $calibAirTemperature;
    my $calibSunlight;


    # wait up to 60s to get a free slot
    while ( (qx(ps ax | grep -v grep | grep -iE "gatttool|hcitool") && $loop < 60) ) {
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - check if gattool or hcitool is running. loop: $loop";
        sleep 1;
        $loop++;
    }

    if ( $loop < 60 ) {    
        #### Read Sensor Data
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - run gatttool";

        if ( "" eq $deviceName ) {
            $deviceName = ParrotFlowerPower_convertHexToString( ParrotFlowerPower_readSensorValue( $name, $mac, "00002a00-0000-1000-8000-00805f9b34fb" ) );
            Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. deviceName: $deviceName";
        } else {
            Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - deviceName already available: $deviceName";
        }

        if ( "" eq $deviceColor ) {
            $deviceColor = ParrotFlowerPower_convertStringToU16( ParrotFlowerPower_readSensorValue( $name, $mac, "39e1fe04-84a8-11e2-afba-0002a5d5c51b" ) );
            Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. deviceColor: $deviceColor";
        } else {
            Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - deviceColor already available: $deviceColor";
        }    
        
        $batteryLevel = ParrotFlowerPower_convertStringToU8( ParrotFlowerPower_readSensorValue( $name, $mac, "00002a19-0000-1000-8000-00805f9b34fb" ) );
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. batteryLevel: $batteryLevel";
        
        $calibSoilMoisture = ParrotFlowerPower_round( ParrotFlowerPower_convertStringToFloat( ParrotFlowerPower_readSensorValue( $name, $mac, "39e1fa09-84a8-11e2-afba-0002a5d5c51b" ) ) );
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibSoilMoisture: $calibSoilMoisture";
        
        $calibAirTemperature = ParrotFlowerPower_round( ParrotFlowerPower_convertStringToFloat( ParrotFlowerPower_readSensorValue( $name, $mac, "39e1fa0a-84a8-11e2-afba-0002a5d5c51b" ) ) );
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibAirTemperature: $calibAirTemperature";
        
        $calibSunlight = ParrotFlowerPower_round( ParrotFlowerPower_convertStringToFloat( ParrotFlowerPower_readSensorValue( $name, $mac, "39e1fa0b-84a8-11e2-afba-0002a5d5c51b" ) ) );
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - processing gatttool response. calibSunlight: $calibSunlight";
    } else {
        Log3 $name, 4, "Sub ParrotFlowerPower_callGatttool ($name) - no free slot found to start gatttool";
    }
    
    return "$deviceName|$deviceColor|$batteryLevel|$calibSoilMoisture|$calibAirTemperature|$calibSunlight";
}

sub ParrotFlowerPower_readSensorValue($$$) {
    my ($name, $mac, $uuid ) = @_;
    my $hci = ReadingsVal( $name, "hciDevice", "hci0" );
    my $result;
    my $loop = 0;

    
    do {
        # try to read the value from sensor
        $result = qx( gatttool -i $hci -b $mac --char-read --uuid=$uuid 2>&1 );
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - call gatttool char read loop: $loop, result: $result";
        $loop++;
    }
    while ( ($loop < 10) && (not $result =~ /handle\:.*value\:(.*)/) );

    if ( defined($1) ) {
        $result = $1;
        
        # remove spaces
        $result =~ s/\s//g;
        
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - processing gatttool response: $result";

        return $result;
    } else {
        Log3 $name, 4, "Sub ParrotFlowerPower_readSensorValue ($name) - invalid gatttool response";
        
        # return empty string in case of an error
        return "";
    }
}

sub ParrotFlowerPower_convertStringToFloat($) {
    $_ = shift;

    if ( "" ne $_ ) {
        # switch endianess of string
        $_ = unpack( "H*", reverse(pack("H*", $_)) );

        # convert string to float
        return unpack( "f", pack("L", hex($_)) );
    } else {
        return "";
    }
}

sub ParrotFlowerPower_convertStringToU8($) {
    $_ = shift;

    if ( "" ne $_ ) {
        # convert string to U8
        return hex($_);
    } else {
        return "";
    }
}

sub ParrotFlowerPower_convertStringToU16($) {
    $_ = shift;

    if ( "" ne $_ ) {
        # switch endianess of string
        $_ = unpack( "H*", reverse(pack("H*", $_)) );

        # convert string to U16
        return hex($_);
    } else {
        return "";
    }
}

sub ParrotFlowerPower_convertHexToString($) {
    $_ = shift;

    if ( "" ne $_ ) {
        # convert hex string into string
        return pack( "H*", $_ );
    } else {
        return "";
    }
}

sub ParrotFlowerPower_round($) {
    $_ = shift;
    
    return ( int((($_ * 100) + 0.0005) / 100) );
}

sub ParrotFlowerPower_BlockingDone($) {
    my ($string)            = @_;
    my ( $name, $deviceName, $deviceColor, $batteryLevel, $calibSoilMoisture, $calibAirTemperature, $calibSunlight ) = split( "\\|", $string );
    my $hash                = $defs{$name};


    delete($hash->{helper}{RUNNING_PID});

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingDone ($name) - helper disabled. abort" if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );

    readingsBeginUpdate( $hash );

    readingsBulkUpdate( $hash, "deviceName", $deviceName );
    readingsBulkUpdate( $hash, "deviceColor", $deviceColor );
    readingsBulkUpdate( $hash, "battery", (("" eq $batteryLevel) || ($batteryLevel > 15)) ? "ok" : "low" );
    readingsBulkUpdate( $hash, "batteryLevel", $batteryLevel );
    readingsBulkUpdate( $hash, "soilMoisture", $calibSoilMoisture );
    readingsBulkUpdate( $hash, "airTemperature", $calibAirTemperature );
    readingsBulkUpdate( $hash, "sunlight", $calibSunlight );
    readingsBulkUpdate( $hash, "state", "active" );
    
    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4, "Sub ParrotFlowerPower_BlockingDone ($name) - done";
}

sub ParrotFlowerPower_BlockingAborted($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1);
    
    Log3 $name, 3, "($name) Sub ParrotFlowerPower_BlockingAborted - BlockingCall process terminated unexpectedly: timeout";
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
    <li>state - status of the flower power sensor or error message if any errors.</li>
    <li>deviceName - name of the Parrot Flower Power sensor.</li>
    <li>deviceColor - color of the Parrot Flower Power sensor.</li>
    <li>battery - current battery state (depends on batteryLevel).</li>
    <li>batteryLevel - current battery level.</li>
    <li>soilMoisture - current soil moisture.</li>
    <li>airTemperature - current air temperature.</li>
    <li>sunlight - current sunlight.</li>
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
