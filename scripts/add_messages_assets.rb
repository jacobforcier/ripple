#!/usr/bin/env ruby
# Wires Ripple Messages/Assets.xcassets into the Ripple Messages target and sets
# the iMessage app-icon name. Idempotent.
require 'xcodeproj'

PROJ = File.expand_path('../Ripple/Ripple.xcodeproj', __dir__)
NAME = 'Ripple Messages'

project = Xcodeproj::Project.open(PROJ)
target = project.targets.find { |t| t.name == NAME } or abort "no #{NAME} target"
group = project.main_group.groups.find { |g| g.display_name == NAME } or abort 'no group'

unless group.files.any? { |f| f.path == 'Assets.xcassets' }
  ref = group.new_file('Assets.xcassets')
  target.add_resources([ref])
  puts '✓ added Assets.xcassets to resources'
end

target.build_configurations.each do |c|
  c.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'iMessage App Icon'
end

project.save
puts '✓ set ASSETCATALOG_COMPILER_APPICON_NAME = iMessage App Icon'
