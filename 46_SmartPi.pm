###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#  
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#
###### Möglicher Aufbau eines JSON Strings für die SmartPi
#
# {"serial":"smartpi160812345","name":"House","lat":52.3667,"lng":9.7167,"time":"2017-05-30 19:52:11","softwareversion":"","ipaddress":"169.254.3.10","datasets":[{"time":"2017-05-30 19:52:08","phases":[{"phase":1,"name":"phase 1","values":[{"type":"current","unity":"A","info":"","data":0.24830514},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":57.110184},{"type":"cosphi","unity":"","info":"","data":0.70275474},{"type":"frequency","unity":"Hz","info":"","data":120.413925}]},{"phase":2,"name":"phase 2","values":[{"type":"current","unity":"A","info":"","data":0.86874366},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":199.81104},{"type":"cosphi","unity":"","info":"","data":0.99155134},{"type":"frequency","unity":"Hz","info":"","data":386.1237}]},{"phase":3,"name":"phase 3","values":[{"type":"current","unity":"A","info":"","data":1.3195294},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":303.49176},{"type":"cosphi","unity":"","info":"","data":-0.25960922},{"type":"frequency","unity":"Hz","info":"","data":153.38525}]},{"phase":4,"name":"phase 4","values":[{"type":"current","unity":"A","info":"","data":1.0668689}]}]}]}
#
#
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.0.23";




# Declare functions
sub SmartPi_Attr(@);
sub SmartPi_Define($$);
sub SmartPi_Initialize($);
sub SmartPi_Get($@);
sub SmartPi_GetData($@);
sub SmartPi_Undef($$);
sub SmartPi_ResponseProcessing($$);
sub SmartPi_ErrorHandling($$$);
sub SmartPi_WriteReadings($$);
sub SmartPi_Timer_GetData($);




sub SmartPi_Initialize($) {

    my ($hash) = @_;
    
    # Consumer
    $hash->{GetFn}      = "SmartPi_Get";
    $hash->{DefFn}      = "SmartPi_Define";
    $hash->{UndefFn}    = "SmartPi_Undef";
    
    $hash->{AttrFn}     = "SmartPi_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{SmartPi}{defptr}}) {
    
        my $hash = $modules{SmartPi}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub SmartPi_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <name> SmartPi <HOST>" if( @a != 3);
    return "Cannot define a HEOS device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my $name                = $a[0];
    
    my $host                = $a[2];
    $hash->{HOST}           = $host;
    $hash->{INTERVAL}       = 300;
    $hash->{PORT}           = 1080;
    $hash->{VERSION}        = $version;


    $attr{$name}{room} = "SmartPi" if( !defined( $attr{$name}{room} ) );
    
    Log3 $name, 3, "SmartPi ($name) - defined SmartPi Device with Host $host, Port $hash->{PORT} and Interval $hash->{INTERVAL}";
    
    
    if( $init_done ) {
        
        SmartPi_Timer_GetData($hash);
            
    } else {
        
        InternalTimer( gettimeofday()+15, "SmartPi_Timer_GetData", $hash, 0 );
    }
    
    $modules{SmartPi}{defptr}{HOST} = $hash;

    return undef;
}

sub SmartPi_Undef($$) {

    my ( $hash, $arg )  = @_;
    
    my $name            = $hash->{NAME};


    Log3 $name, 3, "SmartPi ($name) - Device $name deleted";
    delete $modules{SmartPi}{defptr}{HOST} if( defined($modules{SmartPi}{defptr}{HOST}) and $hash->{HOST} );

    return undef;
}

sub SmartPi_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" ) {
            if( $attrVal eq "0" ) {
            
                readingsSingleUpdate ( $hash, "state", "enabled", 1 );
                Log3 $name, 3, "SmartPi ($name) - enabled";
            } else {

                readingsSingleUpdate ( $hash, "state", "disabled", 1 );
                Log3 $name, 3, "SmartPi ($name) - disabled";
            }
            
        } else {

            readingsSingleUpdate ( $hash, "state", "enabled", 1 );
            Log3 $name, 3, "SmartPi ($name) - enabled";
        }
        
    } elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
        
            $hash->{INTERVAL} = $attrVal;
            
        } else {

            $hash->{INTERVAL} = 300;
        }
    }
    
    return undef;
}

sub SmartPi_Get($@) {
    
    my ($hash, $name, $cmd, @args)  = @_;
    my ($arg, @params)              = @args;

    my @phaseId = ('phase1','phase2','phase3','all');
    my @valueId = ('all','current','voltage','power','cosphi','frequency');
    my $phaseId;
    my $valueId;




    if( $cmd eq 'phase1' ) {

        $phaseId    = 1;
        $valueId    = $arg;
        
    } elsif( $cmd eq 'phase2' ) {
    
        $phaseId    = 2;
        $valueId    = $arg;
        
    } elsif( $cmd eq 'phase3' ) {
    
        $phaseId    = 3;
        $valueId    = $arg;
        
    } elsif( $cmd eq 'phase4' ) {
    
        $phaseId    = 4;
        $valueId    = $arg;
        
    } elsif( $cmd eq 'all' ) {
    
        $phaseId    = 'all';
        $valueId    = $arg;

    } else {
    
        my $list = '';
        
        foreach(@phaseId) {
            $list .= $_ . ':' . join(',',@valueId) . ' ';
        }
        
        $list .= 'phase4:current';
        
        
        return "Unknown argument $cmd, choose one of $list";
    }

    
    SmartPi_GetData($hash,$phaseId,$valueId);
    
    return undef;
}

sub SmartPi_Timer_GetData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    if( not IsDisabled($name) ) {
    
        SmartPi_GetData($hash,'all','all');
        
    } else {
    
        readingsSingleUpdate($hash,'state','disabled',1);
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL}, 'SmartPi_Timer_GetData', $hash, 1 );
    Log3 $name, 4, "SmartPi ($name) - Call InternalTimer SmartPi_Timer_GetData";
}

sub SmartPi_GetData($@) {

    my ($hash,$phaseId,$valueId)    = @_;
    my $name                        = $hash->{NAME};
    my $host                        = $hash->{HOST};
    my $port                        = $hash->{PORT};

    my $uri                         = $host . ':' . $port . '/api/' . $phaseId . '/' . $valueId . '/now';
    
    
    readingsSingleUpdate($hash,'state','fetch data',1);

    HttpUtils_NonblockingGet(
        {
            url         => "http://" . $uri,
            timeout     => 5,
            method      => 'GET',
            hash        => $hash,
            doTrigger   => 1,
            callback    => \&SmartPi_ErrorHandling,
        }
    );
    
    Log3 $name, 5, "SmartPi ($name) - Send with URI: $uri";
}

sub SmartPi_ErrorHandling($$$) {

    my ($param,$err,$data)  = @_;
    
    my $hash                = $param->{hash};
    my $name                = $hash->{NAME};



    
    ### Begin Error Handling
    
    if( defined( $err ) ) {
        if( $err ne "" ) {
        
            readingsBeginUpdate( $hash );
            readingsBulkUpdateIfChanged ( $hash, 'state', $err, 1);
            readingsBulkUpdateIfChanged( $hash, 'lastRequestError', $err, 1 );
            readingsEndUpdate( $hash, 1 );
            
            Log3 $name, 3, "SmartPi ($name) - RequestERROR: $err";
            
            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdateIfChanged ( $hash, 'state', $param->{code}, 1 );

        readingsBulkUpdateIfChanged( $hash, 'lastRequestError', $param->{code}, 1 );

        Log3 $name, 3, "SmartPi ($name) - RequestERROR: ".$param->{code};

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 5, "SmartPi ($name) - RequestERROR: received http code ".$param->{code}." without any data after requesting";

        return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) { 
    
        readingsBeginUpdate( $hash );
        
        readingsBulkUpdateIfChanged( $hash, 'state', $param->{code}, 1 );
        readingsBulkUpdateIfChanged( $hash, "lastRequestError", $param->{code}, 1 );

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 3, "SmartPi ($name) - statusRequestERROR: http error ".$param->{code};

        return;

        ### End Error Handling
    }
    
    SmartPi_ResponseProcessing($hash,$data);
}

sub SmartPi_ResponseProcessing($$) {

    my ($hash,$json)        = @_;
    
    my $name                = $hash->{NAME};
    my $decode_json;




    $decode_json    = eval{decode_json($json)};
    
    if($@){

        Log3 $name, 4, "SmartPi ($name) - error while request: $@";
        readingsSingleUpdate($hash, "state", "error", 1);

        return;
    }
    
    SmartPi_WriteReadings($hash,$decode_json);
}

sub SmartPi_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    
    
    Log3 $name, 4, "SmartPi ($name) - Write Readings";
    
    
    
    #{"serial":"smartpi160812345","name":"House","lat":52.3667,"lng":9.7167,"time":"2017-05-30 19:52:11","softwareversion":"","ipaddress":"169.254.3.10",
    
    
    
    #"datasets":[{"time":"2017-05-30 19:52:08","phases":[
    
    #{"phase":1,"name":"phase 1","values":[
   # {"type":"current","unity":"A","info":"","data":0.24830514},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":57.110184},{"type":"cosphi","unity":"","info":"","data":0.70275474},{"type":"frequency","unity":"Hz","info":"","data":120.413925}]},
    
    #{"phase":2,"name":"phase 2","values":[
    #{"type":"current","unity":"A","info":"","data":0.86874366},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":199.81104},{"type":"cosphi","unity":"","info":"","data":0.99155134},{"type":"frequency","unity":"Hz","info":"","data":386.1237}]},
    
    #{"phase":3,"name":"phase 3","values":[
    #{"type":"current","unity":"A","info":"","data":1.3195294},{"type":"voltage","unity":"V","info":"","data":230},{"type":"power","unity":"W","info":"","data":303.49176},{"type":"cosphi","unity":"","info":"","data":-0.25960922},{"type":"frequency","unity":"Hz","info":"","data":153.38525}]},
    
    #{"phase":4,"name":"phase 4","values":[
    #{"type":"current","unity":"A","info":"","data":1.0668689}]}]}]}

    
    
    readingsBeginUpdate($hash);
    
    readingsBulkUpdateIfChanged($hash,'serialNumber',$decode_json->{serial},1);
    readingsBulkUpdateIfChanged($hash,'smartPiName',$decode_json->{name},1);
    readingsBulkUpdateIfChanged($hash,'latitude',$decode_json->{lat},1);
    readingsBulkUpdateIfChanged($hash,'longitude',$decode_json->{lng},1);
    readingsBulkUpdateIfChanged($hash,'lastfetchTime',$decode_json->{time},1);
    readingsBulkUpdateIfChanged($hash,'serialNumber',$decode_json->{softwareversion},1);
    
    if( ref($decode_json->{datasets}) eq "ARRAY" and scalar(@{$decode_json->{datasets}}) > 0 ) {
    
        my $dataset;
        my $phase;
        my $value;
    
        foreach $dataset (@{$decode_json->{datasets}}) {
        
            readingsBulkUpdateIfChanged($hash,'datasetsTime',$dataset->{time},1);
            
            if( ref($dataset->{phases}) eq "ARRAY" and scalar(@{$dataset->{phases}}) > 0 ) {
            
                foreach $phase (@{$dataset->{phases}}) {
                    if( ref($phase->{values}) eq "ARRAY" and scalar(@{$phase->{values}}) > 0 ) {
                        foreach $value (@{$phase->{values}}) {
                            while( my ( $t, $v ) = each %{$value} ) {
        
                                readingsBulkUpdateIfChanged( $hash, "$phase->{name}_$t", $v, 1 ) if( defined( $v ) );
                            }
                        }
                    }
                }
            }
        }
    }

    readingsBulkUpdateIfChanged($hash,'state','done',1);
    
    readingsEndUpdate($hash,1);
}
