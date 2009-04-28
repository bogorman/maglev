# From rubinius, but not all of common/dir.rb
class Dir
  include Enumerable

  GLOB_VERBOSE = 1 << (4 * 8 - 1) # HACK
  GLOB_RECURSIVE = -2

  def self.[](pattern)
    glob(pattern, 0)
  end

  def self.glob(pat, flags = 0)
    pattern = Type.coerce_to(pat, String, :to_str)  # GEMSTONE
    matches = []

    glob_brace_expand pattern, flags & ~GLOB_VERBOSE, matches

    matches
  end

  def self.glob0(pattern, flags, matches)
    root = pattern.dup
    path = ''

    if root[0] == ?/ then # HACK windows
      root = root[1..-1]
      path = '/'
    end

    list = glob_pattern root, flags

    glob_helper path, false, :unknown, :unknown, list, 0, 1, flags, matches
  end

  def self.find_dirsep(pattern, flags)
    escape = (flags & File::FNM_NOESCAPE).equal?(0)
    open = false

    chars = pattern.split ''

    chars.each_with_index do |char, i|
      case char
      when '[' then
        open = true
      when ']' then
        open = false
      when '/' then
        return i unless open
      when '\\' then
        return i if escape and (i + 1 == chars.length)
      end
    end

    chars.length
  end

  def self.glob_brace_expand(pattern, flags, matches)
    escape = (flags & File::FNM_NOESCAPE).equal?(0)

    rbrace = nil
    lbrace = nil
    nest = 0

    chars = pattern.split ''
    skip = false

    chars.each_with_index do |char, i|
      if skip then
        skip = false
        next
      end

      if char == '{' and nest.equal?(0) then
        lbrace = i
        nest += 1
      end

      if char == '}' and nest - 1 <= 0 then
        rbrace = i
        nest -= 1
      end

      skip = true if char == '\\' and escape
    end

    if lbrace and rbrace then
      pos = lbrace
      front = pattern[0...lbrace]
      back = pattern[(rbrace + 1)..-1]

      while pos < rbrace do
        nest = 0
        pos += 1
        last = pos

        while pos < rbrace and not (chars[pos] == ',' and nest.equal?(0)) do
          nest += 1 if chars[pos] == '{'
          nest -= 1 if chars[pos] == '}'

          if chars[pos] == '\\' and escape then
            pos += 1
            break if pos == rbrace
          end

          pos += 1
        end

        brace_pattern = "#{front}#{pattern[last...pos]}#{back}"

        glob_brace_expand brace_pattern, flags, matches
      end

    else
      glob0 pattern, flags, matches
    end
  end

  ##
  # +dirsep+:: Should '/' be placed before appending child's entry name to
  #            +path+?
  # +exist+:: Does 'path' indicate an existing entry?
  # +isdir+:: Does 'path' indicate a directory or a symlink to a directory?

  def self.glob_helper(path, dirsep, exist, isdir, pattern, start, stop, flags, matches)
    status = nil
    plain = magic = recursive = match_all = match_dir = false
    escape = (flags & File::FNM_NOESCAPE).equal?(0)

    last_type = nil

    pattern[start, stop].each_with_index do |part, i|
      if part[1] == :recursive then
        recursive = true
        part = pattern[i + 1]
      end

      case part[1]
      when :magic then
        magic = true
      when :match_all then
        match_all = true
      when :match_dir then
        match_dir = true
      when :plain then
        plain = true
      when :recursive then
        raise "continuous RECURSIVEs"
      end
    end

    unless path.empty? then
      if match_all and exist == :unknown then
        if stat = File.stat(path) rescue nil then
          exist = :yes
          isdir = if stat.directory? then
                    :yes
                  elsif stat.symlink? then
                    :unknown
                  else
                    :no
                  end
        else
          exist = isdir = :no
        end
      end

      if match_dir and isdir == :unknown then
        if stat = File.stat(path) rescue nil then
          exist = :yes
          isdir = stat.directory? ? :yes : :no
        else
          exist = isdir = :no
        end
      end

      matches << path if match_all and exist == :yes

      if match_dir and isdir == :yes then
        return if path.empty? and not dirsep
        tmp = join_path path, '', dirsep
        matches << tmp
      end
    end

    return if exist == :no or isdir == :no

    if magic or recursive then
      dir = path.empty? ? '.' : path

      return unless File.directory? dir

      begin
        Dir.foreach dir do |entry|
          buf = join_path path, entry, dirsep
          new_isdir = :unknown
          new_pattern = []
          copied = start

          if recursive and not %w[. ..].include?(entry) and
            File.fnmatch('*', entry, flags) then
            stat = File.stat buf
            new_isdir = if stat.directory? then
                          :yes
                        elsif stat.symlink? then
                          :unknown
                        else
                          :no
                        end
          end

          pattern[start, stop].each_with_index do |part, i|
            if part[1] == :recursive then
              if new_isdir == :yes then
                new_pattern << part
                copied += 1
              end
              part = pattern[start + i + 1]
              i += 1
            end

            if (part[1] == :plain or part[1] == :magic) and
              File.fnmatch part[0], entry, flags then
              new_pattern << pattern[start + i + 1]
              copied += 2
            end
          end

          length = new_pattern.length

          _tmp = pattern[copied, pattern.size-copied]
          new_pattern.concat _tmp unless _tmp == nil

#          new_pattern.concat pattern[copied, pattern.size-copied]

          glob_helper(buf, true, :yes, new_isdir, new_pattern, 0, length,
                      flags, matches)
        end
      rescue Errno::ENOTDIR
        # File.directory? may return true on entries in an fdesc file system
        return
      end
    elsif plain then
      copy_end = 0
      copy_pattern = pattern.dup

      pattern[start, stop].each_with_index do |part, i|
        copy_pattern[i] = nil unless part[1] == :plain
      end

      copy_pattern[start, stop].each_with_index do |part, i|
        next unless part

        new_pattern = []
        copied = i
        next_offset = i + 1

        name = part[0]
        name = name.gsub '\\', '' if escape

        new_pattern << copy_pattern[next_offset]
        copied += 1

        copy_pattern[(i+1), stop-(i+1)].each_with_index do |part2, j|
          if part2 and not File.fnmatch part2[0], name, flags then
            new_pattern << copy_pattern[next_offset + j]
            copied += 1

            copy_pattern[next_offset + j] = nil
          end
        end

        length = new_pattern.length

        new_pattern.concat copy_pattern[(copied + 1)..-1]

        buf = join_path path, name, dirsep

        glob_helper(buf, true, :unknown, :unknown, new_pattern,
                    0, length, flags, matches)
      end
    end
  end

  def self.glob_magic?(pattern, flags)
    escape = (flags & File::FNM_NOESCAPE).equal?(0)
    nocase = (flags & File::FNM_CASEFOLD).equal?(0)

    chars = pattern.split ''

    chars.each_with_index do |char, i|
      case char
      when '*', '?', '[' then
        return true
      when '\\' then
        return false if escape && i == chars.length
      else
       return true if char == /[a-z]/i && nocase # HACK FNM_SYSCASE
      end
    end

    false
  end

  def self.glob_pattern(pattern, flags)
    dirsep = false
    glob_pattern = []

    until pattern.empty? do
      part = []

      if pattern =~ /\A\*\*\// then
        # fold continuous :recursive for glob_helper
        pattern.sub!(/\A(\*\*\/)+/, '')
        part[0] = ''
        part[1] = :recursive
        dirsep = true
      else
        m = find_dirsep pattern, flags

        part[0] = pattern[0...m]
        part[1] = glob_magic?(part[0], flags) ? :magic : :plain

        unless pattern.length == m then
          dirsep = true
          pattern = pattern[(m+1), pattern.size-m]
        else
          dirsep = false
          pattern = ''
        end
      end

      glob_pattern << part
    end

    part = []
    part[0] = ''
    part[1] = dirsep ? :match_dir : :match_all

    glob_pattern << part

    glob_pattern
  end

  def self.join_path(p1, p2, dirsep)
    "#{p1}#{dirsep ? '/' : ''}#{p2}"
  end

end
