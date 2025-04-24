# Building a Programmable Software TSN Switch with P4

Time-Sensitive Networking (TSN) enhances traditional Ethernet with capabilities for reliable and predictable communication. It's widely used in systems where precise timing and low latency are critical, such as industrial automation, automotive networks, and professional media streaming.

One key component of TSN is the Time-Aware Shaper (TAS), which schedules traffic based on time slots to ensure that critical data is delivered exactly when needed. Traditionally, implementing TSN features like TAS required specialized hardware. However, recent developments in the Linux kernel have introduced native support for some TSN capabilities, such as [TAPRIO](https://www.man7.org/linux/man-pages/man8/tc-taprio.8.html) (Time-Aware Priority Scheduler).

This blog explores how to build a software-based TSN switch that's not only fully functional but also programmable using the P4 language. This combination brings the benefits of deterministic networking to a flexible, software-defined environment.


# Takeaway Messages

- A fully software-based TSN switch is now possible using Linux's built-in TSN capabilities. This opens up opportunities for testing and prototyping TSN features without requiring specialized hardware.

- By combining Linux's traffic shaping features with P4 programmability, we can create a TSN switch that reacts more intelligently and quickly to changing network conditions, offering better performance and control than traditional setups.



# Motivation

### Motivation for Building a Programmable TSN Switch  

TSN has traditionally relied on dedicated hardware that supports precise timing and scheduling. While powerful, such hardware is often costly and lacks flexibility. In response, recent versions of the Linux kernel have introduced support for features like TAPRIO qdisc, which allow time-aware traffic shaping in software.

Building on this, our earlier [blog post](https://blog.deterministic6g.eu/posts/2024/11/02/software_tsn_switch.html) showed how to configure a Linux bridge as a basic TSN switch. However, that approach had some limitations:

- Cumbersome configuration: It relies on auxiliary components, like `qdisc` and `tc` filters, to classify traffic, making configuration and management.

- Limited flexibility: The bridge's behavior is controlled via the `tc` tool from the control plane, which may introduce delays when rapid traffic adaptation is required.


To overcome these limitations, we introduce a programmable software TSN switch built on Linux's existing TSN features, with added programmability using the P4 language. This allows dynamic, real-time control of packet behavior directly from the data plane.


# Background

## TSN

TSN is a set of IEEE 802.1 standards that extend Ethernet to support deterministic communication with bounded latency, low jitter, and minimal packet loss. 

TAS is one of the core components of TSN, defined in IEEE 802.1Qbv, to enable time-division-based scheduling of network traffic by assigning transmission gates to traffic queues, which open and close according to a periodic schedule synchronized across the network. This allows critical traffic to be transmitted at precise time intervals, ensuring predictability.


## P4: Programming Protocol-independent Packet Processors

Programmable data planes fundamentally change the architecture of network devices by enabling direct control over packet processing logic at the forwarding layer. Unlike traditional fixed-function switches that rely on pre-defined behaviors hardcoded in hardware, programmable data planes allow users to  define how packets are parsed, matched, modified and forwarded. 

The core of this paradigm is P4, a domain-specific language. In contrast to a general purpose language such as C or Python, P4 is optimized for network data processing.
P4 programs are compiled to run on a variety of targets, including software switches (e.g., BMv2), programmable hardware switches based on FPGAs, or ASICs.


# A P4-based Programmable Software TSN switch

The P4 software switch (BMv2) is the key component, serving as the data plane responsible for packet processing. By utilizing the P4 programming language, we remove the dependency on manual traffic control commands, e.g., `tc`, enabling flexible and runtime adjustments. 

<img src="./img/switch.png" width="450px" />

Specifically, we integrate seamlessly the BMv2 with the TAPRIO qdisc. When a packet enters the BMv2, it undergoes a parsing process defined by the P4 program. This parsing step allows us to extract relevant fields from the packet header and perform logical processing as required. For instance, operations like In-band Network Telemetry (INT) can be implemented to monitor the packet's journey through the network, collecting data on latency, jitter, etc. 

After completing the logical processing, the VLAN Priority Code Point (PCP) in the packet header is updated to reflect its traffic class. Simultaneously, BMv2 updates the `skb->priority` value of the packet in the Linux kernel. The TAPRIO qdisc uses this `skb->priority` value to determine the appropriate traffic class for the packet. The packets of a same traffic class will be sent to the same output transmit (TX) queue, aligning it with the preconfigured time slots defined in the time-aware schedule.


Figure below show how each output packet is classified and attributed to corresponding TX queue based on its PCP:

<img src="img/map.png" width="650px"/>

As PCP is a 3-bit value, there are maximumally 8 traffic classes. By dynamically changing PCP of a packet, we can control its TX queue, thus shape the egress traffic. This approach eliminates the need for static configurations or manual intervention, offering a flexibility in handling diverse traffic patterns at runtime.


## Environment Setup

In this experimentation, we use Ubuntu 22.04 which is installed inside a Dell laptop.

As we use P4 language to program the switch, we need to install its compiler, `p4c`, and its executor, BMv2:

First of all, we need to clone the supported elements:

```bash
git clone https://github.com/DETERMINISTIC6G/det6g-blog-prog-soft-tsn-switch.git
```

### P4 compiler

For further information, go [here](https://github.com/p4lang/p4c?tab=readme-ov-file#ubuntu-dependencies)

```bash
source /etc/lsb-release
echo "deb http://download.opensuse.org/repositories/home:/p4lang/xUbuntu_${DISTRIB_RELEASE}/ /" | sudo tee /etc/apt/sources.list.d/home:p4lang.list
curl -fsSL https://download.opensuse.org/repositories/home:p4lang/xUbuntu_${DISTRIB_RELEASE}/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_p4lang.gpg > /dev/null
sudo apt-get update
sudo apt install p4lang-p4c
```


### P4 software switch - BMv2

A pre-compiled version of BMv2 is available [here](https://github.com/p4lang/behavioral-model). However, as we need to patch it to communicate with TAPRIO qdisc via `skb->priority`, we need to install it from source code within our patch.

```bash
# install requirements
sudo apt-get install -y automake cmake libgmp-dev \
    libpcap-dev libboost-dev libboost-test-dev libboost-program-options-dev \
    libboost-system-dev libboost-filesystem-dev libboost-thread-dev \
    libevent-dev libtool flex bison pkg-config g++ libssl-dev
# clone source code
git clone https://github.com/p4lang/behavioral-model.git
# apply our patch
cd behavioral-model
# the latest patch is available here: https://github.com/p4lang/behavioral-model/compare/main...montimage-projects:behavioral-model:main
git checkout 199af48 #same moment we patched BMv2
git apply ../bmv2/bmv2.patch
# compile and install (will take few minutes)
./autogen.sh && ./configure && make -j && sudo make install && cd ..
```

### Testbed

As an example, we will implement a software TSN switch having an input port and an output port to connect a talker and a listener as shown in the following figure.

<img src="img/testbed.png" width="500px" />

To implement this testbed on a single machine, the talker and listener are isolated in two separate containers to prevent direct communication between them. Each container, that is typically a Linux namespace, connects to the switch via a virtual Ethernet link that, like a cable, acutally has 2 ends. When a packet is sent to one end, it becomes available at the other.


We first create 2 namespaces, `talker` and `listener`:
```bash
sudo ip netns add talker
sudo ip netns add listener
```

Then create 2 virtual Ethernet links. 

```bash
sudo ip link add veth-ta type veth peer name veth-tb
sudo ip link add veth-la type veth peer name veth-lb
```

We attach one end of each link to its corresponding container.

```bash
sudo ip link set veth-ta netns talker
sudo ip link set veth-la netns listener
```

We must also activate the links by bringing up its ends:

```bash
sudo ip netns exec talker   ip link set veth-ta up
sudo ip netns exec listener ip link set veth-la up
sudo ip link set veth-tb up
sudo ip link set veth-lb up
```

Then set IP addresses for the ends inside `talker` and `listener` namespaces:

```bash
sudo ip netns exec talker   ip address add 10.0.0.1/24 dev veth-ta
sudo ip netns exec listener ip address add 10.0.0.2/24 dev veth-la
```

We also need to disable its offload features which can cause Linux kernel to incorrectly calculcate checksum of packets:

```bash
sudo ip netns exec talker   ethtool --offload veth-ta tx off rx off
sudo ip netns exec listener ethtool --offload veth-la tx off rx off
```


In this demo, we suppose that there are 2 traffic classes, TC0 and TC1 which will be sent into separated 2 TX queues. Thus we need to set number of TX queues to 2:

```bash
sudo ethtool -L veth-lb tx 2
```

Finally, we attach the TAPRIO qdisc to the output port of the switch:

```bash
sudo tc qdisc replace dev veth-lb parent root handle 100 taprio \
     num_tc 2 \
     map 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 \
     queues 1@0 1@1 \
     base-time 1554445635681310809 \
     sched-entry S 01 100000000 sched-entry S 03 50000000 \
     clockid CLOCK_TAI
```

The essensital parameters are as below:

- `num_tc 2`: there are 2 traffic classes
- `map 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0`: maps skb priorities 0..15 to a specified traffic class (TC). Specifically,
    - map priority 0 (first bit from the left) to TC0
    - map priority 1 to TC1
    - and priorities 2-15 to TC0 (16 mappings for 16 possible traffic classes).

- `queues 1@0 1@1`: map traffic classes to TX queues of the network device.
 Its values use the format `count@offset`. Specifically,
    - map the firs traffic class (TC0) to 1 queue strating at offset 0 (first queue)
    - map the second traffic class (TC1) to 1 queue starting at offset 1 (second queue)

- `sched-entry S 01 100000000 sched-entry S 03 50000000`: define the intervals, in nanoseconds, during which gates are open or closed. For the first 100ms, only the gate of 1st TX queue is opened. Then the next 50ms, gates of both 1st and 2nd (indicated by the 1st and 2nd bits of `03`) TX queues are opended. This means that, TX queue for TC0 is always available; the one for TC1 is 100 ms unavailable and 50 ms available (cycle time is 150 ms).


## Test

Based on the TAPRIO qdisc configuration described above, TC0 packets can be transmitted at any time, whereas TC1 packets are allowed to transmit only during a 50 ms window in each 150 ms cycle. This setup may lead to underutilization of the egress link's bandwidth, especially when only TC1 packets are present.

In this test, we demonstrate that TC1 traffic can opportunistically use TC0's transmission queue if it has remained idle for more than one second. For simplicity, we assign UDP packets with destination port 1000 to TC0, and all other traffic to TC1. We use UDP instead of TCP to avoid the influence of TCP's congestion control mechanisms which may impact traffic rate.

The switch's behavior is controlled by [switch.p4](./switch.p4) program. It contains multiple `control` blocks to parse Ethernet, VLAN, IPv4, UDP headers; perform basic routing; and dynamically adjust PCP value of each packet.
While we won't cover all of these components due to space constraints, let's focus on the most relevant and interesting part, dynamic PCP adjustment, as shown in the snippet below:

```P4
//an array having only one element of 48 bits
//  to store timestamp of the most recent packet belong to traffic class 0, TC0
register <bit<48>>(1) last_tc0_packet_ts;

control myEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t std_data) {
    bit<48> ts;
    bit<48> last_ts;
    apply {
        //enable VLAN if it is not existing
        if( ! hdr.vlan.isValid() ){
            hdr.vlan.setValid();
            hdr.vlan.etherType = hdr.ethernet.etherType;
            hdr.ethernet.etherType = TYPE_VLAN;
        }

        @atomic {
            //get ingress timestamp (in microsecond) of the current packet
            ts = std_data.ingress_global_timestamp;
            //dynamically adjust VLAN PCP
            if( hdr.udp.isValid() && hdr.udp.dstPort == 1000 ){
                hdr.vlan.pcp = 0;
                // remember timestamp of the last packet of TC0
                //   to the first element of the array
                last_tc0_packet_ts.write( 0, ts);
            } else {
                // get the timestamp from the first element of the array
                last_tc0_packet_ts.read( last_ts, 0 );
                if( ts - last_ts > 1*1000*1000 )
                    hdr.vlan.pcp = 0;
                else
                    hdr.vlan.pcp = 1;
            }
        }
    }
}
```


We begin by declaring a *global* variable named `last_tc0_packet_ts` to record the ingress timestamp of the most recent TC0 packet observed.

The core logic is implemented inside the `apply` block. It first ensures that a VLAN header is present in the output packet. Next, if the current packet is a UDP packet with destination port 1000, its PCP field is set to 0, indicating traffic class TC0. For all other packets, the switch compares the current packet's ingress timestamp with the timestamp of the last observed TC0 packet. If more than 1 second has elapsed, the packet is treated as TC0 by setting its PCP to 0; otherwise, it is classified as TC1 by setting the PCP to 1. 

This logic is enclosed within an `atomic` block to ensure that the `write` and `read` operations on the global variable `last_tc0_packet_ts` are executed sequentially and consitently.

This mechanism effectively implements a simple, time-aware packet prioritization strategy directly in the programmable data plane, enabling more flexible traffic handling without relying on the control plane.

We need to compile the P4 code:

```bash
p4c --target  bmv2  --arch  v1model switch.p4
```

Then start the BMv2:

```bash
sudo simple_switch -i 1@veth-tb -i 2@veth-lb switch.json &
```

Start 2 iPerf servers:

```bash
sudo ip netns exec listener iperf3 --server --port 1000 --daemon
sudo ip netns exec listener iperf3 --server --port 2000 --daemon
```

We use tcpdump to capture the output packets of the switch so we can check its traffic shaping:

```bash
sudo ip netns exec listener tcpdump -i veth-la -w trace.pcap --time-stamp-precision=nano --snap 100 tcp or udp &
```

Then start the iPerf clients inside `talker` namespace to generate UDP traffic:

```bash
sudo ip netns exec talker bash -c 'iperf3 --client 10.0.0.2 --port 1000 --udp --time 3 & iperf3 --client 10.0.0.2 --port 2000 --udp --time 5'
```


Stop tcpdump, then plot the traffic shapping:

```bash
python3 ./plot.py
```

We obtain the following figure which illustrates the arrival times of packets at the listener:

<img src="img/arrival_time.png" />

Each vertical line represents the arrival of a single packet. The traffic throughput for each traffic class is set to 1 Mbps, resulting in a total of 789 packets transmitted during the experiment.

The results confirm that TAS is effective and functions as expected. During the first 3 seconds, both traffic classes, TC0 and TC1, are active. As configured in the TAPRIO qdisc, TC1 is transmitted only within its allocated 50 ms time slots in each 150 ms cycle, while TC0 packets are sent without restriction.

After 3 seconds, TC0 traffic ends, leaving its time slots unused. During this period, TC1 continues to transmit only during its scheduled windows, resulting in the egress link being utilized at only one-third of its capacity.

However, after 1 additional second, the system detects that TC0 has been inactive, and TC1 begins to utilize all available time slots, demonstrating the switch's ability to opportunistically reuse idle transmission queues to improve bandwidth efficiency.
