#!/usr/bin/env ruby
# coding: utf-8

require 'date'
require 'fileutils'
require 'tempfile'
require 'yaml'
require 'optparse'
require 'ostruct'
require './okdoc/oktags/lib/oktags'

options = OpenStruct.new
OptionParser.new do |opts|
  opts.banner = 'Usage: example.rb [options]'

  opts.on('-a', '--act-immediately', 'Move files right away') { |d| options.doit = d }
  opts.on('-i', '--interactive', 'Run in interactive mode') { |i| options.interactive = i }
  opts.on('-f', '--file FILE', 'Sort just one file') { |f| options.file = f; options.interactive = true }
  opts.on('-v', '--verbose', 'Run verbosely') { |v| options.verbose = v }
  opts.on('-y', '--yes', 'Auto approve') { |y| options.yes = y }
end.parse!

cli = nil
if options.interactive
  require 'highline'
  cli = HighLine.new
end

def translate(date)
  date
    .sub('März', 'Mar')
    .sub('Mai', 'May')
    .sub('Oktober', 'Oct')
    .sub('Dezember', 'Dec')
end

CONFIG_PATH = File.expand_path('../config.yml', __dir__)
config = {}
def load_config
  YAML.load(File.read(CONFIG_PATH))
end
config = load_config

FILENAME_PATTERN = Regexp.new(config['filename_pattern']).freeze

if options.file
  files = [options.file]
else
  files = Dir.glob(config['file_glob'], File::FNM_CASEFOLD).sort
end

actions = {}

def maybe_parse_date(date)
  { canonical: Date.parse(translate(date)), actual: date }
rescue
  nil
end

def act(pdf, file)
  txt = pdf.sub(/\.pdf$/i, '.txt')
  # create directory
  FileUtils.mkdir_p(File.dirname(file))
  # move files

  if File.exist?("#{file}.pdf")
    puts "Error, file '#{file}.pdf' already exists in target location."
    exit
  end

  `git add #{pdf} #{txt}`
  `git mv #{pdf} #{file}.pdf`
  `git mv #{txt} #{file}.txt`
end

files.each_with_index do |pdf, index|
  final = nil

  # extract the `Identifier` as it is used as an override
  # identifier = `exiftool -s -S -Identifier #{pdf}`.chomp
  # skip this document if it is already in the correct location
  # next if identifier + '.pdf' == pdf

  txt = pdf.sub(/\.pdf$/i, '.txt')
  # skip pdf files which don't have a associated txt file yet
  next unless File.exist?(txt)

  content = File.read(txt)

  good = false
  until good
    good = true
    # puts identifier

    location = nil

    basename = File.basename(pdf, '.pdf')
    new_name = basename

    # if the filename does not match the expected pattern try to
    # extract a meaningful date and rename the file preserving the
    # original filename
    unless new_name.match(FILENAME_PATTERN)
      dates = config['date_patterns'].map { |pattern| content.match(Regexp.new(pattern)).to_a.first }
      dates = dates.compact.sort_by { |date| content.index(date) }
      dates = dates.map { |date| maybe_parse_date(date) }.compact
      date = dates.first && dates.first[:canonical]
      new_name = date.to_s + '_' + basename if date
    end

    # score the locations by the number of matching patterns and the
    # specificity of the location (i.e. directory depth)
    scoring = Hash.new { |h, k| h[k] = 0 }
    matched = []
    config['rules'].each_with_index do |rule, index|
      patterns = rule['patterns']
      next unless patterns
      patterns.each do |pattern|
        if content.match(Regexp.new(pattern.to_s))
          matched << "#{pattern} -> #{rule['location']}"
          scoring[index] += 1
        end
      end
    end

    # just some debugging output
    # scoring.sort_by { |s| - (s.last * 100 + config['rules'][s.first]['location'].split('/').size) }.each do |index, score|
    #   puts "#{score} #{config['rules'][index]['location']}"
    # end

    # find the winner, determine the new location
    highest = scoring.values.max
    candidates = scoring.filter { |_, v| v == highest }.keys
    winner = candidates.sort_by { |c| config['rules'][c]['location'].split('/').size }.first
    if winner
      location = config['rules'][winner]['location']
    else
      location = config['default']
    end

    # compile the results
    data = {
      'matched' => matched,
      'filename' => new_name,
      'path' => location
    }

    file = File.join(data['path'], data['filename'])
    if file + '.pdf' == pdf
      # continue if it is already in the right location
      final = data
    else
      if options.interactive
        # become interactive, show the document
        pid = spawn("evince #{pdf}")

        # show the calculated results
        yaml = YAML.dump(data)
        puts content
        puts '-' * 60
        puts "# [#{index}/#{files.count}] #{pdf}"
        puts yaml
        puts

        sleep 0.25 # That's just enough time for evince to show.
        # Don't focus on the new evince window, but the input prompt of `sort.
        `./okdoc/i3_focus_other.sh`

        # ask what to do
        action = cli.ask('(A)ccept/(r)etry/(d)elete/(t)ag/e(x)it? ') do |q|
          q.default = 'A'
          q.validate = /^[Ardtx]$/
        end

        case action
        when 'A'
          file = File.join(data['path'], data['filename'])
          act(pdf, file)
        when 's'
          puts 'TODO: skip'
        # when 'e'
        #   # edit
        #   Tempfile.open(['document', '.yml']) do |f|
        #     f.write(yaml)
        #     f.close
        #     # blocks
        #     %x[emacs -nw #{f.path}]
        #     final = YAML.load(File.read(f.path))
        #   end
        when 'r'
          # TODO: reload config
          config = load_config
          good = false
        when 'd'
          good = true
          File.delete(pdf)
          File.delete(txt)
        when 't'
          OK::Tags.list_pretty_tags('**/*pdf')
          tags, pdf = OK::Tags.read_and_add_tags_for(pdf)
          file = File.join(data['path'], File.basename(pdf, '.pdf'))
          OK::Tags.add_tags_to_file(tags, txt)

          act(pdf, file)
        when 'x'
          # tear down
          Process.kill('HUP', pid)
          Process.wait(pid)
          exit
        # when 't'
        #   puts content
        #   good = false
        end

        # tear down
        Process.kill('HUP', pid)
        Process.wait(pid)

      else
        final = data
      end
    end
  end

  next unless final

  file = File.join(final['path'], final['filename'])
  # plant the override if the result has been changed manually
  # `exiftool -Identifier=#{file} #{pdf}` if data != final

  # do nothing if the file is already in the correct location
  next if (file + '.pdf') == pdf

  if options.doit
    act(pdf, file)
  else
    actions[pdf] = file
  end
end

def apply
  cli.ask('Apply? (yes/NO) ') == 'yes'
end

unless actions.empty? || options.doit
  puts YAML.dump(actions)
  if options.yes || apply
    actions.each do |pdf, file|
      act(pdf, file)
    end
    # delete empty directories
    `find . -type d -empty -delete`
    `mkdir -p Inbox`
    # TODO: find a way to suppress creating these
    `find . -type f -name \*.pdf_original -delete`
  end
else
  puts
  puts '  Nice! Everything is already in its place.'
  puts
end
