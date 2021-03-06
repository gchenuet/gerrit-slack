class Update
  include Alias

  attr_reader :raw_json, :json

  def initialize(raw_json)
    @raw_json = raw_json
    @json = JSON.parse(raw_json)
  end

  def type
    json['type']
  end

  def project
    json['change']['project'] if json['change']
  end

  def changeID
    json['change']['id']
  end

  def comment_added?
    type == 'comment-added'
  end

  def patchset_added?
    type == 'patchset-created'
  end

  def is_new?
    json['patchSet']['number'] == '1'
  end

  def merged?
    type == 'change-merged'
  end

  def human?
    !['zuul', 'jenkins'].include?(json['author']['username'])
  end

  def jenkins?
    comment_added? && json['author']['username'] == 'zuul'
  end

  def build_successful?
    comment =~ /Succeeded/
  end

  def build_failed?
    comment =~ /Failed/
  end

  def build_aborted?
    comment =~ /Aborted/
  end

  def comment
    frd_lines = []
    json['comment'].split("\n\n").each { |line|
      next if line =~ /Patch Set \d+/
      break if line =~ /Reviewer (DID NOT )?check/
      frd_lines << line
    }
    frd_lines.join("\n\n")
  end

  def number
    json['change']['number']
  end

  def branch
    json['change']['branch']
  end

  def url
    json['change']['url']
  end

  def commit
    "#{commit_without_owner} (by @#{slack_name_for owner})"
  end

  def commit_without_owner
    "<#{json['change']['url']}|#{json['change']['project']} - #{sanitized_subject}>"
  end

  def owner
    if json['change']
      json['change']['owner']['username']
    elsif json['submitter']
      json['submitter']['username']
    end
  end

  def sanitized_subject
    sanitized = subject
    sanitized.gsub!('<', '&lt;')
    sanitized.gsub!('>', '&gt;')
    sanitized.gsub!('&', '&amp;')
    sanitized
  end

  def subject
    json['change']['subject']
  end

  def zuul_pipeline
    json['approvals'].each do |value|
      if json['comment'].include? value['type']
	 return value['description']
      end
    end
    return nil
  end

  def wip?
    comment =~ /Starting/
  end

  def uploader
    json['uploader']['name'].split.map(&:capitalize).join(' ')
  end

  def uploader_username
    json['uploader']['username']
  end

  def uploader_slack_name
    slack_name_for uploader_username
  end

  def author
    json['author']['name'].split.map(&:capitalize).join(' ')
  end

  def short_author
    json['author']['username']
  end

  def author_slack_name
    slack_name_for short_author
  end

  def approvals
    json['approvals']
  end

  def code_review_approved?
    has_approval?('Code-Review', '2')
  end

  def code_review_tentatively_approved?
    has_approval?('Code-Review', '1')
  end

  def code_review_rejected?
    has_approval?('Code-Review', '-1')
  end

  def qa_approved?
    has_approval?('QA-Review', '1')
  end

  def qa_rejected?
    has_approval?('QA-Review', '-1')
  end

  def product_approved?
    has_approval?('Product-Review', '1')
  end

  def product_rejected?
    has_approval?('Product-Review', '-1')
  end

  def minus_1ed?
    qa_rejected? || product_rejected? || code_review_rejected?
  end

  def minus_2ed?
    has_approval?('Code-Review', '-2')
  end

  def has_approval?(type, value)
    approvals && \
      approvals.find { |approval| approval['type'] == type && approval['value'] == value }
  end
end
