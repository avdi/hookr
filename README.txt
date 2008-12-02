= HookR
    by Avdi Grimm
    http://hookr.rubyforge.org

== DESCRIPTION:

HookR is a publish/subscribe callback hook facility for Ruby.

=== What is it?

HookR can be understood in a few different ways.

* If you are familiar with Events and Event Listeners in
  Java[http://java.sun.com/docs/books/tutorial/javabeans/events/index.html] or
  C#[http://msdn.microsoft.com/en-us/library/aa645739(VS.71).aspx];
  Hooks[http://www.gnu.org/software/emacs/manual/html_node/elisp/Hooks.html#Hooks]
  in Emacs-lisp; or signals-and-slots as implemented in the
  Qt[http://doc.trolltech.com/4.4/signalsandslots.html],
  Boost.Signals[http://www.boost.org/doc/libs/1_37_0/doc/html/signals.html], or
  libsigc++[http://libsigc.sourceforge.net/] frameworks - HookR provides a
  very similar facility.
* If youve ever used the Observer standard library, but wished you could
  have more than one type of notification per observable object, HookR is the
  library for you.
* HookR is an easy way to add
  Rails-style[http://api.rubyonrails.org/classes/ActiveRecord/Callbacks.html]
  before- and after-filters to your own classes. 
* HookR is an
  Inversion-of-Control[http://martinfowler.com/bliki/InversionOfControl.html]
  framework in that it makes it easy to write event-driven code. 
* HookR is a way to support a limited, structured form of Aspect Oriented
  Programming (AOP[http://en.wikipedia.org/wiki/Aspect-oriented_programming])
  where the advisable events are explicitly defined. 

=== What HookR is not:

* HookR is not (yet) an asynchronous event notification system.  No provision is
  made for multi-threaded operation or event queueing.
* HookR will show you a good time, but it will not make you breakfast in the
  morning.

== FEATURES:

* Fully spec'd
* Provides class-level and instance-level callbacks
* Inheritance-safe
* Supports both iterative and recursive callback models
* "Wildcard" callbacks can observe all events
* Three types of callback supported - internal (instance-eval'd), external, and
  method callbacks.

== SYNOPSIS:

  require 'rubygems'
  require 'hookr'

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message

    def start_game
      execute_hook(:we_get_signal, "How are you gentlemen?")
    end

    def bomb(event, message)
      puts "somebody set us up the bomb!"
    end

    we_get_signal do |event, message|
      puts "Main screen turn on!"
      puts "Cats: #{message}"
    end

    we_get_signal :bomb

  end

  zw = ZeroWing.new
  zw.we_get_signal do
    puts "Take off every zig!"
  end

  zw.start_game
  # >> Main screen turn on!
  # >> Cats: How are you gentlemen?
  # >> somebody set us up the bomb!
  # >> Take off every zig!

== DETAILS

Pour yourself a drink, loosen your tie, and let's get cozy with HookR.

=== Hooks

Hooks are at the center of HookR's functionality.  A hook is a named attachment
point for arbitrary callbacks.  It is the "publish" portion of
publish/subscribe. From the event-handling perspective, hooks define interesting
events in an object's lifetime.  For example, an XML parser might define hooks
named <code>:tag_start</code> and <code>:tag_end</code> hooks.  A network
protocol class might define <code>:connected</code> and
<code>:message_received</code> hooks.  A database-backed model might define
<code>:before_save</code> and <code>:after_save</code> hooks.

Hooks are defined at the class level, using the <code>define_hook</code> method:

  class ZeroWing
    define_hook :we_get_signal
  end

==== Hook Parameters

Sometimes we want to pass some data along with our events.  Hooks can define
named parameters by passing extra symbol arguments to <code>define_hook</code>:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message
  end

==== Listing Hooks

You can access the full set of hooks defined for a particular class by calling
the #hooks class method:

  ZeroWing.hooks # => #<Hookr::HookSet: ... >

If you are playing along at home you may notice a <code>:__wildcards__</code> hook in this
list.  We'll talk about that in the Advanced section.

=== Callbacks

Hooks aren't much use without callbacks.  Callbacks represent a piece of code to
be run when a hook is executed.  They are the "subscribe" part of the
publish/subscribe duo.

HookR defines three types of callback:

==== Internal Callbacks

An internal callback represents a block of code which will be run in the context
of the source object (the object executing the hook).  That is, it will be run
using #instance_eval.  In general this type of callback should only be defined
internally to the class having the hook, since the called code will have full
access to private members and instance variables of the source object.

One drawback of internal callbacks is that due to limitations of
<code>#instance_eval</code>, they cannot receive arguments.

==== External Callbacks

An external callback is a block of code which will be executed in the context in
which it was defined.  That is, a Proc which will be called with the Event
object (see below) and any parameters defined by the hook.

==== Method Callbacks

A method callback is a callback which when executed will call an instance method
on the source object (the object executing the hook).  Like internal callbacks,
these should usually only be added internally by the source class, since private
methods may be called.  The method will receive as arguments the Event (see
below), and an argument for each parameter defined on the hook.

==== Named Callbacks

A callback may be *named* or *anonymous*.  Naming callbacks makes it easier to
reference them after adding them, for instance if you want to remove a
callback.  Naming calbacks also ensures that only one callback with the given name
will be added to a hook.

==== Adding Callbacks

There are several ways to add callbacks to hooks.

===== Adding callbacks In the class definition

The first way to define a callback is to do it in the class definition:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message

    we_get_signal do
      main_screen.turn_on!
    end
  end

HookR creates class-level macros for each defined hook. The above example
demonstrates an anonymous *internal* callback being defined on the hook
<code>:we_get_signal</code>.  Why internal?  HookR uses a set of rules to
determine what kind of callback to generate.  If the block passed to the
callback macro has no arguments, it will generate an internal callback.  If,
however, the block defines arguments:

  class ZeroWing
    include HookR::Hooks
    define_hook :we_get_signal, :message

    we_get_signal do |event, message|
      puts message.what_you_say?
    end
  end

An *external* callback will be defined.  Why external?  As discussed earlier,
it is impossible for <code>instance_eval</code>-ed code to receive arguments.  So in order
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

===== In instance methods

In instance methods of the class defining the hook, it is possible to explicitly
add the different types of callback using the methods <code>add_external_callback</code>,
<code>add_internal_callback</code>, and #add_method_callback. See the method documentation
for details.

The methods all return a callback *handle*, which can be used to access or remove
the callback.  This will be the same as the <code>handle</code> argument, if one is supplied.

===== In client code

In code that uses a hook-enabled object, callbacks can be easily added using a
method with the same name as the hook:

  zw = ZeroWing.new
  zw.we_get_signal do |event, message|
    puts "it's you!"
  end

Only *external* callbacks may be added using this method. This is consistent
with public/private class protection.

Like the <code>add_*_callback</code> methods described above, this method may be passed an
explicit symbolic handle.  Whether an explicit handle is supplied or not, it
will always return a handle which can be used to access or remove the added
callback.

==== Removing Callbacks

<code>remove_callback</code> methods are available at both the class and instance levels.
They can be used to remove class- or instance-level callbacks, respectively.
Both forms take either a callback index or a handle.

=== Listeners

Listeners embody an alternative model of publish/subscribe event handling.  A
Listener is an object which "listens" to another object.  Instead of attaching
callbacks to individual hooks, you attach a listener to an entire object.
Anytime a hook is executed on the object being listened to, a method with a name
corresponding to the hook is called on the listener.  These handler methods
should take arguments corresponding to the parameters defined on the hook.

This model is similar to the SAX XML event model, and to the Java
Event/EventListener model.

For more convenient listener definition, HookR can generate a base class for you
to base your listeners on.  The base class will provide default do-nothing
methods for each hook, so you only have to redefine the methods you care about.

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message

    define_hook :set_us_up_the_bomb
  end

  class MyListener < ZeroWing::Listener
    def we_get_signal(message)
      # ...
    end

    # :set_us_up_the_bomb events are silently ignored
  end

  zw = ZeroWing.new
  l  = MyListener.new
  
  zw.add_listener(l)

=== Events

Events represent the execution of a hook.  They encapsulate information about
the hook, the object executing the hook, and any parameters passed when the hook
was executed (see Execution, below).  Events are normally passed as the first
argument to external callbacks and method callbacks.

Events have a few important attributes:

==== Source

The event *source* is the object which initiated the hook execution.  Ordinarily
this is an instance of the class which defines the hook.

==== Name

Name is the hook name of the hook being executed.  For instance, given the
following hook definition:

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message
  end

the <code>name</code> would be <code>:we_get_signal</code>.

==== Arguments

Event <code>arguments</code> are the extra arguments passed to #execute_hook, corresponding
to the hook parameters (if any).

=== Execution

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

==== Iterative

In the simple case, callback execution follows the iterative model.  Each
callback is executed in turn (in order of addition).  Callback return calues are
ignored.

==== Recursive

When #execute_hook is called with a block argument, recursive execution is
triggered.  E.g.:

  class ZeroWing
    include HookR::Hooks

    define_hook :we_get_signal, :message

    def game_start
      execute_hook(:we_get_signal, "You have no chance to survive") do |event, message|
        puts message
      end
    end
  end

In this model, the most recently defined hook will be called first.  As usual,
it will be passed an event as its first argument.  In order to continue
execution to the next callback, the first callback must call <code>event.next</code>.  This
will cause the next-most-recently-defined callback to be executed, which will
again be passed an event with a #next method, and so on.  Finally, when the last
callback is executed and calls <code>event.next</code>, the block passed to #execute_hook
will be called.

In this way, it is possible to "wrap" an event with callbacks or, in the
language of AOP, "around advice".  At any point in the chain, a callback can opt
to pass new arguments to Event#next, which will then override the original
arguments for any callbacks further down the chain.  This enables callbacks to
act as "filters" on the callback arguments.

WARNING: This area is still under active development, and the API may change.
Some ideas under consideration include automatically executing the next callback
even if Event#next is not explicitly called; and an Event#cancel method which
will prevent further callbacks from running.

=== Advanced

In which we take a look under HookR's clothes.

==== Adding multiple callbacks with the same name

When adding callbacks with an explicit handle, only one callback for that handle
can be added to a given hook.  Subsequent attempts to add a callback with the
same name will silently fail.  This makes adding named callbacks an idempotent
operation.

==== Hook Chaining

Every hook has a parent, to which it delegates execution when it is finished
executing its own callbacks.  This is how class inheritance is handles, and how
it is possible for callbacks to be added at both the class and instanve levels.
Under normal circumstances, however, this is an implementation detail which Just
Works, and you can safely ignore it.

==== Wildcard Callbacks

It is possible to define a "wildcard" callback which will be called when *any*
hook is executed, using the #add_wildcard_callback class and instance methods.

==== Callback Arity

External and method callbacks must take at least as many arguments as
there are parameters on the hook.  For instance, given the following hook
definition:

  class ZeroWing
    include HookR::Hooks

    define_hook :take_off_every, :what, :why
  end

Callbacks for <code>:take_off_every</code> must accept at least two arguments.  If they accept
exactly two arguments, they will be passed the two arguments only. If they
accept three arguments, they will be passed the event object followed by the two
arguments.  More than three arguments would be an error.

==== Custom Hook Classes

In some special cases it may be desirable to customize the specific class of
Hook generated by #define_hook.  When this is the case you may define a custom
<code>make_hook</code> class method.  This method will be passed a hook name, a parent
hook, and a list of parameters, and should return an instance of a subclass of
HookR::Hook or something that behaves very similarly.

== REQUIREMENTS:

* FailFast (http://fail-fast.rubyforge.org)

== INSTALL:

* sudo gem install hookr

== KNOWN BUGS

* It is currently not possible to define a method callback before the method has
  been defined.  This is either a bug or a feature, depending on your point of
  view.

== SUPPORT/CONTRIBUTING

Questions, comments, suggestions, bug reports: Email Avdi Grimm at mailto:avdi@avdi.org

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
