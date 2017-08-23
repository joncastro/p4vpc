parser start {
    return parse_ethernet;
}

#define ETHERTYPE_VPC  0x0777
#define ETHERTYPE_ARP  0x0806
#define ETHERTYPE_IPV4 0x0800

header ethernet_t ethernet;

parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        ETHERTYPE_VPC : parse_vpc;
        ETHERTYPE_IPV4 : parse_ipv4;
        ETHERTYPE_ARP : parse_arp_rarp;
        default: ingress;
    }
}

header vpc_t vpc;

parser parse_vpc {
    extract(vpc);
    return select(latest.etherType) {
        ETHERTYPE_IPV4 : parse_ipv4;
        ETHERTYPE_ARP : parse_arp_rarp;
        default: ingress;
    }
}

#define ARP_PROTOTYPES_ARP_RARP_IPV4 0x0800

header arp_rarp_t arp_rarp;

parser parse_arp_rarp {
    extract(arp_rarp);
    return select(latest.protoType) {
        ARP_PROTOTYPES_ARP_RARP_IPV4 : parse_arp_rarp_ipv4;
        default: ingress;
    }
}

header arp_rarp_ipv4_t arp_rarp_ipv4;

parser parse_arp_rarp_ipv4 {
    extract(arp_rarp_ipv4);
    return ingress;
}

header ipv4_t ipv4;


parser parse_ipv4 {
    extract(ipv4);
    return ingress;
}
