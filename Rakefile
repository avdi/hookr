gem 'bones', '~> 3.0'

begin
  require 'bones'
rescue LoadError
  abort '### Please install the "bones" gem ###'
end

task :default => 'spec:run'
task 'gem:release' => 'spec:run'

Bones {
  name    'hookr'
  authors 'Avdi Grimm'
  email   'avdi@avdi.org'
  url     'http://hookr.rubyforge.org'

  summary "A callback hooks framework for Ruby."

  # ann.email[:from]     = 'avdi@avdi.org'
  # ann.email[:to]       = 'ruby-talk@ruby-lang.org'
  # ann.email[:server]   = 'smtp.gmail.com'
  # ann.email[:domain]   = 'avdi.org'
  # ann.email[:port]     = 587
  # ann.email[:acct]     = 'avdi.grimm'
  # ann.email[:authtype] = :plain

  depend_on 'fail-fast', '1.0.0'
}


# EOF
