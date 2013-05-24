require 'bundler'
require 'snmp'
require 'ipaddr'

module LRM # Linux Router Monitor
  
  class Router
    def initialize(host, community)
      @host, @community = host, community
    end
    
    def ip_addresses_by_interface
      Hash.new.tap do |addrs|
        SNMP::Manager.open Host: @host, Community: @community do |m|
          m.walk("ipAddressIfIndex.1") do |d|
            (addrs[m.get_value("ifName.#{d.value}")] ||= []) << d.name[-4..-1].to_s
          end
          m.walk("ipAddressIfIndex.2") do |d|
            (addrs[m.get_value("ifName.#{d.value}")] ||= []) << IPAddr.new_ntoh(d.name[-16..-1].to_a.map{|s|s.chr}.join("")).to_s
          end
        end
      end
    end
    
  end  
end

router = LRM::Router.new('10.1.1.253', 'llamafarm')
puts router.ip_addresses_by_interface
