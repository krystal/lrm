require 'snmp'

module SNMP
  
  class OctetString
    def to_prim
      to_s
    end
  end
  
  class IpAddress
    def to_prim
      IPAddr.new(to_s)
    end
  end
  
  class Integer
    def to_prim
      to_i
    end
  end
  
  class NoSuchInstance
    def self.to_prim
      nil
    end
  end
  
  class Manager
    
    alias old_walk walk
    
    def table (args)
      args = Array(args)
      a = []
      old_walk(args) { |vbl|
        hash = {}
        oids = vbl.each_with_index.map { |vb, i|
          hash[args[i]] = vb.value.to_prim
          vb.name.index(mib.oid(args[i]))
        }
        a << (block_given? ? yield(hash, oids) : hash)
      }
      a
    end
    
    def tree (args)
      args = Array(args)
      hash = {}
      old_walk(args) { |vbl|
        oids = vbl.each_with_index.map { |vb, i|
          hash[mib.name(vb.name).split("::")[1]] = vb.value.to_prim
          vb.name.index(mib.oid(args[i]))
        }
      }
      hash
    end
    
    alias old_get get
    
    def get (oid)
      if oid.is_a?(Array)
        old_get(oid).vb_list.map{|x|x.value.to_prim}
      else
        old_get(oid).vb_list[0].value.to_prim
      end
    end
    
  end
  
end
