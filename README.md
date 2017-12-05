# Gerrit integration for Slack

## Notice

This project is forked from [ddonahue99/gerrit-slack](https://github.com/ddonahue99/gerrit-slack) repository where the main difference is to send **Direct Message** instead of **Channel Message** in the most case.

## What is it?

A daemon that sends updates to Slack channels as noteworthy events happen on Gerrit:

**Slack Direct Message**:
  * Comments
  * `-1`,`-2`,`+1` & `+2` votes
  * Builds results (Success/Failure)
  * Code/QA/Product review
  * Notify `-2` owner on new Patchset

**Slack Channel Message**:
  * New Reviews
  * Merges

## Configuration

Sample configuration files are provided in `config`.

### slack.yml

Configure your team name and Incoming Webhook integration URL here.

### gerrit.yml

Set Gerrit URL and the SSH command used to monitor stream-events on gerrit.

### channels.yml

This is where the real fun happens. The structure is as follows:

    channel1:
      project:
        - project1*

    channel2:
      project:
        - project2*
        - project3
      owner:
        - owner1
        - owner2
        - owner3

This configuration would post **all** updates from project1 to channel1, likewise for project2 and channel2. Updates to project3 are only posted to channel2 if the change owner is among those listed.

For channels that hate fun, you can turn celebratory emojis off by setting emoji to false.

    channel1:
      emoji: false

### aliases.yml

In order to ping a user on slack (e.g. for DMs on failed builds, or to @mention them), we need to know their Slack username. By default we assume the gerrit name is equal to the slack name. You can override this behavior on a per-user basis in aliases.yml.

## Running the daemon

    bundle install
    bundle update
    bin/gerrit-slack

## Development mode

Run the integration with DEVELOPMENT set to true to see more debug output and to *not* actually send updates to Slack.

    DEVELOPMENT=1 bin/gerrit-slack

## Running tests

    rspec

## Docker

Copy your Gerrit key on `docker/ssh/` and run:

```
docker build -f docker/Dockerfile

docker run -d [image_id]
```
