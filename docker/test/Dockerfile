ARG RUBY_VERSION
FROM ruby:$RUBY_VERSION

ADD scripts /scripts

RUN /scripts/install.sh

EXPOSE 1234

ENTRYPOINT /scripts/run.sh

