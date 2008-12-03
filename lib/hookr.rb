require 'set'
require 'generator'
require 'rubygems'
require 'fail_fast'

# HookR is a library providing "hooks", aka "signals and slots", aka "events" to
# your Ruby classes.
module HookR

  # No need to document the boilerplate convenience methods defined by Mr. Bones.
  # :stopdoc:

  VERSION = '1.0.1'
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR

  # Returns the version string for the library.
  #
  def self.version
    VERSION
  end

  # Returns the library path for the module. If any arguments are given,
  # they will be joined to the end of the libray path using
  # <tt>File.join</tt>.
  #
  def self.libpath( *args )
    args.empty? ? LIBPATH : ::File.join(LIBPATH, args.flatten)
  end

  # Returns the lpath for the module. If any arguments are given,
  # they will be joined to the end of the path using
  # <tt>File.join</tt>.
  #
  def self.path( *args )
    args.empty? ? PATH : ::File.join(PATH, args.flatten)
  end

  # Utility method used to rquire all files ending in .rb that lie in the
  # directory below this file that has the same name as the filename passed
  # in. Optionally, a specific _directory_ name can be passed in such that
  # the _filename_ does not have to be equivalent to the directory.
  #
  def self.require_all_libs_relative_to( fname, dir = nil )
    dir ||= ::File.basename(fname, '.*')
    search_me = ::File.expand_path(
        ::File.join(::File.dirname(fname), dir, '*', '*.rb'))

    Dir.glob(search_me).sort.each {|rb| require rb}
  end

  # :startdoc:

  # Include this module to decorate your class with hookable goodness.
  #
  # Note: remember to call super() if you define your own self.inherited().
  module Hooks
    module ClassMethods
      # Returns the hooks exposed by this class
      def hooks
        result = fetch_or_create_hooks.dup.freeze
      end

      # Define a new hook +name+.  If +params+ are supplied, they will become
      # the hook's named parameters.
      def define_hook(name, *params)
        fetch_or_create_hooks << make_hook(name, nil, params)

        # We must use string evaluation in order to define a method that can
        # receive a block.
        instance_eval(<<-END)
          def #{name}(handle_or_method=nil, &block)
            add_callback(:#{name}, handle_or_method, &block)
          end
        END
        module_eval(<<-END)
          def #{name}(handle=nil, &block)
            add_external_callback(:#{name}, handle, block)
          end
        END
      end

      def const_missing(const_name)
        if const_name.to_s == "Listener"
          hooks = fetch_or_create_hooks
          listener_class ||= Class.new do
            hooks.each do |hook|
              define_method(hook.name) do |*args|
                # NOOP
              end
            end
          end
          const_set(const_name, listener_class)
        else
          super(const_name)
        end
      end

      protected

      def make_hook(name, parent, params)
        Hook.new(name, parent, params)
      end

      private

      def inherited(child)
        child.instance_variable_set(:@hooks, fetch_or_create_hooks.deep_copy)
      end

      def fetch_or_create_hooks
        @hooks ||= HookSet.new
      end

    end                         # end of ClassMethods

    # These methods are used at both the class and instance level
    module CallbackHelpers
      public

      def remove_callback(hook_name, handle_or_index)
        fetch_or_create_hooks[hook_name].remove_callback(handle_or_index)
      end

      protected

      # Add a callback to a named hook
      def add_callback(hook_name, handle_or_method=nil, &block)
        if block
          add_block_callback(hook_name, handle_or_method, block)
        else
          add_method_callback(hook_name, handle_or_method)
        end
      end

      # Add a callback which will be executed
      def add_wildcard_callback(handle=nil, &block)
        fetch_or_create_hooks[:__wildcard__].add_basic_callback(handle, &block)
      end

      # Remove a wildcard callback
      def remove_wildcard_callback(handle_or_index)
        remove_callback(:__wildcard__, handle_or_index)
      end

      private

      # Add either an internal or external callback depending on the arity of
      # the given +block+
      def add_block_callback(hook_name, handle, block)
        case block.arity
        when -1, 0
          fetch_or_create_hooks[hook_name].add_internal_callback(handle, &block)
        else
          add_external_callback(hook_name, handle, block)
        end
      end

      # Add a callback which will be executed in the context from which it was defined
      def add_external_callback(hook_name, handle, block)
        fetch_or_create_hooks[hook_name].add_external_callback(handle, &block)
      end

      def add_basic_callback(hook_name, handle, block)
        fetch_or_create_hooks[hook_name].add_basic_callback(handle, &block)
      end

      # Add a callback which will call an instance method of the source class
      def add_method_callback(hook_name, method)
        fetch_or_create_hooks[hook_name].add_method_callback(self, method)
      end

    end                         # end of CallbackHelpers

    def self.included(other)
      other.extend(ClassMethods)
      other.extend(CallbackHelpers)
      other.send(:include, CallbackHelpers)
      other.send(:define_hook, :__wildcard__)
    end

    # returns the hooks exposed by this object
    def hooks
      fetch_or_create_hooks.dup.freeze
    end

    # Execute all callbacks associated with the hook identified by +hook_name+,
    # plus any wildcard callbacks.
    #
    # When a block is supplied, this method functions differently.  In that case
    # the callbacks are executed recursively. The most recently defined callback
    # is executed and passed an event and a set of arguments.  Calling
    # event.next will pass execution to the next most recently added callback,
    # which again will be passed an event with a reference to the next callback,
    # and so on.  When the list of callbacks are exhausted, the +block+ is
    # executed as if it too were a callback.  If at any point event.next is
    # passed arguments, they will replace the value of the callback arguments
    # for callbacks further down the chain.
    #
    # In this way you can use callbacks as "around" advice to a block of
    # code. For instance:
    #
    #    execute_hook(:write_data, data) do |data|
    #      write(data)
    #    end
    #
    # Here, the code exposes a :write_data hook.  Any callbacks attached to the
    # hook will "wrap" the data writing event.  Callbacks might log when the
    # data writing operation was started and stopped, or they might encrypt the
    # data before it is written, etc.
    def execute_hook(hook_name, *args, &block)
      event = Event.new(self, hook_name, args, !!block)

      if block
        execute_hook_recursively(hook_name, event, block)
      else
        execute_hook_iteratively(hook_name, event)
      end
    end

    # Add a listener object.  The object should have a method defined for every
    # hook this object publishes.
    def add_listener(listener, handle=listener_to_handle(listener))
      add_wildcard_callback(handle) do |event|
        listener.send(event.name, *event.arguments)
      end
    end

    # Remove a listener by handle or by the listener object itself
    def remove_listener(handle_or_listener)
      handle = case handle_or_listener
               when Symbol then handle_or_listener
               else listener_to_handle(handle_or_listener)
               end
      remove_wildcard_callback(handle)
    end

    private

    def execute_hook_recursively(hook_name, event, block)
      event.callbacks = callback_generator(hook_name, block)
      event.next
    end

    def execute_hook_iteratively(hook_name, event)
      fetch_or_create_hooks[:__wildcard__].execute_callbacks(event)
      fetch_or_create_hooks[hook_name].execute_callbacks(event)
    end

    # Returns a Generator which yields:
    # 1. Wildcard callbacks, in reverse order, followed by
    # 2. +hook_name+ callbacks, in reverse order, followed by
    # 3. a proc which delegates to +block+
    #
    # Intended for use with recursive hook execution.
    def callback_generator(hook_name, block)
      Generator.new do |g|
        fetch_or_create_hooks[:__wildcard__].each_callback_reverse do |callback|
          g.yield callback
        end
        fetch_or_create_hooks[hook_name].each_callback_reverse do |callback|
          g.yield callback
        end
        g.yield(lambda do |event|
                  block.call(*event.arguments)
                end)
      end
    end

    def listener_to_handle(listener)
      ("listener_" + listener.object_id.to_s).to_sym
    end

    def fetch_or_create_hooks
      @hooks ||= self.class.hooks.deep_copy
    end
  end

  # A single named hook
  Hook = Struct.new(:name, :parent, :params) do
    include FailFast::Assertions

    def initialize(name, parent=nil, params=[])
      assert(Symbol === name)
      @handles = {}
      super(name, parent || NullHook.new, params)
    end

    def initialize_copy(original)
      self.name   = original.name
      self.parent = original
      self.params = original.params
      @callbacks  = CallbackSet.new
    end

    def ==(other)
      name == other.name
    end

    def eql?(other)
      self.class == other.class && name == other.name
    end

    def hash
      name.hash
    end

    # Returns false.  Only true of NullHook.
    def terminal?
      false
    end

    # Returns true if this hook has a null parent
    def root?
      parent.terminal?
    end

    def callbacks
      fetch_or_create_callbacks.dup.freeze
    end

    # Add a callback which will be executed in the context where it was defined
    def add_external_callback(handle=nil, &block)
      if block.arity > -1 && block.arity < params.size
        raise ArgumentError, "Callback has incompatible arity"
      end
      add_block_callback(HookR::ExternalCallback, handle, &block)
    end

    # Add a callback which will pass only the event object to +block+ - it will
    # not try to pass arguments as well.
    def add_basic_callback(handle=nil, &block)
      add_block_callback(HookR::BasicCallback, handle, &block)
    end

    # Add a callback which will be executed in the context of the event source
    def add_internal_callback(handle=nil, &block)
      add_block_callback(HookR::InternalCallback, handle, &block)
    end

    # Add a callback which will send the given +message+ to the event source
    def add_method_callback(klass, message)
      method = klass.instance_method(message)
      add_callback(HookR::MethodCallback.new(message, method, next_callback_index))
    end

    def add_callback(callback)
      fetch_or_create_callbacks << callback
      callback.handle
    end

    def remove_callback(handle_or_index)
      assert_exists(handle_or_index)
      case handle_or_index
      when Symbol then fetch_or_create_callbacks.delete_if{|cb| cb.handle == handle_or_index}
      when Integer then fetch_or_create_callbacks.delete_if{|cb| cb.index == handle_or_index}
      else raise ArgumentError, "Key must be integer index or symbolic handle "\
                                "(was: #{handle_or_index.inspect})"
      end
    end

    # Empty this hook of callbacks.  Parent hooks may still have callbacks.
    def clear_callbacks!
      fetch_or_create_callbacks.clear
    end

    # Empty this hook of its own AND parent callbacks.  This also disconnects
    # the hook from its parent, if any.
    def clear_all_callbacks!
      disconnect!
      clear_callbacks!
    end

    # Yields callbacks in order of addition, starting with any parent hooks
    def each_callback(&block)
      parent.each_callback(&block)
      fetch_or_create_callbacks.each(&block)
    end

    # Yields callbacks in reverse order of addition, starting with own callbacks
    # and then moving on to any parent hooks.
    def each_callback_reverse(&block)
      fetch_or_create_callbacks.each_reverse(&block)
      parent.each_callback_reverse(&block)
    end

    # Excute the callbacks in order.  +source+ is the object initiating the event.
    def execute_callbacks(event)
      parent.execute_callbacks(event)
      fetch_or_create_callbacks.each do |callback|
        callback.call(event)
      end
    end

    # Callback count including parents
    def total_callbacks
      fetch_or_create_callbacks.size + parent.total_callbacks
    end

    private

    def next_callback_index
      return 0 if fetch_or_create_callbacks.empty?
      fetch_or_create_callbacks.map{|cb| cb.index}.max + 1
    end

    def add_block_callback(type, handle=nil, &block)
      assert_exists(block)
      assert(handle.nil? || Symbol === handle)
      handle ||= next_callback_index
      add_callback(type.new(handle, block, next_callback_index))
    end

    def fetch_or_create_callbacks
      @callbacks ||= CallbackSet.new
    end

    def disconnect!
      self.parent = NullHook.new unless root?
    end
  end

  # A null object class for terminating Hook inheritance chains
  class NullHook
    def each_callback(&block)
      # NOOP
    end

    def each_callback_reverse(&block)
      # NOOP
    end

    def execute_callbacks(event)
      # NOOP
    end

    def total_callbacks
      0
    end

    def terminal?
      true
    end

    def root?
      true
    end
  end

  class HookSet < Set
    WILDCARD_HOOK = HookR::Hook.new(:__wildcard__)

    # Find hook by name.
    #
    # TODO: Optimize this.
    def [](key)
      detect {|v| v.name == key} or raise IndexError, "No such hook: #{key}"
    end

    def deep_copy
      result = HookSet.new
      each do |hook|
        result << hook.dup
      end
      result
    end

    # Length minus the wildcard hook (if any)
    def length
      if include?(WILDCARD_HOOK)
        super - 1
      else
        super
      end
    end
  end

  class CallbackSet < SortedSet

    # Fetch callback by either index or handle
    def [](index)
      case index
      when Integer then detect{|cb| cb.index == index}
      when Symbol  then detect{|cb| cb.handle == index}
      else raise ArgumentError, "index must be Integer or Symbol"
      end
    end

    # get the first callback
    def first
      each do |cb|
        return cb
      end
    end

    def each_reverse(&block)
      sort{|x, y| y <=> x}.each(&block)
    end

  end

  Callback = Struct.new(:handle, :index) do
    include Comparable
    include FailFast::Assertions

    # Callbacks with the same handle are always equal, which prevents duplicate
    # handles in CallbackSets.  Otherwise, callbacks are sorted by index.
    def <=>(other)
      if handle == other.handle
        return 0
      end
      self.index <=> other.index
    end

    # Must be overridden in subclass
    def call(*args)
      raise NotImplementedError, "Callback is an abstract class"
    end
  end

  # A base class for callbacks which execute a block
  class BlockCallback < Callback
    attr_reader :block

    def initialize(handle, block, index)
      @block = block
      super(handle, index)
    end
  end

  # A callback which will execute outside the event source
  class ExternalCallback < BlockCallback
    def call(event)
      block.call(*event.to_args(block.arity))
    end
  end

  # A callback which will call a one-arg block with an event object
  class BasicCallback < BlockCallback
    def initialize(handle, block, index)
      check_arity!(block)
      super
    end

    def call(event)
      block.call(event)
    end

    private

    def check_arity!(block)
      if block.arity != 1
        raise ArgumentError, "Callback block must take a single argument"
      end
    end
  end

  # A callback which will execute in the context of the event source
  class InternalCallback < BlockCallback
    def initialize(handle, block, index)
      assert(block.arity <= 0)
      super(handle, block, index)
    end

    def call(event)
      event.source.instance_eval(&block)
    end
  end

  # A callback which will call a method on the event source
  class MethodCallback < Callback
    attr_reader :method

    def initialize(handle, method, index)
      @method = method
      super(handle, index)
    end

    def call(event)
      method.bind(event.source).call(*event.to_args(method.arity))
    end
  end

  # Represents an event which is triggering callbacks.
  #
  # +source+::    The object triggering the event.
  # +name+::      The name of the event
  # +arguments+:: Any arguments passed associated with the event
  Event = Struct.new(:source, :name, :arguments, :recursive, :callbacks) do
    include FailFast::Assertions

    # Convert to arguments for a callback of the given arity. Given an event
    # with three arguments, the rules are as follows:
    #
    # 1. If arity is -1 (meaning any number of arguments), or 4, the result will
    #    be [event, +arguments[0]+, +arguments[1]+, +arguments[2]+]
    # 2. If arity is 3, the result will just be +arguments+
    # 3. If arity is < 3, an error will be raised.
    #
    # Notice that as the arity is reduced, the event argument is trimmed off.
    # However, it is not permitted to generate a subset of the +arguments+ list.
    # If the arity is too small to allow all arguments to be passed, the method
    # fails.
    def to_args(arity)
      case arity
      when -1
        full_arguments
      when (min_argument_count..full_argument_count)
        full_arguments.slice(full_argument_count - arity, arity)
      else
        raise ArgumentError, "Arity must be between #{min_argument_count} "\
                             "and #{full_argument_count}"
      end
    end

    # This method, along with the callback generator defined in Hook,
    # implements recursive callback execution.
    #
    # TODO: Consider making the next() automatically if the callback doesn't
    # call it explicitly.
    #
    # TODO: Consider adding a cancel() method, implementation TBD.
    def next(*args)
      assert(recursive, callbacks)
      event = self.class.new(source, name, arguments, recursive, callbacks)
      event.arguments = args unless args.empty?
      if callbacks.next?
        callbacks.next.call(event)
      else
        raise "No more callbacks!"
      end
    end

    private

    def full_argument_count
      full_arguments.size
    end

    def min_argument_count
      arguments.size
    end

    def full_arguments
      @full_arguments ||= [self, *arguments]
    end
  end

end  # module HookR

HookR.require_all_libs_relative_to(__FILE__)

# EOF
