#!/usr/bin/env ruby
# coding: utf-8

Dir.glob('**/*.pdf').each do |file|
  # strip filename and replace unwanted characters
  renamed = "#{File.dirname(file)}/#{File.basename(file, ".pdf").strip.gsub(%r{[^A-Za-z0-9.,_\[\]\-\/äüöÄÜÖ]}, '_')}.pdf"
  puts 'mv "%s" "%s"' % [file, renamed] if renamed != file
end
