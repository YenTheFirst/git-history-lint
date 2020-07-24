#!/usr/bin/env ruby

require 'git'
dir, first, last = *ARGV[0,3]

g = Git.open(dir)

overall_stats = g.diff(first, last).stats
per_file_stats = {}
per_commit_stats = []
first_commit = {}
history = g.log(nil).between(first, last).reverse_each
history.each do |commit|
  commit.diff_parent.stats[:files].each do |path, stats|
    per_file_stats[path] ||= {}
    first_commit[path] ||= commit.sha
    per_file_stats[path][commit.sha] = stats[:insertions] + stats[:deletions]
  end
end

shas = history.map(&:sha)

file_scores = per_file_stats.map do |path, commit_stats|
  score = 0
  churn = commit_stats.values.inject(&:+)
  overall_change = overall_stats[:files][path]&.values&.inject(&:+)
  if churn.to_i > 0 && overall_change.to_i > 0
    # add 0, 1, or 2 to score depending on how much 'hidden churn' this file has
    score += [1.0, 1.2, Float::INFINITY].index {|v| churn/overall_change < v}
  end

  # add 0, 1, or 2 to score depending on how many commits the file is in
  score += [1, Math.sqrt(history.count).ceil, Float::INFINITY].index {|v| commit_stats.count <= v}

  # add 0, 1, or 2 depending on how the size of the largest gap in commit history for this file
  # [only applies for files with > 1 commit in this history
  my_commits = commit_stats.values_at(*shas)
  commits_i = my_commits.each_with_index.select {|touched, i| !touched.nil?}.map(&:last)
  largest_gap = commits_i.each_cons(2).map {|a,b| b-a}.max || 0
  score += [2, Math.sqrt(history.count).ceil, Float::INFINITY].index {|v| largest_gap <= v}

  [path, score]
end.to_h

commit_scores = history.map do |e|
  # score starts as max score of file in commit
  score = e.diff_parent.stats[:files].keys.map {|path| file_scores[path]}.compact.max || 0

  # add 0, 1, or 2 depending on total lines touched
  score += [30, 100, Float::INFINITY].index {|v| e.diff_parent.lines <= v}

  # add 0, 1, or 2 depending on files touched
  total_files_touched = e.diff_parent.size
  score += [5, 30, Float::INFINITY].index {|v| total_files_touched <= v}

  # add 0, 1, or 2 depending on how many 'new' vs 'already edited' files we're touching.
  new_files_touched = first_commit.values_at(*e.diff_parent.stats[:files].keys).count(e.sha)
  score += [0.8, 0.4, 0.0].index {|v| new_files_touched / total_files_touched >= v}

  score
end

commits = history.zip(commit_scores).map do |e, score|
  [
    e.sha[0,6],
    e.message.each_line.first.strip,
    e.diff_parent.lines,
    e.diff_parent.size,
    score
  ]
end

commit_header = [
  *[[nil]*5]*5,
  ["sha", "message", "lines touched", "files touched", "score"],
  *commits
].transpose

file_header = ["path", "lines churned", "final lines touched", "times changed", "score"]

file_rows = per_file_stats.map do |path, commit_stats|
  header = [
    path.strip,
    commit_stats.values.inject(&:+), # churn
    overall_stats[:files][path]&.values&.inject(&:+), # overall lines changed
    commit_stats.count,
    file_scores[path],
    nil
  ]
  values = commit_stats.values_at(*shas)
  [header, values]
end.sort_by do |header, values|
  inclusion = values.map {|v| v.nil? ? 1 : 0}
  [inclusion, header[0]]
end.map do |header, values|
  header + values
end

result = commit_header + [file_header] + file_rows

print result.map {|row| row.map(&:to_s).join("\t")}.join("\n")

