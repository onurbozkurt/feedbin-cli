# Feedbin CLI

A command-line interface for interacting with the Feedbin API.

## Installation

1. Clone this repository
2. Run `bundle install` to install dependencies

## Usage

First, make the CLI executable:

```bash
chmod +x bin/feedbin
```

### Authentication

To authenticate with your Feedbin account:

```bash
./bin/feedbin authenticate YOUR_EMAIL YOUR_PASSWORD
```

This will store your credentials securely in `~/.feedbin-cli/config.json`.

### View Account Stats

To view basic statistics about your Feedbin account:

```bash
./bin/feedbin stats
```

This will show:
- Number of unread entries
- Number of starred entries
- Total number of subscriptions

### Read Unread Entries

To view and read your unread entries:

```bash
./bin/feedbin unread
```

This will:
1. Show a list of your most recent 100 unread entries sorted by date (newest first)
2. Allow you to select an entry to read using arrow keys
3. Display the selected entry's content in a readable format
4. Give you the option to mark the entry as read
5. Let you continue reading other entries or exit

Note: The command shows up to 100 most recent unread entries at a time to ensure optimal performance.
