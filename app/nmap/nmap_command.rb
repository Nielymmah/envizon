class NmapCommand
  def parse_ip_range(input)
    ip_range, subnet = input.split('/').map(&:strip)
    ip_parts = ip_range.split('.')
    return unless [4, 7].include? ip_parts.size

    begin
      case ip_parts.size
      when 4 # eg ["192", "168", "1-4", "15"]
        result = parse_splited_ip_range(ip_parts).flatten.map do |range|
          IPAddress.parse [range, subnet].compact.join('/')
        end

      when 7 # eg ["192", "168", "1", "1-192", "168", "1", "10"]
        s_start, s_end = ip_parts[3].split('-').map(&:strip)
        ip_start_s = (ip_parts[0, 3] + [s_start]).join('.')
        ip_end_s = ([s_end] + ip_parts[4, 7]).join('.')
        ip_start = IPAddr.new([ip_start_s, subnet].compact.join('/'))
        ip_end = IPAddr.new([ip_end_s, subnet].compact.join('/'))
        result = (ip_start..ip_end).map { |ipad| IPAddress.parse "#{ipad}/#{ipad.prefix}" }
      end

      # [ip_range, subnet].compact.join('/')
    rescue StandardError # not compatible ip range
      return nil
    end
    result
  end

  # recursive funktion
  def parse_splited_ip_range(ip_parts)
    result = []
    ip = ip_parts.join('.')
    if ip.include?('-') || ip.include?(',')
      ip_parts.each_with_index do |ip_part, i|
        if ip_part.include? '-'
          s_start, s_end = ip_part.split('-').map(&:strip).reject(&:empty?)
          result += (s_start..s_end).map do |curr|
            iner_range = (ip_parts[0, i] + [curr] + ip_parts[(i + 1), ip_parts.size])
            parse_splited_ip_range(iner_range)
          end
          return result # do not go on. the rest of the parts will get by the recursive function
        elsif ip_part.include? ','
          result += ip_part.split(',').map(&:strip).reject(&:empty?).map do |curr|
            iner_range = (ip_parts[0, i] + [curr] + ip_parts[(i + 1), ip_parts.size])
            parse_splited_ip_range(iner_range)
          end
          return result # do not go on. the rest of the parts will get by the recursive function
        end
        # go to next part and search for "-" or ","
      end
    else
      result.push ip
    end
    result
  end

  def initialize(options, user_id, targets = [])
    @timestamp = Time.now.strftime('%Y%m%d_%H%M%S_%L')
    @run_counter = 0

    @user_id = user_id
    begin
      @simultane_targets = User.find(@user_id).settings.where(name: 'max_host_per_scan').first_or_create.value.to_i
      @simultane_targets = @simultane_targets.positive? ? @simultane_targets : 0
    rescue StandardError
      @simultane_targets = 0
    end

    # split targets
    targets_list = targets.respond_to?(:split) ? targets.split(' ') : targets
    ip_targets = []
    host_targets = []
    targets_list.each do |address|
      begin
        ip_targets.push(IPAddress.parse(address))
      rescue ArgumentError
        # not a CIDR range
        ip_range = parse_ip_range(address)
        if ip_range.blank?
          host_targets.push address
        else
          ip_targets += ip_range
        end
      end
    end

    # if the user set '31' or '30' prefix, handle them like single host. this is a workarout because IPAddress maps these range in different ways
    special_targets = ip_targets.select { |value| [30, 31].any? value.prefix.to_i }
    special_targets.each do |value|
      host_targets.push value.to_string
      ip_targets.delete(value)
    end

    ip_targets = IPAddress::IPv4.summarize(*ip_targets)

    # split Targets to array
    if @simultane_targets.positive?
      @all_targets = host_targets.each_slice(@simultane_targets).to_a
      # get all single ips as list
      unless ip_targets.blank?

        # workaround for subnet with two clients, because the subnet '31' not ever suported
        ip_targets = ip_targets.map do |ip|
          case ip.prefix.to_i
          when 31, 30 # workaround for subnet with two/four clients, because the subnet '31','30' not ever suported
            result = ip.entries.map do |inner|
              inner.prefix = 32
              inner
            end
          else
            result = ip
          end
          result
        end

        ip_targets = ip_targets.flatten.map { |i| i.hosts.blank? ? i : i.hosts }.flatten
        # .hosts do not split to single ips, because its don't set the subnet to /32
        ip_targets = ip_targets.map do |single|
          single.prefix = 32
          single
        end
      end
      # fill last array to max
      if !@all_targets.blank? && !ip_targets.blank? && @all_targets.last.length < @simultane_targets
        ips = address_array_to_string_array(ip_targets.shift(@simultane_targets - @all_targets.last.length))
        @all_targets.last.push(*ips)
      end

      unless ip_targets.blank?
        # map ips to compact string arrays and apand to @all_targets
        @all_targets += ip_targets.each_slice(@simultane_targets).to_a.map { |i| address_array_to_string_array(i) }
      end
    else
      # all hosts at same scan
      @all_targets = host_targets + address_array_to_string_array(ip_targets)
    end

    @max_run_counter = @all_targets.length

    # file names
    FileUtils.mkdir_p(Rails.root.join('nmap', 'uploads'))
    gen_exclude_file(user_id)
    @options = args(options)
  end

  def address_array_to_string_array(ip_address_list)
    result_map = IPAddress::IPv4.summarize(*ip_address_list).map do |ip|
      case ip.prefix.to_i
      when 32 # single target without subnet
        result = ip.address
      when 31, 30 # workaround for subnet with two/four clients, because the subnet '31'/'32' not ever suported
        result = ip.entries.map(&:address)
      else
        result = ip.to_string
      end
      result
    end
    result_map.flatten.uniq
  end

  def gen_exclude_file(user_id)
    exclude_hosts = Socket.ip_address_list.map do |ip|
      ipaddr = IPAddress(ip.ip_address)
      ipaddr.respond_to?(:compressed) ? ipaddr.compressed : ipaddr.address
    end

    host = User.find(user_id).settings.where(name: 'exclude_hosts').first_or_create.value
    exclude_hosts += YAML.safe_load(host).lines if host.present?

    exclude_hosts = exclude_hosts.uniq.sort

    path = Rails.root.join('nmap', 'uploads', @timestamp + '_exclude.txt')
    exclude_file = File.open(path, 'w')
    exclude_hosts.each { |h| exclude_file.puts h }
    exclude_file.close

    wait_for_file(path)
    @exclude_file = path
  end

  def wait_for_file(file_name)
    sleep 0.5 until File.exist? file_name
  end

  def args(options)
    options = options.split
    %w[nmap sudo -iL -oX -oN -oS -oG --datadir].each { |o| options.delete o }

    options.dup.each do |option|
      # we'll assume nothing else in here uses path separators
      # => CIDR style targets are passed separately to NmapCommand
      (options.delete(option) && next) if option.include?('datadir=')
      next unless option.match(%r{\\|\/})

      next if File.directory?(File.expand_path(option))

      # we also skip relative pathes even in nmap-nse-directories, to avoid path traversel
      # users should just enter the script name directly - if it's in there, it will be found
      prefixes = %w[~/.nmap /usr/local/share/nmap /usr/share/nmap]
      is_bad_path = prefixes.any do |prefix|
        File.file?(Pathname(prefix).join(option).expand_path) ||
          File.file?(Pathname(prefix).join(option, 'scripts').expand_path)
      end

      options.delete(option) if is_bad_path
    end

    ['--stats-every', '60s',
     '--excludefile',
     @exclude_file.to_s].each { |o| options.push o }
    options
  end

  def run_worker(scan)
    scan.startdate = Time.now
    scan.save

    @all_targets.each.with_index(1) do |targets, index|
      options = @options.dup
      file_name = Rails.root.join('nmap', 'uploads', "#{@timestamp}_output#{index}-#{@max_run_counter}.xml")
      options.push '-oX'
      options.push file_name.to_s
      options.push targets
      options.flatten!
      cmd = 'nmap'

      args_parse = {
        'scan_id' => scan.id,
        'user_id' => @user_id,
        'cmd' => cmd,
        'options' => options.join(' '),
        'run_counter' => index,
        'filename' => file_name.to_s,
        'max_run_counter' => @max_run_counter
      }
      ScanWorker.perform_async(args_parse)
    end
  end

  attr_reader :run_counter
  attr_reader :max_run_counter
end
