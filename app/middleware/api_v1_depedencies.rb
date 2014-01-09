require 'dalli'

class V1MarshaledDepedencies

  LIMIT = 250

  BadRequest = [404, {}, ["Go away"]]
  TooMany =    [413, {},
                ["Too many gems to resolve, please request less than #{LIMIT}"]]

  def data_for(name, ary, cache)
    gem = Rubygem.find_by_name(name)
    raise "Unknown gem - #{name}" unless gem

    these = []

    gem.versions.order(:number).reverse_each do |ver|
      deps = ver.dependencies.find_all { |d| d.scope == "runtime" }

      data = {
        :name => name,
        :number => ver.number,
        :platform => ver.platform,
        :dependencies => deps.map { |d| [d.name, d.requirements] }
      }
      these << data
      ary << data
    end

    if cache
      cache.set "gem.#{name}", Marshal.dump(these)
    end

    ary
  end

  CACHE = Dalli::Client.new("localhost:11211")

  def call(env)
    request = Rack::Request.new(env)

    return BadRequest unless request.path == "/api/v1/dependencies"

    gems = request.params['gems']

    return BadRequest unless gems

    gems = gems.split(",")

    return TooMany if gems.size > LIMIT

    ary = catch :bad_request do
      acquire gems, CACHE.clone
    end

    return BadRequest unless ary

    body = Marshal.dump ary

    [200, {}, [body]]
  end

  def acquire(gems, cache)
    ary = cache.get_multi(*gems.map { |g| "gem.#{g}" }).values.flat_map { |e| Marshal.load e }
    cache.multi do
      (gems - ary.map { |e| e[:name] }).each do |g|
        begin
          data_for g, ary, cache
        rescue
          throw :bad_request
        end
      end
    end
    ary
  end
end
