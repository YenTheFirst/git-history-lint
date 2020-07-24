require 'git'
dir, first, last = *ARGV[0,3]

g = Git.open(dir)

overall_stats = g.diff(first, last).stats
per_file_stats = {}
per_commit_stats = []
history = g.log(nil).between(first, last).reverse_each
history.each do |commit|
  commit.diff_parent.stats[:files].each do |path, stats|
    per_file_stats[path] ||= {}
    per_file_stats[path][commit.sha] = stats[:insertions] + stats[:deletions]
  end
end

commits = history.map do |e|
  [
    e.sha[0,6],
    e.message.each_line.first.strip,
    e.diff_parent.lines,
    e.diff_parent.size
  ]
end

commit_header = [
  *[[nil]*4]*4,
  ["sha", "message", "lines touched", "files touched"],
  *commits
].transpose

file_header = ["path", "lines churned", "final lines touched", "times changed"]

shas = history.map(&:sha)
file_rows = per_file_stats.map do |path, commit_stats|
  header = [
    path.strip,
    commit_stats.values.inject(&:+), # churn
    overall_stats[:files][path]&.values&.inject(&:+), # overall lines changed
    commit_stats.count,
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

