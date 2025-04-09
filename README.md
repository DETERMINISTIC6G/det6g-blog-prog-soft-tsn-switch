# A P4-Programmable Software TSN Switch for Deterministic Networking

In this post, we present a software TSN switch which can be programmable using P4 language to control the switch's behaviour from the data plane at runtime.

# tl;dr - Takeaway Messages

- The Time-Aware Priority shaper (TAPRIO) is one technology to implement the Time-Aware Shaper (TAS) on Linux software bridges.
- 

# Motivation

### Motivation for Building a Programmable TSN Switch  

Time-Sensitive Networking (TSN) is a crucial technology for achieving deterministic communication in various domains, including industrial automation, automotive networks, and telecommunications. However, traditional TSN implementations typically rely on hardware-specific devices, limiting their flexibility and adaptability.  

To bridge this gap, the Linux kernel has recently integrated several TSN-related features, such as the Time-Aware Traffic Shaper (TAPRIO) qdisc, enabling software-based TSN capabilities. By leveraging these features, it is possible to construct a software-based TSN bridge, as demonstrated in our previous [blog post](https://blog.deterministic6g.eu/posts/2024/11/02/software_tsn_switch.html). However, this software bridge comes with some limitations:

- Cumbersome: It relies on additional components, such as `qdisc` and `tc` filters, to classify traffic based on priority, making configuration and management complex.

- Inflexibility: The bridge's behavior is controlled via the `tc` tool from the control plane, which may introduce delays when rapid traffic adaptation is required.

In this blog post, we introduce a software TSN switch programmable with P4, combining the deterministic features of TSN with the flexibility and programmability of P4-enabled data planes. Our switch is built on Linux’s TAPRIO qdisc, which is essential for traffic shaping in TSN environments. By integrating P4 programmability, the switch enables dynamic traffic management, including real-time packet classification, adaptive scheduling, and in-depth network monitoring. This approach provides a more agile, scalable, and customizable solution for modern deterministic networking needs.


# Background

## TSN

## P4

# A P4-Programmable Software TSN switch

The P4 Virtual Switch (BMv2) is the key component of the switch, serving as the data plane responsible for packet processing. By utilizing the P4 programming language, the switch allows users to define at runtime how packets are processed, classified, forwarded them to appropriate qdisc ports. This programmability removes the dependency on manual traffic control commands, e.g., tc, enabling flexible and runtime adjustments. 

<img src="./img/switch.png" width="400px" />

Specifically, the BMv2 virtual switch integrates seamlessly with the TAPRIO qdisc by leveraging Linux packet priority. When a packet enters the BMv2, it undergoes a parsing process defined by the P4 program. This parsing step allows users to extract relevant fields from the packet header and perform logical processing as required. For instance, operations like In-band Network Telemetry (INT) can be implemented to monitor the packet's journey through the network, collecting data on latency, jitter, or path utilization. After completing the logical processing, the VLAN Priority Code Point (PCP) in the packet header is updated to reflect its traffic class or priority. Simultaneously, BMv2 updates the `skb->priority` value of the packet in the Linux kernel. The TAPRIO qdisc uses this priority value to determine the appropriate output queue for the packet, aligning it with the preconfigured time slots defined in the time-aware schedule. By dynamically setting priorities at runtime, this approach eliminates the need for static configurations or manual intervention, offering greater flexibility in handling diverse traffic patterns.


## Environment Setup

In this experimentation, we use Ubuntu 22.04 which is installed inside a virtual machine.

### P4 compiler

For further information, go [here](https://github.com/p4lang/p4c?tab=readme-ov-file#ubuntu-dependencies)

```bash
source /etc/lsb-release
echo "deb http://download.opensuse.org/repositories/home:/p4lang/xUbuntu_${DISTRIB_RELEASE}/ /" | sudo tee /etc/apt/sources.list.d/home:p4lang.list
curl -fsSL https://download.opensuse.org/repositories/home:p4lang/xUbuntu_${DISTRIB_RELEASE}/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_p4lang.gpg > /dev/null
sudo apt-get update
sudo apt install p4lang-p4c
```


### P4 virtual switch - BMv2

A pre-compiled version of BMv2 is available [here](https://github.com/p4lang/behavioral-model). However, we need to patch this switch to communicate with TAPRIO qdisc via `skb->priority`, then we need to install it from source code within our patch.

```bash
# install requirements
sudo apt-get install -y automake cmake libgmp-dev \
    libpcap-dev libboost-dev libboost-test-dev libboost-program-options-dev \
    libboost-system-dev libboost-filesystem-dev libboost-thread-dev \
    libevent-dev libtool flex bison pkg-config g++ libssl-dev
# clone source code
git clone https://github.com/p4lang/behavioral-model.git
# apply our patch
cd behaviral-model
# the latest patch is available here: https://github.com/p4lang/behavioral-model/compare/main...montimage-projects:behavioral-model:main
git checkout 199af48 #moment I tested BMv2
git apply ../bmv2/bmv2.patch
# compile and install
./autogen.sh && ./configure && make -j && sudo make install
```

### Testbed

We first create 2 namespaces, `talker` and `listener`:
```bash
sudo ip netns add talker
sudo ip netns add listener
```


```bash
sudo ip link add veth-ta type veth peer name veth-tb
sudo ip link add veth-la type veth peer name veth-lb numtxqueues 2
```

```bash
sudo ip link set veth-ta netns talker
sudo ip link set veth-la netns listener
```

We must also bring all interfaces up:

```bash
sudo ip netns exec talker veth-ta up
sudo ip netns exec listener veth-la up
sudo ip link set veth-tb up
sudo ip link set veth-lb up
```

```bash
sudo tc qdisc replace dev veth-lb parent root handle 100 taprio \
num_tc 2 \
map 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 \
queues 1@0 1@1 \
base-time 1554445635681310809 \
sched-entry S 01 100000000 sched-entry S 03 50000000 \
clockid CLOCK_TAI
```

## Test



```P4
/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x0800;
const bit<16> TYPE_VLAN = 0x8100;

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

control myIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std_data) {

    apply {
        // naif routing
        if( std_data.ingress_port == 1 ){
            std_data.egress_spec = 2;
         } else {
            std_data.egress_spec = 1;
         }

         //enable VLAN if it is not existing
         if( ! hdr.vlan.isValid() ){
             hdr.vlan.setValid();
             hdr.vlan.etherType = hdr.ethernet.etherType;
             hdr.ethernet.etherType = TYPE_VLAN;
         }

         //dynamically adjust VLAN PCP
         if( hdr.udp.dstPort == 6666 )
             hdr.vlan.pcp = 1;
         else
             hdr.vlan.pcp = 0;
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
```