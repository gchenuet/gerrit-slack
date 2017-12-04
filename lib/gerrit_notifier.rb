class GerritNotifier
  extend Alias

  @@buffer = {}
  @@channel_config = nil
  @@semaphore = Mutex.new

  def self.start!
    @@channel_config = ChannelConfig.new
    start_buffer_daemon
    listen_for_updates
  end

  def self.psa!(msg)
    notify @@channel_config.all_channels, msg
  end

  def self.notify(channels, msg, emoji = '')
    channels.each do |channel|
      slack_channel = "##{channel}"
      add_to_buffer slack_channel, @@channel_config.format_message(channel, msg, emoji)
    end
  end

  def self.notify_user(user, msg)
    channel = "@#{slack_name_for user}"
    add_to_buffer channel, msg
  end

  def self.add_to_buffer(channel, msg)
    @@semaphore.synchronize do
      @@buffer[channel] ||= []
      @@buffer[channel] << msg
    end
  end

  def self.start_buffer_daemon
    # post every X seconds rather than truly in real-time to group messages
    # to conserve slack-log
    Thread.new do
      slack_config = YAML.load(File.read('config/slack.yml'))['slack']

      while true
        @@semaphore.synchronize do
          if @@buffer == {}
            puts "[#{Time.now}] Buffer is empty"
          else
            puts "[#{Time.now}] Current buffer:"
            ap @@buffer
          end

          if @@buffer.size > 0 && !ENV['DEVELOPMENT']
            @@buffer.each do |channel, messages|
              notifier = Slack::Notifier.new slack_config['token']
	      notifier.post(attachments: [messages[0]],
	        channel: channel,
		username: 'Gerrit',
		mrkdwn: true,
		link_names: 1
	      )
            end
          end

          @@buffer = {}
        end

        sleep 15
      end
    end
  end

  def self.listen_for_updates
    stream = YAML.load(File.read('config/gerrit.yml'))['gerrit']['stream']
    puts "Listening to stream via #{stream}"

    IO.popen(stream).each do |line|
      update = Update.new(line)
      process_update(update)
    end

    puts "Connection to Gerrit server failed, trying to reconnect."
    sleep 3
    listen_for_updates
  end

  def self.process_update(update)
    if ENV['DEVELOPMENT']
      ap update.json
      puts update.raw_json
    end

    channels = @@channel_config.channels_to_notify(update.project, update.owner)

    return if channels.size == 0

    # Jenkins update
    if update.jenkins?
      if update.build_successful? && !update.wip?
        content = {
          text: "All checks have passed.",
          title: "##{update.number}: #{update.commit_without_owner}",
          color: "good",
          mrkdwn_in: ["text"]
        }
        notify_user update.owner, content
      elsif update.build_failed? && !update.build_aborted?
        content = {
	  text: "All checks have failed.",
          title: "##{update.number}: #{update.commit_without_owner}",
          color: "danger",
          mrkdwn_in: ["text"]
        }
        notify_user update.owner, content
      end
    end

    # Code review +2
    if update.code_review_approved?
      content = {
	text: "#{update.author} (@#{update.author_slack_name}) has *+2* your review!",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: "good",
	mrkdwn_in: ["text"]
      }
      notify_user update.owner, content
    end

    # Code review +1
    if update.code_review_tentatively_approved?
      content = {
        text: "#{update.author} (@#{update.author_slack_name}) has *+1* your review!",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: "good",
        mrkdwn_in: ["text"]
      }
      notify_user update.owner, content
    end

    # QA/Product
    if update.qa_approved? && update.product_approved?
      notify_user update.owner, "#{update.author_slack_name} has *QA/Product-approved* #{update.commit}!", ":mj: :victory:"
    elsif update.qa_approved?
      notify_user update.owner, "#{update.author_slack_name} has *QA-approved* #{update.commit}!", ":mj:"
    elsif update.product_approved?
      notify_user update.owner, "#{update.author_slack_name} has *Product-approved* #{update.commit}!", ":victory:"
    end

    # Any minuses (Code/Product/QA)
    if update.minus_1ed? || update.minus_2ed?
      verb = update.minus_1ed? ? "-1" : "-2"
      color = update.minus_1ed? ? "warning" : "danger"
      content = {
	text: "#{update.author} (@#{update.author_slack_name}) has *#{verb}* your review.\n```#{update.comment} ```",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: color,
	mrkdwn_in: ["text"]
      }
      notify_user update.owner, content
    end

    # New Ref Updated
    if update.patchset_added? && update.is_new?
      content = {
	text: "#{update.uploader} opened a new review!",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: "#439FE0",
	mrkdwn_in: ["text"]
      }
      notify channels, content
    end

    # New comment added
    if update.comment_added? && update.human? && update.comment != ''
      content = {
	text: "```#{update.comment}```",
      	pretext: "#{update.author} (@#{update.author_slack_name}) has posted comments on this change!",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: "#4183d7",
	mrkdwn_in: ["text"]
      }
      notify_user update.owner, content
    end

    # Notify -2 owner on new patchset
    if update.patchset_added?
      gerrit_url = YAML.load(File.read('config/gerrit.yml'))['gerrit']['url']
      uri = URI(gerrit_url+"/changes/#{update.changeID}/detail")
      response = Net::HTTP.get(uri)
      response.slice! ")]}'"
      parsed = JSON.parse(response)
      if parsed['labels']['Code-Review']['rejected']
	parsed['labels']['Code-Review']['all'].each do |value|
	  if value['value'] == -2
            content = {
	      text: "#{update.uploader} (@#{update.uploader_slack_name}) has pushed a new patchset! Please review it.",
              title: "##{update.number}: #{update.commit_without_owner}",
              color: "#4183d7",
              mrkdwn_in: ["text"]
            }
            notify_user value['username'], content
	  end
        end
      end
    end

    # Merged
    if update.merged?
      content = {
	text: "#{update.commit} have been *merged* into #{update.branch}! :champagne:",
        title: "##{update.number}: #{update.commit_without_owner}",
        color: "good",
	mrkdwn_in: ["text"]
      }
      notify channels, content
    end
  end
end
