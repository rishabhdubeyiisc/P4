/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> TYPE_UDP = 0x11;
const bit<8> TYPE_ICMP = 0x01;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
//Defining some types 
typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
//Defining some types 
header ethernet_t {
          macAddr_t dstAddr;
          macAddr_t srcAddr;
          bit<16>   etherType;
}
//ipv4 header we will extract
header ipv4_t {
          bit<4>    version;
          bit<4>    ihl;
          bit<8>    diffserv;
          bit<16>   totalLen;
          bit<16>   identification;
          bit<3>    flags;
          bit<13>   fragOffset;
          bit<8>    ttl;
          bit<8>    protocol;
          bit<16>   hdrChecksum;
          ip4Addr_t srcAddr;
          ip4Addr_t dstAddr;
}
header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> lenght;
    bit<16> checksum;
}

header icmp_t {
    bit<8> type ;
    bit<8> code ;
    bit<16> checksum ;
}
// no metadata
struct metadata {
    /* empty */
}
// combining the headers in struct as non alignment is better
struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    udp_t        udp;
    icmp_t       icmp;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/
// packet_in is predefined 
// out type is headers
// inout metadatas 
parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
        // simple transit to next state that is parse ethernet header
        state start {
		    transition parse_ethernet;    
    	}
        // extract ethernet header
    	state parse_ethernet {
		packet.extract(hdr.ethernet);
		transition select (hdr.ethernet.etherType) {
			// if type of ethernet is IPv4 then extract ipv4 header out
            TYPE_IPV4 : parse_ipv4;
			default : accept;
		}
	}
	state parse_ipv4 {
		packet.extract(hdr.ipv4);
        transition select (hdr.ipv4.protocol){
            TYPE_UDP : parse_UDP;
            TYPE_ICMP  : parse_ICMP;
            default : accept;
        }
	}
    state parse_UDP {
        packet.extract(hdr.udp);
        transition accept;
    }
    state parse_ICMP {
        packet.extract(hdr.icmp);
        transition accept;
    }
}
/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {   
          apply {  } 
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    // actions are functions same as in C
    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr ;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
    table ipv4_lpm_udp_valid {
        key = {
                    hdr.ipv4.dstAddr: lpm;
        }
        actions = {
                    ipv4_forward;
                    drop;
                    NoAction;
        }
        size = 1024;
        default_action = drop();
    }
    table ipv4_lpm_icmp_valid {
        key = {
                    hdr.ipv4.dstAddr: lpm;
        }
        actions = {
                    ipv4_forward;
                    drop;
                    NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    apply {
        if (hdr.udp.isValid()){
            ipv4_lpm_udp_valid.apply();
        }
        if (hdr.icmp.isValid()){
            ipv4_lpm_icmp_valid.apply();
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
          apply {  } 
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
          apply {
                    update_checksum(    
                        hdr.ipv4.isValid(),
                    {         
                        hdr.ipv4.version,
                        hdr.ipv4.ihl,
                        hdr.ipv4.diffserv,
                        hdr.ipv4.totalLen,
                        hdr.ipv4.identification,
                        hdr.ipv4.flags,
                        hdr.ipv4.fragOffset,
                        hdr.ipv4.ttl,
                        hdr.ipv4.protocol,
                        hdr.ipv4.srcAddr,
                        hdr.ipv4.dstAddr 
                    },
                    hdr.ipv4.hdrChecksum,
                    HashAlgorithm.csum16);
          }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
	    packet.emit(hdr.ipv4);
            packet.emit(hdr.udp);
            packet.emit(hdr.icmp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/
 
V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
