#!/usr/bin/ruby

require 'digest'
require 'fileutils'
require 'json'
require 'shellwords'
require 'tempfile'

LEASE_SECONDS = 10 * 60
MAX_PAYLOAD_BYTES = 2 * 1024 * 1024
POCK_HOOK_LABEL = 'Pock Community: update Touch Bar activity'
# Read and check the exact bytes before running the script approved in Codex.
VERIFIED_HOOK = 'path, hash = ARGV.shift(2); code = File.binread(path); abort "Pock hook changed" unless Digest::SHA256.hexdigest(code) == hash; eval(code.force_encoding(Encoding::UTF_8), TOPLEVEL_BINDING, path, 1)'.freeze
VERIFIED_COMMAND = ['/usr/bin/env', '-u', 'RUBYOPT', '-u', 'RUBYLIB', '/usr/bin/ruby', '--disable=gems', '-rdigest', '-e', VERIFIED_HOOK].freeze
PROVIDERS = {
  'codex' => {
    title: 'Codex',
    running: %w[UserPromptSubmit PreModelRequest PreToolUse PostToolUse],
    finished: %w[Stop Interrupt SessionEnd PermissionRequest],
    notifications: []
  },
  'claude' => {
    title: 'Claude Code',
    running: %w[UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure ElicitationResult],
    finished: %w[Stop StopFailure SessionEnd PermissionRequest Elicitation],
    notifications: %w[permission_prompt idle_prompt elicitation_dialog elicitation_url_dialog]
  },
  'gemini' => {
    title: 'Gemini CLI',
    running: %w[BeforeAgent BeforeModel BeforeTool AfterTool],
    finished: %w[AfterAgent SessionEnd],
    notifications: %w[ToolPermission]
  }
}.freeze

TERMINAL_BUNDLES = {
  'Apple_Terminal' => 'com.apple.Terminal',
  'iTerm.app' => 'com.googlecode.iterm2',
  'WarpTerminal' => 'dev.warp.Warp-Stable',
  'ghostty' => 'com.mitchellh.ghostty',
  'vscode' => 'com.microsoft.VSCode',
  'WezTerm' => 'com.github.wez.wezterm'
}.freeze

def hook_config(provider_name, provider, verified: false)
  script = File.expand_path(__FILE__)
  timeout = provider_name == 'gemini' ? 2000 : 2
  arguments = ['/usr/bin/ruby', script, provider_name]
  if verified
    arguments = VERIFIED_COMMAND + [script, Digest::SHA256.file(script).hexdigest, provider_name]
  end
  command = { 'type' => 'command', 'command' => "exec #{Shellwords.join(arguments)}", 'timeout' => timeout }
  command['statusMessage'] = POCK_HOOK_LABEL if verified
  hooks = {}
  (provider[:running] + provider[:finished]).each { |event| hooks[event] = [{ 'hooks' => [command] }] }
  unless provider[:notifications].empty?
    hooks['Notification'] = [{ 'matcher' => provider[:notifications].join('|'), 'hooks' => [command] }]
  end
  hooks
end

def pock_hook_group?(group)
  return false unless group.is_a?(Hash) && group.keys == ['hooks'] && group['hooks'].is_a?(Array) &&
    group['hooks'].length == 1 && group['hooks'].first.is_a?(Hash)

  hook = group['hooks'].first
  return false unless hook['statusMessage'] == POCK_HOOK_LABEL && hook['command'].is_a?(String)

  words = Shellwords.split(hook['command'])
  words.first == 'exec' && words.last == 'codex' &&
    words.length >= 4 && File.basename(words[-3]) == 'pock-agent-activity.rb' &&
    words[-2].match?(/\A[0-9a-f]{64}\z/)
rescue ArgumentError
  false
end

def install_codex_hooks
  home = ENV['CODEX_HOME']
  home = File.join(Dir.home, '.codex') if home.nil? || home.empty?
  return unless File.directory?(home)
  home_info = File.stat(home)
  raise ArgumentError, 'Unsafe Codex home directory' unless home_info.uid == Process.uid && (home_info.mode & 0o022).zero?

  path = File.join(home, 'hooks.json')
  lock = File.join(home, '.pock-activity-hooks.lock')
  File.open(lock, File::WRONLY | File::CREAT | File::NOFOLLOW | File::NONBLOCK, 0o600) do |lock_file|
    raise ArgumentError, 'Unsafe Codex hooks lock' unless lock_file.stat.file? && lock_file.stat.uid == Process.uid
    lock_file.flock(File::LOCK_EX)
    original = begin
      File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
        raise ArgumentError, 'Unsafe Codex hooks file' unless file.stat.file? && file.stat.uid == Process.uid
        file.read(MAX_PAYLOAD_BYTES + 1)
      end
    rescue Errno::ENOENT
      nil
    end
    raise ArgumentError, 'Codex hooks file is too large' if original && original.bytesize > MAX_PAYLOAD_BYTES
    config = original ? JSON.parse(original) : {}
    raise ArgumentError, 'Expected a Codex hooks JSON object' unless config.is_a?(Hash)
    config['hooks'] = {} unless config.key?('hooks')
    raise ArgumentError, 'Expected a hooks object' unless config['hooks'].is_a?(Hash)

    updated = false
    hook_config('codex', PROVIDERS.fetch('codex'), verified: true).each do |event, addition|
      entries = config['hooks'].fetch(event, [])
      raise ArgumentError, "Invalid hook groups for #{event}" unless entries.is_a?(Array)
      managed = entries.select { |group| pock_hook_group?(group) }
      next if managed == addition

      config['hooks'][event] = (entries - managed) + addition
      updated = true
    end
    return unless updated

    Tempfile.create(['.pock-hooks-', '.json'], home) do |file|
      file.write(JSON.pretty_generate(config) + "\n")
      file.close
      File.rename(file.path, path)
    end
    puts 'Codex hooks installed. Review Pock Community in Codex Settings → Hooks.'
  end
end

def update_activity(provider, payload)
  return unless payload.is_a?(Hash)

  id = payload['session_id']
  return unless id.is_a?(String) && !id.empty? && id.length <= 200

  event = payload['hook_event_name']
  running = provider[:running].include?(event)
  finished = provider[:finished].include?(event) ||
    (event == 'Notification' && provider[:notifications].include?(payload['notification_type']))
  return unless running || finished

  # The generated hook uses exec so the parent is the provider, not a transient shell.
  pid = Process.ppid
  return if pid <= 1

  directory = ENV.fetch('POCK_AGENT_ACTIVITY_DIR') do
    File.join(Dir.home, 'Library', 'Application Support', 'Pock', 'AgentActivity')
  end
  FileUtils.mkdir_p(directory, mode: 0o700) if running
  info = File.lstat(directory)
  return unless info.directory? && info.uid == Process.uid && (info.mode & 0o077).zero?

  name = Digest::SHA256.hexdigest(JSON.generate([provider[:title], id, pid]))
  destination = File.join(directory, "#{name}.json")
  if finished
    File.unlink(destination)
    return
  end

  cwd = payload['cwd']
  project = File.basename(cwd).gsub(/[[:cntrl:]]/, ' ').strip if cwd.is_a?(String) && !cwd.include?("\0")
  short_id = id[-8, 8] || id
  title = if project && !project.empty? && project != '/'
    "#{project[0, 24]} · #{short_id}"
  else
    "Session #{short_id}"
  end
  record = { provider: provider[:title], id: id, title: title, pid: pid, expiresAt: Time.now.to_i + LEASE_SECONDS }
  bundle = TERMINAL_BUNDLES[ENV['TERM_PROGRAM']]
  record[:bundleIdentifier] = bundle if bundle
  if provider[:title] == 'Codex' && id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    record[:url] = "codex://threads/#{id}"
  end

  Tempfile.create(['.pock-agent-', '.tmp'], directory) do |file|
    file.write(JSON.generate(record))
    file.close
    File.rename(file.path, destination)
  end
rescue SystemCallError, ArgumentError
  # The hook is observational. A missing or unwritable registry must not stop the agent.
end

provider_name = ARGV.shift
provider = PROVIDERS[provider_name]
unless provider && (ARGV.empty? || ARGV == ['--config'] || (provider_name == 'codex' && ARGV == ['--install']))
  abort 'Usage: pock-agent-activity.rb {codex|claude|gemini} [--config] or codex --install'
end

if ARGV == ['--config']
  puts JSON.pretty_generate(hooks: hook_config(provider_name, provider, verified: provider_name == 'codex'))
elsif ARGV == ['--install']
  begin
    install_codex_hooks
  rescue SystemCallError, ArgumentError, JSON::ParserError => error
    abort "Could not install Pock Codex hooks: #{error.class}"
  end
else
  begin
    input = STDIN.read(MAX_PAYLOAD_BYTES + 1) || ''
    if input.bytesize <= MAX_PAYLOAD_BYTES
      update_activity(provider, JSON.parse(input))
    else
      IO.copy_stream(STDIN, File::NULL)
    end
  rescue JSON::ParserError
    # Keep the provider running if the hook payload is incomplete.
  ensure
    puts '{}' if provider_name == 'codex' || provider_name == 'gemini'
  end
end
