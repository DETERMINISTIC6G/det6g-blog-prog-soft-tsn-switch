#!/usr/bin/python3

# Contact:
#   huunghia.nguyen@montimage.com
#
import time

# to plot statistic
from scapy.all import rdpcap, TCP, UDP
import matplotlib.pyplot as plt
# avoid showing plot window
import matplotlib as mpl
mpl.use('Agg')


# Read the PCAP file
packets = rdpcap("trace.pcap")

# Dictionary to store the arrival times per protocol, either UDP or TCP
data = {"UDP": [], "TCP": []}

print("loading packets' timestamp ...")
first_time = 0
# range of 1 second
RANGE = [2, 3]
#RANGE = [0, 1000000]
# Iterate over the packets
for pkt in packets:
    # Extract the packet timestamp and destination port
    arrival_time = pkt.time # e.g., 1712073023.619379
    
    # take into account only the packets arriving in RANGE
    if first_time == 0:
        first_time = arrival_time
    
    #use offset to plot
    offset = arrival_time - first_time
    
    # take into account only packets in RANGE
    if offset < RANGE[0]:
        continue
    if  offset > RANGE[1]:
        break;

    #offset -= RANGE[0]

    # Add the arrival time to the list for the destination port
    if TCP in pkt:
        data["TCP"].append(offset)
    else:
        data["UDP"].append(offset)

print("plotting ...")
# Plotting
plt.figure(figsize=(10, 6))

# Create a colormap for the different ports
colors = {"TCP": "red", "UDP": "blue"}

# Assign a color for each port and plot its vertical lines
for proto in data:
    plt.vlines(data[proto], ymin=0, ymax=1, colors=colors[proto], alpha=0.6, label=proto)

# Formatting the plot
plt.title('Packet Arrival Times')
plt.xlabel('Arrival Time (s)') #nanosecond
plt.ylabel('packet')
plt.legend(loc='upper right', bbox_to_anchor=(1.15, 1))
plt.grid(True)
plt.savefig( "arrival_time.pdf", dpi=30, format='pdf', bbox_inches='tight')
