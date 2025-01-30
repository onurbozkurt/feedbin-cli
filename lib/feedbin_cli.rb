require 'thor'
require 'httparty'
require 'json'
require 'fileutils'
require 'tty-prompt'
require 'terminal-table'
require 'nokogiri'
require 'time'
require 'io/console'

module FeedbinCLI
  class CLI < Thor
    include Terminal

    CONFIG_DIR = File.join(Dir.home, '.feedbin-cli')
    CONFIG_FILE = File.join(CONFIG_DIR, 'config.json')
    BASE_URL = 'https://api.feedbin.com/v2'

    desc "authenticate EMAIL PASSWORD", "Authenticate with Feedbin using email and password"
    def authenticate(email, password)
      response = HTTParty.get(
        "#{BASE_URL}/authentication.json",
        basic_auth: { username: email, password: password }
      )

      if response.code == 200
        FileUtils.mkdir_p(CONFIG_DIR)
        File.write(CONFIG_FILE, {
          email: email,
          password: password
        }.to_json)
        puts "Authentication successful! Credentials stored."
      else
        puts "Authentication failed. Please check your credentials."
      end
    rescue => e
      puts "Error occurred: #{e.message}"
    end

    desc "stats", "Show basic stats about your Feedbin account"
    def stats
      credentials = load_credentials
      return unless credentials

      unread_entries = get_unread_entry_ids(credentials)
      starred_entries = get_starred_entries(credentials)
      subscriptions = get_subscriptions(credentials)

      if unread_entries && starred_entries && subscriptions
        puts "\nFeedbin Stats:"
        puts "-------------"
        puts "Unread entries: #{unread_entries.size}"
        puts "Starred entries: #{starred_entries.size}"
        puts "Total subscriptions: #{subscriptions.size}"
      end
    end

    desc "unread", "List and read unread entries"
    def unread
      credentials = load_credentials
      return unless credentials

      # First, get the unread entry IDs (limit to 100)
      unread_ids = get_unread_entry_ids(credentials)
      return unless unread_ids && !unread_ids.empty?

      # Take only the first 100 entries
      unread_ids = unread_ids.reverse.take(100)

      # Get the actual entries content
      entries = get_entries_by_ids(credentials, unread_ids)
      return puts "No unread entries found." if entries.empty?

      # Sort entries by published date
      entries.sort_by! { |e| e['published'] }.reverse!

      # Create a prompt for selection
      prompt = TTY::Prompt.new(interrupt: :exit)

      # Format entries for selection
      choices = entries.map do |entry|
        {
          name: "[#{entry['feed_title']}] #{entry['title']} (#{Time.parse(entry['published']).strftime('%Y-%m-%d %H:%M')})",
          value: entry
        }
      end

      # Add a quit option
      choices << { name: 'Exit', value: :exit }

      loop do
        begin
          selected = prompt.select(
            "Select an entry to read (Press 'q' to quit):",
            choices,
            per_page: 15,
            cycle: true,
            quiet: true,
            keys: { quit: 'q', up: 'k', down: 'j' }
          )
          break if selected == :exit

          display_entry(selected)

          # After reading, ask if user wants to mark as read
          if prompt.yes?("Mark this entry as read?")
            mark_as_read(credentials, [selected['id']])
            choices.reject! { |c| c[:value] == selected }
            break if choices.size <= 1 # Only :exit option left
          end
        rescue TTY::Reader::InputInterrupt
          break
        end
      end
    end

    private

    def load_credentials
      unless File.exist?(CONFIG_FILE)
        puts "Please authenticate first using: feedbin authenticate EMAIL PASSWORD"
        return nil
      end

      JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
    rescue JSON::ParserError
      puts "Error reading credentials. Please authenticate again."
      nil
    end

    def get_unread_entry_ids(credentials)
      response = make_request('/unread_entries.json', credentials)
      handle_response(response, 'unread entries')
    end

    def get_starred_entries(credentials)
      response = make_request('/starred_entries.json', credentials)
      handle_response(response, 'starred entries')
    end

    def get_subscriptions(credentials)
      response = make_request('/subscriptions.json', credentials)
      handle_response(response, 'subscriptions')
    end

    def get_entries_by_ids(credentials, ids)
      response = make_request("/entries.json?ids=#{ids.join(',')}&mode=extended", credentials)
      entries = handle_response(response, 'entries')
      return unless entries

      # Get feed information for these entries
      feed_ids = entries.map { |e| e['feed_id'] }.uniq
      feeds = get_feeds_by_ids(credentials, feed_ids)
      return entries unless feeds

      # Add feed titles to entries
      feed_map = feeds.each_with_object({}) { |feed, map| map[feed['id']] = feed['title'] }
      entries.each { |entry| entry['feed_title'] = feed_map[entry['feed_id']] }
      entries
    end

    def get_feeds_by_ids(credentials, ids)
      response = make_request("/feeds.json", credentials)
      feeds = handle_response(response, 'feeds')
      return unless feeds

      feeds.select { |feed| ids.include?(feed['id']) }
    end

    def mark_as_read(credentials, ids)
      response = HTTParty.post(
        "#{BASE_URL}/unread_entries/delete.json",
        basic_auth: {
          username: credentials[:email],
          password: credentials[:password]
        },
        headers: { 'Content-Type' => 'application/json' },
        body: { unread_entries: ids }.to_json
      )

      if response.code == 200
        puts "Entry marked as read."
      else
        puts "Failed to mark entry as read."
      end
    end

    def make_request(endpoint, credentials)
      HTTParty.get(
        "#{BASE_URL}#{endpoint}",
        basic_auth: {
          username: credentials[:email],
          password: credentials[:password]
        }
      )
    end

    def handle_response(response, type)
      case response.code
      when 200
        JSON.parse(response.body)
      else
        puts "Failed to fetch #{type}. Status code: #{response.code}"
        nil
      end
    rescue => e
      puts "Error fetching #{type}: #{e.message}"
      nil
    end

    def display_entry(entry)
      system('clear') || system('cls')

      puts "Title: #{entry['title']}"
      puts "Published: #{Time.parse(entry['published']).strftime('%Y-%m-%d %H:%M')}"
      puts "Author: #{entry['author']}" if entry['author']
      puts "Feed: #{entry['feed_title']}" if entry['feed_title']
      puts "URL: #{entry['url']}"

      puts "\n#{'-' * 80}\n\n"

      # Parse and display content
      if entry['content']
        doc = Nokogiri::HTML(entry['content'])
        # Remove script and style elements
        doc.css('script, style').remove
        # Get text content
        content = doc.text.strip.gsub(/\n+/, "\n\n")
        puts content
      else
        puts "No content available."
      end

      puts "\n#{'-' * 80}\n"
      puts "Press any key to continue..."
      $stdin.getch
    end
  end
end
