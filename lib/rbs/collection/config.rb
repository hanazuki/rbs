# frozen_string_literal: true

module RBS
  module Collection

    # This class represent the configration file.
    class Config
      class CollectionNotAvailable < StandardError
        def initialize
          super <<~MSG
            rbs collection is not initialized.
            Run `rbs collection install` to install RBSs from collection.
          MSG
        end
      end

      PATH = Pathname('rbs_collection.yaml')

      def self.find_config_path
        current = Pathname.pwd

        loop do
          config_path = current.join(PATH)
          return config_path if config_path.exist?
          current = current.join('..')
          return nil if current.root?
        end
      end

      # Generate a rbs lockfile from Gemfile/Gemfile.lock to `config_path`.
      # If `with_lockfile` is true, it respects existing rbs lockfile.
      #
      def self.generate_lockfile(config_path:, gemfile_lock_path:, with_lockfile: true)
        config, _ = LockfileGenerator.generate(config_path: config_path, gemfile_lock_path: gemfile_lock_path, with_lockfile: with_lockfile)
        config
      end

      def self.from_path(path)
        new(YAML.load(path.read), config_path: path)
      end

      def self.lockfile_of(config_path)
        lock_path = to_lockfile_path(config_path)
        if lock_path.file?
          Lockfile.load(lock_path, YAML.load_file(lock_path.to_s))
        end
      end

      def self.to_lockfile_path(config_path)
        config_path.sub_ext('.lock' + config_path.extname)
      end

      def initialize(data, config_path:)
        @data = data
        @config_path = config_path
      end

      def add_gem(gem)
        gems << gem
      end

      def gem(gem_name)
        gems.find { |gem| gem['name'] == gem_name }
      end

      def repo_path
        @config_path.dirname.join data_path
      end

      def data_path
        @data['path']
      end

      def data_sources
        @data['sources']
      end

      def sources
        @sources ||= (
          data_sources
            .map { |c| Sources.from_config_entry(c) }
            .push(Sources::Stdlib.instance)
            .push(Sources::Rubygems.instance)
        )
      end

      def dump_to(io)
        gems = self.gems.reject {|gem| gem['ignore'] }.sort_by {|gem| gem['name'] }
        YAML.dump(
          @data.merge({ "gems" => gems }),
          io
        )
      end

      def gems
        @data['gems'] ||= []
      end

      def gemfile_lock_path=(path)
        @data['gemfile_lock_path'] = path.relative_path_from(@config_path.dirname).to_s
      end

      def gemfile_lock_path
        path = @data['gemfile_lock_path']
        return unless path
        @config_path.dirname.join path
      end

      # It raises an error when there are non-available libraries
      def check_rbs_availability!
        raise CollectionNotAvailable unless repo_path.exist?

        gems.each do |gem|
          source = gem['source'] or next
          case source['type']
          when 'git'
            meta_path = repo_path.join(gem['name'], gem['version'] || raise, Sources::Git::METADATA_FILENAME)
            raise CollectionNotAvailable unless meta_path.exist?
            raise CollectionNotAvailable unless gem == YAML.load(meta_path.read)
          end
        end
      end
    end
  end
end
