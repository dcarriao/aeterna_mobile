require 'xcodeproj'

project_path = File.join(File.dirname(__FILE__), 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'Runner' }
extension_target = project.targets.find { |t| t.name == 'ShareExtension' }
created_target = false

unless extension_target
  puts 'Adding ShareExtension target to Runner.xcodeproj...'
  created_target = true

  # 1. Create target
  extension_target = project.new_target(:app_extension, 'ShareExtension', :ios, '14.0', nil, :swift)

  # 2. Add files group
  share_ext_group = project.main_group.find_subpath('ShareExtension', true)
  share_ext_group.set_source_tree('<group>')
  share_ext_group.set_path('ShareExtension')

  swift_file = share_ext_group.new_file('ShareViewController.swift')
  share_ext_group.new_file('Info.plist')
  extension_target.source_build_phase.add_file_reference(swift_file)
else
  puts 'ShareExtension target already exists — verifying embed + settings...'
end

# 3. Configure / refresh build settings
# SKIP_INSTALL=NO: com YES o exportArchive em CI pode omitir o .appex do IPA
extension_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'ShareExtension'
  config.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'br.com.aeternalegado.app.ShareExtension'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] =
    '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  config.build_settings['DEVELOPMENT_TEAM'] = 'R2KU8Q68QG'
  config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'ShareExtension/ShareExtension.entitlements'
  config.build_settings['PRODUCT_BUNDLE_PACKAGE_TYPE'] = 'XPC!'
  config.build_settings['SKIP_INSTALL'] = 'NO'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end

# 4. Embed in Runner (idempotente)
if main_target
  embed_extensions_phase = main_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
  unless embed_extensions_phase
    embed_extensions_phase = main_target.new_copy_files_build_phase('Embed App Extensions')
    embed_extensions_phase.symbol_dst_subfolder_spec = :plug_ins
    puts "Created 'Embed App Extensions' copy phase"
  end

  unless main_target.dependencies.any? { |d| d.target == extension_target }
    main_target.add_dependency(extension_target)
    puts 'Added Runner → ShareExtension dependency'
  end

  already_embedded = embed_extensions_phase.files.any? do |bf|
    ref = bf.file_ref
    ref && (ref.path == 'ShareExtension.appex' || ref == extension_target.product_reference)
  end
  unless already_embedded
    build_file = embed_extensions_phase.add_file_reference(extension_target.product_reference)
    build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
    puts 'Embedded ShareExtension.appex into Runner'
  else
    puts 'ShareExtension.appex already in Embed App Extensions'
  end

  # Embed App Extensions before Thin Binary
  embed_phase = main_target.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Embed App Extensions' }
  thin_phase = main_target.build_phases.find do |p|
    (p.respond_to?(:name) && p.name == 'Thin Binary') ||
      (p.respond_to?(:shell_script) && p.shell_script.to_s.include?('thin'))
  end
  if embed_phase && thin_phase
    main_target.build_phases.delete(embed_phase)
    thin_index = main_target.build_phases.index(thin_phase)
    main_target.build_phases.insert(thin_index, embed_phase) if thin_index
    puts "Moved 'Embed App Extensions' before 'Thin Binary'"
  end
end

project.save

# 5. Validate
project2 = Xcodeproj::Project.open(project_path)
ext = project2.targets.find { |t| t.name == 'ShareExtension' }
unless ext
  puts 'ERROR: ShareExtension target was not saved to project.pbxproj!'
  exit 1
end
cfg = ext.build_configurations.first
%w[SKIP_INSTALL PRODUCT_BUNDLE_PACKAGE_TYPE APPLICATION_EXTENSION_API_ONLY].each do |key|
  unless cfg.build_settings[key]
    puts "ERROR: Build setting #{key} is missing! Injection incomplete."
    exit 1
  end
end

runner = project2.targets.find { |t| t.name == 'Runner' }
embed = runner&.copy_files_build_phases&.find { |p| p.name == 'Embed App Extensions' }
embedded = embed&.files&.any? { |bf| bf.file_ref&.path == 'ShareExtension.appex' }
unless embedded
  puts 'ERROR: ShareExtension.appex not in Embed App Extensions after save!'
  exit 1
end

puts created_target ? 'ShareExtension target created and embedded!' : 'ShareExtension embed/settings refreshed!'
puts "  Bundle ID: #{cfg.build_settings['PRODUCT_BUNDLE_IDENTIFIER']}"
puts "  SKIP_INSTALL: #{cfg.build_settings['SKIP_INSTALL']}"
puts "  PACKAGE_TYPE: #{cfg.build_settings['PRODUCT_BUNDLE_PACKAGE_TYPE']}"
