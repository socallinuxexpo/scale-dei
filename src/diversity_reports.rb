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
].freeze

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
  # amazingly, we don't always get all of them ever year, so
  # we list them all so the CSV lines up
  'ethnicity' => [
    'asian',
    'black / african american',
    'latino / hispanic',
    'native american / american indian',
    'native hawaiian or pacific islander',
    'other/unknown',
    'prefer not to say',
    'two or more',
    'white / caucasian',
    'no response',
  ],
  'gender' => [
    'male',
    'female',
    'other',
    'no response',
    'prefer not to say',
    'non-binary',
  ],
  'household income' => [
    'below $10k / year',
    '$10k-$50k / year',
    '$50k-$100k / year',
    '$100k-$200k / year',
    '$200k-$500k / year',
    'more than $500k / year',
    'prefer not to say',
    'no response',
  ],
}.freeze

def parse_cfp_data(
  demo_data, results, possible_values, global_totals, demo_types, logger
)
  demo_data.each do |entry|
    global_totals['submissions'] += 1
    global_totals['accepts'] += 1 if %w{Accepted Hold}.include?(entry[:status])
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
        raise "Got unexpected status: '#{entry[:status]}' for #{entry}"
      end
      results['totals'][type][value] += 1
    end
  end
end

# not much to parse, since it's basically totals, but we need
# to build possible_values and global_totals
def parse_reg_data(
  demo_data, totals_data, results, demo_types, possible_values, global_totals,
  logger
)
  global_totals['total'] = 0
  totals_data.each do |entry|
    global_totals['total'] += entry[1]
  end

  demo_data.each do |entry|
    type = entry[1].downcase
    value = entry[3].downcase
    count = entry[4]
    logger.debug("Logging a #{type}/#{value}")
    unless demo_types.include?(type)
      raise "Unrecognized demographic type #{type}"
    end

    possible_values[type] ||= Set.new
    possible_values[type].add(value)
    global_totals[type] ||= 0
    global_totals[type] += count
    results[type] ||= {}
    results[type][value] = count
  end
end

def get_calculated_cfp_data(data, type, possible_values, global_totals, logger)
  results = {}
  %w{accept_rate submission_pct accept_pct}.each do |k|
    results[k] = {}
  end
  possible_values.each do |value|
    logger.debug("Crunching numbers for #{type}/#{value}")

    # For each value, calculate...

    # Acceptance rate for this value (i.e. x% of submissions by women
    # were accepted)
    results['accept_rate'][value] = (
        (data['accepts'][type][value].to_f / data['totals'][type][value]) * 100
      ).round(1)

    # % Submissions of total (i.e. of all submissions how many were from
    # non-binary folks)
    results['submission_pct'][value] = (
        (data['totals'][type][value].to_f / global_totals['submissions']) * 100
      ).round(1)

    # % Acceptabes of total (i.e. of all accepted submissions, how many
    # were from men)
    results['accept_pct'][value] = (
        (data['accepts'][type][value].to_f / global_totals['accepts']) * 100
      ).round(1)
  end
  results
end

def gen_reg_output(type, static_fields, results, global_totals, logger, options)
  fields = []
  values = []

  # first, simple fields
  fields += static_fields
  values += static_fields.map do |field|
    # fill in 'no response' which isn't an recorded directly
    # in reg
    if field == 'no response'
      num = global_totals['total'] - global_totals[type]
      results[type][field] = num
    end
    results[type][field]
  end

  # then percentages of attendees
  fields += static_fields.map { |field| "pct:#{field}" }
  values += static_fields.map do |field|
    num = results[type][field].to_f
    ((num / global_totals['total']) * 100).round(1)
  end

  # then percentages of those who replied to this question
  modified_fields = static_fields.reject { |x| x == 'no response' }
  fields += modified_fields.map { |field| "pct_replies:#{field}" }
  values += modified_fields.map do |field|
    num = results[type][field].to_f
    ((num / global_totals[type]) * 100).round(1)
  end

  case options[:output_type]
  when 'csv'
    logger.info(type.upcase)
    logger.info("# #{fields.join(', ')}")
    logger.info(values.join(', ') + "\n")
  when 'simple'
    logger.error('not implemented yet')
  end
end

def gen_cfp_output(
  type, static_fields, possible, results, global_totals, logger, options
)
  fields = []
  values = []

  # now fill values with those values
  %w{totals accepts}.each do |status|
    fields += static_fields.map { |value| "#{status}:#{value}" }
    values += static_fields.map { |value| results[status][type][value] }
  end

  # Now add global totals
  fields += ['total submissions', 'total accepts']
  values += [global_totals['submissions'], global_totals['accepts']]

  # Now add calculated fields
  calculated_data = get_calculated_cfp_data(
    results, type, possible, global_totals, logger
  )
  %w{accept_rate submission_pct accept_pct}.each do |calc|
    static_fields.each do |value|
      fields << "#{calc}:#{value}"
      values << calculated_data[calc][value]
    end
  end

  case options[:output_type]
  when 'csv'
    logger.info(type.upcase)
    logger.info("# #{fields.join(', ')}")
    logger.info(values.join(', ') + "\n")
  when 'simple'
    logger.info("\tPossible values: #{static_fields.join(', ')}")
    %w{totals accepts rejects}.each do |status|
      name = status == 'totals' ? 'Submissions' : status
      logger.info("\t#{name.capitalize}: ")
      logger.info(
        "\t#{static_fields.map do |value|
          results[status][type][value]
        end.join(', ')}",
      )
    end
  end
end

def munge_fields_for_reg!(preferred, type)
  return unless type == 'age'

  preferred.map! do |x|
    x == '55+' ? '55 and up' : x.gsub('-', ' to ')
  end
end

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
options = { :output_type => 'csv', :input_type => 'cfp' }
OptionParser.new do |opts|
  opts.on('-l', '--log-level LEVEL', 'Enable debug') do |level|
    logger.level = level.to_sym
  end

  opts.on(
    '-o',
    '--output-type TYPE',
    %w{csv simple},
    'Output format. Default is "csv" and includes all calculated fields. ' +
    'You can "simple" for a human-readable printout of only the parsed data.',
  ) do |t|
    options[:output_type] = t
  end

  opts.on(
    '-i',
    '--input-type TYPE',
    %w{cfp reg},
    'The input type. Default is "cfp" - what the CFP system exports. ' +
    'The "reg" option is for what we get from reg.',
  ) do |t|
    options[:input_type] = t
  end

  opts.on(
    '-t',
    '--demo-type TYPE[,TYPE...]',
    Array,
    'Limit to demographic type TYPE. Possibilities: ' +
      ALL_DEMO_TYPES.join(', '),
  ) do |t|
    demo_types = t
  end

  opts.on(
    '-T',
    '--totals-csv FILE',
    'When in reg mode, this is the totals information',
  ) do |f|
    options[:totals_csv] = f
  end
end.parse!

filename = ARGV.pop
raise 'Need to specify a file' unless filename

if options[:input_type] == 'reg' && !options[:totals_csv]
  raise 'Need to specify -T'
end

demo_data = CSV.table(filename)

results = {}
possible_values = {}
if options[:input_type] == 'cfp'
  global_totals = { 'submissions' => 0, 'accepts' => 0 }
  %w{accepts rejects totals}.each do |status|
    results[status] = {}
    demo_types.each do |type|
      results[status][type] = Hash.new(0)
      possible_values[type] = Set.new
    end
  end

  parse_cfp_data(
    demo_data, results, possible_values, global_totals, demo_types, logger
  )
else
  global_totals = {}
  totals_data = CSV.table(options[:totals_csv])
  parse_reg_data(
    demo_data, totals_data, results, demo_types, possible_values, global_totals,
    logger
  )
end

demo_types.each do |type|
  # First, see if we have a static order of the fields
  possible = possible_values[type].to_a
  if ORDER_PREFS[type]
    preferred = ORDER_PREFS[type]
    munge_fields_for_reg!(preferred, type) if options[:input_type] == 'reg'
    logger.debug("possible is: #{possible.join(', ')}")
    logger.debug("prefs is is: #{preferred.join(', ')}")
    extra_vals = possible - ORDER_PREFS[type]
    unless extra_vals.empty?
      logger.warn("Preferred field order is missing vals: #{extra_vals}")
    end
    missing_vals = ORDER_PREFS[type] - possible
    unless missing_vals.empty? || missing_vals == ['no response']
      logger.warn(
        'Did not see any entries with vals specified in order preference: ' +
        missing_vals.join(', '),
      )
    end
    static_fields = ORDER_PREFS[type] + extra_vals
  else
    static_fields = possible.sort
    static_fields.delete('no response')
    static_fields << 'no response'
  end

  # Then generate any calculated data and output it all
  case options[:input_type]
  when 'cfp'
    gen_cfp_output(
      type, static_fields, possible, results, global_totals, logger, options
    )
  when 'reg'
    gen_reg_output(
      type, static_fields, results, global_totals, logger, options
    )
  end
end
