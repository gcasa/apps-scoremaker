#!/usr/bin/env ruby

require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "ScoreMaker.xcodeproj")

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastUpgradeCheck"] = "2630"
project.root_object.attributes["ORGANIZATIONNAME"] = "Black Lotus"

sources_group = project.main_group.new_group("Sources", "src")
resources_group = project.main_group.new_group("Resources", "Resources")
tests_group = project.main_group.new_group("Tests", "tests")
support_group = project.main_group.new_group("Supporting Files")

source_files = Dir[File.join(ROOT, "src", "*.{m,h}")].sort.to_h do |path|
  [File.basename(path), sources_group.new_file(File.basename(path))]
end

resource_names = %w[
  ScoreMakerAppIcon.icns
  ScoreMakerDocumentIcon.icns
  treble_clef.png
  bass_clef.png
]
resource_files = resource_names.map { |name| resources_group.new_file(name) }
test_file = tests_group.new_file("ScorefileCompatibilityTests.m")
xcode_test_file = tests_group.new_file("ScoreMakerXcodeTests.m")
info_plist = support_group.new_file("Info.plist")
entitlements = support_group.new_file("ScoreMaker.entitlements")

app = project.new_target(:application, "ScoreMaker", :osx, "12.0")
app.add_file_references(source_files.values.select { |ref| ref.path.end_with?(".m") })
resource_files.each { |resource| app.resources_build_phase.add_file_reference(resource) }

%w[Cocoa AVFoundation AudioToolbox CoreAudioKit CoreMIDI].each do |name|
  app.add_system_framework(name)
end

app.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.blacklotus.ScoreMaker"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["INFOPLIST_FILE"] = "Info.plist"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["CODE_SIGN_ENTITLEMENTS"] = "ScoreMaker.entitlements"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CLANG_ENABLE_OBJC_ARC"] = "NO"
  settings["CLANG_ENABLE_MODULES"] = "YES"
  settings["CLANG_ENABLE_OBJC_WEAK"] = "YES"
  settings["ENABLE_HARDENED_RUNTIME"] = "YES"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
  settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks"
end

test_sources = %w[
  RealtimeDSP.m ScorefileParser.m ScoreProjectSerializer.m MusicXMLParser.m
  MidiParser.m ScoreModel.m MusicPlatformModel.m MusicEngine.m NotationModel.m
  EngravingLayout.m
].map { |name| source_files.fetch(name) }

compatibility_tests = project.new_target(
  :command_line_tool,
  "ScoreMakerCompatibilityTests",
  :osx,
  "12.0"
)
compatibility_tests.add_file_references([test_file] + test_sources)
%w[Foundation AppKit AVFoundation AudioToolbox CoreAudioKit].each do |name|
  compatibility_tests.add_system_framework(name)
end

compatibility_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.blacklotus.ScoreMaker.CompatibilityTests"
  settings["CLANG_ENABLE_OBJC_ARC"] = "NO"
  settings["CLANG_ENABLE_MODULES"] = "YES"
  settings["HEADER_SEARCH_PATHS"] = "$(SRCROOT)/src"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
end

project.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["CLANG_WARN_BOOL_CONVERSION"] = "YES"
  settings["CLANG_WARN_CONSTANT_CONVERSION"] = "YES"
  settings["CLANG_WARN_UNREACHABLE_CODE"] = "YES"
  settings["COPY_PHASE_STRIP"] = "NO"
  settings["SDKROOT"] = "macosx"
end

app_scheme = Xcodeproj::XCScheme.new
app_scheme.add_build_target(app)
app_scheme.set_launch_target(app)
app_scheme.save_as(PROJECT_PATH, "ScoreMaker", true)

tests_scheme = Xcodeproj::XCScheme.new
tests_scheme.add_build_target(compatibility_tests)
tests_scheme.set_launch_target(compatibility_tests)

xcode_tests = project.new_target(:unit_test_bundle, "ScoreMakerTests", :osx, "14.0")
xcode_tests.add_file_references([xcode_test_file])
xcode_tests.add_dependency(compatibility_tests)
xcode_tests.add_system_framework("XCTest")
xcode_tests.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.blacklotus.ScoreMaker.Tests"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["CLANG_ENABLE_OBJC_ARC"] = "NO"
  settings["GCC_PREPROCESSOR_DEFINITIONS"] = ['PROJECT_DIR=@\"$(PROJECT_DIR)\"']
  settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
end
tests_scheme.add_build_target(xcode_tests)
tests_scheme.add_test_target(xcode_tests)
project.save
tests_scheme.save_as(PROJECT_PATH, "ScoreMakerCompatibilityTests", true)

puts "Generated #{PROJECT_PATH}"
