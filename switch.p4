/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_VLAN = 0x8100;

const bit<8>  TYPE_TCP  = 6;

typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header vlan_h {
    bit<3> pcp;
    bit<1> dei;
    bit<12> vid;
    bit<16> etherType;
}


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

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t   ethernet;
    vlan_h       vlan;
    ipv4_t       ipv4;
}

parser myParser(packet_in packet, out headers hdr,
    inout metadata meta, inout standard_metadata_t std_data) {

    state start {

        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){
            TYPE_VLAN: parse_vlan; 
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_vlan {
        packet.extract(hdr.vlan);
        transition select(hdr.vlan.etherType){
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}


control myVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

// an array having only one element of 48 bits
register <bit<48>>(1) last_tcp_packet_ts;

control myIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std_data) {
    bit<48> ts;
    bit<48> last_ts;
    apply {
        // naif routing
        if( std_data.ingress_port == 1 )
            std_data.egress_spec = 2;
        else
           std_data.egress_spec = 1;

        //enable VLAN if it is not existing
        if( ! hdr.vlan.isValid() ){
            hdr.vlan.setValid();
            hdr.vlan.etherType = hdr.ethernet.etherType;
            hdr.ethernet.etherType = TYPE_VLAN;
        }

        //get ingress timestamp (in microsecond) of the current packet
        ts = std_data.ingress_global_timestamp;
        //dynamically adjust VLAN PCP
        if( hdr.ipv4.protocol == TYPE_TCP ){
            hdr.vlan.pcp = 0;
            // remember timestamp of the last TCP packet
            //   to the first element of the array
            last_tcp_packet_ts.write( 0, ts);
        } else {
            // get the timestamp from the first element of the array
            last_tcp_packet_ts.read( last_ts, 0 );
            if( ts - last_ts > 1*1000*1000 )
                hdr.vlan.pcp = 0;
            else
                hdr.vlan.pcp = 1;
        }
    }
}

control myEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t std_data) {
    apply {}
}

control myComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {}
}

control myDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.vlan);
        packet.emit(hdr.ipv4);
    }
}

//switch architecture
V1Switch( 
  myParser(), myVerifyChecksum(), myIngress(), myEgress(), myComputeChecksum(), myDeparser()
) main;