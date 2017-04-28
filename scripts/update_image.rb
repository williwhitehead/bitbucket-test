require 'fileutils'

raise "Please provide the path to the docker and stash repository" unless ARGV.length.eql?(2)

DOCKER_REPO=ARGV.shift
STASH_REPO=ARGV.shift


def with_repo(repo)
  FileUtils.cd(repo) do
    return yield
  end
end

class Docker

  def initialize(repo); @repo = repo; end

  def stash_versions_on_current_branch
    with_repo(@repo) do
      resolve_docker_version_on_current_branch
    end
  end

  def stash_versions_in_docker
    with_repo(@repo) do
      resolve_docker_versions
    end
  end


  def ensure_version_branch_for_latest_exists!(version)
    puts "Ensure version branch exists for #{version}"
    with_repo(@repo) do
      if version =~ /(\d+)\.(\d+).(\d+)/
        major, minor = $1, $2
        branch = "release/#{major}.#{minor}"
        create_branch!(branch) unless branch_exists?(branch)
      end
    end
  end

  def update_version_on_branch!(branch, version)
    raise "Version is empty" if version.nil? || version.strip.empty?
    with_branch(branch) do
      content = IO.readlines("Dockerfile")
      File.open("Dockerfile", "w") do |f|
        content.each do |line|
          if line =~ /^ENV BITBUCKET_VERSION/
            f << "ENV BITBUCKET_VERSION #{version}\n"
          elsif line =~ /^ARG BITBUCKET_VERSION/
            f << "ARG BITBUCKET_VERSION=#{version}\n"
          else
            f << line
          end
        end
      end

      `git add Dockerfile`
      `git commit -m "Rev Atlassian Stash version to #{version} on #{branch}"`
    end
  end

  private
  def with_branch(branch)
    with_repo(@repo) do
      current_branch = resolve_current_branch
      `git checkout -b #{branch} origin/#{branch}` unless branch_exists?(branch)
      yield
      `git checkout #{current_branch}`unless current_branch.eql?(resolve_current_branch)
    end
  end

  def branch_exists?(name)
    !`git branch --no-color`.split("\n").select {|branch| branch =~ /#{name}/}.empty?
  end

  def create_branch!(name)
    `git branch #{name} master`
  end

  def resolve_current_branch
    `git branch --no-color`.split("\n").select {|branch| branch =~ /^\*/}.collect{|branch| branch.gsub(/^\* /, "")}.first
  end

  def resolve_docker_version_on_current_branch
    current_branch = resolve_current_branch
    {"#{current_branch}" => version_in_dockerfile(current_branch)}
  end

  def resolve_docker_versions
    branches = `git branch --no-color -r`.split
    filtered = branches.collect{|branch| branch.gsub /origin\//, ''}.select{|branch| branch =~ /(master|release)/}
    filtered.inject({}) do |hsh, branch|
      hsh[branch] = version_in_dockerfile(branch)
      hsh
    end
  end

  def version_in_dockerfile(branch)
    content = `git show #{branch}:Dockerfile`
    result=''
    if content =~ /ENV BITBUCKET_VERSION ([\d.]+)/
      result=$1.dup.strip
    elsif content =~ /ARG BITBUCKET_VERSION=([\d.]+)/
      result=$1.dup.strip
    end
    result
  end
end

class Stash
  def initialize(repo)
    @repo = repo
    @versions = resolve_stash_versions
  end

  def most_recent_version
    @versions.last
  end

  def most_recent_version_matching(prefix)
    @versions.select{|version| version =~ /^#{prefix}/}.last
  end


  private

  def resolve_stash_versions
    with_repo(@repo) do
      tags = `git tag`.split.select {|tag| tag =~ /bitbucket-parent/}.collect{|tag| tag.gsub(/bitbucket-parent-/,"")}.select{|version| version =~ /(\d+\.\d+\.\d+$)/}
      raise "Tags list is empty" if tags.empty?
      tags.sort_by do |version|
        if version =~ /^(\d+)\.(\d+)\.(\d+).*/
          major, minor, patch = $1.dup.to_i, $2.dup.to_i, $3.dup.to_i
          major * 10000 + minor * 100 + patch
        end
      end
    end
  end
end

$docker = Docker.new(DOCKER_REPO)

def determine_required_updates
  current_versions_in_docker = $docker.stash_versions_on_current_branch
  stash = Stash.new(STASH_REPO)

  to_update = {}
  current_versions_in_docker.each do |k,v|
    stash_latest = k.eql?("master") ? stash.most_recent_version : stash.most_recent_version_matching(k.gsub(/release\//,''))
    unless stash_latest.eql?(v) || stash_latest.nil? || stash_latest.strip.empty?
      to_update[k] = stash_latest
    end
  end
  to_update
end

def check_release_branches_exist!
  stash = Stash.new(STASH_REPO)
  $docker.ensure_version_branch_for_latest_exists!(stash.most_recent_version)
end

check_release_branches_exist!

versions_to_update = determine_required_updates
puts "Version update required: #{versions_to_update}" if $DEBUG

if versions_to_update.empty?
  puts "Nothing to do, all versions up to date"
  exit 0
else
  versions_to_update.each do |branch, version|
    puts "Updating #{branch} to #{version}"
    $docker.update_version_on_branch!(branch, version)
  end
  exit 1
end
