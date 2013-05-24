$:.unshift "lib"

require 'pp'
require 'bundler'
require 'snmp'
require 'ipaddr'
require 'snmp-monkey'

module LRM # Linux Router Monitor
  
  # This must be run when you want a new MIB.
  # Use the real name of the MIB, e.g. BRIDGE-MIB.
  def self.import_mib name
    SNMP::MIB.import_module("/usr/share/snmp/mibs/#{name}", "mibs")
  end
  
  class Router
    
    def initialize(host, community)
      @host, @community = host, community
    end
    
    def snmp_args
      {
        host: @host,
        community: @community,
        mib_dir: 'mibs',
        mib_modules: ['BGP4-MIB', 'IF-MIB', 'IP-MIB', 'SNMPv2-MIB']
      }
    end
    
    def snmp &block
      if block
        SNMP::Manager.open snmp_args, &block
      else
        SNMP::Manager.new snmp_args
      end
    end
    
    def uptime
      snmp.get("sysUpTime.0")
    end
    
    def interfaces
      snmp do |m|
        r = m.table(["ifIndex", "ifDescr", "ifType", "ifMtu", "ifSpeed", "ifPhysAddress", "ifAdminStatus", "ifOperStatus", "ifLastChange"]) do |h|
          if h["ifPhysAddress"] != ""
            h["ifPhysAddress"] = h["ifPhysAddress"].unpack("H2" * 6).join(":")
            h["ifPhysAddress"]
          end
          h
        end
        r
      end
    end
    
    def bgp_peers
      {}.tap do |addrs|
        snmp do |m|
          m.tree("bgpPeerTable").each do |k, v|
            name, peer = k.split(".", 2)
            addrs[peer] ||= {}
            addrs[peer][name] = v
          end
        end
      end
    end
    
    def bgp_paths
      {}.tap do |addrs|
        snmp do |m|
          m.tree("bgp4PathAttrTable").each do |k, v|
            boom = k.split(".")
            name = boom[0]
            prefix = boom[1, 4].join(".")
            length = boom[5]
            peer = boom[6, 4].join(".")
            prefix = "%s/%i" % [prefix, length]
            addrs[[prefix, peer]] ||= {}
            addrs[[prefix, peer]][name] = v
          end
        end
      end
    end
    
    def ip_addresses_by_interface
      Hash.new{|h,k|h[k]=[]}.tap do |addrs|
        snmp do |m|
          m.table("ipAddressIfIndex.1") do |d, i|
            addrs[m.get("ifName.#{d.values[0]}")] << i[0][1, 4].join("")
          end
          m.table("ipAddressIfIndex.2") do |d, i|
            addrs[m.get("ifName.#{d.values[0]}")] << IPAddr.new_ntoh(i[0][1, 16].map(&:chr).join).to_s
          end
        end
      end
    end
    
  end
  
end

#Neighbor        V    AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
#10.1.1.254      4 60899     518     525        0    0    0 01:08:15        0
#93.191.35.116   4 47264       0       0        0    0    0 never    Active

format = "%-16{neighbor} %{version} %6{as} %8{msg_rcvd} %8{msg_sent} %8{table_ver} %4{in_q} %4{out_q} %-8{up_down} %-8{state}"

puts format % { neighbor: "Neighbor",
                version: "V",
                as: "AS",
                msg_rcvd: "MsgRcvd",
                msg_sent: "MsgSent",
                table_ver: "TblVer",
                in_q: "InQ",
                out_q: "OutQ",
                up_down: "Up/Down",
                state: "State" }

if $0 == __FILE__
  router = LRM::Router.new('10.1.1.253', 'llamafarm')
  #router = LRM::Router.new('bigv.p12a.org.uk', 'llamafarm')
  router.bgp_peers.each do |peer, data|
    row = {}
    row[:neighbor] = peer
    row[:version] = data["bgpPeerNegotiatedVersion"]
    row[:as] = data["bgpPeerRemoteAs"]
    row[:msg_rcvd] = data["bgpPeerInTotalMessages"]
    row[:msg_sent] = data["bgpPeerOutTotalMessages"]
    row[:table_ver] = "?"
    row[:in_q] = "?"
    row[:out_q] = "?"
    if data["bgpPeerFsmEstablishedTime"] == 0
      row[:up_down] = "never"
    else
      row[:up_down] = Time.at(data["bgpPeerFsmEstablishedTime"]).utc.strftime("%H:%M:%S")
    end
    row[:state] = [nil, "Idle", "Connect", "Active", "Open Sent", "Open Confirm", "Established"][data["bgpPeerState"]]
    puts format % row
  end
  #router.bgp_paths.each do |(prefix, peer), data|
  #  puts "Prefix #{prefix} via #{peer}"
  #  data.each do |k, v|
  #    puts "  %-30s %s" % [k, v]
  #  end
  #  puts
  #end
end
