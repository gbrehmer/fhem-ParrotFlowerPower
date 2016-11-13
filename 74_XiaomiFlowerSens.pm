###############################################################################
# 
# Developed with Kate
#
#  (c) 2016 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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

my $version = "0.1.55";





sub XiaomiFlowerSens_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}	    = "XiaomiFlowerSens_Set";
    $hash->{DefFn}	    = "XiaomiFlowerSens_Define";
    $hash->{UndefFn}	    = "XiaomiFlowerSens_Undef";
    $hash->{AttrFn}	    = "XiaomiFlowerSens_Attr";
    $hash->{AttrList} 	    = "interval ".
                              "disable:1 ".
                              $readingFnAttributes;



    foreach my $d(sort keys %{$modules{XiaomiFlowerSens}{defptr}}) {
	my $hash = $modules{XiaomiFlowerSens}{defptr}{$d};
	$hash->{VERSION} 	= $version;
    }
}

sub XiaomiFlowerSens_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "too few parameters: define <name> XiaomiFlowerSens <BTMAC>" if( @a != 3 );
    

    my $name    	= $a[0];
    my $mac     	= $a[2];
    
    $hash->{BTMAC} 	= $mac;
    $hash->{VERSION} 	= $version;
    $hash->{INTERVAL}   = 3600;
        
    $modules{XiaomiFlowerSens}{defptr}{$hash->{BTMAC}} = $hash;
    readingsSingleUpdate ($hash,"state","initialized", 0);
    $attr{$name}{room}          = "FlowerSens" if( !defined($attr{$name}{room}) );
    
    
    
    RemoveInternalTimer($hash);
    
    if( $init_done ) {
        XiaomiFlowerSens_stateRequestTimer($hash);
    } else {
        InternalTimer( gettimeofday()+25, "XiaomiFlowerSens_stateRequestTimer", $hash, 0 );
    }
    
    Log3 $name, 3, "XiaomiFlowerSens ($name) - defined with BTMAC $hash->{BTMAC}";
    
    $modules{XiaomiFlowerSens}{defptr}{$hash->{BTMAC}} = $hash;
    return undef;
}

sub XiaomiFlowerSens_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $mac = $hash->{BTMAC};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    delete($modules{XiaomiFlowerSens}{defptr}{$mac});
    Log3 $name, 3, "XiaomiFlowerSens ($name) - undefined";
    return undef;
}

sub XiaomiFlowerSens_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "model" ) {
	if( $cmd eq "set" ) {
	    
            XiaomiFlowerSens($hash) if( $init_done );
        }
    }
    
    if( $attrName eq "disable" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal eq "1" ) {
	    
                RemoveInternalTimer( $hash );
                readingsSingleUpdate ( $hash, "state", "disabled", 1 );
		Log3 $name, 3, "Sub XiaomiFlowerSens ($name) - disabled";
		
	    }
	}
	
	elsif( $cmd eq "del" ) {
	
            RemoveInternalTimer( $hash );
            InternalTimer( gettimeofday()+2, "XiaomiFlowerSens_stateRequestTimer", $hash, 0 ) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
            readingsSingleUpdate ( $hash, "state", "initialized", 1 );
            Log3 $name, 3, "Sub XiaomiFlowerSens ($name) - enabled";
        }
    }
    
    if( $attrName eq "interval" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal < 300 ) {
		Log3 $name, 3, "Sub XiaomiFlowerSens ($name) - interval too small, please use something >= 300 (sec), default is 3600 (sec)";
		return "interval too small, please use something >= 300 (sec), default is 3600 (sec)";
	    } else {
		$hash->{INTERVAL} = $attrVal;
		Log3 $name, 3, "Sub XiaomiFlowerSens ($name) - set interval to $attrVal";
	    }
	}
	
	elsif( $cmd eq "del" ) {
	    $hash->{INTERVAL} = 3600;
	    Log3 $name, 3, "Sub XiaomiFlowerSens ($name) - set interval to default";
        }
    }
    
    return undef;
}

sub XiaomiFlowerSens_stateRequest($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    
    readingsSingleUpdate ( $hash, "state", "active", 1 ) if( ReadingsVal($name, "state", 0) eq "initialized" or ReadingsVal($name, "state", 0) eq "unreachable" );
    XiaomiFlowerSens($hash);
}

sub XiaomiFlowerSens_stateRequestTimer($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    readingsSingleUpdate ( $hash, "state", "active", 1 ) if( ReadingsVal($name, "state", 0) eq "initialized" or ReadingsVal($name, "state", 0) eq "unreachable" );
    
    Log3 $name, 5, "Sub XiaomiFlowerSens ($name) - Request Timer wird aufgerufen";
    XiaomiFlowerSens($hash);
    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "XiaomiFlowerSens_stateRequestTimer", $hash, 1 );
}

sub XiaomiFlowerSens_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, $arg) = @aa;
    my $action;

    if( $cmd eq 'statusRequest' ) {
        $action = $cmd;
        $arg    = undef;
    
    } else {
        my $list = "statusRequest:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    XiaomiFlowerSens($hash);
    
    return undef;
}

sub XiaomiFlowerSens($) {

    my ( $hash, $cmd ) = @_;
    
    my $name    = $hash->{NAME};
    my $mac     = $hash->{BTMAC};
    my $wfr     = 1 if( ReadingsVal($name, "firmware", 0) ne "2.6.2" );
    

    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
        
    my $response_encode = XiaomiFlowerSens_forRun_encodeJSON($mac,$wfr);
        
    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiFlowerSens_Run", $name."|".$response_encode, "XiaomiFlowerSens_Done", 15, "XiaomiFlowerSens_Aborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - Starte Blocking Call";
    
    readingsSingleUpdate ( $hash, "state", "call data", 1 ) if( ReadingsVal($name, "state", 0) eq "active" );
}

sub XiaomiFlowerSens_Run($) {

    my ($string)        = @_;
    my ($name,$data)    = split("\\|", $string);
    my $data_json       = decode_json($data);
    
    my $mac             = $data_json->{mac};
    my $wfr             = $data_json->{wfr};
    
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_Run ($name) - Running nonBlocking";


    ##### Abruf des aktuellen Status
    my ($temp,$lux,$moisture,$fertility)  = XiaomiFlowerSens_gattCharRead($mac,$wfr);
    
    ###### Batteriestatus einlesen    
    my ($blevel,$fw) = XiaomiFlowerSens_readBatFW($mac);


    Log3 $name, 4, "Sub XiaomiFlowerSens_Run ($name) - Rückgabe an Auswertungsprogramm beginnt";

    return "$name|err"
    unless( defined($temp) and defined($blevel) );
    
    my $response_encode = XiaomiFlowerSens_forDone_encodeJSON($temp,$lux,$moisture,$fertility,$blevel,$fw);
    return "$name|$response_encode";
}

sub XiaomiFlowerSens_gattCharRead($$) {

    my ($mac,$wfr)       = @_;
    
    
    my $loop = 0;
    while ( (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop = 0) or (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop < 5) ) {
        printf "\n(Sub XiaomiFlowerSens_Run) - gatttool noch aktiv, wait 0.5s for new check\n";
        sleep 0.5;
        $loop++;
    }
    
    #printf "\n\nSub XiaomiFlowerSens - WriteForRead: $wfr";
    ## support for Firmware 2.6.6, man muß erst einen Characterwert schreiben
    my $wresp       = qx(gatttool -b $mac --char-write-req -a 0x33 -n A01F) if($wfr == 1);
    #printf "\nSub XiaomiFlowerSens - WriteResponse: $wresp\n\n";
    
    my @readData        = split(": ",qx(gatttool -b $mac --char-read -a 0x35));
    
    return (undef,undef,undef,undef)
    unless( defined($readData[0]) );
    
    my @data            = split(" ",$readData[1]);
    
    my $temp            = hex("0x".$data[1].$data[0]);
    my $lux             = hex("0x".$data[4].$data[3]);
    my $moisture        = hex("0x".$data[7]);
    my $fertility       = hex("0x".$data[9].$data[8]);
    
    return ($temp,$lux,$moisture,$fertility);
}

sub XiaomiFlowerSens_readBatFW($) {

    my ($mac)   = @_;
    
    
    my $loop = 0;
    while ( (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop = 0) or (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop < 5) ) {
        printf "\n(Sub XiaomiFlowerSens_Run) - gatttool noch aktiv, wait 0.5s for new check\n";
        sleep 0.5;
        $loop++;
    }
    
    my @readData        = split(": ",qx(gatttool -b $mac --char-read -a 0x38));
    
    return (undef,undef,undef,undef)
    unless( defined($readData[0]) );
    
    my @data            = split(" ",$readData[1]);
    
    my $blevel          = hex("0x".$data[0]);
    my $fw              = ($data[2]-30).".".($data[4]-30).".".($data[6]-30);
    
    return ($blevel,$fw);
}

sub XiaomiFlowerSens_forRun_encodeJSON($$) {

    my ($mac,$wfr) = @_;

    my %data = (
        'mac'           => $mac,
        'wfr'           => $wfr
    );
    
    return encode_json \%data;
}

sub XiaomiFlowerSens_forDone_encodeJSON($$$$$$) {

    my ($temp,$lux,$moisture,$fertility,$blevel,$fw)        = @_;

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

sub XiaomiFlowerSens_Done($) {

    my ($string) = @_;
    my ($name,$response)       = split("\\|",$string);
    my $hash    = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 3, "Sub XiaomiFlowerSens_Done ($name) - Der Helper ist diabled. Daher wird hier abgebrochen" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    if( $response eq "err" ) {
        readingsSingleUpdate($hash,"state","unreachable", 1);
        return undef;
    }
    
    
    my $response_json = decode_json($response);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "battery", $response_json->{blevel});
    readingsBulkUpdate($hash, "temperature", $response_json->{temp}/10);
    readingsBulkUpdate($hash, "lux", $response_json->{lux});
    readingsBulkUpdate($hash, "moisture", $response_json->{moisture});
    readingsBulkUpdate($hash, "fertility", $response_json->{fertility});
    readingsBulkUpdate($hash, "firmware", $response_json->{firmware});
    readingsBulkUpdate($hash, "state", "active") if( ReadingsVal($name,"state", 0) eq "call data" or ReadingsVal($name,"state", 0) eq "unreachable" );
    readingsEndUpdate($hash,1);
    
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_Done ($name) - Abschluss!";
}

sub XiaomiFlowerSens_Aborted($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,"state","unreachable", 1);
    Log3 $name, 3, "($name) - The BlockingCall Process terminated unexpectedly. Timedout";
}











1;








=pod
=item device
=item summary    
=item summary_DE 

=begin html

=end html

=begin html_DE

=end html_DE

=cut