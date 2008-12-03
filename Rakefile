# Look in the tasks/setup.rb file for the various options that can be
# configured in this Rakefile. The .rake files in the tasks directory
# are where the options are used.

begin
  require 'bones'
  Bones.setup
rescue LoadError
  load 'tasks/setup.rb'
end

ensure_in_path 'lib'
require 'hookr'

task :default => 'spec:run'

PROJ.name = 'hookr'
PROJ.authors = 'Avdi Grimm'
PROJ.email = 'avdi@avdi.org'
PROJ.url = 'http://hookr.rubyforge.org'
PROJ.version = HookR::VERSION
PROJ.rubyforge.name = 'hookr'

# TODO I want to be able to use -w here, but RSpec produces a hojillion warnings
PROJ.ruby_opts = []
PROJ.spec.opts << '--color'

depend_on 'fail-fast', '1.0.0'

# EOF
