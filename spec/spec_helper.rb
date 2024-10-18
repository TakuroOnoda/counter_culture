require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'counter_culture'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'rails/all'

module PapertrailSupport
  def self.supported_here?
    true
  end
end

module DynamicAfterCommit
  def self.update_counter_cache_in_transaction(&block)
    Thread.current[:update_counter_cache_in_transaction] = true
    yield
  ensure
    Thread.current[:update_counter_cache_in_transaction] = nil
  end
end

require 'rspec'
require 'timecop'

if PapertrailSupport.supported_here?
  require 'paper_trail'
  require "paper_trail/frameworks/active_record"
  require 'paper_trail/frameworks/active_record/models/paper_trail/version'
  require 'paper_trail/frameworks/rspec'
end

case ENV['DB']
when 'postgresql'
  require 'pg'
when 'mysql2'
  require 'mysql2'
else
  require 'sqlite3'
end

CI_TEST_RUN = (ENV['TRAVIS'] && 'TRAVIS') \
                || (ENV['CIRCLECI'] && 'CIRCLE') \
                || ENV['CI'] \
                && 'CI'

DB_CONFIG = {
  defaults: {
    pool: 5,
    timeout: 5000,
    host: 'localhost',
    database: CI_TEST_RUN ? 'circle_test' : 'counter_culture_test',
  },
  sqlite3: {
    adapter: 'sqlite3',
    database: 'db/test.sqlite3',
  },
  mysql2: {
    adapter: 'mysql2',
    username: 'root',
    encoding: 'utf8',
    collation: 'utf8_unicode_ci',
    host: '127.0.0.1',
    port: '3306',
  },
  postgresql: {
    adapter: 'postgresql',
    # username: CI_TEST_RUN ? 'postgres' : '',
    host: 'postgres',
    username: "postgres",
    password: "postgres",
    min_messages: 'ERROR',
  }
}.with_indifferent_access.freeze

if Gem::Version.new(Rails.version) < Gem::Version.new('5.0.0')
  ActiveRecord::Base.raise_in_transactional_callbacks = true
end

ActiveRecord::Base.establish_connection(
  DB_CONFIG[:defaults].merge(DB_CONFIG[ENV['DB'] || :sqlite3])
)

begin
  was, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false unless ENV['SHOW_MIGRATION_MESSAGES']
  load "#{File.dirname(__FILE__)}/schema.rb"
ensure
  ActiveRecord::Migration.verbose = was unless ENV['SHOW_MIGRATION_MESSAGES']
end

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = 1

module DbRandom
  def db_random
    Arel.sql(ENV['DB'] == 'mysql2' ? 'rand()' : 'random()')
  end
end

# Spec for checking the number of queries executed within the block
def expect_queries(num = 1, filter: "", &block)
  queries = []

  callback = lambda do |_name, _start, _finish, _id, payload|
    next if payload[:sql].match?(/^SELECT a\.attname/)
    next unless payload[:sql].match?(/^SELECT|UPDATE|INSERT/)

    sql = payload[:sql].gsub(%Q{\"}, '').gsub('`', '') # to remove differences between DB adaptors

    matches_filter = sql.match?(filter)
    next unless matches_filter

    queries.push(sql)
  end

  ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)

  expect(queries.size).to eq(num), "#{queries.size} instead of #{num} queries were executed. #{"\nQueries:\n#{queries.join("\n")}" unless queries.empty?}"
end

RSpec.configure do |config|
  config.include DbRandom
  config.fail_fast = true unless CI_TEST_RUN
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

I18n.available_locales = [:ja, :en]

require 'mobility'
Mobility.configure do
  # PLUGINS
  plugins do
    # Backend
    #
    # Sets the default backend to use in models. This can be overridden in models
    # by passing +backend: ...+ to +translates+.
    #
    # To default to a different backend globally, replace +:key_value+ by another
    # backend name.
    #
    backend :jsonb

    # ActiveRecord
    #
    # Defines ActiveRecord as ORM, and enables ActiveRecord-specific plugins.
    active_record

    # Accessors
    #
    # Define reader and writer methods for translated attributes. Remove either
    # to disable globally, or pass +reader: false+ or +writer: false+ to
    # +translates+ in any translated model.
    #
    reader
    writer

    # Backend Reader
    #
    # Defines reader to access the backend for any attribute, of the form
    # +<attribute>_backend+.
    #
    backend_reader
    #
    # Or pass an interpolation string to define a different pattern:
    # backend_reader "%s_translations"

    # Query
    #
    # Defines a scope on the model class which allows querying on
    # translated attributes. The default scope is named +i18n+, pass a different
    # name as default to change the global default, or to +translates+ in any
    # model to change it for that model alone.
    #
    query

    # Cache
    #
    # Comment out to disable caching reads and writes.
    #
    # TBD: cache x jsonb で特定の問題（*1）があるため、一旦コメントアウト
    # cache

    # Dirty
    #
    # Uncomment this line to include and enable globally:
    dirty
    #
    # Or uncomment this line to include but disable by default, and only enable
    # per model by passing +dirty: true+ to +translates+.
    # dirty false

    # Column Fallback
    #
    # Uncomment line below to fallback to original column. You can pass
    # +column_fallback: true+ to +translates+ to return original column on
    # default locale, or pass +column_fallback: [:en, :de]+ to +translates+
    # to return original column for those locales or pass
    # +column_fallback: ->(locale) { ... }+ to +translates to evaluate which
    # locales to return original column for.
    # column_fallback
    #
    # Or uncomment this line to enable column fallback with a global default.
    # column_fallback true

    # Fallbacks
    #
    # Uncomment line below to enable fallbacks, using +I18n.fallbacks+.
    fallbacks
    #
    # Or uncomment this line to enable fallbacks with a global default.
    # fallbacks { :pt => :en }

    # Presence
    #
    # Converts blank strings to nil on reads and writes. Comment out to
    # disable.
    #
    # TBD: ブランクを nil として保存する
    #      mobility で使用するカラムは nil | 値あり で統一する。
    #      よって、 frontend に blank を送信したい場合は、 decorator で対応する。
    #      この設定を disable にしても、
    #      ブランク | nil | 値あり の 3 パターンでの validate がうまくできなかったが、
    #      (*1) 問題が関係している可能性がある。
    presence

    # Default
    #
    # Set a default translation per attributes. When enabled, passing +default:
    # 'foo'+ sets a default translation string to show in case no translation is
    # present. Can also be passed a proc.
    #
    # default 'foo'

    # Fallthrough Accessors
    #
    # Uses method_missing to define locale-specific accessor methods like
    # +title_en+, +title_en=+, +title_fr+, +title_fr=+ for each translated
    # attribute. If you know what set of locales you want to support, it's
    # generally better to use Locale Accessors (or both together) since
    # +method_missing+ is very slow.  (You can use both fallthrough and locale
    # accessor plugins together without conflict.)
    #
    # fallthrough_accessors

    # Locale Accessors
    #
    # Uses +def+ to define accessor methods for a set of locales. By default uses
    # +I18n.available_locales+, but you can pass the set of locales with
    # +translates+ and/or set a global default here.
    #
    # locale_accessors
    #
    # Or define specific defaults by uncommenting line below
    locale_accessors [:en, :ja]

    # Attribute Methods
    #
    # Adds translated attributes to +attributes+ hash, and defines methods
    # +translated_attributes+ and +untranslated_attributes+ which return hashes
    # with translated and untranslated attributes, respectively. Be aware that
    # this plugin can create conflicts with other gems.
    #
    # attribute_methods
  end
end
