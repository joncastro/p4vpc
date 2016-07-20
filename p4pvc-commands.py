import sys
import argparse
import networkx as nx
from minip4.p4topo import P4Topo


def get_subnet(ip, mask):
    mask = convert_mask(mask)
    ip = convert_ip(ip)
    ip = ip & mask
    return '.'.join([str((ip >> 8 * i) % 256) for i in [3, 2, 1, 0]])


def convert_ip(ip):
    return int('0x{:02X}{:02X}{:02X}{:02X}'.format(*map(int, ip.split('.'))), 16)


def convert_mask(mask):
    bits = 0
    for i in xrange(32 - int(mask), 32):
        bits |= (1 << i)
    return bits


def are_in_same_subnet(ip, mask, ipB):
    mask = convert_mask(mask)
    ip = convert_ip(ip)
    ipB = convert_ip(ipB)

    return (ip & mask) == (ipB & mask)


def run(p4topo):

    hosts = p4topo.hosts
    switches = p4topo.switches
    links = p4topo.links
    host_connected_switch = p4topo.host_connected_switch
    portmap = p4topo.portmap
    print portmap

    host_customers = {}
    commands = {}

    for name in hosts:
        host = hosts[name]
        if 'customer' not in host:
            host['customer'] = 1
        customer = host['customer']
        if customer not in host_customers:
            host_customers[customer] = []
        host_customers[customer].append(name)

    G = nx.Graph()
    for link in p4topo.links:
        G.add_edge(link['source'], link['destination'])

    for name in switches:
        commands[name] = []
        commands[name].append(
            'table_set_default address_ip_packet set_address_ip_packet')
        commands[name].append(
            'table_set_default address_arp_packet set_address_arp_packet')
        commands[name].append('table_set_default encapsulate_vpc push_vpc')
        commands[name].append('table_set_default vpc_dst _drop')
        commands[name].append('table_set_default vpc_customer _drop')
        commands[name].append('table_set_default arp_reply _drop')
        commands[name].append('table_set_default l2_addr _noop')
        commands[name].append(
            'table_add vpc_sw_id set_vpc_src_sw_id => {}'.format(switches[name]['id']))

    for host_name in host_connected_switch:
        host = hosts[host_name]
        mac = host['mac']
        ip = host['ip'].split('/')[0]
        mask = host['ip'].split('/')[1]
        subnet = get_subnet(ip, mask)
        gw = host['gw']
        mac_to_hex = str(hex(int(int('0x' + gw.replace('.', ''), 16))))[2:].zfill(12)
        blocks = [mac_to_hex[x:x + 2] for x in xrange(0, len(mac_to_hex), 2)]
        gw_mac = ':'.join(blocks)
        customer = host['customer']

        sw_name = host_connected_switch[host_name]
        switch = switches[sw_name]
        sw_id = switch['id']

        port = portmap[sw_name][host_name]
        commands[sw_name].append('table_add vpc_customer set_vpc_customer {} {} => {}'.format(mac, ip, customer))
        commands[sw_name].append(
            'table_add arp_reply set_arp_reply {} {}/{} {} => {}'.format(customer, subnet, mask, ip, gw_mac))
        commands[sw_name].append(
            'table_add arp_reply set_arp_reply {} {}/{} {} => {}'.format(customer, subnet, mask, gw, gw_mac))
        commands[sw_name].append(
            'table_add l2_addr _noop {} {} {}/{} {} => '.format(customer, sw_id, subnet, mask, ip))
        commands[sw_name].append(
            'table_add l2_addr set_l2_addr {} {} 0.0.0.0/0 {} => {} {}'.format(customer, sw_id, ip, gw_mac, mac))

        commands[sw_name].append(
            'table_add deliver_pvc pop_route_vpc {} {} {}/32 => {}'.format(sw_id, customer, ip, port))

        for remote_host_name in host_customers[customer]:
            if remote_host_name == host_name:
                continue
            remote_ip = hosts[remote_host_name]['ip'].split('/')[0]
            remote_mask = hosts[remote_host_name]['ip'].split('/')[1]
            remote_mac = hosts[remote_host_name]['mac']
            remote_subnet = subnet = get_subnet(remote_ip, remote_mask)
            remote_switch = switches[host_connected_switch[remote_host_name]]['id']
            remote_gw = host['gw']
            mac_to_hex = str(hex(int(int('0x' + remote_gw.replace('.', ''), 16))))[2:].zfill(12)
            blocks = [mac_to_hex[x:x + 2] for x in xrange(0, len(mac_to_hex), 2)]
            remote_gw_mac = ':'.join(blocks)
            commands[sw_name].append(
                'table_add vpc_dst set_vpc_dst {} {}/32 => {}'.format(customer, remote_ip, remote_switch))

            if are_in_same_subnet(ip, mask, remote_ip):
                commands[sw_name].append(
                    'table_add arp_reply set_arp_reply {} {}/{} {} => {}'.format(customer, subnet, mask, remote_ip, remote_mac))

    shortest_paths = nx.shortest_path(G)

    for src_sw_name in switches:
        for dst_sw_name in switches:
            if src_sw_name == dst_sw_name:
                continue
            if src_sw_name in shortest_paths and dst_sw_name in shortest_paths[src_sw_name]:
                shortest_path = shortest_paths[src_sw_name][dst_sw_name]
                hops = len(shortest_path)
                if hops < 2:
                    print "{} and {} not connected".format(src_sw_name, dst_sw_name)
                    continue

                first = shortest_path[0]
                second = shortest_path[1]
                commands[src_sw_name].append('table_add routing_pvc route_vpc {} => {}'.format(
                    switches[dst_sw_name]['id'], portmap[src_sw_name][second]))

    for sw_name in switches:
        with open("commands-{}.txt".format(sw_name), 'w') as f:
            cmdlist = list(set(commands[sw_name]))
            cmdlist.sort()
            f.write('\n'.join(cmdlist))


class SRSWCommands(object):
    """ Segment Routing Switch Commands """

    def __init__(self):
        self.prog = 'vpc-commands'

        parser = argparse.ArgumentParser(description='VPC Commands Generator')
        parser.add_argument('-t', '--topology',
                            help='Topology yaml file. Default; p4-topo.yml',
                            type=str,
                            action="store",
                            default='p4-topo.yml',
                            required=False)

        parser.add_argument('-s', '--p4src',
                            help='Path to p4 source file',
                            type=str,
                            action="store",
                            required=False)

        args = parser.parse_args()

        p4topo = P4Topo(args.topology, p4src=args.p4src)

        run(p4topo)


def main():
    SRSWCommands()

if __name__ == "__main__":
    main()
