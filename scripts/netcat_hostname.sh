while true; do echo `ifconfig -a | awk '/^[a-z]/ { iface=$1; mac=$NF; next } /inet addr:/ { print iface, mac }' | head -1` | nc -l ${2:-8888} ; done
