
FROM ruby:3.0.3

WORKDIR /home/app
ENV PORT 3000

expose $PORT

RUN gem install rails bundler
RUN gem install rails

ENTRYPOINT [ "/bin/bash" ]
