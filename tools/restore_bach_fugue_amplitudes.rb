#!/usr/bin/env ruby
# Restore note amplitudes lost when the MusicKit BachFugue score was imported.

require "base64"
require "json"

source_path, score_path = ARGV
abort "usage: #{$PROGRAM_NAME} MusicKit-BachFugue.score ScoreMaker.score" unless score_path

source = File.read(source_path)
source_time = 0.0
events = Hash.new { |hash, key| hash[key] = [] }
source.each_line do |line|
  source_time = Regexp.last_match(1).to_f if line =~ /^t\s+([0-9.]+);/
  next unless line =~ /^p([1-6]) \((?:noteOn \d+|[0-9.]+ \d+)\).*?amp:([0-9.]+),.*?freq:([0-9.]+);/

  voice = Regexp.last_match(1).to_i
  amplitude = Regexp.last_match(2).to_f
  frequency = Regexp.last_match(3).to_f
  pitch = (69 + 12 * Math.log2(frequency / 440.0)).round
  events[[voice, pitch]] << [source_time, amplitude]
end

score = File.read(score_path)
match = score.match(%r{/\* ScoreMaker Structure V2\n(.*?)\n\*/}m)
abort "ScoreMaker Structure V2 metadata not found" unless match
structure = JSON.parse(Base64.decode64(match[1].delete("\n")))
notes = structure.fetch("noteDetails")

amplitudes = notes.map do |note|
  candidates = events[[note.fetch("voice"), note.fetch("pitch")]]
  abort "No source amplitude for voice #{note["voice"]}, pitch #{note["pitch"]}" if candidates.empty?

  source_note_time = note.fetch("startTick").to_f / 240.0
  candidates.min_by { |time, _amplitude| (time - source_note_time).abs }[1]
end

notes.zip(amplitudes).each do |note, amplitude|
  note["velocity"] = [[(amplitude * 127).round, 1].max, 127].min
end

encoded = Base64.strict_encode64(JSON.generate(structure)).scan(/.{1,76}/).join("\n")
score.sub!(match[0], "/* ScoreMaker Structure V2\n#{encoded}\n*/")

index = 0
score.gsub!(/^(Harpsichord \([^\n;]+\) keyNum:[^;\n]+)(?: amp:[0-9.]+)?;/) do
  amplitude = amplitudes.fetch(index)
  index += 1
  format("%s amp:%.5f;", Regexp.last_match(1), amplitude)
end
abort "Expected #{notes.length} note events, updated #{index}" unless index == notes.length

File.write(score_path, score)
puts "Restored #{index} amplitudes (#{amplitudes.uniq.length} distinct values)."
