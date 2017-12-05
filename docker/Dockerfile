FROM ruby:2.2.3

MAINTAINER Guillaume Chenuet <guillaume.chenuet@schibsted.com>

RUN apt-get update && apt-get install -qq -y build-essential

ENV INSTALL_PATH /gerrit-slack
RUN mkdir -p $INSTALL_PATH

WORKDIR $INSTALL_PATH

ADD docker/ssh/ /root/.ssh/

COPY Gemfile Gemfile

RUN bundle install

RUN bundle update

COPY . .

CMD bin/gerrit-slack
