# P4 Virtual Private Cloud (P4VPC)

This repository contains an experimental [P4](https://github.com/p4lang) program to enable a Virtual Private Cloud with P4 based switches.

**P4VPC** tries to emulate Amazon VPC solution as described in [this presentation](https://www.youtube.com/watch?v=Zd5hsL-JNY4).

- [Execute](#execute)
- [Topology YAML](#topology-yaml)
- [Demo](#demo)

## Execute

### From source

```
git clone https://github.com/joncastro/p4vpc
cd p4vpc
python p4vpc-commands.py
sudo mnp4
```

### Dependencies

- [MiniP4](https://github.com/joncastro/minip4)

### P4 switches commands

`p4vpc-commands.py` script generates all the required P4 switch commands for the given topology.

## Topology YAML

The topology YAML file follows the [MiniP4 definition](https://github.com/joncastro/minip4#topology-yaml) and only adds `customer` optional property with it sets to `1` by default is not given.

## Demo

Given `p4-topo.yml` topology contains two customers with the same number of hosts and ip addresses. This demo explains how run and test network reachability between hosts belonging to the same customer.

The topology contains two customer `red` and `blue`. Both customer contains the same number of hosts and ip addresses. Host mac addresses are unique.

Each customer has two subnets: `10.0.0.0/24` and `192.168.0.0/24`.

- **pinging two hosts in the same subnet**

The hosts that starts the ping will first send an ARP request to discover the mac address of the destination host. Notice that the ARP request is returned directly by the P4 switch using the table `arp_reply` and this ARP request is not flooded into the network. P4 captures the ARP packet and transforms the packet into ARP reply sending it back to the host. P4 switches are pre-populated with the mac addresses on the same subnet.

Then, the source host sends an ICMP request to the destination switch. The initial P4 switch captures the IP packet and encapsulate into a new header type called `vpc`. This encapsulation mechanism contains the customer, source and destination switch, and source and destination IP.

The packet is transmitted through the network and the egress P4 switch will remove the `vpc` header and deliver the packet to the destination host.

The ICMP reply from the destination host to the source switch is treated in the same way.

**Testing**

Ping from host `h102red` to `h103red`.

```
mininet> h102red ping h103red
PING 10.0.0.3 (10.0.0.3) 56(84) bytes of data.
64 bytes from 10.0.0.3: icmp_seq=1 ttl=64 time=4.40 ms
```

To ensure `h103red` is the one replying to the ICMP packet, execute `h102red nc h103red 8888` which will return the mac address and then very that it is the same as the one by execute `h103red ifconfig eth0`

Note: all hosts creates a netcat process listening on 8888 which returns the mac address of eth0 using `scripts/netcat_hostname.sh` script.

```
mininet> h102red nc h103red 8888
eth0 00:00:00:00:00:67
mininet> h103red ifconfig eth0
nohup: appending output to ‘nohup.out’
eth0      Link encap:Ethernet  HWaddr 00:00:00:00:00:67
          inet addr:10.0.0.3  Bcast:10.0.0.255  Mask:255.255.255.0
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:14 errors:0 dropped:0 overruns:0 frame:0
          TX packets:9 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:1060 (1.0 KB)  TX bytes:705 (705.0 B)

mininet>
```

- **pinging two hosts in different subnets**

In this case, two hosts in different subnets require a gateway in between to talk each other. Notice, this gateway does not really exists in our topology and P4VPC emulates this non-existing gateway. When the hosts send the ARP requests to obtain the gateway mac address, the P4 switch will capture and convert that packet into a reply with the fictitious gateway mac address.

Then the source host will send a ICMP packet to the destination host and P4 switches will perform the same encapsulation. The only difference is the ethernet source and destination mac address will be overwritten to the gateway on destination switch before delivering into the port.

**Testing**

Ping from host `h102red` to `h202red`.

```
mininet> h102red ping h202red
PING 192.168.0.2 (192.168.0.2) 56(84) bytes of data.
64 bytes from 192.168.0.2: icmp_seq=1 ttl=64 time=2.13 ms
```

To ensure `h202red` is the one replying to the ICMP packet, execute `h102red nc h202red 8888` which will return the mac address and then very that it is the same as the one by execute `h202red ifconfig eth0`

```
mininet> h102red nc h202red 8888
eth0 00:00:00:00:00:ca
mininet> h202red ifconfig eth0
eth0      Link encap:Ethernet  HWaddr 00:00:00:00:00:ca
          inet addr:192.168.0.2  Bcast:192.168.0.255  Mask:255.255.255.0
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:16 errors:0 dropped:0 overruns:0 frame:0
          TX packets:13 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000
          RX bytes:1200 (1.2 KB)  TX bytes:1013 (1.0 KB)

mininet>
```
