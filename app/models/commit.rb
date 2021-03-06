# == Schema Information
#
# Table name: commits
#
#  id         :integer          not null, primary key
#  project_id :integer
#  ref        :string(255)
#  sha        :string(255)
#  before_sha :string(255)
#  push_data  :text
#  created_at :datetime
#  updated_at :datetime
#

class Commit < ActiveRecord::Base
  belongs_to :project
  has_many :builds, dependent: :destroy

  serialize :push_data

  validates_presence_of :ref, :sha, :before_sha, :push_data
  validate :valid_commit_sha

  def self.truncate_sha(sha)
    sha[0...8]
  end

  def to_param
    sha
  end

  def last_build
    builds.order(:id).last
  end

  def retry
    builds_without_retry.each do |build|
      Build.retry(build)
    end
  end

  def valid_commit_sha
    if self.sha == Git::BLANK_SHA
      self.errors.add(:sha, " cant be 00000000 (branch removal)")
    end
  end

  def new_branch?
    before_sha == Git::BLANK_SHA
  end

  def compare?
    !new_branch?
  end

  def git_author_name
    commit_data[:author][:name] if commit_data && commit_data[:author]
  end

  def git_author_email
    commit_data[:author][:email] if commit_data && commit_data[:author]
  end

  def git_commit_message
    commit_data[:message] if commit_data && commit_data[:message]
  end

  def short_before_sha
    Commit.truncate_sha(before_sha)
  end

  def short_sha
    Commit.truncate_sha(sha)
  end

  def commit_data
    push_data[:commits].find do |commit|
      commit[:id] == sha
    end
  rescue
    nil
  end

  def project_recipients
    recipients = project.email_recipients.split(' ')

    if project.email_add_pusher? && push_data[:user_email].present?
      recipients << push_data[:user_email]
    end

    recipients.uniq
  end

  def create_builds
    filter_param = tag? ? :tags : :branches
    config_processor.builds.each do |build_attrs|
      if build_attrs[filter_param]
        builds.create!({ project: project }.merge(build_attrs.extract!(:name, :commands, :tag_list)))
      end
    end
  end

  def builds_without_retry
    @builds_without_retry ||=
      begin
        grouped_builds = builds.group_by(&:name)
        grouped_builds.map do |name, builds|
          builds.sort_by(&:id).last
        end
      end
  end

  def retried_builds
    @retried_builds ||= (builds - builds_without_retry)
  end

  def create_deploy_builds
    config_processor.deploy_builds_for_ref(ref).each do |build_attrs|
      builds.create!({ project: project }.merge(build_attrs))
    end
  end

  def status
    if success?
      'success'
    elsif pending?
      'pending'
    elsif running?
      'running'
    elsif canceled?
      'canceled'
    else
      'failed'
    end
  end

  def pending?
    builds_without_retry.all? do |build|
      build.pending?
    end
  end

  def running?
    builds_without_retry.any? do |build|
      build.running? || build.pending?
    end
  end

  def success?
    builds_without_retry.all? do |build|
      build.success?
    end
  end

  def failed?
    status == 'failed'
  end

  def canceled?
    builds_without_retry.all? do |build|
      build.canceled?
    end
  end

  def duration
    @duration ||= builds_without_retry.select(&:duration).sum(&:duration).to_i
  end

  def finished_at
    @finished_at ||= builds.order('finished_at DESC').first.try(:finished_at)
  end

  def coverage
    if project.coverage_enabled? && builds.size > 0
      builds.last.coverage
    end
  end

  def matrix?
    builds_without_retry.size > 1
  end

  def config_processor
    @config_processor ||= GitlabCiYamlProcessor.new(push_data[:ci_yaml_file])
  end
end
