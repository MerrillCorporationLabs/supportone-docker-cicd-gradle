# supportone-docker-cicd-gradle
Docker container for CICD builds that has openjdk, and gradle


[![Docker Build Status](https://img.shields.io/docker/build/merrillcorporation/docker-cicd-node.svg?style=for-the-badge)](https://hub.docker.com/r/merrillcorporation/docker-cicd-node/builds/)

## Gradle
Example build command
```docker
docker build --pull -t merrillcorporation/supportone-docker-cicd-gradle/gradle-build:1 .
```

Run the following in your code workspace.
```docker
docker run \
    -d -it --rm -p 3000:3000 \
    -p 49152:49152 \
    -p 4200:4200 \
    -v $(pwd):/home/gradle/test \
    --name supportone-docker-cicd-gradle \
    merrillcorporation/supportone-docker-cicd-gradle/chrome-headless:1
```

Execute against container
```docker
docker exec -it supportone-docker-cicd-gradle bash
```

Run example code. replace {appName} with your angular app
```bash
cd ~/test
gradle -version
```
