#include "includes/headers.p4"
#include "includes/parser.p4"

header_type ingress_metadata_t {
    fields {
        srcAddr : 32;
        dstAddr : 32;
        customer: 32;
    }
}

metadata ingress_metadata_t ingress_metadata;

action _noop() {
    no_op();
}

action _drop() {
    drop();
}

action set_address_ip_packet() {
    modify_field(ingress_metadata.customer, 0);
    modify_field(ingress_metadata.srcAddr, ipv4.srcAddr);
    modify_field(ingress_metadata.dstAddr, ipv4.dstAddr);
}

table address_ip_packet {
  actions {
    set_address_ip_packet;
  }
  size : 1;
}


action set_address_arp_packet() {
    modify_field(ingress_metadata.customer, 0);
    modify_field(ingress_metadata.srcAddr, arp_rarp_ipv4.srcProtoAddr);
    modify_field(ingress_metadata.dstAddr, arp_rarp_ipv4.dstProtoAddr);
}

table address_arp_packet {
  actions {
    set_address_arp_packet;
  }
  size : 1;
}


action push_vpc() {
  add_header(vpc);
  modify_field(vpc.etherType, ethernet.etherType);
  modify_field(ethernet.etherType, ETHERTYPE_VPC);
  modify_field(vpc.customer, ingress_metadata.customer);
  modify_field(vpc.srcAddr, ingress_metadata.srcAddr);
  modify_field(vpc.dstAddr, ingress_metadata.dstAddr);
}

table encapsulate_vpc {
  actions {
      push_vpc;
  }
  size : 1;
}

action set_l2_addr(srcAddr, dstAddr) {
  modify_field(ethernet.srcAddr, srcAddr);
  modify_field(ethernet.dstAddr, dstAddr);
}

table l2_addr {
  reads {
      vpc.customer : exact;
      vpc.dstSw : exact;
      vpc.srcAddr : lpm;      
      vpc.dstAddr : exact;
  }
  actions {
    _noop;
    set_l2_addr;
  }
  size : 1024;
}

action set_vpc_dst(dstSw) {
  modify_field(vpc.dstSw, dstSw);
}

table vpc_dst {
  reads {
      vpc.customer : exact;
      vpc.dstAddr : lpm;
  }
  actions {
    _drop;
    set_vpc_dst;
  }
  size : 1024;
}

action set_vpc_src_sw_id(srcSw) {
  modify_field(vpc.srcSw, srcSw);
}

table vpc_sw_id {
  actions {
    set_vpc_src_sw_id;
  }
  size : 1;
}

action route_vpc(port) {
  modify_field(standard_metadata.egress_spec, port);
}

table routing_pvc {
  reads {
      vpc.dstSw : exact;
  }
  actions {
      route_vpc;
  }
  size : 1024;
}


action pop_route_vpc(port) {
  modify_field(standard_metadata.egress_spec, port);
  modify_field(ethernet.etherType, vpc.etherType);
  remove_header(vpc);
}

table deliver_pvc {
  reads {
      vpc.dstSw : exact;
      vpc.customer : exact;
      vpc.dstAddr : lpm;
  }
  actions {
      pop_route_vpc;
  }
  size : 1024;
}

action set_arp_reply(hwAddr) {
  modify_field(ethernet.dstAddr, ethernet.srcAddr);
  modify_field(ethernet.srcAddr, hwAddr);
  modify_field(arp_rarp.opcode, 2);
  modify_field(arp_rarp_ipv4.dstHwAddr, arp_rarp_ipv4.srcHwAddr);
  modify_field(arp_rarp_ipv4.dstProtoAddr, arp_rarp_ipv4.srcProtoAddr);
  modify_field(arp_rarp_ipv4.srcHwAddr, hwAddr);
  modify_field(arp_rarp_ipv4.srcProtoAddr, ingress_metadata.dstAddr);
  modify_field(standard_metadata.egress_spec, standard_metadata.ingress_port);
}

table arp_reply {
  reads {
      ingress_metadata.customer : exact;
      ingress_metadata.srcAddr : lpm;
      ingress_metadata.dstAddr : exact;
  }
  actions {
    _drop;
    set_arp_reply;
  }
  size : 1024;
}

action set_vpc_customer(customer) {
  modify_field(ingress_metadata.customer, customer);
}

table vpc_customer {
  reads {
      ethernet.srcAddr : exact;
      ingress_metadata.srcAddr : exact;
  }
  actions {
    _drop;
    set_vpc_customer;
  }
  size : 1024;
}

control ingress {

    if (ethernet.etherType == ETHERTYPE_ARP and arp_rarp.opcode == 1) {
        apply(address_arp_packet);
    } else if (ethernet.etherType == ETHERTYPE_IPV4 ){
        apply(address_ip_packet);
    }
    if ((ethernet.etherType == ETHERTYPE_ARP and arp_rarp.opcode == 1) or (ethernet.etherType == ETHERTYPE_IPV4 )){
      apply(vpc_customer);
    }
    if (ethernet.etherType == ETHERTYPE_ARP and arp_rarp.opcode == 1) {
        if (ingress_metadata.customer > 0){
          apply(arp_reply);
        }
    } else if (ethernet.etherType == ETHERTYPE_IPV4 ){
        if (ingress_metadata.customer > 0){
          apply(encapsulate_vpc);
          apply(vpc_sw_id);
          apply(vpc_dst);
        }
    }
    if (valid(vpc)){
      apply(l2_addr);
      apply(routing_pvc);
      apply(deliver_pvc);
    }
}

control egress {

}
