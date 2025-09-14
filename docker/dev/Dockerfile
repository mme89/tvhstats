ARG ELIXIR_VERSION=1.14.1
ARG OTP_VERSION=25.1.1
ARG DEBIAN_VERSION=bullseye-20220801

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}

# Set Locale
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PHOENIX_VERSION=1.6.13

# Add inotify-tools and essentials
RUN apt-get update -y && apt-get install -y --no-install-recommends \
        inotify-tools wget ca-certificates bash libstdc++6 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create required dirs
RUN mkdir /app

# Install hex and rebar
RUN mix local.hex --force
RUN mix local.rebar --force

# Install phoenix
RUN mix archive.install hex phx_new $PHOENIX_VERSION --force

# Set /app as workdir
WORKDIR /app
