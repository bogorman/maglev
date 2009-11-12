require 'ffi'

# This is an experimental FFI wrapper for http://pyyaml.org/wiki/LibYAML
#
# == TODO
# * Get structs and proper sizes working the right way
# * auto create the Enums, in case the c-code ever changes.

class MAML
  extend FFI::Library
  ffi_lib '/Users/pmclain/external/yaml-0.1.3-64/src/.libs/libyaml-0.2.dylib'

  attach_function :yaml_get_version, [:pointer, :pointer, :pointer], :void
  attach_function :yaml_parser_initialize, [:pointer], :int
  attach_function :yaml_parser_set_input_string, [:pointer, :string, :int], :void
  attach_function :yaml_parser_parse, [:pointer, :pointer], :int
  attach_function :yaml_event_delete, [:pointer], :void
  attach_function :yaml_parser_delete, [:pointer], :void

  # return the version of libyaml we are using, e.g., "0.1.3"
  def self.version
    result = [FFI::MemoryPointer.new(:pointer),
              FFI::MemoryPointer.new(:pointer),
              FFI::MemoryPointer.new(:pointer)]
    yaml_get_version(*result)
    result.map {|el| el.read_int}.join(".")
  end

  class Parser
    ParserEventEnum = FFI::Enum.new([:yaml_no_event,
                                     :yaml_stream_start_event,
                                     :yaml_stream_end_event,
                                     :yaml_document_start_event,
                                     :yaml_document_end_event,
                                     :yaml_alias_event,
                                     :yaml_scalar_event,
                                     :yaml_sequence_start_event,
                                     :yaml_sequence_end_event,
                                     :yaml_mapping_start_event,
                                     :yaml_mapping_end_event ],
                                    :yaml_event_type_e)

    ErrorCodes = FFI::Enum.new([:yaml_no_error,
                                :yaml_memory_error,
                                :yaml_reader_error,
                                :yaml_scanner_error,
                                :yaml_parser_error,
                                :yaml_composer_error,
                                :yaml_writer_error,
                                :yaml_emitter_error],
                               :yaml_error_type_e)


    # TODO: Figure these out differently...
    # TODO: Make classes for each?  class YamlParser < FFI::Buffer
    YAML_PARSER_T_SIZE = 480 # sizeof(yaml_parser_t)
    YAML_EVENT_T_SIZE  = 104 # sizeof(yaml_event_t)

    def initialize(string_to_parse)
      @yaml = string_to_parse
      @parser = FFI::Buffer.alloc_inout YAML_PARSER_T_SIZE
      @documents = []
      MAML.yaml_parser_initialize(@parser)
    end

    def parse
      MAML.yaml_parser_set_input_string(@parser, @yaml, @yaml.size)
      event = FFI::Buffer.alloc_inout YAML_EVENT_T_SIZE

      done = false
      while not done
        res = MAML.yaml_parser_parse(@parser, event)
        raise_lib_yaml_exception if res == 0

        event_name = ParserEventEnum[event.read_int]
        case event_name
        when :yaml_stream_start_event
          raise "non-empty stack at stream start" unless @stack.nil?
          @stack = []
        when :yaml_stream_end_event
          done = true

        when :yaml_document_start_event
          @stack.push Document.new
        when :yaml_document_end_event
          puts event_name
          # TODO: Should we mark that we are in a state that expects a new
          # container?

        when :yaml_sequence_start_event
          @stack.push Sequence.new
        when :yaml_sequence_end_event
          seq = @stack.pop
          raise "no sequence for yaml_sequence_end_event" unless Sequence === seq
          @stack[0] << seq

        when :yaml_mapping_start_event
          @stack.push Mapping.new
        when :yaml_mapping_end_event
          mapping = @stack.pop
          raise "no mapping for yaml_mapping_end_event" unless Mapping === mapping
          @stack[0] << mapping

        when :yaml_scalar_event
          puts "scalar"

        else
          raise "Unhandled event: #{event_name}"
        end
      end

      documents = @stack
      @stack = nil
      return documents
    ensure
      MAML.yaml_event_delete(event) if event
      MAML.yaml_parser_delete(@parser) if @parser
    end

    def raise_lib_yaml_exception
      error = @parser.read_int
      raise "libYAML error: #{error} #{ErrorCodes[error]}"
    end
  end

  class Document
    def initialize
      puts "New document created"
      @elements = []
    end
    def <<(obj)
      @elements << obj
    end
  end

  class Sequence < Array
    def initialize
      super()
      puts "New sequence created"
    end
  end

  class Mapping < Hash
    def initialize
      super()
      puts "New mapping created"
    end
  end

  class Scalar
    def initialize
      puts "New scalar created"
    end
  end
end

p MAML.version
yaml = "- Mark McGwire" # a small yaml filef
parser = MAML::Parser.new(yaml)
p parser.parse
