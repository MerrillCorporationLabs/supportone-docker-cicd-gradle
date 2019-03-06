FROM openjdk:8-jdk-slim
LABEL version="1.0" maintainer="Jordan Ross"
ENV SONAR_SCANNER_VERSION 3.2.0.1227
ENV YARN_VERSION 1.7.0

# install tools
# https://github.com/docker-library/buildpack-deps/blob/b0fc01aa5e3aed6820d8fed6f3301e0542fbeb36/sid/curl/Dockerfile
# plus git and ssh
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    netbase \
    wget \
    vim \
    openssh-client \
    git \
    gradle \
    gzip \
    jq \
    && rm -rf /var/lib/apt/lists/*

RUN set -ex; \
    if ! command -v gpg > /dev/null; then \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    gnupg \
    dirmngr \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Add jfrog cli
RUN curl -fL https://getcli.jfrog.io | sh \
    && mv ./jfrog /usr/local/bin/jfrog \
    && chmod 777 /usr/local/bin/jfrog

# Add a gradle user and setup home dir.
RUN groupadd --system --gid 1000 gradle && \
    useradd --system --create-home --uid 1000 --gid gradle --groups audio,video --shell /bin/bash gradle && \
    mkdir --parents /home/gradle/reports && \
    chown --recursive gradle:gradle /home/gradle

# https://docs.sonarqube.org/display/SCAN/Analyzing+with+SonarQube+Scanner
# install sonar-scanner
RUN apt-get update && apt-get install -y --no-install-recommends \
    unzip && \
    wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip && \
    unzip sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux -d /usr/local/share/ && \
    chown -R gradle: /usr/local/share/sonar-scanner-${SONAR_SCANNER_VERSION}-linux

ENV SONAR_RUNNER_HOME "/usr/local/share/sonar-scanner-${SONAR_SCANNER_VERSION}-linux"
ENV PATH="${SONAR_RUNNER_HOME}/bin:${PATH}"

# install dumb-init
# https://engineeringblog.yelp.com/2016/01/dumb-init-an-init-for-docker.html
ADD https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 /usr/local/bin/dumb-init
RUN chmod +x /usr/local/bin/dumb-init

# Need to use old 6.42.0 version because latest 6.43.0 version has problem in 1.10 prodeu
# When pushing ui app get following error -- No resource exists with the name processes
RUN wget -qO- "https://packages.cloudfoundry.org/stable?release=linux64-binary&version=6.42.0&source=github" | tar -zx && \
	mv cf /usr/local/bin && \
	cf --version

COPY cf-cli.sh /usr/local/bin
COPY rolling-deploy.sh /usr/local/bin
COPY test-deploy.sh /usr/local/bin
COPY validate-test-deploy-health.sh /usr/local/bin
COPY cutover-test-deploy.sh /usr/local/bin
COPY recent-logs.sh /usr/local/bin
COPY cleanup.sh /usr/local/bin

USER gradle
VOLUME /home/gradle
EXPOSE 3000
EXPOSE 49152
EXPOSE 4200
ENTRYPOINT ["dumb-init", "--"]
CMD ["gradle"]
