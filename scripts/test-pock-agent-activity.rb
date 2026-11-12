#!/usr/bin/ruby

require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

def assert(condition, message)
  abort message unless condition
end

def invoke(config, event, env, payload)
  hook = config.fetch(event).first.fetch('hooks').first.fetch('command')
  stdout, stderr, status = Open3.capture3(env, '/bin/sh', '-c', hook, stdin_data: payload)
  assert(status.success? && stderr.empty?, "Hook #{event} failed: #{stderr}")
  stdout
end

def activity_records(directory)
  Dir.glob(File.join(directory, '*.json')).map { |path| JSON.parse(File.read(path)) }
end

Dir.mktmpdir("pock agent's fixtures") do |directory|
  bridge = File.join(directory, 'pock-agent-activity.rb')
  FileUtils.cp(File.join(__dir__, 'pock-agent-activity.rb'), bridge)
  registry = File.join(directory, 'registry')
  env = { 'POCK_AGENT_ACTIVITY_DIR' => registry, 'TERM_PROGRAM' => 'Apple_Terminal' }
  id = '01234567-89ab-cdef-0123-456789abcdef'
  fixture = { 'session_id' => id, 'cwd' => '/sample/Example', 'prompt' => 'private fixture text' }
  providers = {
    'codex' => ['Codex', 'UserPromptSubmit', 'PermissionRequest', 'PreModelRequest', 'Interrupt'],
    'claude' => ['Claude Code', 'UserPromptSubmit', 'PermissionRequest', 'PostToolUse', 'StopFailure'],
    'gemini' => ['Gemini CLI', 'BeforeAgent', 'Notification', 'AfterTool', 'AfterAgent']
  }

  providers.each do |name, (label, start, wait, resume, stop)|
    output, status = Open3.capture2('/usr/bin/ruby', bridge, name, '--config')
    assert(status.success?, "Could not generate hook config for #{name}")
    config = JSON.parse(output).fetch('hooks')
    expected_stdout = name == 'claude' ? '' : "{}\n"

    run = ->(event, session_id = id) do
      payload = fixture.merge('session_id' => session_id, 'hook_event_name' => event, 'notification_type' => 'ToolPermission')
      assert(invoke(config, event, env, JSON.generate(payload)) == expected_stdout, "Unexpected #{name} hook output")
    end

    run.call(start)
    records = activity_records(registry)
    assert(records.length == 1, "Expected one record after starting #{name}")
    record = records.first
    assert(record['provider'] == label && record['id'] == id, "Invalid identity for #{name}")
    assert(record['title'] == 'Example · 89abcdef' && record['pid'] == Process.pid, "Invalid display data for #{name}")
    assert(record['bundleIdentifier'] == 'com.apple.Terminal', "Invalid terminal destination for #{name}")
    assert(record['expiresAt'].between?(Time.now.to_i + 595, Time.now.to_i + 600), "Invalid lease for #{name}")
    assert(record['url'] == ("codex://threads/#{id}" if name == 'codex'), "Invalid chat link for #{name}")
    assert(!JSON.generate(record).include?('private fixture text'), "Hook leaked prompt content for #{name}")

    other_id = '11234567-89ab-cdef-0123-456789abcdee'
    run.call(start, other_id)
    run.call(wait)
    assert(activity_records(registry).map { |activity| activity['id'] } == [other_id], "Waiting affected another #{name} session")
    run.call('SessionEnd', other_id)
    assert(activity_records(registry).empty?, "Waiting #{name} still appears active")
    run.call(resume)
    assert(activity_records(registry).length == 1, "Resumed #{name} did not reappear")
    run.call(stop)
    run.call('SessionEnd')
    assert(activity_records(registry).empty?, "Stopped #{name} still appears active")

    invoke(config, start, env, '{invalid JSON')
    invoke(config, start, env, ' ' * (2 * 1024 * 1024 + 2))
    assert(activity_records(registry).empty?, "Invalid #{name} payload created activity")
  end

  codex_home = File.join(directory, 'Codex configuration')
  Dir.mkdir(codex_home, 0o700)
  config_path = File.join(codex_home, 'hooks.json')
  existing = { 'hooks' => { 'Stop' => [{ 'hooks' => [{ 'type' => 'command', 'command' => 'true' }] }] } }
  File.write(config_path, JSON.generate(existing))
  install = ['/usr/bin/ruby', bridge, 'codex', '--install']
  install_env = env.merge('CODEX_HOME' => codex_home)
  _, _, status = Open3.capture3(install_env, *install)
  assert(status.success?, 'Could not merge Codex hooks')
  merged = File.read(config_path)
  config = JSON.parse(merged).fetch('hooks')
  assert(config['Stop'].first == existing['hooks']['Stop'].first, 'Install changed an existing hook')
  assert((File.stat(config_path).mode & 0o077).zero?, 'Codex hook config is readable by other users')
  _, _, status = Open3.capture3(install_env, *install)
  assert(status.success? && File.read(config_path) == merged, 'Repeated install changed Codex hooks')
  payload = JSON.generate(fixture.merge('hook_event_name' => 'UserPromptSubmit'))
  invoke(config, 'UserPromptSubmit', install_env, payload)
  assert(activity_records(registry).length == 1, 'The installed hook did not publish activity')
  File.open(bridge, 'a') { |file| file.puts("\nraise 'This script has changed'") }
  command = config.fetch('UserPromptSubmit').first.fetch('hooks').first.fetch('command')
  _, error, status = Open3.capture3(install_env, '/bin/sh', '-c', command, stdin_data: payload)
  assert(!status.success? && error.include?('Pock hook changed'), 'A changed script bypassed the installed checksum')
  File.unlink(config_path)
  File.symlink(bridge, config_path)
  _, _, status = Open3.capture3(install_env, *install)
  assert(!status.success? && File.symlink?(config_path), 'Install followed a symlink in Codex settings')
end

puts 'Agent activity hook fixtures passed.'
