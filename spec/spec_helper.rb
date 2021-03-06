# frozen_string_literal: true
$:.unshift File.expand_path("..", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)
$:.unshift File.expand_path("../../../delfos/lib", __FILE__)

require "binding_of_caller"

require "bundler/psyched_yaml"
require "fileutils"
require "uri"
require "digest/sha1"

begin
  require "rubygems"
  spec = Gem::Specification.load("bundler.gemspec")
  rspec = spec.dependencies.find {|d| d.name == "rspec" }
  gem "rspec", rspec.requirement.to_s
  require "rspec"
  require "diff/lcs"
rescue LoadError
  abort "Run rake spec:deps to install development dependencies"
end

if File.expand_path(__FILE__) =~ %r{([^\w/\.])}
  abort "The bundler specs cannot be run from a path that contains special characters (particularly #{$1.inspect})"
end



require "bundler"

# Require the correct version of popen for the current platform
if RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
  begin
    require "win32/open3"
  rescue LoadError
    abort "Run `gem install win32-open3` to be able to run specs"
  end
else
  require "open3"
end

Dir["#{File.expand_path("../support", __FILE__)}/*.rb"].each do |file|
  require file unless file.end_with?("hax.rb")
end

$debug = false

Spec::Manpages.setup
Spec::Rubygems.setup
FileUtils.rm_rf(Spec::Path.gem_repo1)
ENV["RUBYOPT"] = "#{ENV["RUBYOPT"]} -r#{Spec::Path.root}/spec/support/hax.rb"
ENV["BUNDLE_SPEC_RUN"] = "true"

# Don't wrap output in tests
ENV["THOR_COLUMNS"] = "10000"

Spec::CodeClimate.setup

RSpec.configure do |config|
  config.include Spec::Builders
  config.include Spec::Helpers
  config.include Spec::Indexes
  config.include Spec::Matchers
  config.include Spec::Path
  config.include Spec::Rubygems
  config.include Spec::Platforms
  config.include Spec::Sudo
  config.include Spec::Permissions

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.disable_monkey_patching!

  # Since failures cause us to keep a bunch of long strings in memory, stop
  # once we have a large number of failures (indicative of core pieces of
  # bundler being broken) so that running the full test suite doesn't take
  # forever due to memory constraints
  config.fail_fast ||= 25

  if ENV["BUNDLER_SUDO_TESTS"] && Spec::Sudo.present?
    config.filter_run :sudo => true
  else
    config.filter_run_excluding :sudo => true
  end

  if ENV["BUNDLER_REALWORLD_TESTS"]
    config.filter_run :realworld => true
  else
    config.filter_run_excluding :realworld => true
  end

  git_version = Bundler::Source::Git::GitProxy.new(nil, nil, nil).version

  config.filter_run_excluding :ruby => LessThanProc.with(RUBY_VERSION)
  config.filter_run_excluding :rubygems => LessThanProc.with(Gem::VERSION)
  config.filter_run_excluding :git => LessThanProc.with(git_version)
  config.filter_run_excluding :rubygems_master => (ENV["RGV"] != "master")

  config.filter_run_when_matching :focus unless ENV["CI"]

  original_wd  = Dir.pwd
  original_env = ENV.to_hash.delete_if {|k, _v| k.start_with?(Bundler::EnvironmentPreserver::BUNDLER_PREFIX) }

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :all do
    build_repo1
    # HACK: necessary until rspec-mocks > 3.5.0 is used
    # see https://github.com/bundler/bundler/pull/5363#issuecomment-278089256
    if RUBY_VERSION < "1.9"
      FileUtils.module_eval do
        alias_method :mkpath, :mkdir_p
        module_function :mkpath
      end
    end
  end

  config.before :each do
    reset!
    system_gems []
    in_app_root
    @all_output = String.new
  end

  config.after :each do |example|
    Delfos.reset!

    @all_output&.strip!

    if example.exception && !@all_output&.empty?
      warn @all_output unless config.formatters.grep(RSpec::Core::Formatters::DocumentationFormatter).empty?
      message = example.exception.message + "\n\nCommands:\n#{@all_output}"
      (class << example.exception; self; end).send(:define_method, :message) do
        message
      end
    end

    Dir.chdir(original_wd)
    ENV.replace(original_env)
  end
end

require "delfos"
require "fileutils"

FileUtils.mkdir_p "tmp-delfos"

class DelfosLogger
  def initialize

    # iniitialize log files
    %w(error fatal info debug).each do |type|
      FileUtils.touch "./tmp-delfos/#{type}.log"
      log_files[type]
    end
  end

  def error(msg=nil, &block)
    if block_given?
      log((block.call), "error", STDOUT)
    else
      log(msg, "error", STDOUT)
    end
  end

  def info(msg=nil)
    #log(msg, "info")
  end

  def debug(msg=nil)
    #log(msg, "debug")
  end

  def fatal(msg=nil, &block)
    if block_given?
      log((block.call), "fatal", STDOUT)
    else
      log(msg, "fatal", STDOUT)
    end
  end

  def flush
    log_files.values.each(&:flush)
  end

  def close
    flush
    log_files.values.each(&:close)
  end

  private

  def log(msg, *types)
    types.each do |type|
      if type==STDOUT
        STDOUT.puts(msg)
      else
        log_file(type).puts msg
      end
    end
  end

  def log_file(type)
    log_files[type] ||= File.open("./tmp-delfos/#{type}.log", "a")
  end

  def log_files
    @log_files ||= {}
  end

  def write_to_both(msg, type)
    write_to_one(msg, type)

    STDOUT.puts msg
  end
end


Delfos.configure do |c|
  c.include= "lib"
  c.logger = DelfosLogger.new
  c.offline_query_saving = true
  c.offline_query_filename = "tmp-delfos/query_parameters-2.json"
end

Delfos.start!
