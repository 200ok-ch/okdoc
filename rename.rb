#!/usr/bin/env ruby
# coding: utf-8

Dir.glob('**/*.pdf').each do |file|
  renamed = file.gsub(%r{[^A-Za-z0-9._\-\/äüöÄÜÖ]}, '_')
  puts 'mv "%s" "%s"' % [file, renamed] if renamed != file
end
