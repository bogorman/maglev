# File in Ruby is identically Smalltalk GsFile  
class File
    primitive 'close', 'close'
    primitive '<<', 'addAll:'
    primitive 'write', 'addAll:'
    primitive 'next_line', 'nextLineTo:'
    primitive 'eof?', 'atEnd'
    primitive 'read', 'next:'
    primitive 'read', 'contents'
    self.class.primitive '_open', 'openOnServer:mode:'
    self.class.primitive 'stdin'
    self.class.primitive 'stdout'
    self.class.primitive 'stderr'
    self.class.primitive '_environmentAt', '_expandEnvVariable:isClient:'

    def self.new(file, mode="r")
        self._open(file, mode)
    end
    
    def self.open(file, mode="r", &b)
        f = self._open(file, mode)
        if b
            val = b.call(f)
            f.close
            val
        else
          f
        end
    end
    
    def print(*args)
        args.each {|arg| self << arg.to_s}
    end
    
    def self.read(file)
        open(file){|f| f.read}
    end
    
    def self.dirname(str)
        if str =~ /(.+)\//
            $1
        else
          if str[0] == ?/
            "/"
          else
            "."
          end
        end
    end
    
    def self.join(*ary)
        ary.join("/")
    end
    
    def self.read(path)
        file = self.new(path)
        contents = file.read
        file.close
        contents
    end
        
    def each_line(&block)
        sep = $/[0] 
        until eof?
            block.call( next_line( sep ) )
        end
    end
end

class PersistentFile
    def initialize(block)
        @block = block
    end
    
    def _file
        @block.call
    end
    
    def print(*args)
        args.each {|arg| self << arg.to_s}
    end
    
    def <<(data)
        _file << data
    end
    
    def write(data)
      _file << data
    end
    
    def gets(sep=$/ )
        @block.call.next_line( sep[0] ) #whee
    end
    
    def sync
        @block.call.sync
    end

    def sync=
        @block.call.sync
    end

end

STDIN = $stdin = PersistentFile.new(proc{File.stdin})
STDOUT = $stdout = PersistentFile.new(proc{File.stdout})
STDERR = $stderr = PersistentFile.new(proc{File.stderr})
$> = $stdout
