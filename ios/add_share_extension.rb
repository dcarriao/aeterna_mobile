require 'xcodeproj'

project_path = File.join(File.dirname(__FILE__), 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == 'ShareExtension' }
  puts 'ShareExtension target already exists.'
  exit 0
end

puts 'Adding ShareExtension target to Runner.xcodeproj...'

# 1. Create target
extension_target = project.new_target(:app_extension, 'ShareExtension', :ios, '14.0', nil, :swift)

# 2. Add files group
share_ext_group = project.main_group.find_subpath('ShareExtension', true)
share_ext_group.set_source_tree('<group>')
share_ext_group.set_path('ShareExtension')

# Add files to group and compile sources build phase
swift_file = share_ext_group.new_file('ShareViewController.swift')
plist_file = share_ext_group.new_file('Info.plist')

extension_target.source_build_phase.add_file_reference(swift_file)

# 3. Configure build settings
extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'ShareExtension'
  config.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'br.com.aeternalegado.app.ShareExtension'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  config.build_settings['PRODUCT_BUNDLE_PACKAGE_TYPE'] = 'XPC!'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['DEVELOPMENT_TEAM'] = 'R2KU8Q68QG'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
end

# 3b. Add required system frameworks (Social.framework for SLComposeServiceViewController)
social_framework = project.frameworks_group.new_file('Social.framework')
extension_target.frameworks_build_phase.add_file_reference(social_framework)

# 4. Embed in main app's build phase
main_target = project.targets.find { |t| t.name == 'Runner' }
if main_target
  embed_extensions_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
  unless embed_extensions_phase
    embed_extensions_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
    embed_extensions_phase.symbol_dst_subfolder_spec = :plug_ins
  end
  
  # Link target build dependency
  main_target.add_dependency(extension_target)
  
  # Embed the compiled appex binary
  build_file = embed_extensions_phase.add_file_reference(extension_target.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

  # 5. Reorder build phases to avoid dependency cycles (Embed App Extensions before Thin Binary)
  embed_phase = main_target.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Embed App Extensions' }
  thin_phase = main_target.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' || (p.respond_to?(:shell_script) && p.shell_script&.include?('thin')) }
  if embed_phase && thin_phase
    main_target.build_phases.delete(embed_phase)
    thin_index = main_target.build_phases.index(thin_phase)
    main_target.build_phases.insert(thin_index, embed_phase)
    puts "Successfully moved 'Embed App Extensions' before 'Thin Binary' in build phases!"
  end
end

project.save
puts 'ShareExtension target successfully configured and embedded!'
