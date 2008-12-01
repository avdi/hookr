hookr
    by Avdi Grimm
    http://hookr.rubyforge.org

== DESCRIPTION:

HookR is a callback hook facility for Ruby.  With it you can enhance your
objects' APIs with named hooks to which arbitrary callbacks may be attached.

== FEATURES:

* Fully spec'd
* Provides class-level and instance-level callbacks
* Inheritance-safe
* Supports both iterative and recursive callback models
* "Wildcard" callbacks can observe all events
* Three types of callback supported - internal (instance-eval'd), external, and
  method callbacks.


== SYNOPSIS:

  FIXME (code sample of usage)

== DETAILS

=== What is it?

HookR can be understood in a few different ways.

* If you are familiar with Events and Event Listeners in Java or C#; Hooks in
  Emacs-lisp; or signals-and-slots as implemented in the Qt, Boost.Signals, or
  libsigc++ C++ frameworks - HookR provides a very similar facility.
* If youve ever used the Observer standard library, but wished you could
  have more than one type of notification per observable object, HookR is the
  library for you.
* HookR is an Inversion-of-Control framework in that it makes it easy to write
  event-driven code.
* HookR is a way to support a structured form of Aspect Oriented Programming
  where the advisable events are explicitly defined.

=== What HookR is not:

* HookR is not (yet) an asynchronous event notification system.  No provision
  for multi-threaded operation or event queueing is made.
* HookR will show you a good time, but it will not make you breakfast in the
  morning.

=== Concepts

Pour yourself a drink, loosen your tie, and let's get cozy with HookR.

==== Hooks

Hooks are at the center of HookR's functionality.  A hook is a named attachment
point for arbitrary callbacks.  From the event-handling perspective, hooks
define interesting events in an object's lifetime.  For example, an XML parser
might define hooks named +:tag_start+ and +:tag_end+ hooks.  A network protocol
class might define +:connected+ and +:message_received+ hooks.  A
database-backed model might define +:before_save+ and +:after_save+ hooks.

Hooks are defined at the class level, using the +define_hook+ method:

  class ZeroWing
    define_hook :we_get_signal
  end

===== Hook Parameters

Sometimes we want to pass some data along with our events.  Hooks can define
named parameters by passing extra symbol arguments to +define_hook+:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message
  end

===== Listing Hooks

You can access the full set of hooks defined for a particular class by calling
the #hooks class method:

  ZeroWing.hooks # => #<Hookr::HookSet: ... >

If you are playing along at home you may notice a +:__wildcards__+ hook in this
list.  We'll talk about that in the Advanced section.

==== Callbacks

Hooks aren't much use without callbacks.  Callbacks represent a piece of code to
be run when a hook is executed.

HookR defines three types of callback:

===== Internal Callbacks

An internal callback represents a block of code which will be run in the context
of the source object (the object executing the hook).  That is, it will be run
using #instance_eval.  In general this type of callback should only be defined
internally to the class having the hook, since the called code will have full
access to private members and instance variables of the source object.

One limitation of internal callbacks is that due to limitations of
+#instance_eval+, they cannot receive arguments.

===== External Callbacks

An external callback is a block of code which will be executed in the context in
which it was defined.  That is, a Proc which will be called with the Event
object (see below) and any parameters defined by the hook.

===== Method Callbacks

A method callback is a callback which when executed will call an instance method
on the source object (the object executing the hook).  Like internal callbacks,
these should usually only be added internally by the source class, since private
methods may be called.  The method will receive as arguments the Event (see
below), and an argument for each parameter defined on the hook.

A callback may be *named* or *anonymous*.  Naming callbacks makes it easier to
reference them after adding them, for instance if you want to remove a
callback.  Naming calbacks also ensures that only one callback with the given name
will be added to a hook.

There are several ways to add callbacks to hooks.

====== Adding callbacks In the class definition

The first way to define a callback is to do it in the class definition:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message

    we_get_signal do
      main_screen.turn_on!
    end
  end

HookR creates an anonymous, class-level macros for each defined hook. The above example
demonstrates an *internal* callback being defined on the hook +:we_get_signal+.
Why internal?  HookR uses a set of rules to determine what kind of callback to
generate.  If the block passed to the callback macro has no arguments, it will
generate an internal callback.  If, however, the block defines arguments:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message

    we_get_signal do |event, message|
      puts message.what_you_say?
    end
  end

An *external* callback will be defined.  Why external?  As discussed earlier,
it is impossible for +instance_eval+-ed code to receive arguments.  So in order
to supply the defined parameters an external callback must be defined.

If no block is passed, but a method name is supplied, a *method* callback will
be generated:

  class ZeroWing
    include HookR::Hooks

    def take_off_every_zig(event, message)
      # ...
    end

    define_hook :we_get_signal, :message

    we_get_signal :take_off_every_zig
  end

For any of the variations demonstrated above, an explicit symbolic callback
handle may be supplied.  This handle can then be used to access or remove the
callback.

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message

    we_get_signal :zig do
      take_off_every_zig
    end
  end

  ZeroWing.remove_callback(:zig)

====== In instance methods

In instance methods of the class defining the hook, it is possible to explicitly
add the different types of callback using the methods +add_external_callback+,
+add_internal_callback+, and #add_method_callback. See the method documentation
for details.

The methods all return a callback *handle*, which can be used to access or remove
the callback.  If this will be the same as the +handle+ argument, if one is supplied.

====== In client code

In code that uses a hook-enabled object, callbacks can be easily added using a
method with the same name as the hook:

  zw = ZeroWing.new
  zw.we_get_signal do |event, message|
    puts "it's you!"
  end

Only *external* callbacks may be added using this method. This is consistent
with public/private class protection.

Like the +add_*_callback+ methods described above, this method may be passed an
explicit symbolic handle.  Whether an explicit handle is supplied or not, it
will always return a handle which can be used to access or remove the added
callback.

===== Removing Callbacks

+remove_callback+ methods are available at both the class and instance levels.
They can be used to remove class- or instance-level callbacks, respectively.
Both forms take either a callback index or a handle.

==== Events

Events represent the execution of a hook.  They encapsulate information about
the hook, the object executing the hook, and any parameters passed when the hook
was executed (see Execution, below).  Events are normally passed as the first
argument to external callbacks and method callbacks.

Events have a few important attributes:

===== Source

The event *source* is the object which initiated the hook execution.  Ordinarily
this is an instance of the class which defines the hook.

===== Name

Name is the hook name of the hook being executed.  For instance, given the
following hook definition:

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message
  end

the +name+ wold be +:we_get_signal+.

===== Arguments

Event +arguments+ are the extra arguments passed to #execute_hook, corresponding
to the hook parameters (if any).

==== Execution

An instance of the hook-bearing class can initiate hook execution by calling
#execute_hook.  It takes as arguments the hook name and an argument for every
parameter defined by the hook.  Example:

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message

    def game_start
      execute_hook(:we_get_signal, "You have no chance to survive")
    end
  end

There are two models of callback execution.  Each is described below.

===== Iterative

In the simple case, callback execution follows the iterative model.  Each
callback is executed in turn (in order of addition).  Callback return calues are
ignored.

===== Recursive

==== Advanced

===== Hook Chaining
===== Wildcard Callbacks
===== Callback Arity
===== Custom Hook Classes

== REQUIREMENTS:

* FailFast (http://fail-fast.rubyforge.org)

== INSTALL:

* sudo gem install hookr

== SUPPORT/CONTRIBUTING

Questions, comments, suggestions, bug reports: mailto:avdi@avdi.org

== LICENSE:

(The MIT License)

Copyright (c) 2008

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
