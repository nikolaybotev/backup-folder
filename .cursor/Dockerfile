FROM swift:6.4.1-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends git sudo ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && (id ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ubuntu) \
 && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /home/ubuntu
