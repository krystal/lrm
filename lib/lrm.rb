$:.unshift "lib"

require 'awesome_print'
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
    
    def parse_as_path path
      as = []
      while path
        as += path[2, path[1].ord * 2].unpack("n*")
        path = path[(path[1].ord*2)..-1]
      end
      as
    end
    
    def bgp_route prefix, len
      prefix = IPAddr.new("#{prefix}/#{len}").to_s
      routes = []
      snmp do |m|
        m.tree("bgp4PathAttrPeer.#{prefix}.#{len}") do |k, v|
          k = k.split(".", 2)[1]
          routes << {
            origin: [:internal, :external][m.get("bgp4PathAttrOrigin.#{k}")],
            next_hop: m.get("bgp4PathAttrNextHop.#{k}").to_s,
            path: parse_as_path(m.get("bgp4PathAttrASPathSegment.#{k}")),
          }
        end
      end
      routes
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

if $0 == __FILE__
  router = LRM::Router.new('a.routing.atech.io', 'llamafarm')
  router = LRM::Router.new('b.routing.atech.io', 'llamafarm')
  a = Resolv.getaddress("www.gnu.org")
  32.downto(1) do |i|
    r = router.bgp_route(a, i)
    unless r.empty?
      ap r
      break
    end
  end
end
