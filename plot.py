#!/usr/bin/python3

# Contact:
#   huunghia.nguyen@montimage.com
#
import time
import numpy as np

# to plot statistic
from scapy.all import rdpcap, IP, UDP
import matplotlib.pyplot as plt
# avoid showing plot window
import matplotlib as mpl
mpl.use('Agg')


# Read the PCAP file
packets = rdpcap("trace.pcap")

# Dictionary to store the arrival times per traffic class
data = {"UDP:1000": [], "Other": []}

print("loading packets' timestamp ...")
first_time = 0
# range of 1 second
RANGE = [0, 6]
#RANGE = [0, 1000000]
# Iterate over the packets
for pkt in packets:
    
    #only interested in IP packet
    if IP not in pkt:
        continue
    
    #only interested in IP packet which target to the talker
    if pkt[IP].dst != "10.0.0.2":
        continue

    # Extract the packet timestamp and destination port
    arrival_time = pkt.time # e.g., 1712073023.619379
    
    # start Ox at the first UDP packet (starting bandwidth test)
    if first_time == 0:
        first_time = arrival_time
    
    #use offset to plot
    offset = arrival_time - first_time
    
    # take into account only packets in RANGE
    if offset < RANGE[0]:
        continue
    if  offset > RANGE[1]:
        break;

    # Add the arrival time to the list for the destination port
    if (UDP in pkt) and (pkt[UDP].dport == 1000):
        data["UDP:1000"].append(offset)
        None
    else:
        data["Other"].append(offset)
        None

print("plotting ...")
# Plotting
plt.figure(figsize=(12, 3))

# Create a colormap for the different ports
colors = {"UDP:1000": "red", "Other": "blue"}

# Assign a color for each port and plot its vertical lines
for proto in data:
    plt.vlines(data[proto], ymin=0, ymax=1, colors=colors[proto], alpha=0.6, label=proto)

# Formatting the plot
plt.title('Packet Arrival Times')
plt.xlabel('Arrival Time (s)') #nanosecond
plt.ylabel(None)
# Hide y-axis ticks and tick labels
plt.tick_params(axis='y', which='both', left=False, labelleft=False)

# Set x-axis ticks every 0.5 units
plt.xticks(np.arange(RANGE[0], RANGE[1], 0.5))  # From 0 to 5, step 0.5

plt.legend(loc='upper right', bbox_to_anchor=(1.15, 1))
#plt.grid(True)
plt.savefig( "arrival_time.png", dpi=200, format='png', bbox_inches='tight')
