#!/usr/bin/env ruby
# 把 DSHWebViewController 挂到跟 SceneDelegate 同一个 target 上
require 'xcodeproj'

proj = Xcodeproj::Project.open('iSH.xcodeproj')

target = proj.targets.find do |t|
  t.source_build_phase.files_references.any? { |f| f.path.to_s.end_with?('SceneDelegate.m') }
end
abort('没找到包含 SceneDelegate.m 的 target') unless target
puts "target = #{target.name}"

group = proj.main_group['app'] || proj.main_group.new_group('app', 'app')

%w[app/DSHWebViewController.m app/DSHWebViewController.h].each do |rel|
  path = File.expand_path(rel)
  if group.files.any? { |f| f.path.to_s.end_with?(File.basename(rel)) }
    puts "skip #{rel}"
    next
  end
  ref = group.new_reference(path)
  if rel.end_with?('.m')
    target.source_build_phase.add_file_reference(ref)
    puts "added to build phase: #{rel}"
  else
    puts "added header: #{rel}"
  end
end

proj.save
puts 'project saved'
