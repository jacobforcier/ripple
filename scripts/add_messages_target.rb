#!/usr/bin/env ruby
# Adds the "Ripple Messages" iMessage extension target to Ripple.xcodeproj.
# Idempotent: bails if the target already exists.
require 'xcodeproj'

PROJ = File.expand_path('../Ripple/Ripple.xcodeproj', __dir__)
NAME = 'Ripple Messages'
BUNDLE_ID = 'com.ripple.sharewithripple.Messages'
TEAM = '856ZD9L98G'
HOST = 'Ripple (iOS)'

project = Xcodeproj::Project.open(PROJ)

if project.targets.any? { |t| t.name == NAME }
  puts "→ target '#{NAME}' already exists; nothing to do."
  exit 0
end

# Group + file references (folder already on disk as "Ripple Messages/")
group = project.main_group.new_group(NAME, NAME)
swift = %w[MessagesViewController.swift ComposerView.swift
           RippleMessageCard.swift RippleLinkService.swift]
swift_refs = swift.map { |f| group.new_file(f) }
group.new_file('Info.plist')
group.new_file('RippleMessages.entitlements')

# The target itself → override to the Messages product type
target = project.new_target(:app_extension, NAME, :ios, '16.0')
target.product_type = 'com.apple.product-type.app-extension.messages'

settings = {
  'PRODUCT_BUNDLE_IDENTIFIER'  => BUNDLE_ID,
  'PRODUCT_NAME'               => '$(TARGET_NAME)',
  'INFOPLIST_FILE'             => "#{NAME}/Info.plist",
  'CODE_SIGN_ENTITLEMENTS'     => "#{NAME}/RippleMessages.entitlements",
  'GENERATE_INFOPLIST_FILE'    => 'NO',
  'DEVELOPMENT_TEAM'           => TEAM,
  'CODE_SIGN_STYLE'            => 'Automatic',
  'SWIFT_VERSION'              => '5.0',
  'MARKETING_VERSION'          => '1.0',
  'CURRENT_PROJECT_VERSION'    => '1',
  'IPHONEOS_DEPLOYMENT_TARGET' => '16.0',
  'TARGETED_DEVICE_FAMILY'     => '1,2',
  'SKIP_INSTALL'               => 'YES',
  'LD_RUNPATH_SEARCH_PATHS'    => ['$(inherited)', '@executable_path/Frameworks',
                                   '@executable_path/../../Frameworks'],
}
target.build_configurations.each { |c| c.build_settings.merge!(settings) }

# Compile sources + Messages.framework
target.add_file_references(swift_refs)
target.add_system_framework('Messages')

# Embed into the host app's existing PlugIns copy-files phase + dependency
host = project.targets.find { |t| t.name == HOST } or abort "host target #{HOST} not found"
host.add_dependency(target)
embed = host.copy_files_build_phases.find { |ph| ph.dst_subfolder_spec.to_s == '13' }
abort 'no PlugIns embed phase on host' unless embed
bf = embed.add_file_reference(target.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "✓ added target '#{NAME}' (#{BUNDLE_ID}), #{swift_refs.size} sources, embedded in #{HOST}"
