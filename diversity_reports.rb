#!/usr/bin/ruby

require 'csv'
require 'logger'
require 'optparse'

ALL_DEMO_TYPES = [
  'gender',
  'age',
  'ethnicity',
  'education',
  'employment status',
  'marital status',
  'household income',
]

# order makes it easier to pop into the spreadsheet
ORDER_PREFS = {
  'age' => [
    'under 18',
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55+',
    'prefer not to say',
    'no response',
  ],
  'education' => [
    'some high school',
    'high school or equivalent',
    'trade school',
    'bachelor\'s degree',
    'master\'s degree',
    'doctorate (e.g. phd, edd, md)',
    'other',
    'prefer not to say',
    'no response',
  ],
  'gender' => [
    'male', 'female', 'other', 'no response', 'prefer not to say', 'non-binary',
  ],
}

logger = Logger.new($stdout)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, _progname, msg|
  if severity == 'INFO'
    "#{msg}\n"
  else
    "#{severity}[#{datetime}]: #{msg}\n"
  end
end

demo_types = ALL_DEMO_TYPES
OptionParser.new do |opts|
  opts.on(
    '-t',
    '--demo-type TYPE[,TYPE...]',
    Array,
    'Limit to demographic type TYPE. Possibilities: ' +
      ALL_DEMO_TYPES.join(', '),
  ) do |t|
    demo_types = t
  end
  opts.on('-l', '--log-level LEVEL', 'Enable debug') do |level|
    logger.level = level.to_sym
  end
end.parse!

filename = ARGV.pop
fail "Need to specify a file" unless filename
demo_data = CSV.table(filename)

results = {}
totals = {}
possible_values = {}
%w{accepts rejects totals}.each do |status|
  results[status] = {}
  demo_types.each do |type|
    results[status][type] = Hash.new(0)
    possible_values[type] = Set.new()
  end
end

demo_data.each do |entry|
  demo_types.each do |type|
    value = entry[type.to_sym].to_s.downcase
    value = 'no response' if value.empty?
    possible_values[type].add(value)
    logger.debug("Logging a #{type}/#{value}/#{entry[:status]}")

    if %w{Accepted Hold}.include?(entry[:status])
      results['accepts'][type][value] += 1
    elsif ['Rejected', ''].include?(entry[:status])
      results['rejects'][type][value] += 1
    else
      fail "Got unexpected status: '#{entry[:status]}' for #{entry}"
    end
    results['totals'][type][value] += 1
  end
end

demo_types.each do |type|
  possible = possible_values[type].to_a

  if ORDER_PREFS[type]
    extra_vals = possible - ORDER_PREFS[type]
    unless extra_vals.empty?
      logger.warn("Preferred field order is missing vals: #{extra_vals}")
    end
    missing_vals = ORDER_PREFS[type] - possible
    unless missing_vals.empty?
      logger.warn(
        'Did not see any entries with vals specified in order preference: '  +
        missing_vals.join(', ')
      )
    end
    fields = ORDER_PREFS[type] + extra_vals
  else
    fields = possible.sort
  end

  logger.info(type.upcase)
  logger.info("\tPossible values: #{fields.join(', ')}")
  %w{totals accepts rejects}.each do |status|
    name = status == 'totals' ? 'Submissions' : status
    logger.info("\t#{status.capitalize}: ")
    logger.info(
      "\t#{fields.map { |value| results[status][type][value] }.join(', ')}"
    )
  end
end
